# Step Track

Step Track is a personal iOS fitness, gym, and activity tracking app built with SwiftUI for sideloaded `.ipa` installation without accounts, ads, or external servers.

## Capabilities

- **Activity & Step Tracking**: Daily step ring, distance, goal progress, and long-term local history via CoreMotion (`CMPedometer`) with manual entry fallback when sideloaded without HealthKit entitlements.
- **Workouts & Weight (kg) Progression**: Weekly training split schedule, set-by-set weight (kg) and rep logging, estimated 1RM / PR tracking, and built-in rest timer.
- **Offline 3D Body Map & Exercise Library**: Interactive SceneKit 3D body mesh (`human_body.obj`) paired with 1,324 offline categorized exercises (`exercises.json`).
- **Health, Nutrition & Dashboards**: Sleep, meals, calorie balance, hydration, body weight, personal goals, and Weekly / Monthly / Yearly analytics.
- **Themes, Localization & Backups**: Multiple color themes, light/dark appearance, `en` / `vi` / `ja` / `es` localization, 100% bundled SVG icons, and JSON export/import backup.

## Architecture & Sideload Design

- `project-sideload.yml` (Primary): Targets iOS 17.0+ with `MOTION_ONLY` enabled. Requires only `NSMotionUsageDescription` and avoids restricted entitlements (no HealthKit, App Groups, iCloud, or WidgetKit extension), ensuring compatibility with free Apple developer sideloading.
- `project.yml` (Optional Full Build): Enables HealthKit, App Groups, and `StepTrackWidget` for paid developer signing.

## Repository Layout

```text
.
├── .github/workflows/build-ios.yml   # macOS-15 XcodeGen, Simulator tests, unsigned .ipa CI
├── project-sideload.yml              # Primary sideload XcodeGen spec (MOTION_ONLY)
├── project.yml                       # Full HealthKit + WidgetKit XcodeGen spec
├── scripts/                          # Icon, asset, dataset, 3D mesh, and R2 compliance tools
├── StepTrack/
│   ├── App/                          # App entry point & navigation shell
│   ├── Core/                         # Models, Persistence, Services, DesignSystem, Localization
│   ├── Features/                     # Today, Workouts, BodyMap, Health, Analytics, Settings
│   ├── Resources/                    # Assets.xcassets (AppIcon + Icons), Datasets, Models3D, Localization
│   ├── Widget/                       # WidgetKit extension (used by project.yml)
│   └── Config/                       # Generated Info.plist / entitlements (gitignored)
└── Tests/
    ├── UnitTests/                    # Domain, history, snapshot, and signing tests
    ├── StepsTests/                   # Migrated goal, checkpoint, reminder, and attribution tests
    └── UITests/                      # UI and localization verification
```

## Generating the Xcode Project Locally (macOS)

```sh
brew install xcodegen
xcodegen generate --spec project-sideload.yml
open StepTrackSideload.xcodeproj
```

See [BUILD-IPHONE.md](BUILD-IPHONE.md) for GitHub Actions CI and iPhone sideload instructions.

## License

MIT License. Based in part on [brittanyarima/Steps](https://github.com/brittanyarima/Steps) (`LICENSE`). See [LICENSE](LICENSE).
