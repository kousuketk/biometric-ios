import Foundation

/// Launch-argument overrides so a test can put the app into a known state
/// without tapping anything first. MagicPod can pass these through the iOS
/// `processArguments` capability.
///
///   --gate-on / --gate-off      force the launch gate for this run
///   --auto-auth <MODE>          authenticate right after the main screen appears
///                               MODE = BIOMETRICS_ONLY | BIOMETRICS_OR_PASSCODE | KEYCHAIN
///   --reset-keychain            delete the stored secret on launch
///   --seed-keychain             store the demo secret on launch
enum LaunchOptions {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// nil means "leave whatever the user toggled in the UI".
    static var forcedGate: Bool? {
        if arguments.contains("--gate-on") { return true }
        if arguments.contains("--gate-off") { return false }
        return nil
    }

    static var autoAuth: String? {
        guard let index = arguments.firstIndex(of: "--auto-auth"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    static var resetKeychain: Bool { arguments.contains("--reset-keychain") }

    static var seedKeychain: Bool { arguments.contains("--seed-keychain") }
}
