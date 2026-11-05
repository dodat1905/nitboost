import Foundation
import IOKit.ps

final class PowerSourceMonitor {
    private var source: CFRunLoopSource?
    var onChange: (() -> Void)?

    static var isOnACPower: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return false }
        return type as String == kIOPSACPowerValue
    }

    init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue().onChange?()
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    deinit {
        if let source { CFRunLoopSourceInvalidate(source) }
    }
}
