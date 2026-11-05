import AppKit
import ApplicationServices
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = BrightnessController()
    private let hud = BrightnessHUD()
    private lazy var keyTap = MediaKeyTap { [weak self] key, flags in self?.handle(key, flags: flags) }
    private var statusItem: NSStatusItem!
    private let headerItem = NSMenuItem()
    private let powerItem = NSMenuItem(title: "On battery — boost is manual", action: nil, keyEquivalent: "")
    private let slider = NSSlider(value: 100, minValue: 0, maxValue: BrightnessController.maxPercent, target: nil, action: nil)
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let peakMenu = NSMenu()
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private let automaticUpdatesItem = NSMenuItem(title: "Automatically Update", action: #selector(toggleAutomaticUpdates), keyEquivalent: "")
    private var permissionTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        CGDisplayRestoreColorSyncSettings()
        buildStatusItem()
        controller.onChange = { [weak self] in self?.refreshMenu() }
        installSignalHandlers()
        startKeyTap()
        updaterController.startUpdater()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenu()
    }

    private func handle(_ key: MediaKeyTap.Key, flags: NSEvent.ModifierFlags) {
        let fine = flags.contains(.option) && flags.contains(.shift)
        let percent = controller.step(key, fine: fine)
        hud.show(title: "Built-in Display", percent: percent, nits: controller.nits(for: percent))
    }

    private func startKeyTap() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DiagnosticLog.write("launch: accessibility trusted=\(trusted)")
        if trusted, keyTap.start() {
            DiagnosticLog.write("key tap started at launch")
            refreshMenu()
            return
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.keyTap.start() else { return }
            DiagnosticLog.write("key tap started after permission granted")
            timer.invalidate()
            self.permissionTimer = nil
            self.refreshMenu()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
        refreshMenu()
    }

    private func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.controller.stop()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max.circle", accessibilityDescription: "NitBoost")

        let menu = NSMenu()
        menu.delegate = self
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isContinuous = true
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        slider.frame = NSRect(x: 18, y: 4, width: 224, height: 22)
        sliderView.addSubview(slider)
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        powerItem.isEnabled = false
        menu.addItem(powerItem)
        menu.addItem(.separator())

        for nits in BrightnessController.peakNitChoices {
            let item = NSMenuItem(title: "\(Int(nits)) nits", action: #selector(choosePeak(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = nits
            peakMenu.addItem(item)
        }
        let peakItem = NSMenuItem(title: "Peak Brightness at 200%", action: nil, keyEquivalent: "")
        peakItem.submenu = peakMenu
        menu.addItem(peakItem)

        let resetItem = NSMenuItem(title: "Reset to 100%", action: #selector(resetToSDR), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)
        automaticUpdatesItem.target = self
        menu.addItem(automaticUpdatesItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit NitBoost", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        refreshMenu()
    }

    private func refreshMenu() {
        let percent = controller.percent
        headerItem.title = "Built-in Display — \(Int(percent.rounded()))% • \(Int(controller.nits(for: percent).rounded())) nits"
        slider.doubleValue = percent
        powerItem.isHidden = controller.isOnACPower
        for item in peakMenu.items {
            item.state = (item.representedObject as? Double) == controller.maxNits ? .on : .off
        }
        accessibilityItem.isHidden = keyTap.isRunning
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let updater = updaterController.updater
        automaticUpdatesItem.state = updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates ? .on : .off
        statusItem.button?.image = NSImage(
            systemSymbolName: controller.boostPercent > 0 ? "sun.max.circle.fill" : "sun.max.circle",
            accessibilityDescription: "NitBoost"
        )
    }

    @objc private func sliderMoved() {
        controller.setPercent(slider.doubleValue.rounded())
    }

    @objc private func choosePeak(_ sender: NSMenuItem) {
        guard let nits = sender.representedObject as? Double else { return }
        controller.maxNits = nits
    }

    @objc private func resetToSDR() {
        controller.setPercent(100)
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        refreshMenu()
    }

    @objc private func quit() {
        controller.stop()
        NSApp.terminate(nil)
    }

    @objc private func toggleAutomaticUpdates() {
        let updater = updaterController.updater
        let enabled = !(updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates)
        updater.automaticallyDownloadsUpdates = enabled
        updater.automaticallyChecksForUpdates = enabled
        refreshMenu()
    }
}
