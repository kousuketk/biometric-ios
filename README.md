# BiometricDemo (iOS)

A deliberately small SwiftUI app that exercises every iOS biometric path we need
to automate, and reports the outcome as a machine-readable string so a test can
assert on it without parsing localized system text.

## Requirements

- Xcode 26 / 27 (verified on Xcode 27.0, iOS 27 SDK)
- Deployment target: iOS 15.0
- No third-party dependencies, no code signing needed for the simulator

## Build & run

```bash
xcodebuild -project BiometricDemo.xcodeproj -scheme BiometricDemo \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath build -destination 'generic/platform=iOS Simulator' build

xcrun simctl boot 'iPhone 17 Pro'
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/BiometricDemo.app
xcrun simctl launch booted com.magicpod.biometricdemo
```

Bundle ID: `com.magicpod.biometricdemo`

## What it covers

| Path | Why it is in here |
|---|---|
| `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` | The plain biometric gate. This is what `mobile: sendBiometricMatch` drives. |
| `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` | Biometrics with passcode fallback. |
| Keychain item with `.biometryCurrentSet` | The Secure Enclave path. Cloud farms that instrument `LAContext` cannot intercept this one, so it is worth having a case that exercises it. |
| Launch gate | The "mandatory security layer" case: nothing is reachable until authentication succeeds. This is the flow that blocks E2E automation today. |
| `canEvaluatePolicy` reporting | Distinguishes not-enrolled / not-available / passcode-not-set before any prompt appears. |

## Accessibility identifiers

The result block is rendered first so a test can read it without scrolling.

| Identifier | Element | Notes |
|---|---|---|
| `app_title` | StaticText | "Biometric Demo" |
| `result_status` | StaticText | **The value to assert on.** See below. |
| `result_detail` | StaticText | `mode=… LAError.…` — useful for diagnosis |
| `attempt_count_value` | StaticText | Attempt counter |
| `reset_button` | Button | Clears status/detail/counter |
| `biometry_type_value` | StaticText | `NONE` / `TOUCH_ID` / `FACE_ID` / `OTHER(n)` |
| `can_evaluate_biometrics_value` | StaticText | `OK` or `NG LAError.…` |
| `can_evaluate_any_value` | StaticText | `OK` or `NG LAError.…` |
| `refresh_button` | Button | Re-reads device state |
| `allow_fallback_toggle` | Switch | Off hides the prompt's fallback button |
| `auth_biometrics_button` | Button | Biometrics only |
| `auth_biometrics_or_passcode_button` | Button | Biometrics or passcode |
| `keychain_save_button` | Button | Stores the secret with `.biometryCurrentSet` |
| `keychain_read_button` | Button | Reads it back (triggers the prompt) |
| `keychain_delete_button` | Button | Deletes it |
| `gate_toggle` | Switch | Arms the launch gate for the next cold launch |
| `gate_title` / `gate_status` / `gate_detail` | StaticText | Gate overlay |
| `gate_unlock_button` / `gate_disable_button` | Button | Gate overlay |

### `result_status` values

Uppercase ASCII, never localized.

`IDLE` / `RUNNING` / `SUCCESS` / `FAILED` / `CANCELED` / `FALLBACK` /
`NOT_ENROLLED` / `NOT_AVAILABLE` / `LOCKED_OUT` / `PASSCODE_NOT_SET` / `ERROR`

Mapping from `LAError`: `authenticationFailed`→`FAILED`,
`userCancel`/`systemCancel`/`appCancel`→`CANCELED`, `userFallback`→`FALLBACK`,
`biometryNotEnrolled`→`NOT_ENROLLED`, `biometryNotAvailable`→`NOT_AVAILABLE`,
`biometryLockout`→`LOCKED_OUT`, `passcodeNotSet`→`PASSCODE_NOT_SET`.

## Launch arguments

Pass these through the iOS `processArguments` capability so a test can start
from a known state without tapping anything first.

| Argument | Effect |
|---|---|
| `--gate-on` / `--gate-off` | Force the launch gate on/off for this run |
| `--auto-auth <MODE>` | Authenticate as soon as the main screen appears. `MODE` = `BIOMETRICS_ONLY`, `BIOMETRICS_OR_PASSCODE`, `KEYCHAIN` |
| `--seed-keychain` | Store the demo secret on launch |
| `--reset-keychain` | Delete the stored secret on launch |

```bash
xcrun simctl launch booted com.magicpod.biometricdemo --gate-off --auto-auth BIOMETRICS_ONLY
```

## Driving it from Appium

```ts
// Enrollment is a prerequisite; sendBiometricMatch does nothing without it.
await driver.executeScript('mobile: enrollBiometric', [{ isEnabled: true }]);

// Success
await driver.executeScript('mobile: sendBiometricMatch', [{ type: 'faceId', match: true }]);

// Non-match — see "Findings" below, this does not immediately produce FAILED
await driver.executeScript('mobile: sendBiometricMatch', [{ type: 'faceId', match: false }]);

// Un-enrolled device (NOT_ENROLLED path)
await driver.executeScript('mobile: enrollBiometric', [{ isEnabled: false }]);
```

