import Foundation

/// Small helpers for validating and normalising IPv4 addresses and masks.
enum IPv4 {
    /// Parses a strict dotted-quad string ("192.168.1.10") into a 32-bit value.
    static func parse(_ string: String) -> UInt32? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3,
                  part.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        return value
    }

    static func format(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }

    static func isValidAddress(_ string: String) -> Bool {
        parse(string) != nil
    }

    /// Accepts a dotted mask ("255.255.255.0") or a prefix length ("24" or "/24")
    /// and returns the dotted form, or nil if it is not a valid contiguous mask.
    static func normalizeMask(_ string: String) -> String? {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("/") { text.removeFirst() }

        if let prefix = Int(text) {
            guard (1...32).contains(prefix) else { return nil }
            return format(UInt32.max << UInt32(32 - prefix))
        }

        guard let mask = parse(text), mask != 0 else { return nil }
        let inverted = ~mask
        guard inverted & (inverted &+ 1) == 0 else { return nil }
        return format(mask)
    }

    static func prefixLength(ofMask mask: String) -> Int? {
        guard let dotted = normalizeMask(mask), let value = parse(dotted) else { return nil }
        return value.nonzeroBitCount
    }
}

enum IPAddress {
    /// True for a valid IPv4 or IPv6 address (used for DNS servers).
    static func isValid(_ string: String) -> Bool {
        if IPv4.isValidAddress(string) { return true }
        var addr = in6_addr()
        return string.withCString { inet_pton(AF_INET6, $0, &addr) } == 1
    }
}
