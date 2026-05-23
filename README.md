# StudyMate

macOS menu bar AI teacher app built with SwiftUI.

## Features

- Menu bar app using `MenuBarExtra`
- App/study language, study topic, difficulty, prompt, question interval, and OpenAI model settings
- OpenAI Responses API integration with configurable model ID
- OpenAI API key storage in app settings
- Scheduled question generation while the app is running
- macOS notifications for generated questions
- Answer grading with score, feedback, and explanation

## Run

Open `StudyMate.xcodeproj` in Xcode, select the `StudyMate` scheme, and run on My Mac.

The app runs as a menu bar utility, so it does not show a Dock icon. Click the graduation cap icon in the macOS menu bar, open Settings, enter your OpenAI API key, then save.

## Test

```sh
xcodebuild test -project StudyMate.xcodeproj -scheme StudyMate -destination 'platform=macOS,arch=arm64' -derivedDataPath ./DerivedData
```
