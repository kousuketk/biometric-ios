import Foundation
import LocalAuthentication

/// Machine-readable outcome of one authentication attempt.
///
/// These raw values are what an automated test asserts on, so they are
/// intentionally uppercase ASCII and are never localized.
enum AuthOutcome: String {
    case idle = "IDLE"
    case running = "RUNNING"
    case success = "SUCCESS"
    /// The biometric did not match (LAError.authenticationFailed).
    case failed = "FAILED"
    /// The user, the system or the app dismissed the prompt.
    case canceled = "CANCELED"
    /// The user tapped the fallback ("Enter Password") button.
    case fallback = "FALLBACK"
    case notEnrolled = "NOT_ENROLLED"
    case notAvailable = "NOT_AVAILABLE"
    case lockedOut = "LOCKED_OUT"
    case passcodeNotSet = "PASSCODE_NOT_SET"
    case error = "ERROR"

    static func from(_ error: Error) -> AuthOutcome {
        guard let laError = error as? LAError else { return .error }
        switch laError.code {
        case .authenticationFailed: return .failed
        case .userCancel, .systemCancel, .appCancel: return .canceled
        case .userFallback: return .fallback
        case .biometryNotEnrolled: return .notEnrolled
        case .biometryNotAvailable: return .notAvailable
        case .biometryLockout: return .lockedOut
        case .passcodeNotSet: return .passcodeNotSet
        default: return .error
        }
    }
}

enum ErrorFormatter {
    /// Renders an error so that both a human and a log grep can read it.
    static func describe(_ error: Error) -> String {
        if let laError = error as? LAError {
            return "LAError.\(name(for: laError.code)) (\(laError.code.rawValue)): \(laError.localizedDescription)"
        }
        let nsError = error as NSError
        return "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
    }

    static func name(for code: LAError.Code) -> String {
        switch code {
        case .authenticationFailed: return "authenticationFailed"
        case .userCancel: return "userCancel"
        case .userFallback: return "userFallback"
        case .systemCancel: return "systemCancel"
        case .passcodeNotSet: return "passcodeNotSet"
        case .appCancel: return "appCancel"
        case .invalidContext: return "invalidContext"
        case .notInteractive: return "notInteractive"
        case .biometryNotAvailable: return "biometryNotAvailable"
        case .biometryNotEnrolled: return "biometryNotEnrolled"
        case .biometryLockout: return "biometryLockout"
        default: return "unknown"
        }
    }
}
