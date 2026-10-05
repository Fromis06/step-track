"""Generate a simple geometric app icon, with no external image assets."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / "StepTrack/Assets.xcassets"
icon = root / "AppIcon.appiconset"
icon.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (1024, 1024), (17, 49, 37))
draw = ImageDraw.Draw(image)
draw.arc((170, 170, 854, 854), 135, 435, fill=(183, 232, 130), width=63)
# Two rounded footprints inside an open activity ring.
draw.rounded_rectangle((383, 405, 477, 640), radius=47, fill=(247, 250, 239))
draw.rounded_rectangle((547, 325, 641, 560), radius=47, fill=(183, 232, 130))
image.save(icon / "AppIcon.png")
(root / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
(icon / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2))
