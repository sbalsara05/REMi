// MagicPointer.swift
// macOS Magic Pointer — wiggle OR drag-select to activate, glow by LLM, TARS backend
//
// Setup:
//   1. New macOS App target (AppKit, NOT SwiftUI)
//   2. Replace AppDelegate.swift with this file
//   3. Info.plist: NSAccessibilityUsageDescription → "Reads text under your cursor"
//   4. Set TARS_BASE_URL below
//   5. Entitlements: app-sandbox = false
//
// Triggers:
//   Wiggle mouse        → point-and-ask (cursor context)
//   ⌘⇧Space            → drag-to-select mode (region capture)

import Cocoa
import CoreGraphics
import ApplicationServices

// ─────────────────────────────────────────────
// MARK: — Config
// ─────────────────────────────────────────────

enum Config {
    static let tarsBaseURL                = "http://localhost:8080"
    static let wiggleThreshold: Int       = 3
    static let wiggleWindowSeconds        = 0.5
    static let wiggleMinDistance: CGFloat = 10
    static let overlayWidth: CGFloat      = 480
    static let overlayHeight: CGFloat     = 130
    static let selectModeKeyCode: UInt16  = 49   // Space
    static let selectModeModifiers: NSEvent.ModifierFlags = [.command, .shift]
}

// ─────────────────────────────────────────────
// MARK: — LLM
// ─────────────────────────────────────────────

enum LLM: String, CaseIterable {
    case claude  = "claude"
    case chatgpt = "chatgpt"
    case gemini  = "gemini"

    var displayName: String {
        switch self {
        case .claude:  return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini:  return "Gemini"
        }
    }

    var glowColor: NSColor {
        switch self {
        case .claude:  return NSColor(red: 0.91, green: 0.34, blue: 0.16, alpha: 1)
        case .chatgpt: return NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1)
        case .gemini:  return NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)
        }
    }

    static let geminiColors: [NSColor] = [
        NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1),
        NSColor(red: 0.93, green: 0.26, blue: 0.21, alpha: 1),
        NSColor(red: 0.99, green: 0.73, blue: 0.01, alpha: 1),
        NSColor(red: 0.20, green: 0.66, blue: 0.33, alpha: 1),
    ]

    var icon: String {
        switch self {
        case .claude:  return "⬡"
        case .chatgpt: return "◉"
        case .gemini:  return "✦"
        }
    }
}

// ─────────────────────────────────────────────
// MARK: — Context Bundle
// ─────────────────────────────────────────────

enum CaptureSource {
    case cursor(position: CGPoint)
    case selection(rect: CGRect)
}

struct CursorContext {
    let source: CaptureSource
    let hoveredText: String?
    let appName: String?
    let screenshotData: Data?

