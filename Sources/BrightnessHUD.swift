import AppKit
import SwiftUI

struct BrightnessBar: View {
    let sdrFraction: Double
    let boostFraction: Double
    private let tickCount = 17

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule().fill(Color.white).frame(width: geometry.size.width * sdrFraction)
                    if boostFraction > 0 {
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.3), .orange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(5, geometry.size.width * boostFraction))
                    }
                }
            }
            .frame(height: 5)
            HStack(spacing: 0) {
                ForEach(0..<tickCount, id: \.self) { index in
                    Circle().fill(Color.white.opacity(0.32)).frame(width: 2.5, height: 2.5)
                    if index < tickCount - 1 { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

struct BrightnessHUDView: View {
    let title: String
    let percent: Int
    let nits: Int
    let sdrFraction: Double
    let boostFraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(percent)% • \(nits) nits")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.black.opacity(0.78))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(boostFraction > 0 ? Color(red: 1, green: 0.86, blue: 0.45) : Color.white.opacity(0.88)))
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                BrightnessBar(sdrFraction: sdrFraction, boostFraction: boostFraction)
                    .padding(.top, 9)
                Image(systemName: boostFraction > 0 ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(boostFraction > 0 ? Color.yellow : Color.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 290)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

final class BrightnessHUD {
    private static let cornerRadius: CGFloat = 26
    private static let visibleSeconds = 1.6
    private static let edgeMargin: CGFloat = 10

    private let panel: NSPanel
    private let effectView = NSVisualEffectView()
    private let hosting = NSHostingView(rootView: BrightnessHUDView(title: "", percent: 0, nits: 0, sdrFraction: 0, boostFraction: 0))
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .darkAqua)
        effectView.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        panel.contentView = effectView
    }

    func show(title: String, percent: Double, nits: Double) {
        let sdrFraction = min(1, max(0, percent / 100))
        let boostFraction = min(1, max(0, (percent - 100) / 100))
        hosting.rootView = BrightnessHUDView(
            title: title,
            percent: Int(percent.rounded()),
            nits: Int(nits.rounded()),
            sdrFraction: sdrFraction,
            boostFraction: boostFraction
        )
        let size = hosting.fittingSize
        if let screen = BuiltInDisplay.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(x: visible.maxX - size.width - Self.edgeMargin, y: visible.maxY - size.height - Self.edgeMargin)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        hideWork?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleSeconds, execute: work)
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
        })
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
