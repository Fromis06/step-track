"""Static R2 compliance, asset integrity, and legacy cleanup verifier."""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"

SF_SYMBOL_RE = re.compile(r"systemName\s*:|systemImage\s*:")
EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF\u2600-\u26FF\u2700-\u27BF\uFE0F\u200D]")
ARROW_GLYPH_RE = re.compile(r"[\u2192\u2190\u2191\u2193\u279C\u27A4\u25BA\u25B8\u2022\u25CF\u25C6\u25A0\u25A1\u2713\u2714\u2715\u2716\u2717\u2718]")
FILLER_PATTERNS = (
    re.compile(r"\btap\s+(?:here|to|on|any)\b", re.IGNORECASE),
    re.compile(r"\bclick\s+(?:here|to|on)\b", re.IGNORECASE),
    re.compile(r"\bhold\s+home\s+screen\b", re.IGNORECASE),
    re.compile(r"\b\d+\s+color\s+modes?\b", re.IGNORECASE),
    re.compile(r"\byou\s+can\s+(?:tap|swipe|scroll|drag|use|choose|select)\b", re.IGNORECASE),
    re.compile(r"\bpull\s+to\s+refresh\b", re.IGNORECASE),
    re.compile(r"\bdrag\s+to\s+rotate\b", re.IGNORECASE),
    re.compile(r"\bmanage\s+access\s+in\b", re.IGNORECASE),
    re.compile(r"\bopen\s+the\s+app\s+every\s+few\s+days\b", re.IGNORECASE),
)

SWIFT_STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
STRINGS_ENTRY_RE = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"')

