import PiccoloCore
import SwiftUI

/// The "Shortcuts" tab: a keymap. A top bar with the search and the "⋯" menu, the banner of config problems, and
/// the cards of the sections with a row per action, in the order of ``KeymapSection``. Errors show where they
/// happen: under a row, or in the banner.
struct ShortcutsTab: View {
    /// The height of the search field, which the "⋯" button shares.
    static let controlHeight: CGFloat = 26
    /// The width of the "⋯" button.
    static let menuWidth: CGFloat = 30
    /// The corner radius of the search field, which the "⋯" button shares.
    static let cornerRadius: CGFloat = 6

    @Bindable var model: SettingsModel
    let host: SettingsHost

    var body: some View {
        VStack(spacing: 8) {
            topBar
            ProblemsBanner(model: model)
                .padding(.horizontal, 16)
            keymap
        }
        .alert(
            Text(localized: "Restore the default shortcuts?"), isPresented: $model.isConfirmingRestore
        ) {
            Button(role: .destructive) {
                model.restoreDefaultShortcuts()
            } label: {
                Text(localized: "Restore")
            }
            Button(role: .cancel) {
                model.cancelRestoreDefaults()
            } label: {
                Text(localized: "Cancel")
            }
        } message: {
            Text(
                localized:
                    "The current shortcuts will be replaced by the defaults. A copy of the config file is kept next to it."
            )
        }
        .sheet(item: LayoutEditorSheet.presentation(of: model)) { presentation in
            LayoutEditorSheet(model: model, request: presentation.request)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        controls
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    /// The search field and the "⋯" button on one row. Internal, so that the render tests can measure them.
    var controls: some View {
        HStack(spacing: 8) {
            searchField
            menu
        }
    }

    var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                String(localized: "Search", bundle: .module),
                text: Binding(get: { model.search }, set: { model.setSearch($0) })
            )
            .textFieldStyle(.plain)
            .onExitCommand {
                model.setSearch("")
            }
            if !model.search.isEmpty {
                Button {
                    model.setSearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(localized: "Clear Search"))
                .accessibilityLabel(Text(localized: "Clear Search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: Self.controlHeight)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    /// The "⋯" button, which opens the menu. Internal, so that the render tests can measure it.
    var menu: some View {
        MoreMenuButton(model: model, host: host)
    }

    // MARK: Cards

    @ViewBuilder
    private var keymap: some View {
        let groups = model.keymap
        if groups.isEmpty {
            Text(localized: "No shortcuts match")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.section) { group in
                            KeymapCard(model: model, group: group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // A click on anything that is not a control ends a recording.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if model.isRecording {
                            model.cancelRecording()
                        }
                    }
                }
                .onChange(of: model.recordingRow) { _, row in
                    if let row {
                        proxy.scrollTo(row)
                    }
                }
            }
        }
    }
}

/// The "⋯" button next to the search field: the system's bordered button, a small square as tall as the search
/// field and with its corner radius, which pops a menu up under it. It is a `Button` and not a `Menu`: a `Menu`
/// draws the system's short capsule whatever its button style, border shape and frame, and a borderless one draws
/// nothing but its label.
private struct MoreMenuButton: View {
    let model: SettingsModel
    let host: SettingsHost

    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            popUpMenu()
        } label: {
            // The label fills the button, so that the frame below sets the size of the bezel.
            Image(systemName: "ellipsis")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: ShortcutsTab.cornerRadius))
        .frame(width: ShortcutsTab.menuWidth, height: ShortcutsTab.controlHeight)
        .background { MenuAnchorView(anchor: anchor).allowsHitTesting(false) }
        .accessibilityLabel(Text(localized: "More"))
    }

    /// Shows the menu with its top-left corner at the button's bottom-left corner.
    private func popUpMenu() {
        guard let view = anchor.view else { return }
        let entries = [
            MenuEntry(
                title: String(localized: "Restore Default Shortcuts…", bundle: .module),
                toolTip: String(
                    localized:
                        "Replace every shortcut with the defaults. A copy of the config file is kept next to it.",
                    bundle: .module)
            ) { [model] in
                model.askToRestoreDefaults()
            },
            MenuEntry(title: String(localized: "Reveal Config in Finder", bundle: .module)) { [host] in
                host.revealConfigInFinder()
            },
        ]
        let menu = NSMenu()
        for entry in entries {
            menu.addItem(entry.item)
        }
        let bottom = view.isFlipped ? view.bounds.maxY : view.bounds.minY
        // An item does not retain its target: the entries stay alive until the menu is gone.
        withExtendedLifetime(entries) {
            _ = menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: bottom), in: view)
        }
    }
}

/// The view a menu is popped up under, which the button's background holds on to.
@MainActor
private final class MenuAnchor {
    weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

/// A menu item that runs a closure.
@MainActor
private final class MenuEntry: NSObject {
    let item = NSMenuItem()
    private let run: @MainActor () -> Void

    init(title: String, toolTip: String? = nil, run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init()
        item.title = title
        item.toolTip = toolTip
        item.action = #selector(runClosure)
        item.target = self
    }

    @objc private func runClosure() {
        run()
    }
}

/// The card of one section: its header, a row per action and, for grids and custom areas, the row that adds one.
private struct KeymapCard: View {
    let model: SettingsModel
    let group: KeymapGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.section.title())
                .font(.headline)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().padding(.leading, 12)
                    }
                    KeymapRowView(model: model, row: row)
                        .id(row.id)
                }
                if let title = group.section.addRowTitle() {
                    if !group.rows.isEmpty {
                        Divider().padding(.leading, 12)
                    }
                    addRow(title)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }

    private func addRow(_ title: String) -> some View {
        Button {
            model.editLayout(.new(group.section))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .frame(width: ActionGlyph.size.width)
                Text(title)
                Spacer()
            }
            .foregroundStyle(Color(nsColor: .controlAccentColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
