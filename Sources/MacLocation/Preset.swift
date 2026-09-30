import Foundation

enum ConfigMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case dhcp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manually (static IP)"
        case .dhcp: return "Using DHCP"
        }
    }
}

/// A named IPv4 configuration that can be applied to a macOS network service
/// (e.g. "Ethernet", "USB 10/100/1000 LAN", "Thunderbolt Bridge").
struct Preset: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var service: String
    var mode: ConfigMode = .manual
    var ipAddress: String = ""
    var subnetMask: String = "255.255.255.0"
    var router: String = ""
    /// Comma or space separated list, kept as typed so editing stays natural.
    var dnsServers: String = ""

    var dnsList: [String] {
        dnsServers
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var trimmedIP: String { ipAddress.trimmingCharacters(in: .whitespaces) }
    private var trimmedRouter: String { router.trimmingCharacters(in: .whitespaces) }

    var summary: String {
        switch mode {
        case .dhcp:
            return "DHCP"
        case .manual:
            if let prefix = IPv4.prefixLength(ofMask: subnetMask) {
                return "\(trimmedIP)/\(prefix)"
            }
            return trimmedIP
        }
    }

    var validationErrors: [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Name is required.")
        }
        if service.isEmpty {
            errors.append("Choose a network service.")
        }
        if mode == .manual {
            if !IPv4.isValidAddress(trimmedIP) {
                errors.append("IP address must be a valid IPv4 address.")
            }
            if IPv4.normalizeMask(subnetMask) == nil {
                errors.append("Subnet mask must be like 255.255.255.0 or a prefix like 24.")
            }
            if !trimmedRouter.isEmpty && !IPv4.isValidAddress(trimmedRouter) {
                errors.append("Router must be a valid IPv4 address or left blank.")
            }
        }
        for server in dnsList where !IPAddress.isValid(server) {
            errors.append("DNS server \"\(server)\" is not a valid IP address.")
        }
        return errors
    }

    var isValid: Bool { validationErrors.isEmpty }

    /// The networksetup argument lists needed to apply this preset.
    var commands: [[String]] {
        var result: [[String]] = []
        switch mode {
        case .dhcp:
            result.append(["-setdhcp", service])
        case .manual:
            var args = ["-setmanual", service, trimmedIP, IPv4.normalizeMask(subnetMask) ?? subnetMask]
            if !trimmedRouter.isEmpty { args.append(trimmedRouter) }
            result.append(args)
        }
        let dns = dnsList
        result.append(["-setdnsservers", service] + (dns.isEmpty ? ["Empty"] : dns))
        return result
    }

    /// Whether the interface's current configuration corresponds to this preset.
    func matches(_ info: InterfaceInfo?) -> Bool {
        guard let info else { return false }
        switch mode {
        case .dhcp:
            return info.isDHCP
        case .manual:
            return !info.isDHCP
                && info.ipAddress == trimmedIP
                && info.subnetMask == IPv4.normalizeMask(subnetMask)
        }
    }
}

extension Preset: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, service, mode, ipAddress, subnetMask, router, dnsServers
    }

    // Tolerant decoding so presets.json can be edited by hand with keys omitted.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        service = try c.decodeIfPresent(String.self, forKey: .service) ?? ""
        mode = try c.decodeIfPresent(ConfigMode.self, forKey: .mode) ?? .manual
        ipAddress = try c.decodeIfPresent(String.self, forKey: .ipAddress) ?? ""
        subnetMask = try c.decodeIfPresent(String.self, forKey: .subnetMask) ?? "255.255.255.0"
        router = try c.decodeIfPresent(String.self, forKey: .router) ?? ""
        if let list = try? c.decodeIfPresent([String].self, forKey: .dnsServers) {
            dnsServers = list.joined(separator: ", ")
        } else {
            dnsServers = try c.decodeIfPresent(String.self, forKey: .dnsServers) ?? ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(service, forKey: .service)
        try c.encode(mode, forKey: .mode)
        try c.encode(ipAddress, forKey: .ipAddress)
        try c.encode(subnetMask, forKey: .subnetMask)
        try c.encode(router, forKey: .router)
        try c.encode(dnsList, forKey: .dnsServers)
    }
}