    var cursorPosition: CGPoint {
        switch source {
        case .cursor(let p):    return p
        case .selection(let r): return CGPoint(x: r.midX, y: r.midY)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: — Wiggle Detector
// ─────────────────────────────────────────────

final class WiggleDetector {
    var onWiggle: ((CGPoint) -> Void)?
    private var positions: [(point: CGPoint, time: Date)] = []
    private var lastDirection = 0
    private var reversalCount = 0
    private var windowStart   = Date()

    func process(point: CGPoint) {
        let now = Date()
        positions = positions.filter { now.timeIntervalSince($0.time) < Config.wiggleWindowSeconds }
        positions.append((point, now))
        guard positions.count >= 2 else { return }

        let dx  = point.x - positions[positions.count - 2].point.x
        guard abs(dx) > 1 else { return }
        let dir = dx > 0 ? 1 : -1

        if lastDirection != 0 && dir != lastDirection {
            let seg = positions[max(0, positions.count - 4)].point
            if abs(point.x - seg.x) >= Config.wiggleMinDistance { reversalCount += 1 }
        }
        lastDirection = dir

        if now.timeIntervalSince(windowStart) > Config.wiggleWindowSeconds {
            reversalCount = 0; windowStart = now
        }
        if reversalCount >= Config.wiggleThreshold {
            reversalCount = 0; positions.removeAll(); lastDirection = 0
            onWiggle?(point)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: — Context Capturer
// ─────────────────────────────────────────────

final class ContextCapturer {

    func capture(at point: CGPoint) -> CursorContext {
        CursorContext(
            source: .cursor(position: point),
            hoveredText: readAXText(at: point),
            appName: NSWorkspace.shared.frontmostApplication?.localizedName,
            screenshotData: captureRegion(CGRect(x: point.x - 100, y: point.y - 100, width: 200, height: 200))
        )
    }

    func capture(region rect: CGRect) -> CursorContext {
        CursorContext(
            source: .selection(rect: rect),
            hoveredText: readAXText(at: CGPoint(x: rect.midX, y: rect.midY)),
            appName: NSWorkspace.shared.frontmostApplication?.localizedName,
            screenshotData: captureRegion(rect)
        )
    }

    private func readAXText(at point: CGPoint) -> String? {
        let sys = AXUIElementCreateSystemWide()
        var el: CFTypeRef?
        guard AXUIElementCopyElementAtPosition(sys, Float(point.x), Float(point.y), &el) == .success,
              let axEl = el as! AXUIElement? else { return nil }
        for attr in [kAXValueAttribute, kAXSelectedTextAttribute, kAXTitleAttribute] {
            var val: CFTypeRef?
            AXUIElementCopyAttributeValue(axEl, attr as CFString, &val)
            if let s = val as? String, !s.isEmpty { return s }
        }
        return nil
    }

    func captureRegion(_ rect: CGRect) -> Data? {
        guard let img = CGWindowListCreateImage(
            rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution
        ) else { return nil }
        return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
    }
}

// ─────────────────────────────────────────────
// MARK: — TARS Client
// ─────────────────────────────────────────────

final class TARSClient {

    struct Payload: Encodable {
        let llm, query, captureMode: String
        let cursorX, cursorY: Double
        let selectionRect: SelectionRect?
        let hoveredText, appName, screenshotBase64: String?
        struct SelectionRect: Encodable { let x, y, width, height: Double }
    }

    func send(
        query: String, llm: LLM, context: CursorContext,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        guard let url = URL(string: "\(Config.tarsBaseURL)/query") else {
            onComplete(URLError(.badURL)); return
        }

        var selRect: Payload.SelectionRect?
        if case .selection(let r) = context.source {
            selRect = .init(x: r.minX, y: r.minY, width: r.width, height: r.height)
        }

        let body = Payload(
            llm: llm.rawValue,
            query: query,
            captureMode: selRect != nil ? "selection" : "cursor",
            cursorX: Double(context.cursorPosition.x),
            cursorY: Double(context.cursorPosition.y),
            selectionRect: selRect,
            hoveredText: context.hoveredText,
            appName: context.appName,
            screenshotBase64: context.screenshotData?.base64EncodedString()
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let e = error { DispatchQueue.main.async { onComplete(e) }; return }
            guard let data, let text = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { onComplete(URLError(.cannotDecodeContentData)) }; return
            }
            for line in text.components(separatedBy: "\n") where line.hasPrefix("data: ") {
                let tok = String(line.dropFirst(6))
                if tok != "[DONE]" { DispatchQueue.main.async { onToken(tok) } }
            }
            DispatchQueue.main.async { onComplete(nil) }
        }.resume()
    }
}

// ─────────────────────────────────────────────
// MARK: — Glow Border View
// ─────────────────────────────────────────────

final class GlowBorderView: NSView {
    var llm: LLM = .claude { didSet { rebuild() } }
    private var glowLayer: CALayer?
    private var shimmerLayer: CALayer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = false
        rebuild()
    }

    private func rebuild() {
        glowLayer?.removeFromSuperlayer()
        shimmerLayer?.removeFromSuperlayer()

        let gl = CALayer()
        gl.frame = bounds.insetBy(dx: -20, dy: -20)
        gl.cornerRadius = 34
        gl.borderWidth = 2
        gl.borderColor = llm.glowColor.cgColor
        gl.shadowColor = llm.glowColor.cgColor
        gl.shadowRadius = 20; gl.shadowOpacity = 0.9; gl.shadowOffset = .zero
        layer?.insertSublayer(gl, at: 0)
        glowLayer = gl

        let pulse = CABasicAnimation(keyPath: "shadowOpacity")
        pulse.fromValue = 0.5; pulse.toValue = 1.0
        pulse.duration = 0.9; pulse.autoreverses = true; pulse.repeatCount = .infinity
        gl.add(pulse, forKey: "pulse")

        if llm == .gemini { addGeminiShimmer(above: gl) }
    }

    private func addGeminiShimmer(above gl: CALayer) {
        let sh = CAGradientLayer()
        sh.frame = bounds; sh.cornerRadius = 14
        sh.type = .conic
        sh.startPoint = CGPoint(x: 0.5, y: 0.5)
        sh.endPoint   = CGPoint(x: 1, y: 0)
        sh.colors = LLM.geminiColors.map(\.cgColor) + [LLM.geminiColors[0].cgColor]
        sh.opacity = 0.55
        layer?.insertSublayer(sh, above: gl)
        shimmerLayer = sh

        let rot = CABasicAnimation(keyPath: "transform.rotation")
        rot.fromValue = 0; rot.toValue = CGFloat.pi * 2
        rot.duration = 3; rot.repeatCount = .infinity
        sh.add(rot, forKey: "rot")
    }
}

// ─────────────────────────────────────────────
// MARK: — Selection View (draws the marquee rect)
// ─────────────────────────────────────────────

final class SelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var activeLLM: LLM = .claude

    private var startPt: NSPoint  = .zero
    private var currentRect: NSRect = .zero
    private var dragging = false
    private let handleSize: CGFloat = 8

    func reset(llm: LLM) {
        activeLLM = llm; startPt = .zero; currentRect = .zero; dragging = false
        needsDisplay = true
    }

    override func mouseDown(with e: NSEvent) {
        startPt = convert(e.locationInWindow, from: nil)
        currentRect = NSRect(origin: startPt, size: .zero)
        dragging = true; needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        guard dragging else { return }
        let cur = convert(e.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(startPt.x, cur.x), y: min(startPt.y, cur.y),
            width: abs(cur.x - startPt.x), height: abs(cur.y - startPt.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        dragging = false
        guard currentRect.width > 10, currentRect.height > 10 else {
            currentRect = .zero; needsDisplay = true
            NotificationCenter.default.post(name: .magicPointerSelectionCancelled, object: nil)
            return
        }
        // Flip to CG (top-left origin) coords
        let screenH = NSScreen.main?.frame.height ?? 0
        let cgRect = CGRect(
            x: currentRect.minX,
            y: screenH - currentRect.maxY,
            width: currentRect.width,
            height: currentRect.height
        )
        currentRect = .zero; needsDisplay = true
        onSelection?(cgRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard currentRect.width > 0 || dragging else { return }

        let color = activeLLM.glowColor

        // Scrim outside selection
        let scrim = NSBezierPath(rect: bounds)
        let hole  = NSBezierPath(rect: currentRect)
        scrim.append(hole.reversed)
        NSColor.black.withAlphaComponent(0.35).setFill()
        scrim.fill()

        // Border
        let border = NSBezierPath(rect: currentRect)
        border.lineWidth = 2
        color.withAlphaComponent(0.9).setStroke()
        border.stroke()

        // Fill tint
        color.withAlphaComponent(0.08).setFill()
        border.fill()

        // Corner handles
        for pt in [
            NSPoint(x: currentRect.minX, y: currentRect.minY),
            NSPoint(x: currentRect.maxX, y: currentRect.minY),
            NSPoint(x: currentRect.minX, y: currentRect.maxY),
            NSPoint(x: currentRect.maxX, y: currentRect.maxY),
        ] {
            color.withAlphaComponent(1).setFill()
            NSBezierPath(roundedRect: NSRect(
                x: pt.x - handleSize / 2, y: pt.y - handleSize / 2,
                width: handleSize, height: handleSize
            ), xRadius: 2, yRadius: 2).fill()
        }

        // Dimension label
        let label = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let sz = (label as NSString).size(withAttributes: attrs)
        let lx = currentRect.midX - (sz.width + 10) / 2
        let ly = currentRect.minY - sz.height - 10
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: NSRect(x: lx, y: ly, width: sz.width + 10, height: sz.height + 4),
                     xRadius: 4, yRadius: 4).fill()
        (label as NSString).draw(at: NSPoint(x: lx + 5, y: ly + 2), withAttributes: attrs)
    }
}

// ─────────────────────────────────────────────
// MARK: — Selection Overlay Window
// ─────────────────────────────────────────────

final class SelectionOverlayWindow: NSWindow {
    var activeLLM: LLM = .claude { didSet { selView.activeLLM = activeLLM } }
    private let selView: SelectionView

    var onSelection: ((CGRect) -> Void)? {
        get { selView.onSelection }
        set { selView.onSelection = newValue }
    }

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        selView = SelectionView(frame: screen.frame)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        backgroundColor = NSColor.black.withAlphaComponent(0.001)
        isOpaque = false; hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = selView
        selView.onSelection = { [weak self] rect in
            self?.deactivate()
        }
    }

    override var canBecomeKey: Bool { true }

    func activate(llm: LLM) {
        activeLLM = llm
        selView.reset(llm: llm)
        makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    func deactivate() {
        NSCursor.pop()
        orderOut(nil)
    }
}

// ─────────────────────────────────────────────
// MARK: — Overlay View Controller
// ─────────────────────────────────────────────

final class OverlayViewController: NSViewController {
    private let glowView      = GlowBorderView()
    private let container     = NSVisualEffectView()
    private let llmPicker     = NSSegmentedControl()
    private let textField     = NSTextField()
    private let responseLabel = NSTextField()
    private let modeLabel     = NSTextField()

    var currentLLM: LLM = .claude
    var onSubmit: ((String) -> Void)?
    var onLLMChange: ((LLM) -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0,
                                    width: Config.overlayWidth,
                                    height: Config.overlayHeight))
    }

    override func viewDidLoad() { super.viewDidLoad(); buildUI() }

    private func buildUI() {
        let inner = NSRect(x: 8, y: 8,
                           width: Config.overlayWidth - 16,
                           height: Config.overlayHeight - 16)

        glowView.frame = inner
        view.addSubview(glowView)

        container.frame = inner
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.blendingMode = .behindWindow
        container.material = .hudWindow
        container.state = .active
        view.addSubview(container)

        modeLabel.frame = NSRect(x: 12, y: inner.height - 22, width: 260, height: 16)
        modeLabel.isEditable = false; modeLabel.isBordered = false
        modeLabel.backgroundColor = .clear
        modeLabel.textColor = .tertiaryLabelColor
        modeLabel.font = NSFont.systemFont(ofSize: 11)
        modeLabel.stringValue = "cursor context"
        container.addSubview(modeLabel)

        llmPicker.frame = NSRect(x: 12, y: inner.height - 44, width: Config.overlayWidth - 32, height: 22)
        llmPicker.segmentCount = LLM.allCases.count
        for (i, llm) in LLM.allCases.enumerated() {
            llmPicker.setLabel("\(llm.icon) \(llm.displayName)", forSegment: i)
        }
        llmPicker.selectedSegment = 0
        llmPicker.trackingMode = .selectOne
        llmPicker.target = self; llmPicker.action = #selector(pickerChanged)
        container.addSubview(llmPicker)

        let sep = NSBox(); sep.boxType = .separator
        sep.frame = NSRect(x: 12, y: inner.height - 48, width: Config.overlayWidth - 32, height: 1)
        container.addSubview(sep)

        textField.frame = NSRect(x: 12, y: inner.height - 72, width: Config.overlayWidth - 32, height: 24)
        textField.placeholderString = "Ask about what's under your cursor…"
        textField.isBordered = false; textField.backgroundColor = .clear
        textField.textColor = .labelColor; textField.font = NSFont.systemFont(ofSize: 14)
        textField.focusRingType = .none; textField.delegate = self
        container.addSubview(textField)

        let sep2 = NSBox(); sep2.boxType = .separator
        sep2.frame = NSRect(x: 12, y: inner.height - 76, width: Config.overlayWidth - 32, height: 1)
        container.addSubview(sep2)

        responseLabel.frame = NSRect(x: 12, y: 10, width: Config.overlayWidth - 32, height: 30)
        responseLabel.isEditable = false; responseLabel.isBordered = false
        responseLabel.backgroundColor = .clear; responseLabel.textColor = .secondaryLabelColor
        responseLabel.font = NSFont.systemFont(ofSize: 12)
        responseLabel.lineBreakMode = .byWordWrapping
        responseLabel.cell?.wraps = true; responseLabel.cell?.isScrollable = false
        container.addSubview(responseLabel)
    }

    @objc private func pickerChanged() {
        let llm = LLM.allCases[llmPicker.selectedSegment]
        updateLLM(llm); onLLMChange?(llm)
    }

    func updateLLM(_ llm: LLM) {
        currentLLM = llm; glowView.llm = llm
        llmPicker.selectedSegment = LLM.allCases.firstIndex(of: llm) ?? 0
    }

    func reset(context: CursorContext, llm: LLM) {
        textField.stringValue = ""; responseLabel.stringValue = ""
        updateLLM(llm)

        switch context.source {
        case .cursor:
            modeLabel.stringValue = "cursor context"
            if let t = context.hoveredText, !t.isEmpty {
                textField.placeholderString = "About: "\(String(t.prefix(50)))\(t.count > 50 ? "…" : "")""
            } else {
                textField.placeholderString = context.appName.map { "Ask about \($0)…" }
                    ?? "Ask about what's under your cursor…"
            }
        case .selection(let rect):
            modeLabel.stringValue = "selected region  \(Int(rect.width)) × \(Int(rect.height)) px"
            if let t = context.hoveredText, !t.isEmpty {
                textField.placeholderString = "About selection: "\(String(t.prefix(50)))\(t.count > 50 ? "…" : "")""
            } else {
                textField.placeholderString = "Ask about the selected region…"
            }
        }
    }

    func focus() { view.window?.makeFirstResponder(textField) }

    func showLoading()              { responseLabel.stringValue = "…"; responseLabel.textColor = .tertiaryLabelColor }
    func appendToken(_ t: String)   { responseLabel.stringValue += t; responseLabel.textColor = .labelColor }
    func finishResponse(error: Error?) {
        if let e = error { responseLabel.stringValue = "Error: \(e.localizedDescription)"; responseLabel.textColor = .systemRed }
    }
}

extension OverlayViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let q = textField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return true }
            onSubmit?(q); return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            (view.window?.windowController as? OverlayWindowController)?.dismiss(); return true
        }
        return false
    }
}