Both commands are **Simulator only**. `type` does not have to match the device's
actual biometry — see finding 6 below.

## Verifying without Appium

`scripts/simctl-demo.sh` drives the simulator with the same Darwin notifications
that `appium-ios-simulator` posts, so a green run proves the Appium path too.

```bash
./scripts/simctl-demo.sh 'iPhone 17 Pro'
```

| Operation | Notification |
|---|---|
| Enroll / un-enroll | `notifyutil -s com.apple.BiometricKit.enrollmentChanged 1\|0` then `-p` |
| Face ID match | `notifyutil -p com.apple.BiometricKit_Sim.pearl.match` |
| Face ID no-match | `notifyutil -p com.apple.BiometricKit_Sim.pearl.nomatch` |
| Touch ID match | `notifyutil -p com.apple.BiometricKit_Sim.fingerTouch.match` |
| Touch ID no-match | `notifyutil -p com.apple.BiometricKit_Sim.fingerTouch.nomatch` |

("pearl" is Apple's internal codename for Face ID.)

## Findings so far

Verified on iPhone 17 Pro / iOS 27.0 simulator.

1. **Enrollment is genuinely required.** Before enrolling,
   `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` returns
   `LAError.biometryNotEnrolled (-7)` and no prompt appears at all — a match
   notification has nothing to land on.
2. **`match: false` is a scan event, not an authentication result.** Measured on
   iPhone 17 Pro / iOS 27.0 with `--auto-auth BIOMETRICS_ONLY`:

   | Action | `result_status` | `Attempts` | Screen |
   |---|---|---|---|
   | no-match x1 | `RUNNING` | 0 | "Face Not Recognized" alert, buttons *Try Face ID Again* / *Cancel* |
   | no-match x3 more | `RUNNING` | 0 | unchanged — no-matches posted while the alert is up are dropped |
   | match | `SUCCESS` | 1 | alert dismisses, authentication succeeds |

   `evaluatePolicy` has not returned at that point; it is still waiting. Reaching
   a terminal state needs UI interaction: *Cancel* gives `LAError.userCancel`
   (`CANCELED`), while re-arming with *Try Face ID Again* and posting another
   no-match is what eventually yields `authenticationFailed` / `biometryLockout`.
   (The tapping half is not yet verified here — no tap tooling in this
   environment. Appium can do it with `mobile: alert`.)

   **Implication for the MagicPod step design:** BrowserStack's
   `pass` / `fail` / `cancel` three-value model does not describe iOS honestly.
   A "fail the biometric" step should mean "send one non-matching scan"; the
   prompt stays up and the branch after it is ordinary UI. Android's
   `BiometricPrompt` behaves the same way — `onAuthenticationFailed()` fires but
   the prompt remains — so the two platforms are symmetric here.
3. **Passcode fallback is reachable, but not via a single no-match.** With
   biometry enrolled, one no-match under `.deviceOwnerAuthentication` shows the
   same *Try Face ID Again* / *Cancel* alert as the biometrics-only policy — no
   *Enter Passcode*. iOS withholds the fallback until the biometric retry budget
   is spent, and no-matches posted while the alert is up do not spend it.

   The deterministic, tap-free way to exercise the fallback is to **un-enroll
   biometry first**:

   ```bash
   xcrun simctl spawn <UDID> notifyutil -s com.apple.BiometricKit.enrollmentChanged 0
   xcrun simctl spawn <UDID> notifyutil -p com.apple.BiometricKit.enrollmentChanged
   xcrun simctl launch <UDID> com.magicpod.biometricdemo --gate-off --auto-auth BIOMETRICS_OR_PASSCODE
   ```

   That lands straight on the system passcode screen ("Enter iPhone Passcode for
   BiometricDemo", with our `localizedReason` underneath). It is also the more
   realistic scenario — a device with no enrolled biometry is common; five
   consecutive failed scans are not.
4. **The Keychain `.biometryCurrentSet` path works on the Simulator** and is
   unlocked by the same match notification (`result_detail` shows
   `mode=KEYCHAIN value=s3cr3t-42`). This is the path BrowserStack cannot
   instrument on real devices, so it is a useful contrast case for phase 2.
5. **`biometryType` is only populated after `canEvaluatePolicy` runs.** Reading
   it first returns `NONE`; the app calls them in the right order.
6. **Touch ID vs Face ID is a device-model property, not an iOS-version one**, and
   the match notification is *not* gated on it. Same binary, same API:

   | Simulator | Runtime | `biometry_type_value` |
   |---|---|---|
   | iPhone 17 Pro | iOS 27.0 | `FACE_ID` |
   | iPhone SE (2nd generation) | iOS 15.2 | `TOUCH_ID` |

   Cross-posting the "wrong" notification still authenticated on both:
   `pearl.match` → Touch ID device = SUCCESS, `fingerTouch.match` → Face ID
   device = SUCCESS. So a MagicPod step does **not** need a device→biometry map
   to deliver a match. The rendered prompt still differs, though, so a test that
   taps or asserts on the prompt itself does care.

## Next

- An Android counterpart (`BiometricPrompt`, `BIOMETRIC_STRONG` + `CryptoObject`)
- Wire both into a MagicPod test step prototype
