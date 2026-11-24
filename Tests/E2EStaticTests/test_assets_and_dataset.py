"""Static offline asset and dataset verification tests.

Covers F3 (T1/T2), F4 (T1/T2), F5 (T1/T2), and P15 from TEST_INFRA.md.
"""
from __future__ import annotations

import importlib.util
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
DATASET_PATH = REPO_ROOT / "StepTrack/Resources/Datasets/exercises.json"
ASSETS_DIR = REPO_ROOT / "StepTrack/Resources/Assets.xcassets"
ICONS_DIR = ASSETS_DIR / "Icons"
OBJ_PATH = REPO_ROOT / "StepTrack/Resources/Models3D/human_body.obj"
MTL_PATH = REPO_ROOT / "StepTrack/Resources/Models3D/human_body.mtl"
SCRIPTS_DIR = REPO_ROOT / "scripts"

EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF\u2600-\u26FF\u2700-\u27BF\uFE0F\u200D]")


def _load_script_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {name} from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _parse_obj(obj_path: Path, mtl_path: Path) -> dict:
    mtl_names: set[str] = set()
    for line in mtl_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("newmtl "):
            mtl_names.add(line.split()[1])

    verts: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    groups: dict[str, dict] = {}
    current_group: str | None = None
    mtllibs: list[str] = []
    non_tri_faces = 0
    invalid_face_tokens: list[str] = []

    for line_no, raw_line in enumerate(obj_path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        tokens = line.split()
        cmd = tokens[0]
        if cmd == "mtllib":
            mtllibs.append(tokens[1])
        elif cmd == "o":
            current_group = tokens[1]
            if current_group in groups:
                raise AssertionError(f"Duplicate OBJ group {current_group!r} at line {line_no}")
            groups[current_group] = {"mtls": set(), "faces": [], "v_indices": set(), "vn_indices": set()}
        elif cmd == "usemtl":
            if current_group is None:
                raise AssertionError(f"usemtl outside group at line {line_no}")
            groups[current_group]["mtls"].add(tokens[1])
        elif cmd == "v":
            verts.append((float(tokens[1]), float(tokens[2]), float(tokens[3])))
        elif cmd == "vn":
            normals.append((float(tokens[1]), float(tokens[2]), float(tokens[3])))
        elif cmd == "f":
            if current_group is None:
                raise AssertionError(f"face outside group at line {line_no}")
            corners = tokens[1:]
            if len(corners) != 3:
                non_tri_faces += 1
            face_v: list[int] = []
            for corner in corners:
                m = re.fullmatch(r"(\d+)//(\d+)", corner)
                if not m:
                    invalid_face_tokens.append(f"line {line_no}: {corner}")
                    continue
                vi = int(m.group(1))
                vni = int(m.group(2))
                face_v.append(vi)
                groups[current_group]["v_indices"].add(vi)
                groups[current_group]["vn_indices"].add(vni)
            groups[current_group]["faces"].append(tuple(face_v))

    return {
        "mtl_names": mtl_names,
        "mtllibs": mtllibs,
        "verts": verts,
        "normals": normals,
        "groups": groups,
        "non_tri_faces": non_tri_faces,
        "invalid_face_tokens": invalid_face_tokens,
    }


def _signed_volume_1based(verts: list[tuple[float, float, float]], faces: list[tuple[int, ...]]) -> float:
    vol = 0.0
    for face in faces:
        a = verts[face[0] - 1]
        b = verts[face[1] - 1]
        c = verts[face[2] - 1]
        cross = (
            b[1] * c[2] - b[2] * c[1],
            b[2] * c[0] - b[0] * c[2],
            b[0] * c[1] - b[1] * c[0],
        )
        vol += (a[0] * cross[0] + a[1] * cross[1] + a[2] * cross[2]) / 6.0
    return vol


def _strip_swift_comments_preserving_strings(text: str) -> str:
    """Remove Swift // and nested /* ... */ comments while keeping strings and newlines intact."""
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        if text[i : i + 3] == '"""':
            out.append('"""')
            i += 3
            while i < n:
                if text[i] == "\\" and i + 1 < n:
                    out.append(text[i : i + 2])
                    i += 2
                elif text[i : i + 3] == '"""':
                    out.append('"""')
                    i += 3
                    break
                else:
                    out.append(text[i])
                    i += 1
        elif text[i] == '"':
            out.append('"')
            i += 1
            while i < n:
                if text[i] == "\\" and i + 1 < n:
                    out.append(text[i : i + 2])
                    i += 2
                elif text[i] == '"':
                    out.append('"')
                    i += 1
                    break
                else:
                    if text[i] == "\n":
                        out.append("\n")
                        i += 1
                        break
                    out.append(text[i])
                    i += 1
        elif text[i : i + 2] == "//":
            i += 2
            while i < n and text[i] != "\n":
                i += 1
        elif text[i : i + 2] == "/*":
            depth = 1
            i += 2
            while i < n and depth > 0:
                if text[i : i + 2] == "/*":
                    depth += 1
                    i += 2
                elif text[i : i + 2] == "*/":
                    depth -= 1
                    i += 2
                else:
                    if text[i] == "\n":
                        out.append("\n")
                    i += 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def _extract_enum_body(swift_text: str, enum_name: str) -> str | None:
    """Extract brace-balanced body of `enum <enum_name>` ignoring comments and strings."""
    cleaned = _strip_swift_comments_preserving_strings(swift_text)
    header = re.search(rf"\benum\s+{re.escape(enum_name)}\b[^{{]*\{{", cleaned)
    if header is None:
        return None
    i = header.end()
    n = len(cleaned)
    depth = 1
    while i < n and depth > 0:
        if cleaned[i : i + 3] == '"""':
            i += 3
            while i < n:
                if cleaned[i] == "\\" and i + 1 < n:
                    i += 2
                elif cleaned[i : i + 3] == '"""':
                    i += 3
                    break
                else:
                    i += 1
        elif cleaned[i] == '"':
            i += 1
            while i < n:
                if cleaned[i] == "\\" and i + 1 < n:
                    i += 2
                elif cleaned[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
        elif cleaned[i] == "{":
            depth += 1
            i += 1
        elif cleaned[i] == "}":
            depth -= 1
            if depth == 0:
                return cleaned[header.end() : i]
            i += 1
        else:
            i += 1
    return None


def _parse_string_enum_cases(enum_body: str) -> set[str]:
    """Parse string-backed enum cases including multiline comma continuations and backticked names."""
    top_chars: list[str] = []
    i = 0
    n = len(enum_body)
    depth = 0
    while i < n:
        if enum_body[i : i + 3] == '"""':
            end = i + 3
            while end < n:
                if enum_body[end] == "\\" and end + 1 < n:
                    end += 2
                elif enum_body[end : end + 3] == '"""':
                    end += 3
                    break
                else:
                    end += 1
            if depth == 0:
                top_chars.append(enum_body[i:end])
            i = end
        elif enum_body[i] == '"':
            end = i + 1
            while end < n:
                if enum_body[end] == "\\" and end + 1 < n:
                    end += 2
                elif enum_body[end] == '"':
                    end += 1
                    break
                else:
                    end += 1
            if depth == 0:
                top_chars.append(enum_body[i:end])
            i = end
        elif enum_body[i] == "{":
            if depth == 0:
                top_chars.append(";")
            depth += 1
            i += 1
        elif enum_body[i] == "}":
            if depth > 0:
                depth -= 1
            i += 1
        else:
            if depth == 0:
                top_chars.append(enum_body[i])
            i += 1

    top_level = "".join(top_chars)
    slugs: set[str] = set()
    case_kw_re = re.compile(r"\bcase\b")
    item_re = re.compile(r'`?(\w+)`?(?:\s*=\s*"((?:[^"\\]|\\.)*)")?')

    idx = 0
    length = len(top_level)
    while idx < length:
        if top_level[idx] == '"':
            idx += 1
            while idx < length:
                if top_level[idx] == "\\" and idx + 1 < length:
                    idx += 2
                elif top_level[idx] == '"':
                    idx += 1
                    break
                else:
                    idx += 1
            continue
        m_kw = case_kw_re.match(top_level, idx)
        if m_kw and (idx == 0 or not (top_level[idx - 1].isalnum() or top_level[idx - 1] == "_")):
            idx = m_kw.end()
            while idx < length:
                while idx < length and top_level[idx].isspace():
                    idx += 1
                m_item = item_re.match(top_level, idx)
                if m_item is None:
                    break
                slugs.add(m_item.group(2) if m_item.group(2) is not None else m_item.group(1))
                idx = m_item.end()
                while idx < length and top_level[idx].isspace():
                    idx += 1
                if idx < length and top_level[idx] == ",":
                    idx += 1
                    continue
                break
        else:
            idx += 1
    return slugs


class TestF3OfflineExercisesDataset(unittest.TestCase):
    """F3: Offline MIT-only 1,324-exercise dataset schema, counts, and purity."""

    raw_text: str
    data: list[dict]

    @classmethod
    def setUpClass(cls) -> None:
        cls.raw_text = DATASET_PATH.read_text(encoding="utf-8")
        cls.data = json.loads(cls.raw_text)

    def test_T1_F03_01_dataset_record_count_and_json_array(self) -> None:
        self.assertTrue(DATASET_PATH.is_file())
        self.assertIsInstance(self.data, list)
        self.assertEqual(len(self.data), 1324)
        ids = [rec["id"] for rec in self.data]
        self.assertEqual(ids, sorted(ids), "exercises.json must be sorted deterministically by id")
        expected_compact = json.dumps(self.data, ensure_ascii=False, separators=(",", ":")) + "\n"
        self.assertEqual(self.raw_text, expected_compact, "exercises.json must use compact deterministic JSON")

    def test_T1_F03_02_record_exact_snake_case_schema(self) -> None:
        expected_keys = {
            "id",
            "name",
            "body_part",
            "target",
            "equipment",
            "muscle_group",
            "secondary_muscles",
            "instruction_steps",
        }
        str_keys = ("id", "name", "body_part", "target", "equipment", "muscle_group")
        for idx, rec in enumerate(self.data):
            self.assertIsInstance(rec, dict)
            self.assertEqual(set(rec.keys()), expected_keys, f"Schema mismatch at index {idx}")
            for k in str_keys:
                self.assertIsInstance(rec[k], str)
            for list_key in ("secondary_muscles", "instruction_steps"):
                self.assertIsInstance(rec[list_key], list)
                for item in rec[list_key]:
                    self.assertIsInstance(item, str)

    def test_T1_F03_03_body_part_categories_and_counts(self) -> None:
        expected_counts = {
            "upper arms": 292,
            "upper legs": 227,
            "back": 203,
            "waist": 169,
            "chest": 163,
            "shoulders": 143,
            "lower legs": 59,
            "lower arms": 37,
            "cardio": 29,
            "neck": 2,
        }
        actual_counts = dict(Counter(rec["body_part"] for rec in self.data))
        self.assertEqual(actual_counts, expected_counts)

    def test_T1_F03_04_target_and_equipment_indices(self) -> None:
        targets = Counter(rec["target"] for rec in self.data)
        equipment = Counter(rec["equipment"] for rec in self.data)
        self.assertEqual(len(targets), 19, f"Expected 19 targets, got {len(targets)}")
        self.assertEqual(len(equipment), 28, f"Expected 28 equipment types, got {len(equipment)}")
        self.assertEqual(equipment["band"], 54)
        self.assertEqual(equipment["resistance band"], 7)
        for name, count in targets.items():
            self.assertTrue(name.strip())
            self.assertGreater(count, 0)
        for name, count in equipment.items():
            self.assertTrue(name.strip())
            self.assertGreater(count, 0)

    def test_T1_F03_05_pipeline_deterministic_offline_reproduction(self) -> None:
        mod = _load_script_module("prepare_exercises_dataset", SCRIPTS_DIR / "prepare-exercises-dataset.py")
        stats = mod.validate_output(DATASET_PATH)
        self.assertEqual(stats["records"], 1324)
        self.assertEqual(stats["body_parts"], 10)
        self.assertEqual(stats["targets"], 19)

        # Offline raw-to-MIT schema validation and extraction test using synthetic schema + 1,324 raw records
        minimal_schema = {
            "$defs": {
                "languageMap": {"required": ["en"]},
                "languageStepsMap": {"required": ["en"]},
                "exercise": {
                    "required": [
                        "id",
                        "name",
                        "body_part",
                        "category",
                        "equipment",
                        "muscle_group",
                        "target",
                        "secondary_muscles",
                        "instructions",
                        "instruction_steps",
                        "image",
                        "gif_url",
                        "media_id",
                        "attribution",
                        "created_at",
                    ],
                    "properties": {
                        "id": {"pattern": r"^\d{4}$"},
                        "body_part": {
                            "enum": [
                                "upper arms",
                                "upper legs",
                                "back",
                                "waist",
                                "chest",
                                "shoulders",
                                "lower legs",
                                "lower arms",
                                "cardio",
                                "neck",
                            ]
                        },
                        "image": {"pattern": r"^images/\d{4}\.jpg$"},
                        "gif_url": {"pattern": r"^videos/\d{4}\.gif$"},
                    },
                },
            }
        }
        raw_records = []
        for i in range(1, mod.EXPECTED_RECORD_COUNT + 1):
            rec_id = f"{i:04d}"
            raw_records.append(
                {
                    "id": rec_id,
                    "name": f"sample exercise {rec_id}",
                    "body_part": "chest",
                    "category": "strength",
                    "equipment": "barbell",
                    "muscle_group": "chest",
                    "target": "pectorals",
                    "secondary_muscles": ["triceps"],
                    "instructions": {"en": "Press weight upward."},
                    "instruction_steps": {"en": ["Set grip.", "Press up."]},
                    "image": f"images/{rec_id}.jpg",
                    "gif_url": f"videos/{rec_id}.gif",
                    "media_id": rec_id,
                    "attribution": "MIT",
                    "created_at": "2024-01-01",
                }
            )
        validated = mod.validate_raw_against_schema(raw_records, minimal_schema)
        extracted = mod.extract_mit_records(validated)
        self.assertEqual(len(extracted), mod.EXPECTED_RECORD_COUNT)
        self.assertEqual(set(extracted[0].keys()), mod.MIT_FIELDS)
        serialized = json.dumps(extracted, ensure_ascii=False, separators=(",", ":")) + "\n"
        self.assertNotIn("gif_url", serialized)
        self.assertNotIn("images/", serialized)

        # Fail-closed check: invalid gif_url must be rejected
        bad_records = [dict(r) for r in raw_records]
        bad_records[0] = dict(bad_records[0], gif_url="https://example.com/bad.gif")
        with self.assertRaises(ValueError):
            mod.validate_raw_against_schema(bad_records, minimal_schema)

    def test_T2_F03_01_no_gymvisual_media_or_remote_urls(self) -> None:
        lower = self.raw_text.lower()
        for bad in ("gymvisual", "http://", "https://", "videos/", "images/"):
            self.assertNotIn(bad, lower, f"Forbidden substring {bad!r} in exercises.json")
        datasets_dir = DATASET_PATH.parent
        media_files = [
            p.name
            for p in datasets_dir.rglob("*")
            if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg", ".png", ".gif", ".mp4", ".webp")
        ]
        self.assertEqual(media_files, [], f"Bundled media files not allowed: {media_files}")

    def test_T2_F03_02_compact_file_size_limit(self) -> None:
        size = DATASET_PATH.stat().st_size
        self.assertGreater(size, 0)
        self.assertLess(size, 2.5 * 1024 * 1024)
        self.assertLess(size, 2 * 1024 * 1024)

    def test_T2_F03_03_no_empty_required_fields(self) -> None:
        for rec in self.data:
            for k in ("id", "name", "body_part", "target", "equipment", "muscle_group"):
                self.assertTrue(rec[k].strip(), f"Record {rec['id']} has empty {k}")
            self.assertGreaterEqual(len(rec["instruction_steps"]), 1, f"Record {rec['id']} has empty instruction_steps")
            for step in rec["instruction_steps"]:
                self.assertTrue(step.strip(), f"Record {rec['id']} has blank instruction step")
            for sec in rec["secondary_muscles"]:
                self.assertTrue(sec.strip(), f"Record {rec['id']} has blank secondary_muscle")

    def test_T2_F03_04_unique_exercise_ids(self) -> None:
        ids = [rec["id"] for rec in self.data]
        self.assertEqual(len(set(ids)), 1324)
        for rec_id in ids:
            self.assertRegex(rec_id, r"^\d{4}$")

    def test_T2_F03_05_utf8_special_chars_and_zero_emojis(self) -> None:
        self.assertNotIn("\ufffd", self.raw_text)
        self.assertNotIn("\x00", self.raw_text)
        self.assertIsNone(EMOJI_RE.search(self.raw_text))
        by_id = {rec["id"]: rec for rec in self.data}
        self.assertIn("0002", by_id)
        roundtrip = json.loads(json.dumps(by_id["0002"], ensure_ascii=False))
        self.assertEqual(roundtrip, by_id["0002"])
        self.assertIn("\u00b0", by_id["0002"]["name"])


class TestF4SvgIconAssets(unittest.TestCase):
    """F4: 59 bundled template-ready SVG .imageset assets."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.svg_mod = _load_script_module("prepare_svg_icons", SCRIPTS_DIR / "prepare-svg-icons.py")

    def test_T1_F04_01_icons_directory_and_59_imagesets(self) -> None:
        self.assertTrue(ICONS_DIR.is_dir())
        ns_meta = json.loads((ICONS_DIR / "Contents.json").read_text(encoding="utf-8"))
        self.assertIs(ns_meta.get("properties", {}).get("provides-namespace"), False)

        entries = sorted(p.name for p in ICONS_DIR.iterdir())
        non_imagesets = [e for e in entries if e != "Contents.json" and not e.endswith(".imageset")]
        self.assertEqual(non_imagesets, [], f"Unexpected entries in Icons/: {non_imagesets}")

        disk_slugs = sorted(e[: -len(".imageset")] for e in entries if e.endswith(".imageset"))
        expected_slugs = sorted(self.svg_mod.ALL_ICON_NAMES)
        self.assertEqual(len(disk_slugs), 59)
        self.assertEqual(disk_slugs, expected_slugs)

    def test_T1_F04_02_every_imageset_has_svg_and_contents_json(self) -> None:
        for slug in self.svg_mod.ALL_ICON_NAMES:
            imageset_dir = ICONS_DIR / f"{slug}.imageset"
            files = sorted(p.name for p in imageset_dir.iterdir() if p.is_file())
            self.assertEqual(files, sorted(["Contents.json", f"{slug}.svg"]), f"Unexpected files in {imageset_dir}")

    def test_T1_F04_03_contents_json_template_universal_metadata(self) -> None:
        for slug in self.svg_mod.ALL_ICON_NAMES:
            meta = json.loads((ICONS_DIR / f"{slug}.imageset/Contents.json").read_text(encoding="utf-8"))
            images = meta.get("images", [])
            self.assertEqual(len(images), 1, f"{slug}.imageset must have 1 image entry")
            self.assertEqual(images[0].get("filename"), f"{slug}.svg")
            self.assertEqual(images[0].get("idiom"), "universal")
            props = meta.get("properties", {})
            self.assertIs(props.get("preserves-vector-representation"), True)
            self.assertEqual(props.get("template-rendering-intent"), "template")

    def test_T1_F04_04_valid_svg_xml_and_viewbox(self) -> None:
        for slug in self.svg_mod.ALL_ICON_NAMES:
            svg_text = (ICONS_DIR / f"{slug}.imageset/{slug}.svg").read_text(encoding="utf-8")
            root = ET.fromstring(svg_text)
            local_tag = root.tag.split("}")[-1]
            self.assertEqual(local_tag, "svg", f"{slug}.svg root tag is {local_tag!r}")
            self.assertEqual(root.attrib.get("viewBox"), "0 0 24 24", f"{slug}.svg bad viewBox")

    def test_T1_F04_05_pipeline_script_lucide_version_and_offline_roundtrip(self) -> None:
        self.assertEqual(self.svg_mod.DEFAULT_VERSION, "1.78.0")
        self.assertEqual(self.svg_mod.validate_icons(ASSETS_DIR), 59)

        with tempfile.TemporaryDirectory() as tmp:
            tmp_assets = Path(tmp) / "Assets.xcassets"
            sample_lucide = (
                '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
                'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">'
                '<path d="M3 12h18"/></svg>'
            )
            svgs = {
                name: self.svg_mod.preprocess_svg(
                    self.svg_mod.CUSTOM_ANATOMICAL_SVGS.get(name, sample_lucide),
                    name,
                )
                for name in self.svg_mod.ALL_ICON_NAMES
            }
            self.svg_mod.write_catalog(tmp_assets, svgs)
            self.assertEqual(self.svg_mod.validate_icons(tmp_assets), 59)

        with self.assertRaises(ValueError):
            self.svg_mod.validate_svg_text(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" stroke="currentColor"/>',
                "bad",
            )

    def test_T2_F04_01_zero_current_color_and_black_stroke(self) -> None:
        for slug in self.svg_mod.ALL_ICON_NAMES:
            svg_text = (ICONS_DIR / f"{slug}.imageset/{slug}.svg").read_text(encoding="utf-8")
            self.assertNotIn("currentcolor", svg_text.lower(), f"{slug}.svg contains currentColor")
            self.assertIn('stroke="#000000"', svg_text, f"{slug}.svg missing stroke=\"#000000\"")

    def test_T2_F04_02_no_scale_key_in_imageset_contents(self) -> None:
        for slug in self.svg_mod.ALL_ICON_NAMES:
            meta = json.loads((ICONS_DIR / f"{slug}.imageset/Contents.json").read_text(encoding="utf-8"))
            self.assertNotIn("scale", meta["images"][0], f"{slug}.imageset/Contents.json must not specify scale")

    def test_T2_F04_03_no_script_or_embedded_image_tags(self) -> None:
        svg_ns = "http://www.w3.org/2000/svg"
        for slug in self.svg_mod.ALL_ICON_NAMES:
            svg_text = (ICONS_DIR / f"{slug}.imageset/{slug}.svg").read_text(encoding="utf-8")
            lower_no_ns = svg_text.lower().replace(svg_ns, "")
            for forbidden in ("<script", "<image", "xlink:href", "http://", "https://", "data:image/"):
                self.assertNotIn(forbidden, lower_no_ns, f"{slug}.svg contains forbidden content {forbidden!r}")
            self.assertIsNone(EMOJI_RE.search(svg_text), f"{slug}.svg contains emoji")
            root = ET.fromstring(svg_text)
            for elem in root.iter():
                local = elem.tag.split("}")[-1].lower()
                self.assertNotIn(local, ("script", "image", "foreignobject"), f"{slug}.svg has <{local}> element")
                for attr_name, attr_val in elem.attrib.items():
                    self.assertNotIn("http://", attr_val.lower(), f"{slug}.svg attr {attr_name} has external URL")
                    self.assertNotIn("https://", attr_val.lower(), f"{slug}.svg attr {attr_name} has external URL")
                    self.assertNotIn("data:image/", attr_val.lower(), f"{slug}.svg attr {attr_name} has data URI")

    def test_T2_F04_04_app_icon_swift_mapping_parity(self) -> None:
        svg_icon_swift = REPO_ROOT / "StepTrack/Core/DesignSystem/SvgIcon.swift"
        if not svg_icon_swift.is_file() and os.environ.get("STEPTRACK_REQUIRE_FULL_R2") != "1":
            self.skipTest("SvgIcon.swift pending M2 unless STEPTRACK_REQUIRE_FULL_R2=1")
        self.assertTrue(svg_icon_swift.is_file(), "SvgIcon.swift must exist when STEPTRACK_REQUIRE_FULL_R2=1")

        content = svg_icon_swift.read_text(encoding="utf-8")
        body = _extract_enum_body(content, "AppIcon")
        self.assertIsNotNone(body, "Could not locate `enum AppIcon: String` in SvgIcon.swift")
        declared_slugs = _parse_string_enum_cases(body or "")
        self.assertGreater(len(declared_slugs), 0)
        disk_slugs = {p.name[: -len(".imageset")] for p in ICONS_DIR.iterdir() if p.is_dir() and p.name.endswith(".imageset")}
        missing_on_disk = declared_slugs - disk_slugs
        self.assertEqual(missing_on_disk, set(), f"AppIcon cases missing .imageset on disk: {sorted(missing_on_disk)}")

    def test_T2_F04_05_custom_anatomical_svgs_match_template_convention(self) -> None:
        for slug in ("body-front", "body-back"):
            svg_path = ICONS_DIR / f"{slug}.imageset/{slug}.svg"
            self.assertTrue(svg_path.is_file())
            svg_text = svg_path.read_text(encoding="utf-8")
            self.assertEqual(svg_text, self.svg_mod.CUSTOM_ANATOMICAL_SVGS[slug])
            self.assertIn('viewBox="0 0 24 24"', svg_text)
            self.assertIn('stroke="#000000"', svg_text)
            self.assertIn('fill="none"', svg_text)


class TestF5BodyMesh3D(unittest.TestCase):
    """F5: Offline sculpted multi-part 3D human_body.obj & .mtl mesh."""

    parsed: dict

    @classmethod
    def setUpClass(cls) -> None:
        cls.parsed = _parse_obj(OBJ_PATH, MTL_PATH)
        cls.mesh_mod = _load_script_module("generate_body_mesh", SCRIPTS_DIR / "generate-body-mesh.py")

    def test_T1_F05_01_obj_and_mtl_exist_and_in_xcodegen(self) -> None:
        self.assertTrue(OBJ_PATH.is_file())
        self.assertTrue(MTL_PATH.is_file())
        for spec_name in ("project-sideload.yml", "project.yml"):
            spec = yaml.safe_load((REPO_ROOT / spec_name).read_text(encoding="utf-8"))
            sources = spec["targets"]["StepTrack"]["sources"]
            source_map = {
                (s if isinstance(s, str) else s["path"]): (s if isinstance(s, dict) else {})
                for s in sources
            }
            for asset_rel in (
                "StepTrack/Resources/Models3D/human_body.obj",
                "StepTrack/Resources/Models3D/human_body.mtl",
            ):
                self.assertIn(asset_rel, source_map, f"{spec_name} missing {asset_rel}")
                self.assertEqual(source_map[asset_rel].get("buildPhase"), "resources")

    def test_T1_F05_02_obj_syntax_v_vn_f_and_groups(self) -> None:
        self.assertEqual(self.parsed["mtllibs"], ["human_body.mtl"])
        self.assertEqual(self.parsed["non_tri_faces"], 0, "Expected strictly triangulated faces")
        self.assertEqual(self.parsed["invalid_face_tokens"], [], "Expected v//vn face syntax")
        self.assertGreater(len(self.parsed["verts"]), 0)
        self.assertEqual(len(self.parsed["verts"]), len(self.parsed["normals"]))
        for name, group in self.parsed["groups"].items():
            self.assertEqual(len(group["mtls"]), 1, f"Group {name} should use 1 material")
            self.assertTrue(group["mtls"] <= self.parsed["mtl_names"])

    def test_T1_F05_03_all_15_selectable_submeshes_present(self) -> None:
        expected_selectable = {
            "chest",
            "back_upper",
            "back_lats",
            "back_lower",
            "shoulders",
            "biceps",
            "triceps",
            "forearms",
            "abs",
            "glutes",
            "quads",
            "hamstrings",
            "calves",
            "neck",
            "cardio",
        }
        groups = self.parsed["groups"]
        self.assertTrue(expected_selectable <= set(groups.keys()))
        for name in expected_selectable:
            expected_mtl = "cardio_emblem" if name == "cardio" else "muscle_selectable"
            self.assertEqual(groups[name]["mtls"], {expected_mtl}, f"{name} unexpected material")

    def test_T1_F05_04_all_4_structural_nodes_present(self) -> None:
        structural = {"head", "torso_core", "hands", "feet"}
        groups = self.parsed["groups"]
        self.assertTrue(structural <= set(groups.keys()))
        for name in structural:
            self.assertEqual(groups[name]["mtls"], {"body_structural"})
        self.assertEqual(len(groups), 19)

    def test_T1_F05_05_generator_reproduces_byte_identical_obj_and_mtl(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_obj = Path(tmp) / "human_body.obj"
            out_mtl = Path(tmp) / "human_body.mtl"
            proc = subprocess.run(
                [sys.executable, str(SCRIPTS_DIR / "generate-body-mesh.py"), "--output", str(out_obj)],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(out_obj.read_bytes(), OBJ_PATH.read_bytes(), "Regenerated .obj differs from committed file")
            self.assertEqual(out_mtl.read_bytes(), MTL_PATH.read_bytes(), "Regenerated .mtl differs from committed file")

    def test_T2_F05_01_face_indices_in_bounds_and_finite_coords(self) -> None:
        verts = self.parsed["verts"]
        normals = self.parsed["normals"]
        for v in verts:
            self.assertTrue(all(math.isfinite(c) for c in v))
        for n in normals:
            self.assertTrue(all(math.isfinite(c) for c in n))
        v_count = len(verts)
        vn_count = len(normals)
        for name, group in self.parsed["groups"].items():
            for vi in group["v_indices"]:
                self.assertTrue(1 <= vi <= v_count, f"{name} vertex index out of bounds: {vi}")
            for vni in group["vn_indices"]:
                self.assertTrue(1 <= vni <= vn_count, f"{name} normal index out of bounds: {vni}")

    def test_T2_F05_02_selectable_bounds_face_counts_and_outward_volume(self) -> None:
        verts = self.parsed["verts"]
        for name in self.mesh_mod.SELECTABLE_REGIONS:
            group = self.parsed["groups"][name]
            self.assertGreaterEqual(len(group["faces"]), 4, f"{name} needs >= 4 faces for hitTest")
            pts = [verts[i - 1] for i in group["v_indices"]]
            xs, ys, zs = [p[0] for p in pts], [p[1] for p in pts], [p[2] for p in pts]
            self.assertGreater(max(xs) - min(xs), 1e-4, f"{name} degenerate X extent")
            self.assertGreater(max(ys) - min(ys), 1e-4, f"{name} degenerate Y extent")
            self.assertGreater(max(zs) - min(zs), 1e-4, f"{name} degenerate Z extent")
            vol = _signed_volume_1based(verts, group["faces"])
            self.assertGreater(vol, 0.0, f"{name} must have outward positive signed volume")

    def test_T2_F05_03_selectable_regions_map_to_valid_dataset_categories(self) -> None:
        data = json.loads(DATASET_PATH.read_text(encoding="utf-8"))
        body_parts = {r["body_part"] for r in data}
        targets = {r["target"] for r in data}
        region_to_body_part = {
            "chest": "chest",
            "back_upper": "back",
            "back_lats": "back",
            "back_lower": "back",
            "shoulders": "shoulders",
            "biceps": "upper arms",
            "triceps": "upper arms",
            "forearms": "lower arms",
            "abs": "waist",
            "glutes": "upper legs",
            "quads": "upper legs",
            "hamstrings": "upper legs",
            "calves": "lower legs",
            "neck": "neck",
            "cardio": "cardio",
        }
        self.assertEqual(set(region_to_body_part.keys()), set(self.mesh_mod.SELECTABLE_REGIONS))
        for region, bp in region_to_body_part.items():
            self.assertIn(bp, body_parts, f"{region} mapped to missing body_part {bp!r}")
        for target_hint in ("upper back", "traps", "lats", "spine", "biceps", "triceps", "glutes", "quads", "hamstrings"):
            self.assertIn(target_hint, targets)

    def test_T2_F05_04_obj_and_mtl_lightweight_size(self) -> None:
        obj_size = OBJ_PATH.stat().st_size
        mtl_size = MTL_PATH.stat().st_size
        self.assertGreater(obj_size, 0)
        self.assertLess(obj_size, 2 * 1024 * 1024)
        self.assertLess(obj_size, 1024 * 1024)
        self.assertGreater(mtl_size, 0)

    def test_T2_F05_05_front_back_z_axis_orientation(self) -> None:
        verts = self.parsed["verts"]
        groups = self.parsed["groups"]

        def _z_stats(name: str) -> tuple[float, float, float]:
            zs = [verts[i - 1][2] for i in groups[name]["v_indices"]]
            return min(zs), max(zs), sum(zs) / len(zs)

        for anterior in ("chest", "cardio", "abs", "biceps", "quads"):
            min_z, _, mean_z = _z_stats(anterior)
            self.assertGreater(mean_z, 0.0, f"Anterior {anterior} mean Z must be > 0")
            if anterior in ("chest", "cardio", "abs"):
                self.assertGreater(min_z, 0.0, f"Anterior torso {anterior} min Z must be > 0")

        for posterior in ("back_upper", "back_lats", "back_lower", "glutes", "triceps", "hamstrings"):
            _, max_z, mean_z = _z_stats(posterior)
            self.assertLess(mean_z, 0.0, f"Posterior {posterior} mean Z must be < 0")
            if posterior in ("back_upper", "back_lats", "back_lower", "glutes"):
                self.assertLess(max_z, 0.0, f"Posterior torso {posterior} max Z must be < 0")


class TestP15MeshToDatasetPairwise(unittest.TestCase):
    """P15 (F3 x F5): 100% body_part reachability from 3D body map selectable groups."""

    def test_T3_P15_01_all_selectable_obj_nodes_cover_all_10_body_parts(self) -> None:
        data = json.loads(DATASET_PATH.read_text(encoding="utf-8"))
        parsed = _parse_obj(OBJ_PATH, MTL_PATH)

        # Contract from PROJECT.md §1: node -> (body_part, target_filter_set_or_None)
        node_contracts: dict[str, tuple[str, set[str] | None]] = {
            "chest": ("chest", None),
            "back_upper": ("back", {"upper back", "traps"}),
            "back_lats": ("back", {"lats"}),
            "back_lower": ("back", {"spine"}),
            "shoulders": ("shoulders", None),
            "biceps": ("upper arms", {"biceps"}),
            "triceps": ("upper arms", {"triceps"}),
            "forearms": ("lower arms", None),
            "abs": ("waist", None),
            "glutes": ("upper legs", {"glutes"}),
            "quads": ("upper legs", {"quads"}),
            "hamstrings": ("upper legs", {"hamstrings"}),
            "calves": ("lower legs", None),
            "neck": ("neck", None),
            "cardio": ("cardio", None),
        }

        reached_body_parts: set[str] = set()
        for node, (body_part, target_set) in node_contracts.items():
            self.assertIn(node, parsed["groups"], f"3D mesh missing selectable node {node!r}")
            matches = [
                rec
                for rec in data
                if rec["body_part"] == body_part and (target_set is None or rec["target"] in target_set)
            ]
            self.assertGreaterEqual(len(matches), 1, f"3D node {node!r} matched 0 exercises")
            reached_body_parts.add(body_part)

        all_dataset_body_parts = {rec["body_part"] for rec in data}
        self.assertEqual(reached_body_parts, all_dataset_body_parts)
        self.assertEqual(len([r for r in data if r["body_part"] == "neck"]), 2)
        self.assertEqual(len([r for r in data if r["body_part"] == "cardio"]), 29)


if __name__ == "__main__":
    unittest.main()
