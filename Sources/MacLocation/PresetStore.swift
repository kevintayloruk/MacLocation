import Foundation

/// Loads and saves presets as JSON in ~/Library/Application Support/MacLocation/presets.json.
final class PresetStore: ObservableObject {
    @Published var presets: [Preset] {
        didSet { save() }
    }

    let fileURL: URL
    /// True when no presets file existed yet, i.e. the app is running for the first time.
    let isFirstLaunch: Bool

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = support.appendingPathComponent("MacLocation", isDirectory: true)
            .appendingPathComponent("presets.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = decoded
            isFirstLaunch = false
        } else {
            isFirstLaunch = !FileManager.default.fileExists(atPath: fileURL.path)
            presets = PresetStore.examplePresets()
            save()
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(presets).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("MacLocation: failed to save presets: \(error)")
        }
    }

    /// Services referenced by presets, in the order they first appear.
    var services: [String] {
        var seen = Set<String>()
        return presets.map(\.service).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func examplePresets() -> [Preset] {
        let service = NetworkSetup.defaultServiceName()
        return [
            Preset(name: "DHCP (normal)", service: service, mode: .dhcp),
            Preset(name: "192.168.0.x device", service: service, ipAddress: "192.168.0.250"),
            Preset(name: "192.168.1.x device", service: service, ipAddress: "192.168.1.250"),
            Preset(name: "10.0.0.x device", service: service, ipAddress: "10.0.0.250"),
        ]
    }
}
