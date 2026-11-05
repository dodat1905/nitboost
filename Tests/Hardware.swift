import AppKit

enum BuiltInDisplay {
    static let id: UInt32? = 1
    static var screen: NSScreen? { NSScreen.main }
}

enum SystemBrightness {
    static var value = 1.0
    static func get(_ display: UInt32) -> Double? { value }
    static func set(_ display: UInt32, _ brightness: Double) { value = brightness }
}

enum MediaKeyTap {
    enum Key { case brightnessUp, brightnessDown }
}

final class EDROverlayWindow {
    enum Kind { case headroomTrigger, multiplyFill }
    static var visible: Set<ObjectIdentifier> = []
    init(kind: Kind) {}
    func show(on screen: NSScreen, value: Double = 1.6) {
        Self.visible.insert(ObjectIdentifier(self))
    }
    func hide() { Self.visible.remove(ObjectIdentifier(self)) }
}

final class PowerSourceMonitor {
    static var isOnACPower = true
    static weak var latest: PowerSourceMonitor?
    var onChange: (() -> Void)?
    init() { Self.latest = self }
    static func change(toACPower value: Bool) {
        isOnACPower = value
        latest?.onChange?()
    }
}
