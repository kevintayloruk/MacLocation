import Foundation

struct NetworkService: Hashable {
    let name: String
    let enabled: Bool
}

struct InterfaceInfo: Equatable {
    var isDHCP: Bool
    var ipAddress: String?
    var subnetMask: String?
    var router: String?

    var summary: String {
        let mode = isDHCP ? "DHCP" : "Manual"
        guard let ip = ipAddress else { return "\(mode) · no address" }
        if let mask = subnetMask, let prefix = IPv4.prefixLength(ofMask: mask) {
            return "\(mode) · \(ip)/\(prefix)"
        }
        return "\(mode) · \(ip)"
    }
}

enum NetworkSetupError: LocalizedError {
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        case .cancelled: return "Cancelled."
        }
    }
}

/// Thin wrapper around /usr/sbin/networksetup.
enum NetworkSetup {
    static let tool = "/usr/sbin/networksetup"

    struct Output {
        let status: Int32
        let text: String
    }

    static func run(_ arguments: [String], executable: String = tool) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Output(status: -1, text: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(status: process.terminationStatus, text: String(decoding: data, as: UTF8.self))
    }

    static func listServices() -> [NetworkService] {
        run(["-listallnetworkservices"]).text
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty && !$0.contains("asterisk") }
            .map { line in
                line.hasPrefix("*")
                    ? NetworkService(name: String(line.dropFirst()), enabled: false)
                    : NetworkService(name: line, enabled: true)
            }
    }

    /// Picks a sensible wired service to use for new presets.
    static func defaultServiceName() -> String {
        let enabled = listServices().filter(\.enabled).map(\.name)
        let wired = enabled.first { name in
            ["Ethernet", "LAN", "USB", "Thunderbolt", "Dock"].contains { name.localizedCaseInsensitiveContains($0) }
        }
        return wired ?? enabled.first ?? "Ethernet"
    }

    static func getInfo(service: String) -> InterfaceInfo? {
        let lines = run(["-getinfo", service]).text.split(separator: "\n").map(String.init)
        guard let header = lines.first(where: { $0.hasSuffix("Configuration") }) else { return nil }

        func value(_ prefix: String) -> String? {
            guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return nil }
            let v = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return v.isEmpty || v == "none" ? nil : v
        }

        return InterfaceInfo(
            isDHCP: header.hasPrefix("DHCP"),
            ipAddress: value("IP address:"),
            subnetMask: value("Subnet mask:"),
            router: value("Router:")
        )
    }

    /// Runs the given networksetup commands. They are first tried as the current
    /// user; if macOS refuses for lack of privileges, they are re-run in one batch
    /// through an administrator authentication prompt.
    static func apply(_ commands: [[String]]) throws {
        for args in commands {
            let output = run(args)
            guard isFailure(output) else { continue }
            let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.contains("not a recognized network service") || text.contains("not valid") {
                throw NetworkSetupError.failed(text)
            }
            try runElevated(commands)
            return
        }
    }

    private static func isFailure(_ output: Output) -> Bool {
        if output.status != 0 { return true }
        let text = output.text.lowercased()
        return text.contains("error") || text.contains("admin") || text.contains("privilege")
            || text.contains("not a recognized") || text.contains("not valid")
    }

    private static func runElevated(_ commands: [[String]]) throws {
        let shell = commands
            .map { ([tool] + $0).map(shellQuote).joined(separator: " ") }
            .joined(separator: " && ")
        let script = "do shell script \"\(appleScriptEscape(shell))\" "
            + "with prompt \"MacLocation wants to change your network settings.\" "
            + "with administrator privileges"

        let output = run(["-e", script], executable: "/usr/bin/osascript")
        if output.text.contains("-128") { throw NetworkSetupError.cancelled }
        if isFailure(output) {
            throw NetworkSetupError.failed(output.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