// ─────────────────────────────────────────────
// MARK: — Overlay Window Controller
// ─────────────────────────────────────────────

final class OverlayWindowController: NSWindowController {
    let vc = OverlayViewController()
    var onLLMChange: ((LLM) -> Void)?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Config.overlayWidth, height: Config.overlayHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.contentViewController = vc
        vc.onLLMChange = { [weak self] llm in self?.onLLMChange?(llm) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(at screenPoint: CGPoint, context: CursorContext, llm: LLM) {
        guard let screen = NSScreen.main else { return }
        let origin = NSPoint(
            x: screenPoint.x - Config.overlayWidth / 2,
            y: screen.frame.height - screenPoint.y - Config.overlayHeight / 2 - 70
        )
        window?.setFrameOrigin(origin)
        vc.reset(context: context, llm: llm)
        window?.orderFront(nil); vc.focus()

        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() { window?.orderOut(nil) }

    func submit(query: String, context: CursorContext, tars: TARSClient) {
        vc.showLoading()
        tars.send(
            query: query, llm: vc.currentLLM, context: context,
            onToken:    { [weak self] t   in self?.vc.appendToken(t) },
            onComplete: { [weak self] err in self?.vc.finishResponse(error: err) }
        )
    }
}

// ─────────────────────────────────────────────
// MARK: — App Delegate
// ─────────────────────────────────────────────

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let wiggle    = WiggleDetector()
    private let capturer  = ContextCapturer()
    private let tars      = TARSClient()
    private let overlay   = OverlayWindowController()
    private let selWindow = SelectionOverlayWindow()

    private var eventTap:  CFMachPort?
    private var lastCtx:   CursorContext?
    private var activeLLM: LLM = .claude

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        requestAX()
        setupEventTap()
        wireWiggle()
        wireSelection()
        wireOverlay()
        registerHotkey()
    }

