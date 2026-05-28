# StudyMate

StudyMate is a free macOS menu bar AI tutor.

It quietly stays in the menu bar, asks study questions on a schedule, and grades your answers with feedback. The app is free to use, but you need your own OpenAI API key.

## Why

AI is more useful when you know the subject yourself. Better knowledge leads to sharper questions, better judgment, and better output.

StudyMate was built to help you keep that knowledge fresh through small, repeated questions.

## Features

- Menu bar app built with SwiftUI
- Scheduled study questions by topic, difficulty, and interval
- Answer grading with score, feedback, and explanation
- Pending questions, history, and statistics
- Korean and English app language support
- macOS notifications with configurable sound
- Sparkle-based automatic updates from GitHub Releases
- OpenAI Responses API integration

## Requirements

- macOS 14 or later
- Xcode 16 or later
- OpenAI API key

## Run

1. Open `StudyMate.xcodeproj` in Xcode.
2. Select the `StudyMate` scheme.
3. Run on `My Mac`.
4. Click the StudyMate icon in the macOS menu bar.
5. Open settings and enter your OpenAI API key.

The app runs as a menu bar utility and does not show a Dock icon.

## Install

Download the DMG, open it, and drag `StudyMate.app` to `Applications` before launching it. Sparkle automatic updates only work from `Applications` or `~/Applications`; running the app directly from the DMG is read-only and cannot be updated.

## Test

```sh
xcodebuild test -project StudyMate.xcodeproj -scheme StudyMate -destination 'platform=macOS,arch=arm64' -derivedDataPath ./DerivedData
```

## Release

GitHub Actions builds a DMG when a version tag is pushed.

```sh
git tag v1.0.15
git push origin v1.0.15
```

The release DMG includes:

- `StudyMate.app`
- `Applications` shortcut

If signing secrets are not configured, the workflow builds an unsigned DMG. Users may need to approve unsigned builds in macOS Privacy & Security after opening the app for the first time.

For trusted public distribution without Gatekeeper warnings, configure these GitHub Actions secrets:

- `DEVELOPER_ID_CERTIFICATE_P12_BASE64`: base64-encoded Developer ID Application `.p12`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: password for the `.p12`
- `APPLE_TEAM_ID`: Apple Developer Team ID
- `APPSTORE_CONNECT_KEY_ID`: App Store Connect API key ID
- `APPSTORE_CONNECT_ISSUER_ID`: App Store Connect issuer ID
- `APPSTORE_CONNECT_PRIVATE_KEY_BASE64`: base64-encoded App Store Connect API `.p8` private key
- `SPARKLE_ED_PRIVATE_KEY`: base64 Sparkle EdDSA private key used to sign the appcast update archive
- `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64` optional: base64-encoded Developer ID provisioning profile for `io.github.ghkdqhrbals.StudyMate` with iCloud/CloudKit enabled. If omitted, the workflow creates a `MAC_APP_DIRECT` Developer ID profile through the App Store Connect API.

When Developer ID secrets are present, the workflow signs the app, verifies the embedded iCloud/CloudKit entitlements, notarizes the DMG, staples the notarization ticket, publishes the release, and updates `docs/appcast.xml` for automatic updates.

You can configure the secrets from this machine with:

```sh
gh auth login -h github.com
DEVELOPER_ID_CERTIFICATE_PASSWORD='your-p12-password' ./scripts/configure-release-secrets.sh
```

## Uninstall

Open StudyMate settings and use the Uninstall action, or remove manually:

```sh
rm -rf /Applications/StudyMate.app
rm -rf ~/Applications/StudyMate.app
defaults delete io.github.ghkdqhrbals.StudyMate 2>/dev/null || true
```

## Website

GitHub Pages files live in `docs/`.

- Korean: `docs/index.html`
- English: `docs/en/index.html`

## Notes

- StudyMate only generates scheduled questions while the app is running.
- The app stores settings locally.
- OpenAI API usage is billed through your own OpenAI account.
