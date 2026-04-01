import ApplicationServices
import SwiftUI

struct OnboardingView: View {
    let settings: AppSettings
    var onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var accessibilityGranted = false
    @State private var accessibilityPromptCount = 0
    @State private var screenRecordingGranted = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case accessibility
        case screenRecording
        case excludeApps
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            stepContent
            Spacer()
            stepIndicator
                .padding(.bottom, DS.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.bg)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .accessibility:
            accessibilityStep
        case .screenRecording:
            screenRecordingStep
        case .excludeApps:
            excludeAppsStep
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            Image(systemName: "brain.filled.head.profile")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(DS.Colors.accent)

            VStack(spacing: DS.Spacing.sm) {
                Text("Cobrain")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)

                Text("Your memory, searchable.\nCaptures text from everything you\nread and work on.")
                    .font(DS.Fonts.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            onboardingButton("Get Started") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    step = .accessibility
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xxl)
    }

    // MARK: - Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            permissionIcon("universal.access", granted: accessibilityGranted)

            VStack(spacing: DS.Spacing.sm) {
                Text("Accessibility Access")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)

                Text("Cobrain reads text from your apps\nusing macOS Accessibility. This is how\nit knows what you're looking at.")
                    .font(DS.Fonts.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                Text("Nothing leaves your Mac. Ever.")
                    .font(DS.Fonts.caption)
                    .foregroundStyle(DS.Colors.accent)
                    .padding(.top, DS.Spacing.xs)
            }

            if accessibilityGranted {
                onboardingButton("Continue") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        step = .screenRecording
                    }
                }
            } else {
                onboardingButton("Open Accessibility Settings") {
                    requestAccessibility()
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xxl)
        .onAppear { checkAccessibility() }
    }

    // MARK: - Screen Recording

    private var screenRecordingStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            permissionIcon("rectangle.dashed.badge.record", granted: screenRecordingGranted)

            VStack(spacing: DS.Spacing.sm) {
                Text("Screen Recording")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)

                Text("Cobrain takes a screenshot of your\nactive window to read its text via OCR.\nNo images are stored — only the recognized text.")
                    .font(DS.Fonts.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                Text("Nothing leaves your Mac. Ever.")
                    .font(DS.Fonts.caption)
                    .foregroundStyle(DS.Colors.accent)
                    .padding(.top, DS.Spacing.xs)
            }

            if screenRecordingGranted {
                onboardingButton("Continue") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        step = .excludeApps
                    }
                }
            } else {
                onboardingButton("Grant Screen Recording") {
                    requestScreenRecording()
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xxl)
        .onAppear { checkScreenRecording() }
    }

    // MARK: - Exclude Apps

    private var excludeAppsStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(DS.Colors.accent)

            VStack(spacing: DS.Spacing.sm) {
                Text("Privacy Controls")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)

                Text("These apps will never be captured.\nYou can change this anytime in Settings.")
                    .font(DS.Fonts.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: DS.Spacing.xs) {
                ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DS.Colors.success)
                            .font(.system(size: 14))
                        Text(displayName(for: bundleID))
                            .font(DS.Fonts.body)
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                }
            }
            .dsCard()
            .padding(.horizontal, DS.Spacing.lg)

            onboardingButton("Start Capturing") {
                settings.hasCompletedOnboarding = true
                onComplete()
            }
        }
        .padding(.horizontal, DS.Spacing.xxl)
    }

    // MARK: - Shared Components

    private func permissionIcon(_ systemName: String, granted: Bool) -> some View {
        ZStack {
            Circle()
                .fill(granted ? DS.Colors.success.opacity(0.12) : DS.Colors.surface)
                .frame(width: 72, height: 72)

            Image(systemName: systemName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(granted ? DS.Colors.success : DS.Colors.textSecondary)

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Colors.success)
                    .offset(x: 24, y: -24)
            }
        }
    }

    private func onboardingButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: 220)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(DS.Colors.accent)
                )
        }
        .buttonStyle(.plain)
    }

    private var stepIndicator: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s == step ? DS.Colors.accent : DS.Colors.border)
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Permission Helpers

    private func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func requestAccessibility() {
        accessibilityPromptCount += 1
        if accessibilityPromptCount <= 2 {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        // Poll for grant
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                let granted = AXIsProcessTrusted()
                await MainActor.run {
                    accessibilityGranted = granted
                }
                if granted { break }
            }
        }
    }

    private func checkScreenRecording() {
        Task {
            screenRecordingGranted = await ScreenCaptureService.isScreenRecordingGranted()
        }
    }

    private func requestScreenRecording() {
        ScreenCaptureService.requestScreenRecording()
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                let granted = await ScreenCaptureService.isScreenRecordingGranted()
                await MainActor.run {
                    screenRecordingGranted = granted
                }
                if granted { break }
            }
        }
    }

    private func displayName(for bundleID: String) -> String {
        switch bundleID {
        case "com.1password.1password", "com.agilebits.onepassword7": return "1Password"
        case "com.apple.keychainaccess": return "Keychain Access"
        default:
            // Try to get app name from bundle ID
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return FileManager.default.displayName(atPath: url.path)
            }
            return bundleID
        }
    }
}
