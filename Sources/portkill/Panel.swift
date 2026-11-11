import AppKit
import PortkillCore
import SwiftUI

struct Panel: View {
    @Bindable var store: Store
    @State private var query = ""
    @FocusState private var searching: Bool

    private var matches: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.rows }
        return store.rows.filter {
            [String($0.listener.port), $0.listener.command, $0.project ?? "", $0.container ?? ""]
                .contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Port, app or folder", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searching)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))

                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r")
                .help("Refresh (⌘R)")
            }
            .padding(10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    section("Dev servers", matches.filter(\.isDev))
                    section("Apps and system", matches.filter { !$0.isDev })
                    if matches.isEmpty {
                        Text(query.isEmpty ? "Nothing is listening" : "No matches")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text(store.rows.count == 1 ? "1 listening port" : "\(store.rows.count) listening ports")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 380)
        .onAppear { searching = true }
        // The panel is this app's only window, so it becoming key means the menu was just opened.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await store.refresh() }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [Row]) -> some View {
        if !rows.isEmpty {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(rows) { RowView(row: $0, store: store) }
        }
    }
}

struct RowView: View {
    let row: Row
    let store: Store
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: String(row.listener.port))
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                .frame(width: 58, alignment: .trailing)

            icon.frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title).lineLimit(1)
                    if row.listener.isExposed {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Listening on all interfaces, reachable from your network")
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)
            action
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .help(row.project.map { "\($0)\n\(row.listener.command), PID \(row.listener.pid)" } ?? "")
        .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy localhost:\(String(row.listener.port))") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("localhost:\(row.listener.port)", forType: .string)
            }
            Button("Open in Browser") {
                NSWorkspace.shared.open(URL(string: "http://localhost:\(row.listener.port)")!)
            }
        }
    }

    private var failure: String? {
        if case .failed(let message) = store.states[row.id] { return message }
        return nil
    }

    /// The container, else the project folder's name, else the process: whichever you'd recognise first.
    private var title: String {
        row.container ?? row.project.map { ($0 as NSString).lastPathComponent } ?? row.listener.command
    }

    private var subtitle: String {
        if let failure { return failure }
        if row.container != nil { return "Docker container" }
        return "\(row.listener.command) · PID \(row.listener.pid)"
    }

    @ViewBuilder private var icon: some View {
        if row.container != nil {
            Image(systemName: "shippingbox.fill").font(.title3).foregroundStyle(.tint)
        } else if let app = NSRunningApplication(processIdentifier: row.listener.pid), app.bundleURL != nil,
                  let image = app.icon {
            Image(nsImage: image).resizable()
        } else {
            Image(systemName: "terminal.fill").font(.title3).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var action: some View {
        switch store.states[row.id] {
        case .stopping:
            ProgressView().controlSize(.small).frame(width: 20)
        case .stuck:
            Button("Force Quit") { store.forceKill(row) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .help("Still running after SIGTERM. Sends SIGKILL.")
        default:
            Button { store.stop(row) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(hovering ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.borderless)
            .help(row.container.map { "docker stop \($0)" } ?? "Quit \(row.listener.command) (SIGTERM)")
        }
    }
}
