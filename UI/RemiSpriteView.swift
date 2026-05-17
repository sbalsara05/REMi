// RemiSpriteView.swift — Foozle mouse spritesheet (matches web mouseSpriteFrameCatalog)

import Cocoa
import QuartzCore

private struct SpriteViewport {
    let col: Int
    let row: Int
    let ox: CGFloat
    let oy: CGFloat
    let w: CGFloat
    let h: CGFloat
}

private enum SpriteSheet {
    static let frameW: CGFloat = 64
    static let frameH: CGFloat = 48
    static let cols = 15
    static let rows = 13

    /// double_jump.dj_stand — upright idle (not Foozle row-0 lunge).
    static let idle = SpriteViewport(col: 0, row: 3, ox: 21, oy: 11, w: 22, h: 32)
    /// jump.jump_0 — anticipation while streaming.
    static let streaming = SpriteViewport(col: 0, row: 2, ox: 19, oy: 13, w: 24, h: 35)

    static func loadCGImage() -> CGImage? {
        guard let url = Bundle.main.url(forResource: "mouse-spritesheet", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: img.size).integral
        return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func contentsRect(for vp: SpriteViewport, sheetSize: CGSize) -> CGRect {
        let srcX = CGFloat(vp.col) * frameW + vp.ox
        // Match web clipBackgroundPosition: top = row*frameH + oy (CALayer origin is bottom-left).
        let srcY = sheetSize.height - CGFloat(vp.row) * frameH - vp.oy - vp.h
        return CGRect(
            x: srcX / sheetSize.width,
            y: srcY / sheetSize.height,
            width: vp.w / sheetSize.width,
            height: vp.h / sheetSize.height
        )
    }
}

/// Small animated REMi mouse for the MagicPointer overlay.
final class RemiSpriteView: NSView {
    static let displayScale: CGFloat = 0.78

    private let spriteLayer = CALayer()
    private var sheetCG: CGImage?
    private var sheetSize: CGSize = .zero
    private var timer: Timer?
    private var isStreaming = false
    private var bobPhase: CGFloat = 0
    private var pulsePhase: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        spriteLayer.contentsGravity = .resize
        layer?.addSublayer(spriteLayer)

        if let cg = SpriteSheet.loadCGImage() {
            sheetCG = cg
            sheetSize = CGSize(width: cg.width, height: cg.height)
            spriteLayer.contents = cg
        }
        applyFrame(SpriteSheet.idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { timer?.invalidate() }

    override var intrinsicContentSize: NSSize {
        let vp = SpriteSheet.idle
        return NSSize(
            width: ceil(vp.w * Self.displayScale) + 4,
            height: ceil(vp.h * Self.displayScale) + 4
        )
    }

    var columnWidth: CGFloat { intrinsicContentSize.width }

    func setStreaming(_ streaming: Bool) {
        guard streaming != isStreaming else { return }
        isStreaming = streaming
        applyFrame(streaming ? SpriteSheet.streaming : SpriteSheet.idle)
        startTimer(fps: streaming ? 8 : 4)
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        isStreaming = false
        applyFrame(SpriteSheet.idle)
    }

    func startIdle() {
        isStreaming = false
        applyFrame(SpriteSheet.idle)
        startTimer(fps: 4)
    }

    private func startTimer(fps: Double) {
        timer?.invalidate()
        guard fps > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func tick() {
        bobPhase += 0.14
        if isStreaming { pulsePhase += 0.2 }
        layoutSpriteFrame()
    }

    private func applyFrame(_ vp: SpriteViewport) {
        guard sheetCG != nil, sheetSize.width > 0 else { return }
        spriteLayer.contentsRect = SpriteSheet.contentsRect(for: vp, sheetSize: sheetSize)
        layoutSpriteFrame(for: vp)
    }

    private func layoutSpriteFrame(for vp: SpriteViewport? = nil) {
        let frame = vp ?? (isStreaming ? SpriteSheet.streaming : SpriteSheet.idle)
        let scale = Self.displayScale
        let drawW = frame.w * scale
        let drawH = frame.h * scale
        let bob = isStreaming ? sin(pulsePhase) * 0.8 : sin(bobPhase) * 1.2

        spriteLayer.bounds = CGRect(x: 0, y: 0, width: drawW, height: drawH)
        // Slightly above geometric center so feet line up with single-line field text.
        let alignY = bounds.height * 0.54 + bob
        spriteLayer.position = CGPoint(x: bounds.midX, y: alignY)
        spriteLayer.opacity = isStreaming ? Float(0.88 + 0.12 * abs(sin(pulsePhase))) : 1
    }

    override func layout() {
        super.layout()
        layoutSpriteFrame()
    }
}
