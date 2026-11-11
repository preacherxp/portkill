import Foundation

/// One process listening on one TCP port. IPv4 and IPv6 sockets on the same port are merged.
public struct Listener: Hashable, Identifiable, Sendable {
    public var port: Int
    public var pid: Int32
    public var command: String
    public var user: String
    public var hosts: [String]

    public init(port: Int, pid: Int32, command: String, user: String, hosts: [String]) {
        self.port = port
        self.pid = pid
        self.command = command
        self.user = user
        self.hosts = hosts
    }

    public var id: String { "\(pid):\(port)" }

    /// Bound to every interface, so reachable from the network, rather than to loopback only.
    public var isExposed: Bool { hosts.contains { $0 == "*" || $0 == "0.0.0.0" || $0 == "::" } }
}

/// Parses `lsof -nP -iTCP -sTCP:LISTEN -F pcnL`, sorted by port.
public func parseLsof(_ output: String) -> [Listener] {
    var result: [Listener] = []
    var index: [String: Int] = [:]
    var pid: Int32 = 0
    var command = ""
    var user = ""
    for line in output.split(separator: "\n") {
        guard let tag = line.first else { continue }
        let value = String(line.dropFirst())
        switch tag {
        case "p": pid = Int32(value) ?? 0; command = ""; user = ""
        case "c": command = value
        case "L": user = value
        case "n":
            guard let (host, port) = splitHostPort(value) else { continue }
            let key = "\(pid):\(port)"
            if let i = index[key] {
                if !result[i].hosts.contains(host) { result[i].hosts.append(host) }
            } else {
                index[key] = result.count
                result.append(Listener(port: port, pid: pid, command: command, user: user, hosts: [host]))
            }
        default: break
        }
    }
    return result.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
}

/// `127.0.0.1:3000` → ("127.0.0.1", 3000), `[::1]:5432` → ("::1", 5432), `*:80` → ("*", 80).
func splitHostPort(_ s: String) -> (String, Int)? {
    guard let colon = s.lastIndex(of: ":"), let port = Int(s[s.index(after: colon)...]) else { return nil }
    var host = String(s[..<colon])
    if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
    return (host, port)
}

/// Parses `lsof -a -p PIDS -d cwd -Fn` into pid → working directory.
public func parseCwds(_ output: String) -> [Int32: String] {
    var map: [Int32: String] = [:]
    var pid: Int32 = 0
    for line in output.split(separator: "\n") {
        switch line.first {
        case "p": pid = Int32(line.dropFirst()) ?? 0
        case "n": map[pid] = String(line.dropFirst())
        default: break
        }
    }
    return map
}

/// Parses `docker ps --format '{{.Names}}\t{{.Ports}}'` into published TCP host port → container name.
/// Handles `0.0.0.0:5432->5432/tcp`, `[::]:3000->3000/tcp` and ranges like `0.0.0.0:8000-8002->8000-8002/tcp`.
public func parseDockerPorts(_ output: String) -> [Int: String] {
    var map: [Int: String] = [:]
    for line in output.split(separator: "\n") {
        let parts = line.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let name = String(parts[0])
        for mapping in parts[1].split(separator: ",") {
            guard mapping.hasSuffix("/tcp"), let arrow = mapping.range(of: "->") else { continue }
            let hostSide = mapping[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
            guard let colon = hostSide.lastIndex(of: ":") else { continue }
            let bounds = hostSide[hostSide.index(after: colon)...].split(separator: "-").compactMap { Int($0) }
            guard let lo = bounds.first, let hi = bounds.last, lo <= hi else { continue }
            for port in lo...hi { map[port] = name }
        }
    }
    return map
}

/// Shortens a path under `home` to `~/…`. Returns nil for `/`, which is where GUI apps run, so it says nothing.
public func projectPath(_ cwd: String?, home: String) -> String? {
    guard let cwd, cwd != "/" else { return nil }
    if cwd == home { return "~" }
    if cwd.hasPrefix(home + "/") { return "~" + cwd.dropFirst(home.count) }
    return cwd
}