LEGACY_PATHS = (
    "Steps",
    "StepsWidget",
    "StepsTests",
    "Steps.xcodeproj",
    "ConfigTemplate.xcconfig",
    "StepsWidgetExtension.entitlements",
    "README.upstream.md",
    ".github/FUNDING.yml",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
)


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load module {name} from {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _iter_files(roots: tuple[Path, ...], suffixes: tuple[str, ...]) -> list[Path]:
    found: list[Path] = []
    for root in roots:
        if root.is_file():
            if root.suffix in suffixes:
                found.append(root)
        elif root.is_dir():
            for path in sorted(root.rglob("*")):
                if path.is_file() and path.suffix in suffixes:
                    found.append(path)
    return found


def check_legacy_removed() -> list[str]:
    issues: list[str] = []
    for rel in LEGACY_PATHS:
        if (REPO_ROOT / rel).exists():
            issues.append(f"Legacy path still exists: {rel}")
    if not (REPO_ROOT / "LICENSE").is_file():
        issues.append("Required MIT LICENSE file is missing")
    return issues


def check_sf_symbols() -> list[str]:
    issues: list[str] = []
    for path in _iter_files((REPO_ROOT / "StepTrack", REPO_ROOT / "Tests"), (".swift",)):
        for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if SF_SYMBOL_RE.search(line):
                issues.append(f"{path.relative_to(REPO_ROOT)}:{i}: {line.strip()}")
    return issues


def check_emojis() -> list[str]:
    issues: list[str] = []
    scan_roots = (
        REPO_ROOT / "StepTrack",
        REPO_ROOT / "Tests",
        REPO_ROOT / "scripts",
        REPO_ROOT / "README.md",
        REPO_ROOT / "BUILD-IPHONE.md",
    )
    for path in _iter_files(scan_roots, (".swift", ".json", ".strings", ".py", ".md", ".svg")):
        for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if EMOJI_RE.search(line):
                issues.append(f"{path.relative_to(REPO_ROOT)}:{i}: emoji detected")
    return issues


def _extract_ui_strings(path: Path) -> list[tuple[int, str]]:
    results: list[tuple[int, str]] = []
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".swift":
        for i, line in enumerate(text.splitlines(), 1):
            for m in SWIFT_STRING_RE.finditer(line):
                results.append((i, m.group(1)))
    elif path.suffix == ".strings":
        for i, line in enumerate(text.splitlines(), 1):
            for m in STRINGS_ENTRY_RE.finditer(line):
                results.append((i, m.group(2)))
    elif path.name == "Translations.json":
        data = json.loads(text)
        lines = text.splitlines()
        for key, langs in data.items():
            line_no = next((idx for idx, l in enumerate(lines, 1) if f'"{key}"' in l), 1)
            results.append((line_no, key))
            if isinstance(langs, dict):
                for val in langs.values():
                    if isinstance(val, str):
                        results.append((line_no, val))
    return results


def check_arrow_glyphs() -> list[str]:
    issues: list[str] = []
    files = _iter_files((REPO_ROOT / "StepTrack", REPO_ROOT / "Tests"), (".swift", ".strings")) + [
        REPO_ROOT / "StepTrack/Core/Localization/Translations.json"
    ]
    for path in files:
        if not path.is_file():
            continue
        for line_no, text in _extract_ui_strings(path):
            if ARROW_GLYPH_RE.search(text):
                issues.append(f"{path.relative_to(REPO_ROOT)}:{line_no}: arrow/glyph icon in {text!r}")
    return issues


def check_filler_copy() -> list[str]:
    issues: list[str] = []
    files = _iter_files((REPO_ROOT / "StepTrack",), (".swift", ".strings")) + [
        REPO_ROOT / "StepTrack/Core/Localization/Translations.json"
    ]
    for path in files:
        if not path.is_file():
            continue
        for line_no, text in _extract_ui_strings(path):
            for pat in FILLER_PATTERNS:
                if pat.search(text):
                    issues.append(f"{path.relative_to(REPO_ROOT)}:{line_no}: filler phrase ({pat.pattern}) in {text!r}")
                    break
    return issues


def check_svg_icons() -> str:
    mod = _load_module("prepare_svg_icons", SCRIPTS_DIR / "prepare-svg-icons.py")
    count = mod.validate_icons(REPO_ROOT / "StepTrack/Resources/Assets.xcassets")
    return f"{count} valid template SVG imagesets"


def check_exercises_dataset() -> str:
    mod = _load_module("prepare_exercises_dataset", SCRIPTS_DIR / "prepare-exercises-dataset.py")
    stats = mod.validate_output(REPO_ROOT / "StepTrack/Resources/Datasets/exercises.json")
    return f"{stats['records']} records, {stats['bytes']} bytes, {stats['body_parts']} body_parts, {stats['targets']} targets"


def check_body_mesh() -> str:
    mod = _load_module("generate_body_mesh", SCRIPTS_DIR / "generate-body-mesh.py")
    stats = mod.validate_obj(REPO_ROOT / "StepTrack/Resources/Models3D/human_body.obj")
    return f"{stats['groups']} groups, {stats['triangles']} triangles, {stats['bytes']} bytes"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--strict", action="store_true", help="Enforce all 7 checks and legacy cleanup (default)")
    mode.add_argument("--m1-assets-only", action="store_true", help="Strictly enforce emojis/assets/legacy; mark Swift UI & Translations debt as [M1-DEFERRED]")
    args = parser.parse_args(argv)

    m1_mode = args.m1_assets_only
    failures: list[str] = []

    # 0. Legacy cleanup
    legacy_issues = check_legacy_removed()
    if legacy_issues:
        failures.extend(f"[LEGACY] {item}" for item in legacy_issues)
    else:
        print("[PASS] Legacy cleanup & MIT LICENSE")

    # 1. SF Symbols
    sf_issues = check_sf_symbols()
    if sf_issues:
        tag = "[M1-DEFERRED]" if m1_mode else "[FAIL]"
        print(f"{tag} SF Symbols: {len(sf_issues)} occurrences")
        for item in sf_issues:
            print(f"  - {item}")
        if not m1_mode:
            failures.extend(sf_issues)
    else:
        print("[PASS] Zero SF Symbols")

    # 2. Emojis
    emoji_issues = check_emojis()
    if emoji_issues:
        print(f"[FAIL] Unicode Emojis: {len(emoji_issues)} occurrences")
        for item in emoji_issues:
            print(f"  - {item}")
        failures.extend(emoji_issues)
    else:
        print("[PASS] Zero Unicode Emojis")

    # 3. Keyboard arrow/glyph icons
    arrow_issues = check_arrow_glyphs()
    if arrow_issues:
        tag = "[M1-DEFERRED]" if m1_mode else "[FAIL]"
        print(f"{tag} Keyboard Arrow/Glyph Icons: {len(arrow_issues)} occurrences")
        for item in arrow_issues:
            print(f"  - {item}")
        if not m1_mode:
            failures.extend(arrow_issues)
    else:
        print("[PASS] Zero Keyboard Arrow/Glyph Icons")

    # 4. Instructional filler copy
    filler_issues = check_filler_copy()
    if filler_issues:
        tag = "[M1-DEFERRED]" if m1_mode else "[FAIL]"
        print(f"{tag} Instructional Filler Copy: {len(filler_issues)} occurrences")
        for item in filler_issues:
            print(f"  - {item}")
        if not m1_mode:
            failures.extend(filler_issues)
    else:
        print("[PASS] Zero Instructional Filler Copy")

    # 5. SVG imagesets
    try:
        print(f"[PASS] SVG Icons: {check_svg_icons()}")
    except Exception as exc:  # noqa: BLE001
        print(f"[FAIL] SVG Icons: {exc}")
        failures.append(str(exc))

    # 6. Exercises dataset
    try:
        print(f"[PASS] Exercises Dataset: {check_exercises_dataset()}")
    except Exception as exc:  # noqa: BLE001
        print(f"[FAIL] Exercises Dataset: {exc}")
        failures.append(str(exc))

    # 7. 3D body mesh
    try:
        print(f"[PASS] 3D Body Mesh: {check_body_mesh()}")
    except Exception as exc:  # noqa: BLE001
        print(f"[FAIL] 3D Body Mesh: {exc}")
        failures.append(str(exc))

    if failures:
        print(f"\nCompliance check FAILED ({len(failures)} blocking issue(s)).")
        return 1

    print("\nCompliance check PASSED." + (" (M1 asset-only mode; deferred Swift/copy items tracked above)" if m1_mode else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
