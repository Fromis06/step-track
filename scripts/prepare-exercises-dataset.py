"""Fetch, schema-validate, and minify MIT-only exercise data for offline bundling."""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = REPO_ROOT / "StepTrack/Resources/Datasets/exercises.json"
DEFAULT_SCHEMA_URL = "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/data/exercises.schema.json"
DEFAULT_DATA_URL = "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/data/exercises.json"

EXPECTED_RECORD_COUNT = 1324
EXPECTED_BODY_PART_COUNT = 10
EXPECTED_TARGET_COUNT = 19
MAX_OUTPUT_BYTES = 2 * 1024 * 1024
MIT_FIELDS = {
    "id",
    "name",
    "body_part",
    "target",
    "equipment",
    "muscle_group",
    "secondary_muscles",
    "instruction_steps",
}
FORBIDDEN_SUBSTRINGS = ("gymvisual", "http://", "https://", "videos/", "images/")
EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF\u2600-\u26FF\u2700-\u27BF\uFE0F\u200D]")


def _fetch_json(url: str) -> object:
    req = urllib.request.Request(url, headers={"User-Agent": "StepTrack-AssetPipeline/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def validate_raw_against_schema(raw_records: object, schema: dict) -> list[dict]:
    if not isinstance(raw_records, list):
        raise ValueError("Raw dataset root must be a JSON array")
    if len(raw_records) != EXPECTED_RECORD_COUNT:
        raise ValueError(f"Expected {EXPECTED_RECORD_COUNT} raw records, got {len(raw_records)}")

    defs = schema.get("$defs", {})
    exercise_def = defs["exercise"]
    required_keys = set(exercise_def["required"])
    props = exercise_def["properties"]
    body_part_enum = set(props["body_part"]["enum"])
    id_regex = re.compile(props["id"]["pattern"])
    image_regex = re.compile(props["image"]["pattern"])
    gif_regex = re.compile(props["gif_url"]["pattern"])
    lang_keys = set(defs["languageMap"]["required"])
    step_lang_keys = set(defs["languageStepsMap"]["required"])

    seen_ids: set[str] = set()
    validated: list[dict] = []

    for idx, rec in enumerate(raw_records):
        if not isinstance(rec, dict):
            raise ValueError(f"Record {idx} is not an object")
        if set(rec.keys()) != required_keys:
            missing = required_keys - set(rec.keys())
            extra = set(rec.keys()) - required_keys
            raise ValueError(f"Record {idx} key mismatch: missing={missing}, extra={extra}")

        rec_id = rec["id"]
        if not isinstance(rec_id, str) or not id_regex.match(rec_id):
            raise ValueError(f"Record {idx} invalid id: {rec_id!r}")
        if rec_id in seen_ids:
            raise ValueError(f"Duplicate id: {rec_id}")
        seen_ids.add(rec_id)

        if rec["body_part"] not in body_part_enum:
            raise ValueError(f"Record {rec_id} invalid body_part: {rec['body_part']!r}")

        for str_key in ("name", "category", "equipment", "muscle_group", "target", "media_id", "attribution", "created_at"):
            val = rec[str_key]
            if not isinstance(val, str) or not val.strip():
                raise ValueError(f"Record {rec_id} empty/invalid {str_key}")

        if not isinstance(rec["image"], str) or not image_regex.match(rec["image"]):
            raise ValueError(f"Record {rec_id} invalid image: {rec['image']!r}")
        if not isinstance(rec["gif_url"], str) or not gif_regex.match(rec["gif_url"]):
            raise ValueError(f"Record {rec_id} invalid gif_url: {rec['gif_url']!r}")

        sec = rec["secondary_muscles"]
        if not isinstance(sec, list) or not all(isinstance(s, str) and s.strip() for s in sec):
            raise ValueError(f"Record {rec_id} invalid secondary_muscles")

        instructions = rec["instructions"]
        if not isinstance(instructions, dict) or not (lang_keys <= set(instructions.keys())):
            raise ValueError(f"Record {rec_id} missing required instruction languages")
        for lk in lang_keys:
            if not isinstance(instructions[lk], str):
                raise ValueError(f"Record {rec_id} non-string instruction for {lk}")

        steps_map = rec["instruction_steps"]
        if not isinstance(steps_map, dict) or not (step_lang_keys <= set(steps_map.keys())):
            raise ValueError(f"Record {rec_id} missing required instruction_steps languages")
        for lk in step_lang_keys:
            steps = steps_map[lk]
            if not isinstance(steps, list) or not all(isinstance(st, str) and st.strip() for st in steps):
                raise ValueError(f"Record {rec_id} invalid instruction_steps[{lk}]")
        if len(steps_map["en"]) < 1:
            raise ValueError(f"Record {rec_id} has empty English instruction_steps")

        validated.append(rec)

    return validated


def extract_mit_records(raw_records: list[dict]) -> list[dict]:
    records = [
        {
            "id": rec["id"],
            "name": rec["name"],
            "body_part": rec["body_part"],
            "target": rec["target"],
            "equipment": rec["equipment"],
            "muscle_group": rec["muscle_group"],
            "secondary_muscles": rec["secondary_muscles"],
            "instruction_steps": rec["instruction_steps"]["en"],
        }
        for rec in raw_records
    ]
    records.sort(key=lambda r: r["id"])
    return records


def validate_output(path: Path) -> dict[str, int]:
    if not path.is_file():
        raise FileNotFoundError(f"Dataset file not found: {path}")

    size = path.stat().st_size
    if size <= 0 or size >= MAX_OUTPUT_BYTES:
        raise ValueError(f"Dataset file size out of range: {size} bytes (limit < {MAX_OUTPUT_BYTES})")

    raw_text = path.read_text(encoding="utf-8")
    lower_text = raw_text.lower()
    for bad in FORBIDDEN_SUBSTRINGS:
        if bad in lower_text:
            raise ValueError(f"Forbidden substring {bad!r} found in {path}")
    if EMOJI_RE.search(raw_text):
        raise ValueError(f"Emoji character found in {path}")

    data = json.loads(raw_text)
    if not isinstance(data, list) or len(data) != EXPECTED_RECORD_COUNT:
        raise ValueError(f"Expected {EXPECTED_RECORD_COUNT} records in {path}, got {len(data) if isinstance(data, list) else type(data)}")

    seen_ids: set[str] = set()
    body_parts: set[str] = set()
    targets: set[str] = set()

    for idx, rec in enumerate(data):
        if not isinstance(rec, dict) or set(rec.keys()) != MIT_FIELDS:
            raise ValueError(f"Output record {idx} has unexpected keys: {set(rec.keys()) if isinstance(rec, dict) else type(rec)}")
        for k in ("id", "name", "body_part", "target", "equipment", "muscle_group"):
            if not isinstance(rec[k], str) or not rec[k].strip():
                raise ValueError(f"Output record {idx} invalid {k}")
        if rec["id"] in seen_ids:
            raise ValueError(f"Duplicate output id: {rec['id']}")
        seen_ids.add(rec["id"])
        body_parts.add(rec["body_part"])
        targets.add(rec["target"])

        if not isinstance(rec["secondary_muscles"], list) or not all(isinstance(s, str) and s.strip() for s in rec["secondary_muscles"]):
            raise ValueError(f"Output record {rec['id']} invalid secondary_muscles")
        steps = rec["instruction_steps"]
        if not isinstance(steps, list) or len(steps) < 1 or not all(isinstance(s, str) and s.strip() for s in steps):
            raise ValueError(f"Output record {rec['id']} invalid instruction_steps")

    if len(body_parts) != EXPECTED_BODY_PART_COUNT:
        raise ValueError(f"Expected {EXPECTED_BODY_PART_COUNT} body_parts, got {len(body_parts)}")
    if len(targets) != EXPECTED_TARGET_COUNT:
        raise ValueError(f"Expected {EXPECTED_TARGET_COUNT} targets, got {len(targets)}")

    return {
        "records": len(data),
        "bytes": size,
        "body_parts": len(body_parts),
        "targets": len(targets),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--schema-url", default=DEFAULT_SCHEMA_URL)
    parser.add_argument("--data-url", default=DEFAULT_DATA_URL)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args(argv)

    if args.verify_only:
        stats = validate_output(args.output)
        print(f"Verified {args.output}: {stats['records']} records, {stats['bytes']} bytes, {stats['body_parts']} body_parts, {stats['targets']} targets")
        return 0

    schema = _fetch_json(args.schema_url)
    if not isinstance(schema, dict):
        raise ValueError("Schema JSON must be an object")
    raw_records = _fetch_json(args.data_url)
    validated = validate_raw_against_schema(raw_records, schema)
    compact = extract_mit_records(validated)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    serialized = json.dumps(compact, ensure_ascii=False, separators=(",", ":")) + "\n"
    args.output.write_text(serialized, encoding="utf-8", newline="\n")

    stats = validate_output(args.output)
    print(f"Wrote {args.output}: {stats['records']} records, {stats['bytes']} bytes, {stats['body_parts']} body_parts, {stats['targets']} targets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
