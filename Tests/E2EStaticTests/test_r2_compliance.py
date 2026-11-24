"""Static R2 compliance, localization, and synthetic negative-fixture tests.

Covers F10 (static), F11 (T1/T2), F19 (T1/T2), P16, and Scenario 10 (static).
NOTE: Never place literal Unicode emojis or symbol glyphs in this .py file;
always use ASCII escape sequences so verify-r2-compliance.py stays clean.
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
COMPLIANCE_SCRIPT = REPO_ROOT / "scripts/verify-r2-compliance.py"

EXTENDED_EMOJI_RE = re.compile(
    r"[\U0001F300-\U0001FAFF\U0001F1E6-\U0001F1FF\u231A\u231B\u2B50\u2B55\u2600-\u26FF\u2700-\u27BF\uFE0F\u200D]"
)
EXTENDED_GLYPH_RE = re.compile(r"[\u00b7\u2192\u2190\u2191\u2193\u2022\u2713\u2717]")
EXTENDED_FILLER_PATTERNS = (
    re.compile(r"\btap\s+(?:here|to|on|any)\b", re.IGNORECASE),
    re.compile(r"\badjust\s+by\b", re.IGNORECASE),
    re.compile(r"\bchanges\s+apply\b", re.IGNORECASE),
    re.compile(r"\bwe\s+believe\b", re.IGNORECASE),
    re.compile(r"\boops\b", re.IGNORECASE),
    re.compile(r"\bsoccer\s+fields\b", re.IGNORECASE),
    re.compile(r"\b\d+\s+color\s+modes?\b", re.IGNORECASE),
)
SWIFT_MULTILINE_STRING_RE = re.compile(r'"""(.*?)"""', re.DOTALL)
STRINGS_LINE_RE = re.compile(r'^\s*"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
FORMAT_SPEC_RE = re.compile(r"%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|z|t|j)?[@dDuUxXoOfeEgGcCsSpaAF]")


def _load_compliance_module():
    spec = importlib.util.spec_from_file_location("verify_r2_compliance", COMPLIANCE_SCRIPT)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {COMPLIANCE_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _create_clean_baseline_repo(tmp_root: Path) -> None:
    """Copy clean M1 assets + LICENSE into tmp_root for isolated fail-closed tests."""
    shutil.copy2(REPO_ROOT / "LICENSE", tmp_root / "LICENSE")
    resources_src = REPO_ROOT / "StepTrack/Resources"
    resources_dst = tmp_root / "StepTrack/Resources"
    shutil.copytree(resources_src / "Assets.xcassets", resources_dst / "Assets.xcassets")
    shutil.copytree(resources_src / "Datasets", resources_dst / "Datasets")
    shutil.copytree(resources_src / "Models3D", resources_dst / "Models3D")
    shutil.copytree(resources_src / "Localization", resources_dst / "Localization")

    loc_dir = tmp_root / "StepTrack/Core/Localization"
    loc_dir.mkdir(parents=True, exist_ok=True)
    (loc_dir / "Translations.json").write_text("{}\n", encoding="utf-8", newline="\n")
    (tmp_root / "StepTrack/Features").mkdir(parents=True, exist_ok=True)
    (tmp_root / "Tests/UnitTests").mkdir(parents=True, exist_ok=True)


def _run_compliance_in_dir(mod, tmp_root: Path, argv: list[str]) -> tuple[int, str]:
    old_root = mod.REPO_ROOT
    mod.REPO_ROOT = tmp_root
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            code = mod.main(argv)
    finally:
        mod.REPO_ROOT = old_root
    return code, buf.getvalue()


def _scan_extended_filler(texts: list[str]) -> list[str]:
    hits: list[str] = []
    for text in texts:
        for pat in EXTENDED_FILLER_PATTERNS:
            if pat.search(text):
                hits.append(f"{pat.pattern}: {text!r}")
                break
    return hits


def _extract_format_specs(text: str) -> list[str]:
    """Strip escaped %% literals before extracting printf-style format specifiers."""
    return FORMAT_SPEC_RE.findall(text.replace("%%", ""))


def _validate_translations_table(data: object) -> list[str]:
    """Validate 4-language parity, non-empty overrides, specifier sequences, and conciseness."""
    issues: list[str] = []
    if not isinstance(data, dict) or len(data) == 0:
        return ["Translations.json must be a non-empty JSON object"]
    for key, langs in data.items():
        if not isinstance(langs, dict):
            issues.append(f"Key {key!r} value must be dict")
            continue
        if "en" in langs:
            en_val = langs["en"]
            if not isinstance(en_val, str) or not en_val.strip():
                issues.append(f"Translations.json key {key!r} has invalid/empty 'en' override: {en_val!r}")
                continue
            en_text = en_val
        else:
            en_text = key
        en_specs = _extract_format_specs(en_text)
        for req_lang in ("vi", "ja", "es"):
            if req_lang not in langs:
                issues.append(f"Translations.json key {key!r} missing {req_lang!r}")
                continue
            val = langs[req_lang]
            if not isinstance(val, str) or not val.strip():
                issues.append(f"Translations.json key {key!r} has empty {req_lang!r}")
                continue
            val_specs = _extract_format_specs(val)
            if val_specs != en_specs:
                issues.append(
                    f"Format specifier mismatch for {key!r} ({req_lang}): "
                    f"{val_specs} vs {en_specs} ({val!r} vs {en_text!r})"
                )
            if val.count(". ") > 1:
                issues.append(f"Multi-sentence copy not concise in {key!r} ({req_lang}): {val!r}")
    return issues


def _extract_ui_strings_extended(mod, path: Path) -> list[tuple[int, str]]:
    """Extract UI strings including Swift triple-quoted multiline string literals."""
    results = list(mod._extract_ui_strings(path))
    if path.suffix == ".swift":
        raw = path.read_text(encoding="utf-8")
        for m in SWIFT_MULTILINE_STRING_RE.finditer(raw):
            line_no = raw[: m.start()].count("\n") + 1
            results.append((line_no, m.group(1)))
    return results


def _scan_extended_emojis(repo_root: Path) -> list[str]:
    """Scan repo source/asset text files for emojis including flags and un-variated symbols."""
    scan_roots = (
        repo_root / "StepTrack",
        repo_root / "Tests",
        repo_root / "scripts",
        repo_root / "README.md",
        repo_root / "BUILD-IPHONE.md",
    )
    suffixes = (".swift", ".json", ".strings", ".py", ".md", ".svg")
    issues: list[str] = []
    for root in scan_roots:
        if root.is_file():
            paths = [root] if root.suffix in suffixes else []
        elif root.is_dir():
            paths = [p for p in sorted(root.rglob("*")) if p.is_file() and p.suffix in suffixes]
        else:
            paths = []
        for path in paths:
            for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if EXTENDED_EMOJI_RE.search(line):
                    issues.append(f"{path.relative_to(repo_root)}:{line_no}: extended emoji detected")
    return issues


def _scan_extended_filler_and_glyphs(mod, repo_root: Path) -> list[str]:
    """Scan StepTrack UI strings (including Swift multiline literals) for extended glyphs and filler copy."""
    files = mod._iter_files((repo_root / "StepTrack",), (".swift", ".strings"))
    trans_path = repo_root / "StepTrack/Core/Localization/Translations.json"
    if trans_path.is_file():
        files.append(trans_path)
    violations: list[str] = []
    for path in files:
        if not path.is_file():
            continue
        for line_no, text in _extract_ui_strings_extended(mod, path):
            if EXTENDED_GLYPH_RE.search(text):
                violations.append(f"{path.relative_to(repo_root)}:{line_no}: glyph in {text!r}")
            for hit in _scan_extended_filler([text]):
                violations.append(f"{path.relative_to(repo_root)}:{line_no}: {hit}")
    return violations


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
    # Replace nested { ... } blocks (computed properties, methods, inner switches) with ';'
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


class TestR2ComplianceUnconditional(unittest.TestCase):
    """Group A: Unconditional R2 compliance, InfoPlist.strings, and negative fixture tests."""

    def test_T1_F19_01_verify_r2_m1_assets_only_passes(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(COMPLIANCE_SCRIPT), "--m1-assets-only"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + "\n" + proc.stderr)
        for expected_pass in (
            "[PASS] Legacy cleanup & MIT LICENSE",
            "[PASS] Zero Unicode Emojis",
            "[PASS] SVG Icons: 59 valid template SVG imagesets",
            "[PASS] Exercises Dataset: 1324 records",
            "[PASS] 3D Body Mesh: 19 groups",
        ):
            self.assertIn(expected_pass, proc.stdout)

    def test_T1_F11_02_and_T2_F19_01_02_zero_emojis_utf8_and_binary_safe(self) -> None:
        mod = _load_compliance_module()
        # Ensures UTF-8 across vi/ja/es files and binary/mesh assets do not crash or false-trigger
        emoji_issues = mod.check_emojis()
        self.assertEqual(emoji_issues, [], f"Unexpected emoji detections: {emoji_issues}")
        ext_emoji_issues = _scan_extended_emojis(REPO_ROOT)
        self.assertEqual(ext_emoji_issues, [], f"Unexpected extended emoji detections: {ext_emoji_issues}")

    def test_T1_F10_05_and_T2_F11_04_infoplist_strings_four_languages(self) -> None:
        mod = _load_compliance_module()
        loc_root = REPO_ROOT / "StepTrack/Resources/Localization"
        expected_keys = {"NSHealthShareUsageDescription", "NSMotionUsageDescription"}
        for lang in ("en", "vi", "ja", "es"):
            strings_path = loc_root / f"{lang}.lproj/InfoPlist.strings"
            with self.subTest(language=lang):
                self.assertTrue(strings_path.is_file(), f"Missing {strings_path}")
                raw = strings_path.read_text(encoding="utf-8")
                parsed: dict[str, str] = {}
                for line_no, line in enumerate(raw.splitlines(), 1):
                    if not line.strip():
                        continue
                    m = STRINGS_LINE_RE.match(line)
                    self.assertIsNotNone(m, f"{strings_path}:{line_no} invalid .strings syntax: {line!r}")
                    parsed[m.group(1)] = m.group(2)
                self.assertEqual(set(parsed.keys()), expected_keys)
                for key, val in parsed.items():
                    self.assertTrue(val.strip(), f"{lang}.lproj {key} must be non-empty")
                    self.assertIsNone(mod.EMOJI_RE.search(val), f"{lang}.lproj {key} contains emoji")
                    self.assertIsNone(mod.ARROW_GLYPH_RE.search(val), f"{lang}.lproj {key} contains arrow glyph")
                    self.assertEqual(_scan_extended_filler([val]), [], f"{lang}.lproj {key} contains filler copy")

    def test_T1_F19_03_negative_fixture_catches_sf_symbols(self) -> None:
        mod = _load_compliance_module()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            _create_clean_baseline_repo(tmp_root)
            base_code, base_out = _run_compliance_in_dir(mod, tmp_root, ["--strict"])
            self.assertEqual(base_code, 0, f"Clean baseline failed unexpectedly:\n{base_out}")

            bad_swift = tmp_root / "StepTrack/Features/SampleView.swift"
            bad_swift.write_text(
                'import SwiftUI\nstruct SampleView: View {\n'
                '  var body: some View { Image(systemName: "figure.walk"); Label("Steps", systemImage: "flame") }\n}\n',
                encoding="utf-8",
            )
            code, out = _run_compliance_in_dir(mod, tmp_root, ["--strict"])
            self.assertEqual(code, 1, f"Expected SF Symbol failure, got pass:\n{out}")
            self.assertIn("[FAIL] SF Symbols", out)
            self.assertIn("SampleView.swift:3", out)

    def test_T1_F19_04_negative_fixture_catches_emojis(self) -> None:
        mod = _load_compliance_module()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            _create_clean_baseline_repo(tmp_root)
            base_code, base_out = _run_compliance_in_dir(mod, tmp_root, ["--strict"])
            self.assertEqual(base_code, 0, f"Clean baseline failed unexpectedly:\n{base_out}")

            # Build emoji string using ASCII escape sequences so this .py file contains zero literal emojis
            emoji = "\U0001F3CB\uFE0F"
            (tmp_root / "StepTrack/Features/SampleView.swift").write_text(
                f'let label = "{emoji} Workout"\n',
                encoding="utf-8",
            )
            (tmp_root / "StepTrack/Core/Localization/Translations.json").write_text(
                json.dumps({"Workout": {"vi": f"{emoji} Luyen tap"}}, ensure_ascii=False),
                encoding="utf-8",
            )
            for mode_flag in ("--strict", "--m1-assets-only"):
                code, out = _run_compliance_in_dir(mod, tmp_root, [mode_flag])
                self.assertEqual(code, 1, f"Expected emoji failure under {mode_flag}:\n{out}")
                self.assertIn("[FAIL] Unicode Emojis", out)

    def test_T1_F19_04_negative_fixture_catches_arrow_and_bullet_glyphs(self) -> None:
        mod = _load_compliance_module()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            _create_clean_baseline_repo(tmp_root)
            base_code, _ = _run_compliance_in_dir(mod, tmp_root, ["--strict"])
            self.assertEqual(base_code, 0)

            arrow = "\u2192"
            bullet = "\u2022"
            check = "\u2713"
            (tmp_root / "StepTrack/Features/SampleView.swift").write_text(
                f'let nav = "Next {arrow}"\nlet sep = "A {bullet} B"\nlet done = "{check} Done"\n',
                encoding="utf-8",
            )
            (tmp_root / "StepTrack/Core/Localization/Translations.json").write_text(
                json.dumps({"Done": {"es": f"{check} Listo"}}, ensure_ascii=False),
                encoding="utf-8",
            )
            code, out = _run_compliance_in_dir(mod, tmp_root, ["--strict"])
            self.assertEqual(code, 1, f"Expected arrow/glyph failure:\n{out}")
            self.assertIn("[FAIL] Keyboard Arrow/Glyph Icons", out)

            # Extended glyph check also catches middle dot (\u00b7)
            middle_dot = "\u00b7"
            self.assertIsNotNone(EXTENDED_GLYPH_RE.search(f"3 sets {middle_dot} 10 reps"))

    def test_T1_F19_04_negative_fixture_catches_filler_copy(self) -> None:
        mod = _load_compliance_module()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            _create_clean_baseline_repo(tmp_root)
            base_code, _ = _run_compliance_in_dir(mod, tmp_root, ["--strict"])
            self.assertEqual(base_code, 0)

            (tmp_root / "StepTrack/Features/SampleView.swift").write_text(
                'let a = "Tap here to log"\nlet b = "2 color modes"\n',
                encoding="utf-8",
            )
            (tmp_root / "StepTrack/Core/Localization/Translations.json").write_text(
                json.dumps({"Hint": {"es": "Tap here to start"}}, ensure_ascii=False),
                encoding="utf-8",
            )
            code, out = _run_compliance_in_dir(mod, tmp_root, ["--strict"])
            self.assertEqual(code, 1, f"Expected filler copy failure:\n{out}")
            self.assertIn("[FAIL] Instructional Filler Copy", out)

        # File-backed extended T1-F11-03/04 scanner catches all TEST_INFRA.md filler phrases & middle dot (\u00b7)
        middle_dot = "\u00b7"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            _create_clean_baseline_repo(tmp_root)
            self.assertEqual(_scan_extended_filler_and_glyphs(mod, tmp_root), [])

            (tmp_root / "StepTrack/Features/ExtendedViolations.swift").write_text(
                'let f1 = "Adjust by 500 steps"\n'
                'let f2 = "Changes apply to today and future days."\n'
                'let f3 = "We believe fitness is personal"\n'
                f'let g1 = "3 sets {middle_dot} 10 reps"\n'
                'let ml = """\nTap here to log\n"""\n',
                encoding="utf-8",
            )
            (tmp_root / "StepTrack/Core/Localization/Translations.json").write_text(
                json.dumps(
                    {
                        "Err": {"es": "Oops, something went wrong"},
                        "Dist": {"en": "Equivalent to 4 soccer fields", "es": "4 campos", "vi": "4 san", "ja": "4"},
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            hits = _scan_extended_filler_and_glyphs(mod, tmp_root)
            self.assertEqual(len(hits), 7, f"Expected all 7 file-backed extended violations, got: {hits}")
            joined = "\n".join(hits)
            self.assertIn("ExtendedViolations.swift:1", joined)
            self.assertIn("ExtendedViolations.swift:4", joined)
            self.assertIn("ExtendedViolations.swift:5", joined)
            self.assertIn("Translations.json", joined)

    def test_T1_F19_04_negative_fixture_catches_extended_emojis_and_multiline_swift(self) -> None:
        mod = _load_compliance_module()
        flag_us = "\U0001F1FA\U0001F1F8"
        watch = "\u231A"
        star = "\u2B50"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            _create_clean_baseline_repo(tmp_root)
            self.assertEqual(_scan_extended_emojis(tmp_root), [])
            self.assertEqual(_scan_extended_filler_and_glyphs(mod, tmp_root), [])

            (tmp_root / "StepTrack/Features/EmojiSample.swift").write_text(
                f'let flag = "{flag_us}"\n'
                'let mlHint = """\nTap here to log your steps\n"""\n',
                encoding="utf-8",
            )
            (tmp_root / "StepTrack/Core/Localization/Translations.json").write_text(
                json.dumps({"Watch": {"es": f"{watch} Reloj"}}, ensure_ascii=False),
                encoding="utf-8",
            )
            (tmp_root / "StepTrack/Resources/Localization/en.lproj/InfoPlist.strings").write_text(
                f'"NSMotionUsageDescription" = "{star} Motion";\n',
                encoding="utf-8",
            )

            emoji_hits = _scan_extended_emojis(tmp_root)
            self.assertEqual(len(emoji_hits), 3, f"Expected 3 extended emoji hits, got: {emoji_hits}")
            joined_emoji = "\n".join(emoji_hits)
            self.assertIn("EmojiSample.swift:1", joined_emoji)
            self.assertIn("Translations.json", joined_emoji)
            self.assertIn("InfoPlist.strings:1", joined_emoji)

            ml_hits = _scan_extended_filler_and_glyphs(mod, tmp_root)
            self.assertEqual(len(ml_hits), 1, f"Expected multiline Swift filler hit, got: {ml_hits}")
            self.assertIn("EmojiSample.swift:2", ml_hits[0])

    def test_T2_F10_02_translations_format_specifier_and_en_override_validation(self) -> None:
        self.assertEqual(_extract_format_specs("%@%% of goal"), ["%@"])
        self.assertEqual(_extract_format_specs("%@%% m\u1ee5c ti\u00eau"), ["%@"])
        self.assertEqual(_extract_format_specs("100%% free"), [])

        valid_table = {
            "%@%% of goal": {
                "en": "%@%% of goal",
                "vi": "%@%% m\u1ee5c ti\u00eau",
                "ja": "\u76ee\u6a19\u306e%@%%",
                "es": "%@%% del objetivo",
            },
            "100%% free": {
                "vi": "Mien phi 100%%",
                "ja": "100%% muryo",
                "es": "100%% gratis",
            },
        }
        self.assertEqual(_validate_translations_table(valid_table), [])

        type_mismatch = {
            "Goal: %@ steps": {
                "vi": "Muc tieu: %d buoc",
                "ja": "%@ steps",
                "es": "%@ pasos",
            }
        }
        mismatch_issues = _validate_translations_table(type_mismatch)
        self.assertEqual(len(mismatch_issues), 1)
        self.assertIn("Format specifier mismatch", mismatch_issues[0])

        missing_es = {"Today": {"vi": "Hom nay", "ja": "Kyou"}}
        missing_issues = _validate_translations_table(missing_es)
        self.assertEqual(len(missing_issues), 1)
        self.assertIn("missing 'es'", missing_issues[0])

        empty_es = {"Today": {"vi": "Hom nay", "ja": "Kyou", "es": "   "}}
        empty_es_issues = _validate_translations_table(empty_es)
        self.assertEqual(len(empty_es_issues), 1)
        self.assertIn("empty 'es'", empty_es_issues[0])

        empty_en = {"Today": {"en": "", "vi": "Hom nay", "ja": "Kyou", "es": "Hoy"}}
        empty_en_issues = _validate_translations_table(empty_en)
        self.assertEqual(len(empty_en_issues), 1)
        self.assertIn("'en'", empty_en_issues[0])

    def test_T2_F04_04_app_icon_enum_parser_handles_multiline_and_braces(self) -> None:
        synthetic_swift = (
            "import SwiftUI\n"
            "// enum AppIcon { case commentedOut = \"fake\" }\n"
            "enum AppIcon: String, CaseIterable {\n"
            "    /* /* nested comment */ case blockCommented = \"fake2\" { } */\n"
            "    case flame = \"flame\", // inline comment\n"
            "         `return` = \"rotate-ccw\",\n"
            "         home = \"home\"\n"
            "    var id: String {\n"
            "        switch self {\n"
            "        case .flame: return \"{\"\n"
            "        default: return rawValue\n"
            "        }\n"
            "    }\n"
            "    case trailing = \"activity\"\n"
            "}\n"
        )
        body = _extract_enum_body(synthetic_swift, "AppIcon")
        self.assertIsNotNone(body)
        parsed = _parse_string_enum_cases(body or "")
        self.assertEqual(parsed, {"flame", "rotate-ccw", "home", "activity"})

    def test_T2_F19_04_negative_fixture_catches_bad_svg_and_missing_license(self) -> None:
        mod = _load_compliance_module()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            _create_clean_baseline_repo(tmp_root)
            base_code, _ = _run_compliance_in_dir(mod, tmp_root, ["--strict"])
            self.assertEqual(base_code, 0)

            # Fault 1: inject currentColor into a bundled SVG
            home_svg = tmp_root / "StepTrack/Resources/Assets.xcassets/Icons/home.imageset/home.svg"
            home_svg.write_text(home_svg.read_text(encoding="utf-8").replace("#000000", "currentColor"), encoding="utf-8")
            code, out = _run_compliance_in_dir(mod, tmp_root, ["--strict"])
            self.assertEqual(code, 1)
            self.assertIn("[FAIL] SVG Icons", out)

        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            _create_clean_baseline_repo(tmp_root)
            (tmp_root / "LICENSE").unlink()
            code, out = _run_compliance_in_dir(mod, tmp_root, ["--strict"])
            self.assertEqual(code, 1)
            self.assertNotIn("[PASS] Legacy cleanup & MIT LICENSE", out)
            self.assertIn("Compliance check FAILED", out)
            old_root = mod.REPO_ROOT
            mod.REPO_ROOT = tmp_root
            try:
                self.assertTrue(any("LICENSE" in msg for msg in mod.check_legacy_removed()))
            finally:
                mod.REPO_ROOT = old_root


@unittest.skipUnless(
    os.environ.get("STEPTRACK_REQUIRE_FULL_R2") == "1",
    "Requires M2-M4 completion for full-repo R2 compliance (set STEPTRACK_REQUIRE_FULL_R2=1)",
)
class TestR2ComplianceFullRepo(unittest.TestCase):
    """Group B: Full-repo strict R2, 4-language parity, and SvgIcon/Widget SVG checks."""

    def test_S10_F11_full_repo_strict_r2_compliance(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(COMPLIANCE_SCRIPT), "--strict"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + "\n" + proc.stderr)
        self.assertNotIn("[M1-DEFERRED]", proc.stdout)
        self.assertNotIn("[FAIL]", proc.stdout)

    def test_T1_F11_03_04_extended_filler_and_glyph_scan(self) -> None:
        mod = _load_compliance_module()
        violations = _scan_extended_filler_and_glyphs(mod, REPO_ROOT)
        self.assertEqual(violations, [], "Extended R2 violations found:\n" + "\n".join(violations))
        ext_emoji_issues = _scan_extended_emojis(REPO_ROOT)
        self.assertEqual(ext_emoji_issues, [], "Extended emoji violations found:\n" + "\n".join(ext_emoji_issues))

    def test_T1_F10_01_02_and_T2_F10_02_translations_four_language_parity(self) -> None:
        app_lang_swift = (REPO_ROOT / "StepTrack/Core/Localization/AppLanguage.swift").read_text(encoding="utf-8")
        for code in ("en", "vi", "ja", "es"):
            self.assertRegex(app_lang_swift, rf"\bcase\b.*\b{code}\b", f"AppLanguage.swift missing language {code!r}")

        trans_path = REPO_ROOT / "StepTrack/Core/Localization/Translations.json"
        data = json.loads(trans_path.read_text(encoding="utf-8"))
        issues = _validate_translations_table(data)
        self.assertEqual(issues, [], "Translations.json parity/specifier issues:\n" + "\n".join(issues))

    def test_T1_F11_05_T2_F04_04_P16_app_icon_enum_and_widget_svg_parity(self) -> None:
        svg_icon_path = REPO_ROOT / "StepTrack/Core/DesignSystem/SvgIcon.swift"
        self.assertTrue(svg_icon_path.is_file(), "Missing SvgIcon.swift")
        svg_icon_swift = svg_icon_path.read_text(encoding="utf-8")
        self.assertIn(".renderingMode(.template)", svg_icon_swift)

        enum_body = _extract_enum_body(svg_icon_swift, "AppIcon")
        self.assertIsNotNone(enum_body, "Missing enum AppIcon: String")
        slugs = _parse_string_enum_cases(enum_body or "")
        self.assertGreater(len(slugs), 0)
        icons_dir = REPO_ROOT / "StepTrack/Resources/Assets.xcassets/Icons"
        for slug in slugs:
            self.assertTrue((icons_dir / f"{slug}.imageset/{slug}.svg").is_file(), f"Missing SVG for AppIcon.{slug}")

        widget_swift = (REPO_ROOT / "StepTrack/Widget/StepTrackWidget.swift").read_text(encoding="utf-8")
        mod = _load_compliance_module()
        self.assertIsNone(mod.SF_SYMBOL_RE.search(widget_swift), "StepTrackWidget.swift must not use SF Symbols")
        self.assertIsNone(mod.EMOJI_RE.search(widget_swift), "StepTrackWidget.swift must not use emojis")
        self.assertIsNone(EXTENDED_EMOJI_RE.search(widget_swift), "StepTrackWidget.swift must not use extended emojis")


if __name__ == "__main__":
    unittest.main()
