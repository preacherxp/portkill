import AppKit
import PortkillCore
import SwiftUI

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            snapshot(to: args[i + 1])
        } else {
            PortkillApp.main()
        }
    }
}

struct PortkillApp: App {
    @State private var store = Store(polling: true)

    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
            Text("\(store.rows.count)")
        }
        .menuBarExtraStyle(.window)
    }
}

struct Row: Identifiable, Hashable {
    var listener: Listener
    var project: String?
    var container: String?
    var id: String { listener.id }
    /// Dev servers and containers: things started from a folder, rather than GUI apps and system daemons.
    var isDev: Bool { project != nil || container != nil }
}

enum KillState: Equatable {
    case stopping
    case stuck
    case failed(String)
}

@MainActor @Observable
final class Store {
    var rows: [Row] = []
    var states: [String: KillState] = [:]

    init(polling: Bool) {
        guard polling else { return }
        // ponytail: polls every 10s to keep the menu bar count fresh; a kqueue/NWListener watcher if this ever shows up in Activity Monitor.
        Task { [weak self] in
            while let self {
                await self.refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func refresh() async {
        rows = await Task.detached { Store.load() }.value
        states = states.filter { id, _ in rows.contains { $0.id == id } }
    }

    nonisolated static func load() -> [Row] {
        let listeners = parseLsof(run(lsof, ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcnL"]).out)
        let pids = Set(listeners.map(\.pid)).map(String.init).joined(separator: ",")
        let cwds = pids.isEmpty ? [:] : parseCwds(run(lsof, ["-a", "-p", pids, "-d", "cwd", "-Fn"]).out)
        let ports = docker.map { parseDockerPorts(run($0, ["ps", "--format", "{{.Names}}\t{{.Ports}}"]).out) } ?? [:]
        let home = NSHomeDirectory()
        return listeners.map {
            Row(listener: $0, project: projectPath(cwds[$0.pid], home: home), container: ports[$0.port])
        }
    }

    func stop(_ row: Row) {
        let pid = row.listener.pid
        states[row.id] = .stopping
        Task {
            if let name = row.container, let docker = Store.docker {
                let result = await Task.detached { run(docker, ["stop", name]) }.value
                if result.status != 0 {
                    states[row.id] = .failed(result.err.isEmpty ? "docker stop failed" : result.err)
                    return
                }
            } else {
                guard kill(pid, SIGTERM) == 0 else {
                    states[row.id] = .failed(String(cString: strerror(errno)))
                    return
                }
                if await !exits(pid) {
                    states[row.id] = .stuck
                    return
                }
            }
            states[row.id] = nil
            await refresh()
        }
    }

    func forceKill(_ row: Row) {
        guard kill(row.listener.pid, SIGKILL) == 0 else {
            states[row.id] = .failed(String(cString: strerror(errno)))
            return
        }
        states[row.id] = .stopping
        Task {
            _ = await exits(row.listener.pid)
            states[row.id] = nil
            await refresh()
        }
    }

    /// Waits up to 2 seconds for `pid` to go away.
    private func exits(_ pid: Int32) async -> Bool {
        for _ in 0..<20 {
            if kill(pid, 0) != 0 { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return kill(pid, 0) != 0
    }

    nonisolated static let lsof = "/usr/sbin/lsof"

    /// GUI apps don't inherit the shell's PATH, so look where Docker Desktop, Homebrew and OrbStack put it.
    nonisolated static let docker: String? = {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let known = ["/usr/local/bin", "/opt/homebrew/bin", "/Applications/Docker.app/Contents/Resources/bin",
                     NSHomeDirectory() + "/.docker/bin", NSHomeDirectory() + "/.orbstack/bin"]
        return (path + known).map { $0 + "/docker" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()
}

func run(_ tool: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return (-1, "", error.localizedDescription) }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: o, as: UTF8.self),
            String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

/// Renders the real panel with live data to a 2x PNG, for READMEs. Hidden flag: `portkill --snapshot out.png`.
@MainActor
func snapshot(to path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: .darkAqua)
    let store = Store(polling: false)
    store.rows = Store.load()
    let view = NSHostingView(rootView: Panel(store: store).background(Color(nsColor: .windowBackgroundColor)))
    view.frame.size = view.fittingSize
    let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    // Let SwiftUI finish a layout pass before capturing.
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
                               pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    do {
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    } catch {
        FileHandle.standardError.write(Data("snapshot: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    exit(0)
}
