# BiometricDemo (iOS)

A small SwiftUI app for exercising the iOS biometric authentication paths on a
simulator.

## Build

```bash
xcodebuild -project BiometricDemo.xcodeproj -scheme BiometricDemo \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath build -destination 'generic/platform=iOS Simulator' build
```

Requires Xcode with an iOS simulator SDK. There are no third-party dependencies,
and no code signing is needed for the simulator.

## Build output

```
build/Build/Products/Debug-iphonesimulator/BiometricDemo.app
```

Install and launch it with:

```bash
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/BiometricDemo.app
xcrun simctl launch booted com.magicpod.biometricdemo
```
