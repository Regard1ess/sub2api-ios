# Sub2API iOS

Native SwiftUI iOS app for the Sub2API admin console and works on iPhones that are running iOS 16 or higher. 

## Requirements

- macOS with Xcode 15 or newer
- iOS 17 SDK or newer

## Open

```bash
open ios/Sub2API.xcodeproj
```

## Build

From Xcode, select the `Sub2API` scheme and an iPhone simulator or connected device, then run.

Command line on macOS:

```bash
xcodebuild -project ios/Sub2API.xcodeproj -scheme Sub2API -destination 'platform=iOS Simulator,name=iPhone 15' build
```

## Notes

- The app stores server profiles in `UserDefaults`.
- Admin API keys are stored in Keychain.
- The React Native / Expo source remains in the repository as legacy reference during migration.
- Please report an issue if you found one, advice is also accepted.
