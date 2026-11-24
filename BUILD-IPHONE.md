# Building & Installing Step Track on iPhone

## Building with GitHub Actions

1. Push changes or trigger **Actions -> Build iPhone IPA -> Run workflow**.
2. Wait for the `macos-15` job to generate `StepTrackSideload.xcodeproj`, run automated tests, and package the unsigned device build.
3. Download the `StepTrack-sideload-unsigned` artifact and unzip it to obtain `StepTrack-sideload-unsigned.ipa`.

The workflow requires no Apple ID credentials or secrets on GitHub and produces an unsigned `.ipa` configured with `MOTION_ONLY` for personal sideloading.

## Installing or Updating via Sideloadly / AltStore

1. Open Sideloadly or AltStore, connect your iPhone, and select `StepTrack-sideload-unsigned.ipa`.
2. When updating an existing installation, keep the **same Apple ID and Bundle ID** and install directly over the existing app. Do not uninstall the app beforehand, or local history will be deleted.
3. Enable **Developer Mode** (Settings -> Privacy & Security) and trust your signing certificate under Settings -> General -> VPN & Device Management if prompted by iOS.
4. On first launch, grant **Motion & Fitness** permission when requested.
5. Before 7-day free-developer re-signing expires, export a local JSON backup from Settings so data can be restored at any time.

## Offline Behavior & Permissions

- **Motion & Fitness**: Uses `CMPedometer` for on-device step and distance queries (up to 7 days of sensor history; open the app periodically to persist long-term history). Manual step entry is available as a fallback when motion permissions or sensors are unavailable.
- **3D Body Map & Exercise Library**: Bundled completely offline in the app (`exercises.json` and `human_body.obj`). No internet connection is required.
- **Local Storage**: All workout splits, weight logs (kg), sleep, meals, hydration, goals, and step history are stored locally on-device with no server uploads.

## Automated CI Verification

CI executes all test targets (`StepTrackTests`, `StepsTests`, and `StepTrackUITests`) on the iOS Simulator, verifies bundled offline resources (`exercises.json`, `human_body.obj`, `human_body.mtl`, `Translations.json`), and uploads simulator screenshots (`interface-screenshots`) and diagnostics.
