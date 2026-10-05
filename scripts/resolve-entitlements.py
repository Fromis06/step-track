"""Resolve generated entitlement placeholders from the built products, never a signing secret."""
import plistlib
from pathlib import Path

products = Path("build/package/Payload/StepTrack.app")
for name, app in [("StepTrack", products), ("Widget", products / "PlugIns/StepTrackWidget.appex")]:
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    group = info["AppGroupIdentifier"]
    if not group.startswith("group.") or "$" in group:
        raise ValueError("App Group identifier was not resolved")
    with Path(f"StepTrack/Config/{name}.entitlements").open("rb") as stream:
        entitlements = plistlib.load(stream)
    entitlements["com.apple.security.application-groups"] = [group]
    with Path(f"build/{name}.entitlements").open("wb") as stream:
        plistlib.dump(entitlements, stream)
