"""Static repository layout, XcodeGen specs, GitHub Actions CI, and sideload contract tests.

Covers F1 (T1/T2), F2 (T1/T2), P17, and P19 from TEST_INFRA.md.
"""
from __future__ import annotations

import fnmatch
import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path, PurePosixPath

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]


class _UniqueKeySafeLoader(yaml.SafeLoader):
    """YAML SafeLoader that rejects duplicate mapping keys (T2-F02-05)."""


def _construct_mapping_no_duplicates(loader: _UniqueKeySafeLoader, node: yaml.MappingNode, deep: bool = False) -> dict:
    mapping: dict = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise ValueError(f"Duplicate YAML mapping key detected: {key!r}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


_UniqueKeySafeLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    _construct_mapping_no_duplicates,
)


def _load_yaml_strict(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    data = yaml.load(text, Loader=_UniqueKeySafeLoader)
    if not isinstance(data, dict):
        raise AssertionError(f"Expected YAML mapping at root of {path}, got {type(data).__name__}")
    return data


def _path_exists_exact_case(rel_path: str) -> bool:
    """Verify rel_path exists under REPO_ROOT with exact segment-by-segment casing."""
    parts = [p for p in PurePosixPath(rel_path.replace("\\", "/")).parts if p not in ("", ".")]
    current = REPO_ROOT
    for part in parts:
        if not current.is_dir():
            return False
        try:
            entries = {child.name for child in current.iterdir()}
        except OSError:
            return False
        if part not in entries:
            return False
        current = current / part
    return current.exists()


def _resolve_build_vars(value: str, base_settings: dict) -> str:
    def _repl(match: re.Match[str]) -> str:
        var_name = match.group(1)
        if var_name in base_settings:
            return str(base_settings[var_name])
        return match.group(0)

    resolved = value
    for _ in range(4):
        next_val = re.sub(r"\$\(([^)]+)\)", _repl, resolved)
        if next_val == resolved:
            break
        resolved = next_val
    return resolved


def _get_workflow_on(workflow: dict) -> dict:
    # PyYAML 1.1 parses unquoted `on:` as boolean True.
    if "on" in workflow:
        return workflow["on"]
    if True in workflow:
        return workflow[True]
    raise KeyError("Workflow missing 'on' trigger block")


def _glob_match_posix(rel_posix: str, pattern: str) -> bool:
    """Match a POSIX relative path against a GitHub Actions path glob."""
    # Convert GitHub Actions glob (`**`, `*`) to regex.
    regex_parts: list[str] = ["^"]
    i = 0
    n = len(pattern)
    while i < n:
        if pattern[i : i + 2] == "**":
            if i + 2 < n and pattern[i + 2] == "/":
                regex_parts.append("(?:.+/)?")
                i += 3
            else:
                regex_parts.append(".*")
                i += 2
        elif pattern[i] == "*":
            regex_parts.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            regex_parts.append("[^/]")
            i += 1
        else:
            regex_parts.append(re.escape(pattern[i]))
            i += 1
    regex_parts.append("$")
    return re.match("".join(regex_parts), rel_posix) is not None


def _contains_dict_key(obj: object, target_key: str) -> bool:
    """Recursively check whether any nested dict in obj defines target_key."""
    if isinstance(obj, dict):
        if target_key in obj:
            return True
        return any(_contains_dict_key(v, target_key) for v in obj.values())
    if isinstance(obj, list):
        return any(_contains_dict_key(item, target_key) for item in obj)
    return False


def _strip_shell_comments(script: str) -> str:
    """Remove shell # comments (full-line and trailing outside quotes) from CI run scripts."""
    cleaned_lines: list[str] = []
    for line in script.splitlines():
        out: list[str] = []
        in_single = False
        in_double = False
        escaped = False
        for i, ch in enumerate(line):
            if escaped:
                out.append(ch)
                escaped = False
                continue
            if ch == "\\" and not in_single:
                out.append(ch)
                escaped = True
                continue
            if ch == "'" and not in_double:
                in_single = not in_single
                out.append(ch)
            elif ch == '"' and not in_single:
                in_double = not in_double
                out.append(ch)
            elif ch == "#" and not in_single and not in_double:
                if i == 0 or line[i - 1].isspace():
                    break
                out.append(ch)
            else:
                out.append(ch)
        stripped = "".join(out).strip()
        if stripped:
            cleaned_lines.append(stripped)
    return "\n".join(cleaned_lines)


class TestF1RepositoryRestructure(unittest.TestCase):
    """F1: Clean StepTrack/ + Tests/ layout and retired legacy paths."""

    def test_T1_F01_01_required_directories_exist(self) -> None:
        required_dirs = (
            "StepTrack/App",
            "StepTrack/Core",
            "StepTrack/Features",
            "StepTrack/Resources",
            "StepTrack/Config",
            "StepTrack/Widget",
            "Tests/UnitTests",
            "Tests/StepsTests",
            "Tests/UITests",
            "Tests/E2EStaticTests",
            "scripts",
        )
        for rel in required_dirs:
            with self.subTest(directory=rel):
                self.assertTrue(_path_exists_exact_case(rel), f"Missing required directory (case-exact): {rel}")
                self.assertTrue((REPO_ROOT / rel).is_dir(), f"Expected directory at: {rel}")

    def test_T1_F01_02_legacy_paths_retired(self) -> None:
        retired_paths = (
            "Steps",
            "StepsWidget",
            "Steps.xcodeproj",
            "StepsTests",
            "ConfigTemplate.xcconfig",
            "StepsWidgetExtension.entitlements",
            "README.upstream.md",
            ".github/FUNDING.yml",
            "CODE_OF_CONDUCT.md",
            "CONTRIBUTING.md",
        )
        for rel in retired_paths:
            with self.subTest(legacy_path=rel):
                self.assertFalse((REPO_ROOT / rel).exists(), f"Legacy path must be retired: {rel}")
        self.assertTrue((REPO_ROOT / "LICENSE").is_file(), "Root MIT LICENSE file must exist")

    def test_T1_F01_03_xcodegen_source_paths_resolve(self) -> None:
        for spec_name in ("project-sideload.yml", "project.yml"):
            spec = _load_yaml_strict(REPO_ROOT / spec_name)
            targets = spec.get("targets", {})
            self.assertTrue(targets, f"{spec_name} must define targets")
            for target_name, target_cfg in targets.items():
                for src in target_cfg.get("sources", []):
                    src_path = src if isinstance(src, str) else src["path"]
                    with self.subTest(spec=spec_name, target=target_name, source=src_path):
                        self.assertTrue(
                            (REPO_ROOT / src_path).exists(),
                            f"{spec_name} target {target_name} references missing path: {src_path}",
                        )

    def test_T1_F01_04_steps_tests_migrated_cleanly(self) -> None:
        steps_tests_dir = REPO_ROOT / "Tests/StepsTests"
        swift_files = sorted(steps_tests_dir.glob("*.swift"))
        self.assertGreaterEqual(len(swift_files), 1, "Tests/StepsTests must contain migrated Swift test files")
        forbidden_imports = (
            "@testable import Steps",
            "import Steps\n",
            "import Dependencies",
            "import ComposableArchitecture",
            "import CoreData",
        )
        for path in swift_files:
            content = path.read_text(encoding="utf-8")
            with self.subTest(file=path.name):
                self.assertIn("@testable import StepTrack", content, f"{path.name} must import StepTrack")
                for bad in forbidden_imports:
                    self.assertNotIn(bad, content, f"{path.name} contains forbidden legacy import {bad!r}")

    def test_T1_F01_05_no_teamwork_metadata_or_ds_store(self) -> None:
        forbidden_names = {
            "BRIEFING.md",
            "progress.md",
            "HANDOFF.md",
            "handoff.md",
            "DISPATCH.md",
            ".agents",
            ".DS_Store",
        }
        skip_dirs = {".git", "build", ".tools", "__pycache__"}
        violations: list[str] = []
        for root, dirs, files in os.walk(REPO_ROOT):
            dirs[:] = [d for d in dirs if d not in skip_dirs]
            for name in dirs + files:
                if name in forbidden_names:
                    violations.append(str((Path(root) / name).relative_to(REPO_ROOT)))
        self.assertEqual(violations, [], f"Forbidden metadata/clutter found inside repo: {violations}")

    def test_T2_F01_01_no_stray_swift_files(self) -> None:
        skip_dirs = {".git", "build", ".build", ".tools", "DerivedData"}
        stray: list[str] = []
        for root, dirs, files in os.walk(REPO_ROOT):
            dirs[:] = [d for d in dirs if d not in skip_dirs]
            for name in files:
                if name.endswith(".swift"):
                    rel = (Path(root) / name).relative_to(REPO_ROOT).as_posix()
                    if not (rel.startswith("StepTrack/") or rel.startswith("Tests/")):
                        stray.append(rel)
        self.assertEqual(stray, [], f"Stray .swift files outside StepTrack/ and Tests/: {stray}")

    def test_T2_F01_02_config_gitkeep_and_gitignore(self) -> None:
        self.assertTrue((REPO_ROOT / "StepTrack/Config/.gitkeep").is_file(), "StepTrack/Config/.gitkeep missing")
        gitignore_text = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")
        required_patterns = (
            "build/",
            "*.ipa",
            "StepTrack.xcodeproj/",
            "StepTrackSideload.xcodeproj/",
            "StepTrack/Config/*.plist",
            "StepTrack/Config/*.entitlements",
        )
        for pat in required_patterns:
            with self.subTest(pattern=pat):
                self.assertIn(pat, gitignore_text, f".gitignore missing expected rule {pat!r}")

        if (REPO_ROOT / ".git").exists() and shutil.which("git"):
            sample_ignored = (
                "StepTrack.xcodeproj/",
                "StepTrackSideload.xcodeproj/",
                "StepTrack/Config/Sideload-Info.plist",
                "StepTrack/Config/StepTrack.entitlements",
                "build/StepTrack-sideload-unsigned.ipa",
                "StepTrack-sideload-unsigned.ipa",
            )
            for sample in sample_ignored:
                with self.subTest(git_check_ignore=sample):
                    proc = subprocess.run(
                        ["git", "check-ignore", "-q", sample],
                        cwd=REPO_ROOT,
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(proc.returncode, 0, f"git check-ignore did not ignore {sample!r}")

    def test_T2_F01_03_no_resource_flattening_collisions(self) -> None:
        resources_root = REPO_ROOT / "StepTrack/Resources"
        flat_basenames: dict[str, list[str]] = {}
        for path in sorted(resources_root.rglob("*")):
            if not path.is_file():
                continue
            rel_parts = path.relative_to(resources_root).parts
            if any(part.endswith(".xcassets") or part.endswith(".lproj") for part in rel_parts):
                continue
            if path.name == ".gitkeep":
                continue
            flat_basenames.setdefault(path.name, []).append(path.relative_to(REPO_ROOT).as_posix())

        # Also check non-Swift resource files under StepTrack/Core (e.g. Translations.json)
        for path in sorted((REPO_ROOT / "StepTrack/Core").rglob("*")):
            if path.is_file() and path.suffix not in (".swift",) and path.name != ".gitkeep":
                flat_basenames.setdefault(path.name, []).append(path.relative_to(REPO_ROOT).as_posix())

        collisions = {name: paths for name, paths in flat_basenames.items() if len(paths) > 1}
        self.assertEqual(collisions, {}, f"Resource flattening filename collisions: {collisions}")

        # Verify unique .imageset slugs and .svg filenames inside Icons/
        icons_dir = resources_root / "Assets.xcassets/Icons"
        imagesets = [p for p in icons_dir.iterdir() if p.is_dir() and p.name.endswith(".imageset")]
        self.assertEqual(len(imagesets), len({p.name for p in imagesets}))
        svg_names = [p.name for p in icons_dir.rglob("*.svg")]
        self.assertEqual(len(svg_names), len(set(svg_names)), "Duplicate SVG filenames inside Icons/")

        # Verify matching file sets across all 4 .lproj bundles
        loc_root = resources_root / "Localization"
        lproj_files = {}
        for lang in ("en", "vi", "ja", "es"):
            lproj = loc_root / f"{lang}.lproj"
            self.assertTrue(lproj.is_dir(), f"Missing locale bundle {lproj}")
            lproj_files[lang] = sorted(p.name for p in lproj.iterdir() if p.is_file())
        baseline = lproj_files["en"]
        for lang, names in lproj_files.items():
            self.assertEqual(names, baseline, f"{lang}.lproj file list {names} differs from en.lproj {baseline}")

    def test_T2_F01_04_case_sensitive_xcodegen_paths(self) -> None:
        for spec_name in ("project-sideload.yml", "project.yml"):
            spec = _load_yaml_strict(REPO_ROOT / spec_name)
            for target_name, target_cfg in spec.get("targets", {}).items():
                for src in target_cfg.get("sources", []):
                    if isinstance(src, str):
                        with self.subTest(spec=spec_name, target=target_name, path=src):
                            self.assertTrue(_path_exists_exact_case(src), f"Case mismatch or missing path: {src}")
                    else:
                        base = src["path"]
                        with self.subTest(spec=spec_name, target=target_name, path=base):
                            self.assertTrue(_path_exists_exact_case(base), f"Case mismatch or missing path: {base}")
                        for excl in src.get("excludes", []):
                            if "*" in excl or "?" in excl:
                                continue
                            rel_excl = (PurePosixPath(base) / excl).as_posix()
                            with self.subTest(spec=spec_name, target=target_name, exclude=rel_excl):
                                self.assertTrue(
                                    _path_exists_exact_case(rel_excl),
                                    f"Case mismatch or missing excluded path: {rel_excl}",
                                )

    def test_T2_F01_05_no_agents_or_gemini_md(self) -> None:
        skip_dirs = {".git", ".tools"}
        found: list[str] = []
        for root, dirs, files in os.walk(REPO_ROOT):
            dirs[:] = [d for d in dirs if d not in skip_dirs]
            for name in files:
                if name in ("AGENTS.md", "GEMINI.md"):
                    found.append(str((Path(root) / name).relative_to(REPO_ROOT)))
        self.assertEqual(found, [], f"Forbidden agent rule files found in repo: {found}")


class TestF2BuildAndGitHubCI(unittest.TestCase):
    """F2: XcodeGen specs and GitHub Actions unsigned sideload .ipa workflow."""

    def test_T1_F02_01_ci_workflow_triggers(self) -> None:
        workflow = _load_yaml_strict(REPO_ROOT / ".github/workflows/build-ios.yml")
        on_cfg = _get_workflow_on(workflow)
        expected_paths = {
            "StepTrack/**",
            "Tests/**",
            "project*.yml",
            "scripts/**",
            ".github/workflows/build-ios.yml",
        }
        for trigger in ("push", "pull_request"):
            self.assertIn(trigger, on_cfg, f"Workflow missing {trigger} trigger")
            paths = set(on_cfg[trigger].get("paths", []))
            self.assertTrue(
                expected_paths <= paths,
                f"{trigger}.paths missing entries: {sorted(expected_paths - paths)}",
            )
        self.assertIn("workflow_dispatch", on_cfg, "Workflow missing workflow_dispatch trigger")

    def test_T1_F02_02_ci_steps_test_build_package_ipa(self) -> None:
        workflow = _load_yaml_strict(REPO_ROOT / ".github/workflows/build-ios.yml")
        job = workflow["jobs"]["build"]
        self.assertEqual(job.get("runs-on"), "macos-15")
        self.assertIn("sideload", job["strategy"]["matrix"]["flavor"])

        steps = job["steps"]
        uses_list = [s.get("uses", "") for s in steps if "uses" in s]
        self.assertTrue(any(u.startswith("actions/checkout@") for u in uses_list))
        self.assertTrue(any(u.startswith("actions/upload-artifact@") for u in uses_list))

        combined_run = "\n".join(s.get("run", "") for s in steps)
        required_fragments = (
            "xcodegen generate --spec project-sideload.yml",
            "xcodebuild test -project StepTrackSideload.xcodeproj -scheme StepTrack",
            "xcodebuild build",
            "-sdk iphoneos",
            "CODE_SIGNING_ALLOWED=NO",
            "ditto build/device/Build/Products/Release-iphoneos/StepTrack.app build/package/Payload/StepTrack.app",
            "exercises.json",
            "human_body.obj",
            "human_body.mtl",
            "Translations.json",
            'zip -qry "../StepTrack-$FLAVOR-unsigned.ipa" Payload',
        )
        for frag in required_fragments:
            with self.subTest(fragment=frag):
                self.assertIn(frag, combined_run, f"Workflow steps missing {frag!r}")

        ipa_upload_paths = [
            str(s.get("with", {}).get("path", ""))
            for s in steps
            if s.get("uses", "").startswith("actions/upload-artifact@")
        ]
        self.assertTrue(
            any("StepTrack-*-unsigned.ipa" in p for p in ipa_upload_paths),
            f"No upload-artifact step uploads StepTrack-*-unsigned.ipa (found {ipa_upload_paths})",
        )

    def test_T1_F02_03_sideload_build_settings(self) -> None:
        spec = _load_yaml_strict(REPO_ROOT / "project-sideload.yml")
        self.assertEqual(str(spec["options"]["deploymentTarget"]["iOS"]), "17.0")
        base_settings = spec.get("settings", {}).get("base", {})
        target_settings = spec["targets"]["StepTrack"]["settings"]["base"]

        conditions = str(target_settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", ""))
        self.assertIn("MOTION_ONLY", conditions.split(), f"MOTION_ONLY missing in {conditions!r}")

        raw_bundle_id = str(target_settings.get("PRODUCT_BUNDLE_IDENTIFIER", ""))
        resolved_bundle_id = _resolve_build_vars(raw_bundle_id, base_settings)
        self.assertEqual(resolved_bundle_id, "com.personal.steptrack.sideload")

    def test_T1_F02_04_sideload_info_plist_and_no_restricted_entitlements(self) -> None:
        sideload_path = REPO_ROOT / "project-sideload.yml"
        spec = _load_yaml_strict(sideload_path)
        app_target = spec["targets"]["StepTrack"]
        info_props = app_target.get("info", {}).get("properties", {})
        motion_desc = info_props.get("NSMotionUsageDescription", "")
        self.assertIsInstance(motion_desc, str)
        self.assertTrue(motion_desc.strip(), "Sideload Info.plist must define non-empty NSMotionUsageDescription")
        self.assertNotIn("entitlements", app_target, "Sideload StepTrack target must not declare restricted entitlements")
        self.assertFalse(
            _contains_dict_key(spec, "CODE_SIGN_ENTITLEMENTS"),
            "project-sideload.yml must not set CODE_SIGN_ENTITLEMENTS anywhere in parsed YAML",
        )

        raw_text = sideload_path.read_text(encoding="utf-8")
        raw_lower = raw_text.lower()
        self.assertNotIn("CODE_SIGN_ENTITLEMENTS", raw_text, "project-sideload.yml must not contain CODE_SIGN_ENTITLEMENTS")
        for forbidden in (
            "com.apple.developer.healthkit",
            "application-groups",
            "aps-environment",
            "icloud",
            "code_sign_entitlements",
        ):
            self.assertNotIn(forbidden, raw_lower, f"project-sideload.yml must not reference {forbidden!r}")

    def test_T1_F02_05_project_yml_full_targets_valid(self) -> None:
        spec = _load_yaml_strict(REPO_ROOT / "project.yml")
        targets = spec.get("targets", {})
        expected_types = {
            "StepTrack": "application",
            "StepTrackWidget": "app-extension",
            "StepTrackTests": "bundle.unit-test",
            "StepsTests": "bundle.unit-test",
            "StepTrackUITests": "bundle.ui-testing",
        }
        for name, expected_type in expected_types.items():
            self.assertIn(name, targets, f"project.yml missing target {name}")
            self.assertEqual(targets[name].get("type"), expected_type)

        app_deps = targets["StepTrack"].get("dependencies", [])
        self.assertTrue(
            any(d.get("target") == "StepTrackWidget" and d.get("embed") is True for d in app_deps),
            "project.yml StepTrack target must embed StepTrackWidget",
        )
        test_targets = spec["schemes"]["StepTrack"]["test"]["targets"]
        self.assertEqual(set(test_targets), {"StepTrackTests", "StepsTests", "StepTrackUITests"})

    def test_T2_F02_01_sideload_scheme_testables(self) -> None:
        spec = _load_yaml_strict(REPO_ROOT / "project-sideload.yml")
        test_targets = spec["schemes"]["StepTrack"]["test"]["targets"]
        self.assertEqual(test_targets, ["StepTrackTests", "StepsTests", "StepTrackUITests"])

    def test_T2_F02_02_ci_runs_r2_compliance_gate(self) -> None:
        r2_script = REPO_ROOT / "scripts/verify-r2-compliance.py"
        self.assertTrue(r2_script.is_file(), "scripts/verify-r2-compliance.py must exist")
        if os.environ.get("STEPTRACK_REQUIRE_FULL_R2") != "1":
            self.skipTest("CI workflow R2 gate step pending M5 unless STEPTRACK_REQUIRE_FULL_R2=1")
        workflow = _load_yaml_strict(REPO_ROOT / ".github/workflows/build-ios.yml")
        steps = workflow["jobs"]["build"]["steps"]
        run_scripts = [
            _strip_shell_comments(step["run"])
            for step in steps
            if isinstance(step, dict) and isinstance(step.get("run"), str)
        ]
        combined_run = "\n".join(s for s in run_scripts if s)
        self.assertIn("verify-r2-compliance.py", combined_run)
        self.assertIn("E2EStaticTests", combined_run)

    def test_T2_F02_03_sideload_info_plist_omits_healthkit(self) -> None:
        spec = _load_yaml_strict(REPO_ROOT / "project-sideload.yml")
        info_props = spec["targets"]["StepTrack"]["info"]["properties"]
        for forbidden_key in (
            "NSHealthShareUsageDescription",
            "NSHealthUpdateUsageDescription",
            "AppGroupIdentifier",
            "UIRequiredDeviceCapabilities",
        ):
            self.assertNotIn(
                forbidden_key,
                info_props,
                f"Sideload Info.plist must omit {forbidden_key!r} when MOTION_ONLY is active",
            )

    def test_T2_F02_04_sideload_excludes_widget_sources(self) -> None:
        spec = _load_yaml_strict(REPO_ROOT / "project-sideload.yml")
        targets = spec["targets"]
        self.assertNotIn("StepTrackWidget", targets)
        app_target = targets["StepTrack"]
        self.assertEqual(app_target.get("dependencies", []), [])
        for src in app_target.get("sources", []):
            if isinstance(src, str):
                self.assertNotEqual(src.rstrip("/"), "StepTrack")
                self.assertNotIn("Widget", src)
            else:
                base = src["path"].rstrip("/")
                if base == "StepTrack":
                    self.assertIn("StepTrack/Widget", src.get("excludes", []))
                else:
                    self.assertNotIn("Widget", base)

    def test_T2_F02_05_yaml_syntax_and_no_duplicate_keys(self) -> None:
        for rel in ("project-sideload.yml", "project.yml", ".github/workflows/build-ios.yml"):
            with self.subTest(yaml_file=rel):
                data = _load_yaml_strict(REPO_ROOT / rel)
                self.assertGreater(len(data), 0)


class TestP17AndP19CrossFeatureContracts(unittest.TestCase):
    """P17 (Sideload MOTION_ONLY & fallback contract) and P19 (CI path trigger coverage)."""

    def test_T3_P17_sideload_motion_only_and_fallback_contract(self) -> None:
        spec = _load_yaml_strict(REPO_ROOT / "project-sideload.yml")
        self.assertIn("MOTION_ONLY", str(spec["targets"]["StepTrack"]["settings"]["base"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]))
        self.assertNotIn("entitlements", spec["targets"]["StepTrack"])
        self.assertNotIn("StepTrackWidget", spec["targets"])

        cap_swift = (REPO_ROOT / "StepTrack/Core/Services/CapabilityService.swift").read_text(encoding="utf-8")
        self.assertIn("static func decodeEntitlements", cap_swift)
        self.assertIn('forResource: "embedded", withExtension: "mobileprovision"', cap_swift)
        self.assertIn("return nil", cap_swift)
        self.assertIn("sharedContainerAvailable", cap_swift)

        storage_swift = (REPO_ROOT / "StepTrack/Core/Persistence/ActivityStorage.swift").read_text(encoding="utf-8")
        self.assertIn("sharedDefaults ?? .standard", storage_swift)

        store_swift = (REPO_ROOT / "StepTrack/Core/Services/ActivityStore.swift").read_text(encoding="utf-8")
        self.assertIn("#if MOTION_ONLY", store_swift)
        self.assertIn("!Self.motionOnly", store_swift)
        self.assertIn("CMPedometer.isStepCountingAvailable()", store_swift)

    def test_T3_P19_ci_path_triggers_cover_all_sources_and_tests(self) -> None:
        workflow = _load_yaml_strict(REPO_ROOT / ".github/workflows/build-ios.yml")
        on_cfg = _get_workflow_on(workflow)
        push_globs = list(on_cfg["push"]["paths"])
        pr_globs = list(on_cfg["pull_request"]["paths"])

        sample_files = [
            "StepTrack/App/StepTrackApp.swift",
            "StepTrack/Core/Services/CapabilityService.swift",
            "StepTrack/Resources/Datasets/exercises.json",
            "StepTrack/Resources/Models3D/human_body.obj",
            "Tests/StepsTests/StepsTests.swift",
            "Tests/UnitTests/SigningStatusTests.swift",
            "Tests/UITests/LanguageSwitchTests.swift",
            "Tests/E2EStaticTests/test_repo_and_ci.py",
            "scripts/verify-r2-compliance.py",
            "project.yml",
            "project-sideload.yml",
            ".github/workflows/build-ios.yml",
        ]
        # Verify every sample file exists on disk and matches both push and pull_request path triggers
        for rel in sample_files:
            with self.subTest(rel_path=rel):
                self.assertTrue((REPO_ROOT / rel).exists(), f"Expected sample file missing: {rel}")
                self.assertTrue(
                    any(_glob_match_posix(rel, g) for g in push_globs),
                    f"{rel!r} does not match push.paths {push_globs}",
                )
                self.assertTrue(
                    any(_glob_match_posix(rel, g) for g in pr_globs),
                    f"{rel!r} does not match pull_request.paths {pr_globs}",
                )
        # Sanity check that fnmatch also agrees on non-recursive filename globs
        self.assertTrue(fnmatch.fnmatch("project-sideload.yml", "project*.yml"))


if __name__ == "__main__":
    unittest.main()
