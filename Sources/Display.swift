import AppKit
import CoreGraphics

enum BuiltInDisplay {
    static var id: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var screen: NSScreen? {
        guard let id else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    static var name: String { screen?.localizedName ?? "Built-in Display" }
}

enum SystemBrightness {
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getter: Getter? = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: Getter.self) }
    private static let setter: Setter? = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: Setter.self) }

    private static let fadeSeconds = 1.0
    private static var lastSet: (value: Double, date: Date)?

    static func get(_ display: CGDirectDisplayID) -> Double? {
        if let lastSet, Date().timeIntervalSince(lastSet.date) < fadeSeconds { return lastSet.value }
        guard let getter else { return nil }
        var value: Float = 0
        guard getter(display, &value) == 0 else { return nil }
        return Double(value)
    }

    static func set(_ display: CGDirectDisplayID, _ value: Double) {
        let clamped = Float(min(1, max(0, value)))
        lastSet = (Double(clamped), Date())
        _ = setter?(display, clamped)
    }
}
