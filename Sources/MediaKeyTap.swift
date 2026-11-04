import AppKit

final class MediaKeyTap {
    enum Key { case brightnessUp, brightnessDown }

    private static let systemDefinedEventType: UInt32 = 14
    private static let auxControlSubtype: Int16 = 8
    private static let brightnessUpCode = 2
    private static let brightnessDownCode = 3
    private static let keyDownState = 0xA

    private var tap: CFMachPort?
    private let handler: (Key, NSEvent.ModifierFlags) -> Void

    var isRunning: Bool { tap != nil }

    init(handler: @escaping (Key, NSEvent.ModifierFlags) -> Void) {
        self.handler = handler
    }

    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << Self.systemDefinedEventType)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let keyTap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return MainActor.assumeIsolated { keyTap.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DiagnosticLog.write("tap disabled by system (\(type.rawValue)), re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == Self.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlSubtype else { return Unmanaged.passUnretained(event) }
        let data = nsEvent.data1
        let code = (data & 0xFFFF0000) >> 16
        let state = (data & 0xFF00) >> 8
        let key: Key
        switch code {
        case Self.brightnessUpCode: key = .brightnessUp
        case Self.brightnessDownCode: key = .brightnessDown
        default: return Unmanaged.passUnretained(event)
        }
        if state == Self.keyDownState {
            handler(key, nsEvent.modifierFlags)
        }
        return nil
    }
}