    private func requestAX() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private func setupEventTap() {
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, _, event, ref -> Unmanaged<CGEvent>? in
                Unmanaged<AppDelegate>.fromOpaque(ref!).takeUnretainedValue().handleMouse(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap = eventTap else { print("⚠️  Event tap failed"); return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleMouse(_ event: CGEvent) { wiggle.process(point: event.location) }

    private func wireWiggle() {
        wiggle.onWiggle = { [weak self] pt in
            guard let self else { return }
            DispatchQueue.main.async {
                let ctx = self.capturer.capture(at: pt)
                self.lastCtx = ctx
                self.overlay.show(at: pt, context: ctx, llm: self.activeLLM)
            }
        }
    }

    private func wireSelection() {
        selWindow.onSelection = { [weak self] rect in
            guard let self else { return }
            DispatchQueue.main.async {
                let ctx = self.capturer.capture(region: rect)
                self.lastCtx = ctx
                let anchor = CGPoint(x: rect.midX, y: rect.maxY + 20)
                self.overlay.show(at: anchor, context: ctx, llm: self.activeLLM)
            }
        }
    }

    private func wireOverlay() {
        overlay.onLLMChange = { [weak self] llm in
            self?.activeLLM = llm
            self?.selWindow.activeLLM = llm
        }
        overlay.vc.onSubmit = { [weak self] query in
            guard let self, let ctx = self.lastCtx else { return }
            self.overlay.submit(query: query, context: ctx, tars: self.tars)
        }
    }

    private func registerHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if event.keyCode == Config.selectModeKeyCode &&
               event.modifierFlags.intersection([.command, .shift, .control, .option])
                   == Config.selectModeModifiers {
                DispatchQueue.main.async { self.selWindow.activate(llm: self.activeLLM) }
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: — Notification Names
// ─────────────────────────────────────────────

extension Notification.Name {
    static let magicPointerSubmit             = Notification.Name("magicPointerSubmit")
    static let magicPointerSelectionCancelled = Notification.Name("magicPointerSelectionCancelled")
}

// ─────────────────────────────────────────────
// MARK: — NSBezierPath reversed (scrim cutout)
// ─────────────────────────────────────────────

extension NSBezierPath {
    var reversed: NSBezierPath {
        let rev = NSBezierPath()
        var pts = [NSPoint](repeating: .zero, count: 3)
        for i in (0..<elementCount).reversed() {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo:    rev.move(to: pts[0])
            case .lineTo:    rev.line(to: pts[0])
            case .curveTo:   rev.curve(to: pts[2], controlPoint1: pts[0], controlPoint2: pts[1])
            case .closePath: rev.close()
            default: break
            }
        }
        return rev
    }
}