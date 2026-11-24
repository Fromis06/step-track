"""Fetch Lucide SVGs and build template-ready SVG .imageset assets."""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ASSETS_DIR = REPO_ROOT / "StepTrack/Resources/Assets.xcassets"
DEFAULT_VERSION = "1.78.0"

LUCIDE_SLUGS: tuple[str, ...] = (
    "home",
    "dumbbell",
    "person-standing",
    "heart-pulse",
    "bar-chart-3",
    "footprints",
    "route",
    "target",
    "flame",
    "bar-chart-2",
    "smartphone",
    "heart",
    "alert-circle",
    "arrow-up-right",
    "calendar-days",
    "timer",
    "play",
    "pause",
    "rotate-ccw",
    "trophy",
    "plus",
    "minus",
    "check-circle-2",
    "circle",
    "refresh-cw",
    "rotate-3d",
    "search",
    "sliders-horizontal",
    "book-open",
    "layers",
    "moon",
    "utensils",
    "droplets",
    "scale",
    "chevron-left",
    "chevron-right",
    "trending-up",
    "trending-down",
    "settings",
    "sun",
    "palette",
    "globe",
    "download",
    "upload",
    "trash-2",
    "x",
    "pencil",
    "user",
    "lock",
    "check",
    "clock",
    "activity",
    "shield-check",
    "chevron-down",
    "chevron-up",
    "sparkles",
    "zap",
)

CUSTOM_ANATOMICAL_SVGS: dict[str, str] = {
    "body-front": (
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '
        'fill="none" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
        '<circle cx="12" cy="4.5" r="2.2" />'
        '<path d="M6.5 9.5a2 2 0 0 1 2-1.5h7a2 2 0 0 1 2 1.5l1 4.5-2 .6-.8-3.6v9.5h-2.5v-5.5h-2.4v5.5H8.3V11l-.8 3.6-2-.6 1-4.5Z" />'
        '<path d="M9.5 11.2h5" />'
        '<path d="M12 11.2v4.3" />'
        "</svg>\n"
    ),
    "body-back": (
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '
        'fill="none" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
        '<circle cx="12" cy="4.5" r="2.2" />'
        '<path d="M6.5 9.5a2 2 0 0 1 2-1.5h7a2 2 0 0 1 2 1.5l1 4.5-2 .6-.8-3.6v9.5h-2.5v-5.5h-2.4v5.5H8.3V11l-.8 3.6-2-.6 1-4.5Z" />'
        '<path d="M9.3 10.2 12 12l2.7-1.8" />'
        '<path d="M12 8.2v7.3" />'
        "</svg>\n"
    ),
}

ALL_ICON_NAMES: tuple[str, ...] = LUCIDE_SLUGS + tuple(CUSTOM_ANATOMICAL_SVGS.keys())
EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF\u2600-\u26FF\u2700-\u27BF\uFE0F\u200D]")


def _fetch_lucide_svg(slug: str, version: str) -> str:
    urls = (
        f"https://cdn.jsdelivr.net/npm/lucide-static@{version}/icons/{slug}.svg",
        f"https://unpkg.com/lucide-static@{version}/icons/{slug}.svg",
    )
    last_err: Exception | None = None
    for url in urls:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "StepTrack-AssetPipeline/1.0"})
            with urllib.request.urlopen(req, timeout=20) as resp:
                return resp.read().decode("utf-8")
        except Exception as exc:  # noqa: BLE001
            last_err = exc
    raise RuntimeError(f"Failed to fetch Lucide SVG {slug!r} ({version}): {last_err}")


def preprocess_svg(svg_text: str, name: str) -> str:
    processed = svg_text.replace('stroke="currentColor"', 'stroke="#000000"').replace('fill="currentColor"', 'fill="#000000"')
    processed = processed.replace("\r\n", "\n")
    if not processed.endswith("\n"):
        processed += "\n"
    validate_svg_text(processed, name)
    return processed


