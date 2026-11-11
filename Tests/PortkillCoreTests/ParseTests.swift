import Testing
@testable import PortkillCore

@Test func lsofMergesIPv4AndIPv6AndSortsByPort() {
    let out = """
    p612
    crapportd
    Lprchr
    f10
    n*:57141
    f11
    n*:57141
    p901
    cnode
    Lprchr
    f22
    n[::1]:3000
    f23
    n127.0.0.1:3000
    f24
    n[::]:9229
    """
    let ls = parseLsof(out)
    #expect(ls.map(\.port) == [3000, 9229, 57141])
    #expect(ls[0] == Listener(port: 3000, pid: 901, command: "node", user: "prchr", hosts: ["::1", "127.0.0.1"]))
    #expect(!ls[0].isExposed)
    #expect(ls[1].isExposed)
    #expect(ls[2].command == "rapportd" && ls[2].hosts == ["*"])
}

@Test func lsofSkipsNamesWithoutAPort() {
    #expect(parseLsof("p1\ncx\nf3\nnbogus\n").isEmpty)
}

@Test func cwds() {
    #expect(parseCwds("p612\nfcwd\nn/\np901\nfcwd\nn/Users/me/code/shop\n") == [612: "/", 901: "/Users/me/code/shop"])
}

@Test func dockerPortsIncludingIPv6RangesAndUdp() {
    let out = """
    db\t0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp
    web\t0.0.0.0:8000-8002->8000-8002/tcp
    dns\t0.0.0.0:53->53/udp
    worker\t6379/tcp
    v6\t[::]:3000->3000/tcp
    """
    #expect(parseDockerPorts(out) == [5432: "db", 8000: "web", 8001: "web", 8002: "web", 3000: "v6"])
}

@Test func projectPaths() {
    #expect(projectPath("/", home: "/Users/me") == nil)
    #expect(projectPath(nil, home: "/Users/me") == nil)
    #expect(projectPath("/Users/me", home: "/Users/me") == "~")
    #expect(projectPath("/Users/me/code/shop", home: "/Users/me") == "~/code/shop")
    #expect(projectPath("/Users/meg/x", home: "/Users/me") == "/Users/meg/x")
}
