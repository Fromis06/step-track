
 # 🏃 Steps

> ### 📦 This project is archived and no longer maintained.
>
> Steps was an open source step counting app built with SwiftUI and HealthKit. After several years and 250+ commits from contributors around the world, I've decided to stop active development here and rebuild the app from scratch as a closed source, commercial project.
>
> **This repository is now read-only.** Issues, pull requests, and discussions are closed. The code remains available under the MIT License — you're free to fork it, learn from it, modify it, and ship it. That doesn't change.
>
> Thank you to everyone who contributed. 💙

---

## What this was

An open source step counting app for iOS, built entirely in SwiftUI and designed to be approachable for first-time open source contributors. A lot of people made their very first pull request here, which was always the point.

**Tech used**

- 🎨 SwiftUI
- ❤️‍🩹 HealthKit
- 📊 Swift Charts
- 🔔 Local Notifications
- 🗂️ MVVM
- 💾 App Storage

<img src="https://user-images.githubusercontent.com/76922883/209883943-03fc014d-778a-429d-8817-79d5a665ba0d.jpg" width="200"> <img src="https://user-images.githubusercontent.com/76922883/209884023-aca50258-92ee-4dcf-89db-5e69ee6d3076.jpg" width="200"> <img src="https://user-images.githubusercontent.com/76922883/209884047-f5b8bf5f-7ee5-43f1-bedc-6c7786197a13.jpg" width="200"> <img src="https://user-images.githubusercontent.com/76922883/209884076-f3ebcd7b-5dc2-49c2-9762-83e50c19e102.jpg" width="200">

---

## Why it's archived

Steps started as a teaching project, and it did that job well. But maintaining an open source app alongside the version I want to build next stopped making sense — the app I'm working on now is a full rewrite with a different scope, a different architecture, and a business model behind it so it can actually be supported long term.

Rather than quietly let this repo rot or slowly close it off piece by piece, I'd rather draw a clean line: this version stays open, stays MIT, and stays here.

---

## Running it yourself

Everything below still works if you fork the project. You'll need Xcode 15 or later and macOS 14.0 or later.

1. Fork and clone the repo.
2. In the same folder as `StepsConfigTemplate.xcconfig`, create your own config file:

   ```
   cp StepsConfigTemplate.xcconfig StepsConfig.xcconfig
   ```

3. Fill in your `DEVELOPMENT_TEAM` and `BUNDLE_ID` in `StepsConfig.xcconfig`:

   ```
   DEVELOPMENT_TEAM = YourTeamID
   BUNDLE_ID = com.yourname.steps
   ```

   Your Team ID is in the Apple Developer Portal. This is only needed to run on a physical device, and works with both free and paid developer accounts.

4. Repeat for the widget extension:

   ```
   cp StepsWidgetConfigTemplate.xcconfig StepsWidgetConfig.xcconfig
   ```

   ⚠️ Make sure you append `.widget` to the widget's `PRODUCT_BUNDLE_IDENTIFIER` — e.g. `com.yourname.steps.widget`.

5. Build and run.

Since HealthKit data isn't available in the simulator for step counts, you'll want to run on a real device to see anything meaningful.

---

## Forking and continuing the project

If you want to keep this alive under your own name, please do — that's what the license is for. A couple of asks, none of them legally binding, just neighborly:

- Rename it and use your own bundle identifier and app icon.
- Don't imply your fork is maintained by me or affiliated with what I'm building next.
- Keep the MIT license and attribution intact.

---

## Contributors

This app was built by a lot of people, many of whom were making their first open source contribution. That's the part I'm proudest of.

[![Contributors](https://contrib.rocks/image?repo=brittanyarima/Steps)](https://github.com/brittanyarima/Steps/graphs/contributors)

Made with [contrib.rocks](https://contrib.rocks).

---

## License

MIT — see [LICENSE](LICENSE).

The code published here is MIT licensed and always will be. Archiving the repository doesn't revoke or change that in any way.