def validate_svg_text(svg_text: str, name: str) -> None:
    if "currentColor" in svg_text:
        raise ValueError(f"SVG {name} still contains currentColor")
    if "#000000" not in svg_text:
        raise ValueError(f"SVG {name} does not contain #000000")
    if EMOJI_RE.search(svg_text):
        raise ValueError(f"SVG {name} contains emoji characters")
    root = ET.fromstring(svg_text)
    tag = root.tag.split("}")[-1]
    if tag != "svg":
        raise ValueError(f"SVG {name} root tag is {tag!r}, expected 'svg'")
    if root.attrib.get("viewBox") != "0 0 24 24":
        raise ValueError(f"SVG {name} viewBox is {root.attrib.get('viewBox')!r}, expected '0 0 24 24'")


def validate_icons(assets_dir: Path) -> int:
    icons_dir = assets_dir / "Icons"
    if not icons_dir.is_dir():
        raise FileNotFoundError(f"Missing Icons directory: {icons_dir}")

    ns_contents = icons_dir / "Contents.json"
    if not ns_contents.is_file():
        raise FileNotFoundError(f"Missing {ns_contents}")
    ns_data = json.loads(ns_contents.read_text(encoding="utf-8"))
    if ns_data.get("properties", {}).get("provides-namespace") is not False:
        raise ValueError(f"{ns_contents} must set properties.provides-namespace = false")

    for name in ALL_ICON_NAMES:
        imageset = icons_dir / f"{name}.imageset"
        svg_path = imageset / f"{name}.svg"
        contents_path = imageset / "Contents.json"
        if not svg_path.is_file():
            raise FileNotFoundError(f"Missing SVG asset: {svg_path}")
        if not contents_path.is_file():
            raise FileNotFoundError(f"Missing imageset Contents.json: {contents_path}")

        validate_svg_text(svg_path.read_text(encoding="utf-8"), name)

        meta = json.loads(contents_path.read_text(encoding="utf-8"))
        images = meta.get("images", [])
        if len(images) != 1:
            raise ValueError(f"{contents_path} must contain exactly 1 image entry")
        entry = images[0]
        if entry.get("filename") != f"{name}.svg" or entry.get("idiom") != "universal" or "scale" in entry:
            raise ValueError(f"{contents_path} invalid image entry: {entry}")
        props = meta.get("properties", {})
        if props.get("preserves-vector-representation") is not True or props.get("template-rendering-intent") != "template":
            raise ValueError(f"{contents_path} invalid properties: {props}")

    return len(ALL_ICON_NAMES)


def write_catalog(assets_dir: Path, svgs: dict[str, str]) -> None:
    assets_dir.mkdir(parents=True, exist_ok=True)
    root_contents = assets_dir / "Contents.json"
    if not root_contents.exists():
        root_contents.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8", newline="\n")

    icons_dir = assets_dir / "Icons"
    icons_dir.mkdir(parents=True, exist_ok=True)
    (icons_dir / "Contents.json").write_text(
        json.dumps(
            {
                "info": {"author": "xcode", "version": 1},
                "properties": {"provides-namespace": False},
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )

    for name, svg_content in svgs.items():
        imageset = icons_dir / f"{name}.imageset"
        imageset.mkdir(parents=True, exist_ok=True)
        (imageset / f"{name}.svg").write_text(svg_content, encoding="utf-8", newline="\n")
        (imageset / "Contents.json").write_text(
            json.dumps(
                {
                    "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
                    "info": {"author": "xcode", "version": 1},
                    "properties": {
                        "preserves-vector-representation": True,
                        "template-rendering-intent": "template",
                    },
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
            newline="\n",
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets-dir", type=Path, default=DEFAULT_ASSETS_DIR)
    parser.add_argument("--version", default=DEFAULT_VERSION)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args(argv)

    if args.verify_only:
        count = validate_icons(args.assets_dir)
        print(f"Verified {count} SVG imagesets in {args.assets_dir / 'Icons'}")
        return 0

    svgs: dict[str, str] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        futures = {pool.submit(_fetch_lucide_svg, slug, args.version): slug for slug in LUCIDE_SLUGS}
        for future in concurrent.futures.as_completed(futures):
            slug = futures[future]
            svgs[slug] = preprocess_svg(future.result(), slug)

    for name, raw in CUSTOM_ANATOMICAL_SVGS.items():
        svgs[name] = preprocess_svg(raw, name)

    write_catalog(args.assets_dir, svgs)
    count = validate_icons(args.assets_dir)
    print(f"Generated and verified {count} SVG imagesets in {args.assets_dir / 'Icons'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
