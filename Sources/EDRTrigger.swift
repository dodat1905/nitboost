import AppKit
import MetalKit

final class EDRFillView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue

    var value: Double {
        didSet {
            guard value != oldValue else { return }
            clearColor = MTLClearColorMake(value, value, value, 1)
            draw()
        }
    }

    init?(edrFrame frame: CGRect, value: Double, multiply: Bool) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        self.value = value
        super.init(frame: frame, device: device)
        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        clearColor = MTLClearColorMake(value, value, value, 1)
        preferredFramesPerSecond = 5
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.isOpaque = false
            metalLayer.backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            metalLayer.pixelFormat = .rgba16Float
            if multiply {
                metalLayer.compositingFilter = "multiply"
            }
        }
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

final class EDROverlayWindow {
    static let headroomRequest = 1.6

    enum Kind { case headroomTrigger, multiplyFill }

    private let kind: Kind
    private var window: NSWindow?
    private var fillView: EDRFillView?

    init(kind: Kind) {
        self.kind = kind
    }

    func show(on screen: NSScreen, value: Double = EDROverlayWindow.headroomRequest) {
        let rect = kind == .headroomTrigger
            ? NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1)
            : screen.frame
        if let window, let fillView {
            if window.frame != rect { window.setFrame(rect, display: true) }
            fillView.value = value
            return
        }
        let shielding = Int(CGShieldingWindowLevel())
        let window = NSWindow(
            contentRect: rect,
            styleMask: kind == .multiplyFill ? [.fullSizeContentView, .borderless] : [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: kind == .multiplyFill ? shielding : shielding + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.canHide = false
        window.animationBehavior = .none
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .canJoinAllApplications, .fullScreenAuxiliary]
        let view = EDRFillView(edrFrame: NSRect(origin: .zero, size: rect.size), value: value, multiply: kind == .multiplyFill)
        view?.autoresizingMask = [.width, .height]
        window.contentView = view
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()
        self.window = window
        fillView = view
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        fillView = nil
    }
}
