import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
enum MacLocationMain {
    // NSApplication.delegate is weak, so the delegate must be kept alive here;
    // a local variable can be released by the optimiser before app.run().
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = PresetStore()
    private var statusItem: NSStatusItem!
    private var editorWindow: NSWindow?
    private var infos: [String: InterfaceInfo] = [:]
    private var isApplying = false
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let showNameKey = "ShowPresetNameInMenuBar"
    private var showNameInMenuBar: Bool {
        get { UserDefaults.standard.object(forKey: showNameKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showNameKey) }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "MacLocation")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.imagePosition = .imageLeading
        statusItem.autosaveName = "MacLocationStatusItem"
        statusItem.isVisible = true

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        store.$presets
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshInBackground() }
            .store(in: &cancellables)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshInBackground()
        }
        refreshInBackground()

        // A menu bar app has no window, so on first run open the editor to show it started.
        if store.isFirstLaunch { showEditor() }
    }

    /// Double-clicking the app while it is already running opens the preset editor,
    /// which also helps if the menu bar icon is hidden (e.g. behind the notch).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showEditor()
        return false
    }

    /// An accessory app has no visible menu bar, but a main menu is still needed
    /// so that ⌘C / ⌘V / ⌘W etc. work in the preset editor.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit MacLocation", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status

    private func refreshInBackground() {
        let services = store.services
        DispatchQueue.global(qos: .utility).async {
            let infos = AppDelegate.fetchInfos(services)
            DispatchQueue.main.async {
                self.infos = infos
                self.updateStatusButton()
            }
        }
    }

    private static func fetchInfos(_ services: [String]) -> [String: InterfaceInfo] {
        var result: [String: InterfaceInfo] = [:]
        for service in services {
            result[service] = NetworkSetup.getInfo(service: service)
        }
        return result
    }

    private var activePreset: Preset? {
        // Prefer a matching static preset over a generic DHCP one.
        let matching = store.presets.filter { $0.matches(infos[$0.service]) }
        return matching.first { $0.mode == .manual } ?? matching.first
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        if isApplying {
            button.title = " Applying…"
        } else if showNameInMenuBar, let active = activePreset {
            button.title = " " + active.name
        } else {
            button.title = ""
        }
        button.toolTip = activePreset.map { "MacLocation: \($0.name)" } ?? "MacLocation"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        infos = AppDelegate.fetchInfos(store.services)
        updateStatusButton()

        if isApplying {
            menu.addItem(disabledItem("Applying settings…"))
            menu.addItem(.separator())
        }

        if store.presets.isEmpty {
            menu.addItem(disabledItem("No presets yet"))
        }

        for service in store.services {
            let header = disabledItem(service)
            header.attributedTitle = NSAttributedString(
                string: service,
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
            menu.addItem(header)

            let status = disabledItem(infos[service]?.summary ?? "Not available")
            status.indentationLevel = 1
            menu.addItem(status)

            let presets = store.presets.filter { $0.service == service }
            for preset in presets {
                let item = NSMenuItem(title: preset.name, action: #selector(applyPresetFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id
                item.indentationLevel = 1
                item.state = preset.matches(infos[service]) ? .on : .off
                item.isEnabled = preset.isValid && !isApplying
                item.toolTip = preset.isValid
                    ? preset.summary
                    : preset.validationErrors.joined(separator: "\n")
                if preset.mode == .manual {
                    item.attributedTitle = titleWithDetail(preset.name, detail: preset.summary)
                }
                menu.addItem(item)
            }

            if !presets.contains(where: { $0.mode == .dhcp }) {
                let dhcp = NSMenuItem(title: "Use DHCP", action: #selector(useDHCP(_:)), keyEquivalent: "")
                dhcp.target = self
                dhcp.representedObject = service
                dhcp.indentationLevel = 1
                dhcp.state = infos[service]?.isDHCP == true ? .on : .off
                dhcp.isEnabled = !isApplying
                menu.addItem(dhcp)
            }
            menu.addItem(.separator())
        }

        menu.addItem(actionItem("Edit Presets…", #selector(showEditor), key: ","))
        menu.addItem(actionItem("Open Network Settings…", #selector(openNetworkSettings)))
        menu.addItem(.separator())

        let showName = actionItem("Show Preset Name in Menu Bar", #selector(toggleShowName))
        showName.state = showNameInMenuBar ? .on : .off
        menu.addItem(showName)

        let login = actionItem("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit MacLocation", #selector(quit), key: "q"))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func titleWithDetail(_ title: String, detail: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title,
            attributes: [.font: NSFont.menuFont(ofSize: 0)])
        result.append(NSAttributedString(
            string: "   " + detail,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        return result
    }

    // MARK: - Actions

    @objc private func applyPresetFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let preset = store.presets.first(where: { $0.id == id }) else { return }
        apply(preset)
    }

    @objc private func useDHCP(_ sender: NSMenuItem) {
        guard let service = sender.representedObject as? String else { return }
        apply(Preset(name: "DHCP", service: service, mode: .dhcp))
    }

    private func apply(_ preset: Preset) {
        guard preset.isValid else {
            showAlert(title: "“\(preset.name)” is not valid", message: preset.validationErrors.joined(separator: "\n"))
            return
        }
        guard !isApplying else { return }
        isApplying = true
        updateStatusButton()

        let commands = preset.commands
        let services = store.services.contains(preset.service) ? store.services : store.services + [preset.service]
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try NetworkSetup.apply(commands) }
            // Give configd a moment to publish the new configuration before checking it.
            Thread.sleep(forTimeInterval: 1)
            let infos = AppDelegate.fetchInfos(services)

            DispatchQueue.main.async {
                self.isApplying = false
                self.infos = infos
                self.updateStatusButton()

                switch result {
                case .success:
                    if !preset.matches(infos[preset.service]) {
                        self.showAlert(
                            title: "“\(preset.name)” may not have applied",
                            message: "\(preset.service) now reports: \(infos[preset.service]?.summary ?? "no information").")
                    }
                case .failure(let error):
                    if case .cancelled? = error as? NetworkSetupError { break }
                    self.showAlert(title: "Couldn’t apply “\(preset.name)”", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func showEditor() {
        if editorWindow == nil {
            let view = PresetEditorView(store: store) { [weak self] preset in self?.apply(preset) }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "MacLocation Presets"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 480))
            window.isReleasedWhenClosed = false
            window.center()
            editorWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleShowName() {
        showNameInMenuBar.toggle()
        updateStatusButton()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(
                title: "Couldn’t change Launch at Login",
                message: "\(error.localizedDescription)\n\nThis only works when MacLocation is run as an app bundle (e.g. from /Applications).")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
