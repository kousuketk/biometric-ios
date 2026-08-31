import LocalAuthentication
import SwiftUI

struct ContentView: View {
    @StateObject private var service = BiometricService()
    /// Persisted so that the gate can be armed by one test run and observed on
    /// the next cold launch.
    @AppStorage("gateEnabled") private var gateEnabled = false
    @State private var unlocked = false

    private var gateActive: Bool { LaunchOptions.forcedGate ?? gateEnabled }

    var body: some View {
        ZStack {
            mainScreen
            if gateActive && !unlocked {
                GateView(onUnlock: { unlocked = true }, onDisable: { gateEnabled = false })
            }
        }
        .onAppear(perform: applyLaunchOptions)
    }

    private func applyLaunchOptions() {
        if LaunchOptions.resetKeychain {
            service.deleteKeychainSecret()
        }
        if LaunchOptions.seedKeychain {
            service.saveKeychainSecret()
        }
        guard !gateActive, let mode = LaunchOptions.autoAuth else { return }
        switch mode {
        case "KEYCHAIN": service.readKeychainSecret()
        default:
            guard let authMode = AuthMode(rawValue: mode) else { return }
            service.authenticate(mode: authMode)
        }
    }

    private var mainScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Biometric Demo")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("app_title")

                // Result first: an automated test can assert on it without scrolling.
                resultSection
                deviceStateSection
                authSection
                keychainSection
                gateSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deviceStateSection: some View {
        section("Device state") {
            row("Biometry type", service.biometryType, id: "biometry_type_value")
            row("canEvaluate biometrics", service.canEvaluateBiometrics, id: "can_evaluate_biometrics_value")
            row("canEvaluate any", service.canEvaluateAny, id: "can_evaluate_any_value")
            Button("Refresh") { service.refreshState() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("refresh_button")
        }
    }

    private var authSection: some View {
        section("evaluatePolicy") {
            Toggle("Show fallback button", isOn: $service.allowFallbackButton)
                .accessibilityIdentifier("allow_fallback_toggle")
            Button("Biometrics only") { service.authenticate(mode: .biometricsOnly) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("auth_biometrics_button")
            Button("Biometrics or passcode") { service.authenticate(mode: .biometricsOrPasscode) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("auth_biometrics_or_passcode_button")
        }
    }

    private var keychainSection: some View {
        section("Keychain (.biometryCurrentSet)") {
            Button("Save secret") { service.saveKeychainSecret() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("keychain_save_button")
            Button("Read secret") { service.readKeychainSecret() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("keychain_read_button")
            Button("Delete secret") { service.deleteKeychainSecret() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("keychain_delete_button")
        }
    }

    private var gateSection: some View {
        section("Launch gate") {
            Toggle("Require auth on next launch", isOn: $gateEnabled)
                .accessibilityIdentifier("gate_toggle")
            Text("Relaunch the app to see the gate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var resultSection: some View {
        section("Result") {
            Text(service.outcome.rawValue)
                .font(.system(.title2, design: .monospaced).bold())
                .accessibilityIdentifier("result_status")
            Text(service.detail)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityIdentifier("result_detail")
            row("Attempts", String(service.attemptCount), id: "attempt_count_value")
            Button("Reset") { service.reset() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reset_button")
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: String, _ value: String, id: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
        }
    }
}

/// The "mandatory security layer" case: nothing else in the app is reachable
/// until biometric authentication succeeds.
struct GateView: View {
    let onUnlock: () -> Void
    let onDisable: () -> Void

    @State private var status = AuthOutcome.idle
    @State private var detail = "-"

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Locked")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("gate_title")
                Text(status.rawValue)
                    .font(.system(.title3, design: .monospaced))
                    .accessibilityIdentifier("gate_status")
                Text(detail)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("gate_detail")
                Button("Unlock") { authenticate() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("gate_unlock_button")
                Button("Disable gate") { onDisable() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("gate_disable_button")
            }
            .padding(24)
        }
        .onAppear(perform: authenticate)
    }

    private func authenticate() {
        status = .running
        detail = "-"
        let context = LAContext()
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock Biometric Demo"
        ) { success, error in
            Task { @MainActor in
                if success {
                    status = .success
                    onUnlock()
                } else if let error {
                    status = AuthOutcome.from(error)
                    detail = ErrorFormatter.describe(error)
                } else {
                    status = .error
                }
            }
        }
    }
}
