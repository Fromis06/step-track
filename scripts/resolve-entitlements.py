"""Resolve generated entitlement placeholders from the built products, never a signing secret."""
import plistlib
from pathlib import Path

repo_root = Path(__file__).resolve().parents[1]
products = repo_root / "build/package/Payload/StepTrack.app"
for name, app in [("StepTrack", products), ("Widget", products / "PlugIns/StepTrackWidget.appex")]:
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    group = info["AppGroupIdentifier"]
    if not group.startswith("group.") or "$" in group:
        raise ValueError("App Group identifier was not resolved")
    with (repo_root / f"StepTrack/Config/{name}.entitlements").open("rb") as stream:
        entitlements = plistlib.load(stream)
    entitlements["com.apple.security.application-groups"] = [group]
    with (repo_root / f"build/{name}.entitlements").open("wb") as stream:
        plistlib.dump(entitlements, stream)
