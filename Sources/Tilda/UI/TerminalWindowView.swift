import AppKit
import SwiftUI

struct TerminalWindowView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var preferences: Preferences
    @FocusState private var searchFocused: Bool
    private var theme: TerminalTheme { .named(preferences.value.theme) }
    private var muted: Color { Color(nsColor: theme.foreground).opacity(0.5) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text("~").font(.system(size: 27, weight: .bold, design: .monospaced)).foregroundStyle(Color(nsColor: theme.accent))
                    Text("tilda").font(.system(size: 15, weight: .semibold))
                }.padding(.leading, 18).accessibilityElement(children: .combine)
                Rectangle().fill(muted.opacity(0.25)).frame(width: 1, height: 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                            tabButton(tab, index: index)
                        }
                    }.padding(.vertical, 8)
                }
                HStack(spacing: 3) {
                    tool("plus", help: "New tab · ⌘T") { workspace.newTab() }
                    Menu {
                        Button("Split Right", action: { workspace.split(vertical: true) })
                        Button("Split Below", action: { workspace.split(vertical: false) })
                        Button("Next Pane", action: workspace.cyclePane)
                    } label: { Image(systemName: "rectangle.split.2x1").frame(width: 27, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Split terminal")
                    tool(workspace.pinned ? "pin.fill" : "pin", help: "Keep open when focus changes", active: workspace.pinned) { workspace.pinned.toggle() }
                    tool("gearshape", help: "Preferences · ⌘,") { workspace.showPreferences?() }
                    tool("chevron.up", help: "Hide · \(preferences.value.shortcut.label)") { workspace.hide?() }
                }.padding(.trailing, 12)
            }.frame(height: 52).background(Color(nsColor: theme.foreground).opacity(0.025))
            divider
            if workspace.searchVisible { searchBar; divider }
            if let tab = workspace.activeTab {
                PaneHost(tab: tab, theme: theme)
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            divider
            HStack(spacing: 10) {
                Circle().fill(Color(nsColor: workspace.activeSession?.exited == true ? .hex("F07F88") : theme.accent)).frame(width: 5, height: 5)
                Text(workspace.activeSession?.locationLabel ?? "LOCAL")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                Text(workspace.activeSession?.displayLocation ?? "").font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 12)
                if let pane = workspace.activeSession {
                    Text("\(pane.columns) × \(pane.rows)").font(.system(size: 10, design: .monospaced)).monospacedDigit()
                }
                Text(preferences.value.shortcut.label).font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2).background(muted.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }.foregroundStyle(muted).padding(.horizontal, 19).frame(height: 30)
        }
        .foregroundStyle(Color(nsColor: theme.foreground))
        .background(Color(nsColor: theme.background))
        .clipShape(UnevenBottomCorners())
        .overlay(UnevenBottomCorners().strokeBorder(Color(nsColor: theme.foreground).opacity(0.12), lineWidth: 1))
        .onChange(of: workspace.searchVisible) { visible in if visible { searchFocused = true } }
    }
    private var divider: some View { Rectangle().fill(muted.opacity(0.18)).frame(height: 1) }
    private func tool(_ symbol: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(active ? Color(nsColor: theme.accent) : muted).frame(width: 28, height: 28)
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
    private func tabButton(_ tab: TerminalTab, index: Int) -> some View {
        let selected = tab.id == workspace.selectedTab
        return HStack(spacing: 7) {
            Button { workspace.selectTab(tab.id) } label: {
                HStack(spacing: 7) {
                    Image(systemName: tab.sessions.count > 1 ? "rectangle.split.2x1" : "terminal").font(.system(size: 11))
                    Text(tab.title).font(.system(size: 11, weight: selected ? .medium : .regular)).lineLimit(1).frame(maxWidth: 140)
                    if index < 9 { Text("\(index + 1)").font(.system(size: 9, design: .monospaced)).opacity(0.35) }
                }.padding(.leading, 10).padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { workspace.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 8)).frame(width: 20, height: 24) }
                .buttonStyle(.plain).help("Close tab")
        }
        .foregroundStyle(selected ? Color(nsColor: theme.foreground) : muted)
        .background(selected ? Color(nsColor: theme.foreground).opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .bottom) { if selected { Capsule().fill(Color(nsColor: theme.accent)).frame(height: 2).padding(.horizontal, 12) } }
    }
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(muted)
            TextField("Find in terminal…", text: $workspace.searchQuery)
                .textFieldStyle(.plain).focused($searchFocused)
                .onSubmit { workspace.find() }
                .onChange(of: workspace.searchQuery) { _ in workspace.find(reset: true) }
            Text(workspace.matchLabel).font(.caption).foregroundStyle(muted)
            Toggle("Aa", isOn: $workspace.caseSensitive).help("Match case")
            Toggle(".*", isOn: $workspace.regex).help("Regular expression")
            tool("chevron.up", help: "Previous match") { workspace.find(previous: true) }
            tool("chevron.down", help: "Next match") { workspace.find() }
            tool("xmark", help: "Close search") { workspace.searchVisible = false; workspace.focus() }
        }.toggleStyle(.button).font(.system(size: 11)).padding(.horizontal, 18).frame(height: 40)
            .onChange(of: workspace.caseSensitive) { _ in workspace.find(reset: true) }
            .onChange(of: workspace.regex) { _ in workspace.find(reset: true) }
    }
}

private struct UnevenBottomCorners: InsettableShape {
    var insetAmount: CGFloat = 0
    func inset(by amount: CGFloat) -> some InsettableShape { var shape = self; shape.insetAmount += amount; return shape }
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, 13 - insetAmount)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath(); return p
    }
}

struct PaneHost: NSViewRepresentable {
    let tab: TerminalTab
    let theme: TerminalTheme
    func makeNSView(context: Context) -> TerminalSplitView { TerminalSplitView() }
    func updateNSView(_ split: TerminalSplitView, context: Context) {
        let ids = tab.sessions.map(\.id)
        let changed = split.sessionIDs != ids || split.isVertical != tab.vertical
        split.dividerColorValue = theme.foreground.withAlphaComponent(0.15)
        if changed {
            split.sessionIDs = ids; split.isVertical = tab.vertical
            split.arrangedSubviews.forEach { split.removeArrangedSubview($0); $0.removeFromSuperview() }
            for session in tab.sessions {
                session.view.removeFromSuperview()
                split.addArrangedSubview(session.view)
            }
            split.adjustSubviews()
            DispatchQueue.main.async { [weak split] in
                guard let split, split.sessionIDs == ids, ids.count > 1 else { return }
                split.layoutSubtreeIfNeeded()
                let length = split.isVertical ? split.bounds.width : split.bounds.height
                for index in 0..<(ids.count - 1) {
                    split.setPosition(length * CGFloat(index + 1) / CGFloat(ids.count), ofDividerAt: index)
                }
            }
        }
    }
}

final class TerminalSplitView: NSSplitView {
    var sessionIDs: [UUID] = []
    var dividerColorValue: NSColor = .separatorColor
    override var dividerColor: NSColor { dividerColorValue }
    override var dividerThickness: CGFloat { 1 }
}
