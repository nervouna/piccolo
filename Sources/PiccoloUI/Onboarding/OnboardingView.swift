import PiccoloCore
import SwiftUI

/// What the guide needs from the app that it cannot do itself.
public struct OnboardingHost {
    public var openAccessibilitySettings: @MainActor () -> Void
    public var openSettings: @MainActor () -> Void

    public init(
        openAccessibilitySettings: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.openAccessibilitySettings = openAccessibilitySettings
        self.openSettings = openSettings
    }
}

/// The contents of the guide panel: a title, one or two short sentences, the shortcut as a key cap, a
/// check mark once the step is done, and the buttons.
struct OnboardingView: View {
    static let width: CGFloat = 420

    let model: OnboardingModel
    let host: OnboardingHost
    var characterForKeyCode: @MainActor (Int) -> String? = { KeyboardLayout.character(forKeyCode: $0) }

    private var flow: OnboardingFlow { model.flow }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline)
                Spacer(minLength: 0)
                if flow.isCurrentDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.large)
                }
            }
            content
            buttons
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
    }

    // MARK: Texts per step

    private var title: String {
        switch flow.step {
        case .accessibility: String(localized: "Allow Accessibility", bundle: .module)
        case .moveWindow: String(localized: "Move a window", bundle: .module)
        case .arrange: String(localized: "Arrange windows", bundle: .module)
        case .done: String(localized: "You are all set", bundle: .module)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch flow.step {
        case .accessibility:
            sentence(Text(localized: "Piccolo needs Accessibility to move windows."))
            if !flow.isCurrentDone {
                Button(String(localized: "Open Accessibility Settings…", bundle: .module)) {
                    host.openAccessibilitySettings()
                }
            }
        case .moveWindow:
            shortcutStep(
                prompt: Text(localized: "Click a window, then press this shortcut."), target: flow.move, extra: nil)
        case .arrange:
            shortcutStep(
                prompt: Text(localized: "Click two windows in turn, then press this shortcut."), target: flow.arrange,
                extra: flow.destinationPreview ? Text(localized: "Hold the shortcut to see where the windows go.") : nil)
        case .done:
            sentence(Text(localized: "Every shortcut can be changed in Settings."))
        }
    }

    @ViewBuilder
    private func shortcutStep(
        prompt: Text, target: OnboardingTarget?, extra: Text?
    ) -> some View {
        if !flow.hasGrantForShortcutSteps {
            sentence(Text(localized: "Piccolo needs Accessibility first."))
            Button(String(localized: "Open Accessibility Settings…", bundle: .module)) {
                host.openAccessibilitySettings()
            }
        } else if let target {
            sentence(prompt)
            KeyCap(
                text: ShortcutText.string(for: target.shortcut, character: characterForKeyCode))
            if let extra {
                sentence(extra)
            }
        } else {
            sentence(Text(localized: "There is no shortcut to try."))
            Button(String(localized: "Open Settings", bundle: .module)) {
                host.openSettings()
            }
        }
    }

    private func sentence(_ text: Text) -> some View {
        text
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            if flow.step != .done {
                Button(String(localized: "Skip Guide", bundle: .module)) {
                    model.skipGuide()
                }
                .buttonStyle(.link)
            }
            Spacer(minLength: 0)
            if flow.step == .done {
                Button(String(localized: "Open Settings", bundle: .module)) {
                    host.openSettings()
                }
                Button(String(localized: "Finish", bundle: .module)) {
                    model.finish()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button(String(localized: "Skip", bundle: .module)) {
                    model.skipStep()
                }
                Button(String(localized: "Continue", bundle: .module)) {
                    model.continueStep()
                }
                .disabled(!flow.canContinue)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// A shortcut drawn as a key cap.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 2)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
