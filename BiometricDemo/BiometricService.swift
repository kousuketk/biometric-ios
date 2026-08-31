import Foundation
import LocalAuthentication

/// Which LocalAuthentication policy an attempt should use.
enum AuthMode: String, CaseIterable {
    /// Biometrics only. Fails instead of silently falling back to the passcode.
    case biometricsOnly = "BIOMETRICS_ONLY"
    /// Biometrics with the device passcode as a fallback.
    case biometricsOrPasscode = "BIOMETRICS_OR_PASSCODE"

    var policy: LAPolicy {
        switch self {
        case .biometricsOnly: return .deviceOwnerAuthenticationWithBiometrics
        case .biometricsOrPasscode: return .deviceOwnerAuthentication
        }
    }
}

@MainActor
final class BiometricService: ObservableObject {
    @Published private(set) var biometryType = "UNKNOWN"
    @Published private(set) var canEvaluateBiometrics = "UNKNOWN"
    @Published private(set) var canEvaluateAny = "UNKNOWN"

    @Published private(set) var outcome: AuthOutcome = .idle
    @Published private(set) var detail = "-"
    @Published private(set) var attemptCount = 0

    /// When false, the prompt hides its fallback button so that a non-matching
    /// biometric surfaces as FAILED rather than as a passcode prompt.
    @Published var allowFallbackButton = true

    init() {
        refreshState()
    }

    func refreshState() {
        let context = LAContext()
        var biometricsError: NSError?
        // biometryType is only populated once canEvaluatePolicy has run, so the
        // order here matters.
        let biometricsOK = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &biometricsError)
        biometryType = Self.name(for: context.biometryType)
        canEvaluateBiometrics = biometricsOK ? "OK" : Self.reason(biometricsError)

        let anyContext = LAContext()
        var anyError: NSError?
        let anyOK = anyContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &anyError)
        canEvaluateAny = anyOK ? "OK" : Self.reason(anyError)
    }

    func authenticate(mode: AuthMode) {
        outcome = .running
        detail = "mode=\(mode.rawValue)"

        let context = LAContext()
        if !allowFallbackButton {
            // An empty string removes the fallback button entirely; nil would
            // restore the system default title.
            context.localizedFallbackTitle = ""
        }

        let reason = "Authenticate to reveal the demo secret"
        context.evaluatePolicy(mode.policy, localizedReason: reason) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.attemptCount += 1
                if success {
                    self.outcome = .success
                    self.detail = "mode=\(mode.rawValue) evaluatePolicy=true"
                } else if let error {
                    self.outcome = AuthOutcome.from(error)
                    self.detail = "mode=\(mode.rawValue) \(ErrorFormatter.describe(error))"
                } else {
                    self.outcome = .error
                    self.detail = "mode=\(mode.rawValue) evaluatePolicy=false without an error"
                }
            }
        }
    }

    /// Exercises the Keychain access-control path, which is separate from
    /// evaluatePolicy: the match happens inside the Secure Enclave and never
    /// reaches app code. Cloud device farms that instrument LAContext cannot
    /// intercept this one.
    func readKeychainSecret() {
        outcome = .running
        detail = "mode=KEYCHAIN"
        Task.detached {
            do {
                let secret = try KeychainStore.read(prompt: "Authenticate to read the Keychain secret")
                await MainActor.run {
                    self.attemptCount += 1
                    self.outcome = .success
                    self.detail = "mode=KEYCHAIN value=\(secret)"
                }
            } catch {
                await MainActor.run {
                    self.attemptCount += 1
                    self.outcome = AuthOutcome.from(error)
                    self.detail = "mode=KEYCHAIN \(ErrorFormatter.describe(error))"
                }
            }
        }
    }

    func saveKeychainSecret() {
        do {
            try KeychainStore.save(secret: KeychainStore.demoSecret)
            outcome = .idle
            detail = "mode=KEYCHAIN saved with .biometryCurrentSet"
        } catch {
            outcome = .error
            detail = "mode=KEYCHAIN save failed: \(ErrorFormatter.describe(error))"
        }
    }

    func deleteKeychainSecret() {
        KeychainStore.delete()
        outcome = .idle
        detail = "mode=KEYCHAIN deleted"
    }

    func reset() {
        outcome = .idle
        detail = "-"
        attemptCount = 0
    }

    private static func name(for type: LABiometryType) -> String {
        switch type {
        case .none: return "NONE"
        case .touchID: return "TOUCH_ID"
        case .faceID: return "FACE_ID"
        default:
            // .opticID on visionOS-capable SDKs, plus anything Apple adds later.
            return "OTHER(\(type.rawValue))"
        }
    }

    private static func reason(_ error: NSError?) -> String {
        guard let error else { return "NG (no error)" }
        return "NG \(ErrorFormatter.describe(error))"
    }
}
