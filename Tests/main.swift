import AppKit

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

_ = NSApplication.shared
expect(BuiltInDisplay.screen != nil, "A display is required for the overlay checks")
PowerSourceMonitor.isOnACPower = false
let controller = BrightnessController()

PowerSourceMonitor.change(toACPower: false)
expect(controller.percent == 100, "Battery startup must remain at 100% without a manual request")
expect(EDROverlayWindow.visible.isEmpty, "Battery startup must not create EDR windows")
controller.setPercent(150)
expect(controller.percent == 150, "Manual battery slider must allow 150%; got \(controller.percent)%")
PowerSourceMonitor.change(toACPower: false)
RunLoop.main.run(until: Date().addingTimeInterval(0.7))
expect(controller.percent == 150, "Battery updates and the watchdog must preserve manual 150%")
expect(!EDROverlayWindow.visible.isEmpty, "Manual battery boost must keep the EDR windows")

for fine in [false, true] {
    controller.setPercent(100)
    for _ in 0..<50 { controller.step(.brightnessUp, fine: fine) }
    expect(controller.percent == 200, "Manual battery brightness keys must reach 200%")
    expect(!EDROverlayWindow.visible.isEmpty, "Manual battery brightness keys must enable EDR")
}
expect(controller.step(.brightnessDown, fine: false) == 190, "Battery keys must decrease manual boost")
controller.setPercent(50)
expect(controller.step(.brightnessDown, fine: false) == 43.75, "SDR keys must still work on battery")
SystemBrightness.value = 0.3
PowerSourceMonitor.change(toACPower: false)
expect(controller.percent == 30, "Power notifications must preserve macOS SDR brightness")
controller.stop()
SystemBrightness.value = 1
PowerSourceMonitor.change(toACPower: false)
RunLoop.main.run(until: Date().addingTimeInterval(0.7))
expect(controller.percent == 100, "System brightness changes must not enable boost automatically")
expect(EDROverlayWindow.visible.isEmpty, "System brightness changes must not create EDR windows")

PowerSourceMonitor.change(toACPower: true)
controller.setPercent(200)
expect(controller.percent == 200, "AC power must allow 200%")
PowerSourceMonitor.change(toACPower: false)
expect(controller.boostPercent == 0, "Unplugging must cancel boost immediately")
expect(EDROverlayWindow.visible.isEmpty, "Unplugging must remove all EDR windows immediately")
controller.setPercent(150)
PowerSourceMonitor.change(toACPower: false)
expect(controller.percent == 150, "Further battery notifications must preserve the new manual boost")
PowerSourceMonitor.change(toACPower: true)
expect(controller.percent == 150, "Reconnecting power must preserve a new manual choice")
PowerSourceMonitor.change(toACPower: false)
expect(controller.percent == 100, "A second unplug must reset boost again")
PowerSourceMonitor.change(toACPower: true)
expect(controller.percent == 100, "Reconnecting power must not restore boost automatically")

controller.setPercent(150)
PowerSourceMonitor.isOnACPower = false
RunLoop.main.run(until: Date().addingTimeInterval(0.7))
expect(controller.boostPercent == 0, "The watchdog must detect an unplug if its notification is missed")
expect(EDROverlayWindow.visible.isEmpty, "The watchdog must remove EDR windows after an unplug")
controller.setPercent(150)
RunLoop.main.run(until: Date().addingTimeInterval(0.7))
expect(controller.percent == 150, "The watchdog must allow a manual boost after it detects an unplug")

PowerSourceMonitor.change(toACPower: true)
controller.setPercent(150)
PowerSourceMonitor.isOnACPower = false
controller.setPercent(150)
PowerSourceMonitor.change(toACPower: false)
RunLoop.main.run(until: Date().addingTimeInterval(0.7))
expect(controller.percent == 150, "A manual request after an unplug must survive its delayed notification")
controller.stop()
print("PASS: manual battery boost, power transitions, battery updates, SDR controls, delayed notifications, watchdog")
