import AppKit
import SwiftUI

struct PresetEditorView: View {
    @ObservedObject var store: PresetStore
    let onApply: (Preset) -> Void

    @State private var selection: Preset.ID?
    @State private var services: [String] = []

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 340)
            detail
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 660, minHeight: 420)
        .onAppear {
            services = NetworkSetup.listServices().filter(\.enabled).map(\.name)
            if selection == nil { selection = store.presets.first?.id }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.presets) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name.isEmpty ? "Untitled" : preset.name)
                            Text("\(preset.service) · \(preset.summary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if !preset.isValid {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onMove { store.presets.move(fromOffsets: $0, toOffset: $1) }
            }

            Divider()

            HStack(spacing: 4) {
                Button(action: addPreset) { Image(systemName: "plus") }
                    .help("Add preset")
                Button(action: removeSelected) { Image(systemName: "minus") }
                    .help("Remove preset")
                    .disabled(selection == nil)
                Button(action: duplicateSelected) { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate preset")
                    .disabled(selection == nil)
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                } label: {
                    Image(systemName: "folder")
                }
                .help("Show presets.json in Finder")
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let binding = binding(for: id) {
            PresetDetailView(preset: binding, services: services, onApply: onApply)
                .id(id)
        } else {
            Text("Select a preset, or click + to add one.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A binding looked up by id, so deleting a preset never leaves a stale index.
    private func binding(for id: UUID) -> Binding<Preset>? {
        guard let initial = store.presets.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.presets.first(where: { $0.id == id }) ?? initial },
            set: { newValue in
                if let index = store.presets.firstIndex(where: { $0.id == id }) {
                    store.presets[index] = newValue
                }
            }
        )
    }

    private func addPreset() {
        let service = store.presets.first(where: { $0.id == selection })?.service
            ?? store.services.first
            ?? NetworkSetup.defaultServiceName()
        let preset = Preset(name: "New preset", service: service)
        store.presets.append(preset)
        selection = preset.id
    }

    private func removeSelected() {
        guard let index = store.presets.firstIndex(where: { $0.id == selection }) else { return }
        store.presets.remove(at: index)
        selection = store.presets.indices.contains(index)
            ? store.presets[index].id
            : store.presets.last?.id
    }

    private func duplicateSelected() {
        guard let index = store.presets.firstIndex(where: { $0.id == selection }) else { return }
        var copy = store.presets[index]
        copy.id = UUID()
        copy.name += " copy"
        store.presets.insert(copy, at: index + 1)
        selection = copy.id
    }
}

struct PresetDetailView: View {
    @Binding var preset: Preset
    let services: [String]
    let onApply: (Preset) -> Void

    private var serviceOptions: [String] {
        var options = services
        if !preset.service.isEmpty && !options.contains(preset.service) {
            options.insert(preset.service, at: 0)
        }
        return options
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $preset.name)
                Picker("Network service", selection: $preset.service) {
                    ForEach(serviceOptions, id: \.self) { Text($0).tag($0) }
                }
                Picker("Configure IPv4", selection: $preset.mode) {
                    ForEach(ConfigMode.allCases) { Text($0.label).tag($0) }
                }
            }

            if preset.mode == .manual {
                Section("Address") {
                    TextField("IP address", text: $preset.ipAddress, prompt: Text("192.168.1.10"))
                    TextField("Subnet mask", text: $preset.subnetMask, prompt: Text("255.255.255.0 or 24"))
                    TextField("Router", text: $preset.router, prompt: Text("Optional"))
                }
            }

            Section("DNS") {
                TextField("DNS servers", text: $preset.dnsServers, prompt: Text("Optional, comma separated"))
            }

            if !preset.isValid {
                Section {
                    ForEach(preset.validationErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                HStack {
                    Button("Fill from Current Settings", action: fillFromCurrent)
                        .help("Copy the address currently configured on \(preset.service) into this preset")
                    Spacer()
                    Button("Apply Now") { onApply(preset) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!preset.isValid)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func fillFromCurrent() {
        guard let info = NetworkSetup.getInfo(service: preset.service) else { return }
        preset.mode = info.isDHCP ? .dhcp : .manual
        preset.ipAddress = info.ipAddress ?? ""
        preset.subnetMask = info.subnetMask ?? "255.255.255.0"
        preset.router = info.router ?? ""
    }
}
