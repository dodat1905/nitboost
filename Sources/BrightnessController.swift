import AppKit

final class BrightnessController {
    static let sdrNits = 500.0
    static let maxPercent = 200.0
    static let peakNitChoices: [Double] = [1000, 1200, 1400, 1600]
    private static let sdrSteps = 16.0
    private static let fineSdrSteps = 64.0
    private static let boostStep = 10.0
    private static let fineBoostStep = 2.5
    private static let maxNitsKey = "maxNits"
    private static let defaultMaxNits = 1600.0

    private let trigger = EDROverlayWindow(kind: .headroomTrigger)
    private let overlay = EDROverlayWindow(kind: .multiplyFill)
    private static let smoothing = 0.22
    private static let headroomRampSeconds = 1.5

    private var watchdog: Timer?
    private var animator: Timer?
    private var appliedFactor = 1.0
    private var settleUntil = Date.distantPast
    private(set) var boostPercent = 0.0
    var onChange: (() -> Void)?

    var maxNits: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: Self.maxNitsKey)
            return stored > 0 ? stored : Self.defaultMaxNits
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.maxNitsKey)
            if boostPercent > 0 { startAnimator() }
            onChange?()
        }
    }

    var percent: Double {
        if boostPercent > 0 { return 100 + boostPercent }
        guard let id = BuiltInDisplay.id, let system = SystemBrightness.get(id) else { return 100 }
        return system * 100
    }

    func nits(for percent: Double) -> Double {
        if percent <= 100 { return percent / 100 * Self.sdrNits }
        return Self.sdrNits + (percent - 100) / 100 * (maxNits - Self.sdrNits)
    }

    @discardableResult
    func step(_ key: MediaKeyTap.Key, fine: Bool) -> Double {
        guard let id = BuiltInDisplay.id else { return percent }
        let system = SystemBrightness.get(id) ?? 1
        let boostStep = fine ? Self.fineBoostStep : Self.boostStep
        let steps = fine ? Self.fineSdrSteps : Self.sdrSteps
        let result: Double
        switch key {
        case .brightnessUp:
            if boostPercent > 0 || system >= 0.995 {
                if system < 0.995 { SystemBrightness.set(id, 1) }
                setBoost(min(100, boostPercent + boostStep))
                result = 100 + boostPercent
            } else {
                let next = min(1, (floor(system * steps + 0.01) + 1) / steps)
                SystemBrightness.set(id, next)
                result = next * 100
            }
        case .brightnessDown:
            if boostPercent > 0 {
                setBoost(max(0, boostPercent - boostStep))
                result = 100 + boostPercent
            } else {
                let next = max(0, (ceil(system * steps - 0.01) - 1) / steps)
                SystemBrightness.set(id, next)
                result = next * 100
            }
        }
        onChange?()
        return result
    }

    func setPercent(_ value: Double) {
        guard let id = BuiltInDisplay.id else { return }
        let clamped = min(Self.maxPercent, max(0, value))
        if clamped > 100 {
            SystemBrightness.set(id, 1)
            setBoost(clamped - 100)
        } else {
            setBoost(0)
            SystemBrightness.set(id, clamped / 100)
        }
        onChange?()
    }

    func stop() {
        boostPercent = 0
        animator?.invalidate()
        animator = nil
        finishBoost()
    }

    private func setBoost(_ value: Double) {
        boostPercent = value < 0.01 ? 0 : value
        if boostPercent > 0 {
            guard let screen = BuiltInDisplay.screen else { return }
            trigger.show(on: screen)
            startWatchdog()
            settleUntil = Date().addingTimeInterval(Self.headroomRampSeconds)
        }
        startAnimator()
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func startAnimator() {
        guard animator == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.animationFrame() }
        RunLoop.main.add(timer, forMode: .common)
        animator = timer
    }

    private func animationFrame() {
        guard let screen = BuiltInDisplay.screen else {
            stop()
            return
        }
        let desired = desiredFactor()
        appliedFactor += (desired - appliedFactor) * Self.smoothing
        if abs(desired - appliedFactor) < 0.002 { appliedFactor = desired }
        overlay.show(on: screen, value: appliedFactor)
        guard appliedFactor == desired, Date() >= settleUntil else { return }
        animator?.invalidate()
        animator = nil
        if boostPercent == 0 { finishBoost() }
    }

    private func finishBoost() {
        watchdog?.invalidate()
        watchdog = nil
        appliedFactor = 1
        overlay.hide()
        trigger.hide()
    }

    private func tick() {
        guard let id = BuiltInDisplay.id, let screen = BuiltInDisplay.screen else {
            stop()
            onChange?()
            return
        }
        guard boostPercent > 0 else { return }
        if let system = SystemBrightness.get(id), system < 0.99 {
            setBoost(0)
            onChange?()
            return
        }
        trigger.show(on: screen)
        overlay.show(on: screen, value: appliedFactor)
        if abs(desiredFactor() - appliedFactor) > 0.002 { startAnimator() }
    }

    private func desiredFactor() -> Double {
        guard boostPercent > 0 else { return 1 }
        let target = nits(for: 100 + boostPercent) / Self.sdrNits
        let headroom = Double(BuiltInDisplay.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1)
        return min(target, max(1, headroom))
    }
}
