import Foundation

/// Launch-argument overrides so a test can put the app into a known state
/// without tapping anything first. An automation tool can pass these through the
/// iOS `processArguments` capability.
///
///   --gate-on / --gate-off      force the launch gate for this run
///   --auto-auth <MODE>          authenticate right after the main screen appears
///                               MODE = BIOMETRICS_ONLY
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
}
