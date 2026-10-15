import StillpointFeatures
import StillpointModel
import StillpointUI
import SwiftUI

/// Chooses between loading, the database-problem screen and the main window,
/// and applies the appearance and text size from Settings.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Themed(settings: model.settings) {
            switch model.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let problem):
                DatabaseProblemView(problem: problem)
            case .ready:
                if let store = model.store {
                    MainWindow(store: store)
                }
            }
        }
        .environment(model.clock)
        .frame(minWidth: 720, minHeight: 480)
        .task { model.start() }
    }
}

/// Applies Light / Dark / Black / Automatic and the text-size setting.
struct Themed<Content: View>: View {
    let settings: StillpointModel.Settings
    @ViewBuilder let content: () -> Content

    var body: some View {
        Palettized(appearance: settings.appearance, content: content)
            .environment(\.textScale, TextScale(rawValue: settings.textSize.rawValue) ?? .medium)
            .preferredColorScheme(AppearanceMapping.colorScheme(for: settings.appearance))
    }
}

/// How the Appearance setting maps to SwiftUI's colour scheme and Stillpoint's palette.
enum AppearanceMapping {
    static func colorScheme(for appearance: Appearance) -> ColorScheme? {
        switch appearance {
        case .automatic: nil
        case .light: .light
        case .dark, .black: .dark
        }
    }

    static func variant(for appearance: Appearance, effective scheme: ColorScheme) -> PaletteVariant {
        if appearance == .black { return .black }
        return scheme == .dark ? .dark : .light
    }
}

/// Reads the effective colour scheme (after `preferredColorScheme`) and picks the palette.
private struct Palettized<Content: View>: View {
    let appearance: Appearance
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content().environment(\.palette, .variant(AppearanceMapping.variant(for: appearance, effective: scheme)))
    }
}

struct DatabaseProblemView: View {
    let problem: AppModel.DatabaseProblem
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(problem.message)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack {
                if let backup = problem.backup {
                    Button("Restore Latest Backup") { model.restoreBackup(backup) }
                        .keyboardShortcut(.defaultAction)
                }
                if problem.canStartFresh {
                    Button("Start with an Empty Database") { model.startFresh() }
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
