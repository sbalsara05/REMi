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
import ScreenCaptureKit

// ─────────────────────────────────────────────
// MARK: — Config
// ─────────────────────────────────────────────

enum Config {
    static let tarsBaseURL                = "http://localhost:8080"
    static let wiggleThreshold: Int       = 3
    static let wiggleWindowSeconds        = 1.2
    static let wiggleMinDistance: CGFloat = 28
    static let wiggleCooldownSeconds      = 1.0
    static let overlayWidth: CGFloat      = 540
    static let overlayHeight: CGFloat     = 124
    static let overlayCornerRadius: CGFloat = 18
    static let cursorCaptureSize: CGFloat = 360
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

    var shimmerColors: [NSColor] {
        switch self {
        case .gemini:
            return Self.geminiColors
        case .claude:
            return [
                NSColor(red: 0.98, green: 0.62, blue: 0.34, alpha: 1),
                NSColor(red: 0.91, green: 0.34, blue: 0.16, alpha: 1),
                NSColor(red: 0.82, green: 0.22, blue: 0.10, alpha: 1),
                NSColor(red: 0.98, green: 0.62, blue: 0.34, alpha: 1),
            ]
        case .chatgpt:
            return [
                NSColor(red: 0.28, green: 0.84, blue: 0.70, alpha: 1),
                NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1),
                NSColor(red: 0.02, green: 0.44, blue: 0.34, alpha: 1),
                NSColor(red: 0.28, green: 0.84, blue: 0.70, alpha: 1),
            ]
        }
    }

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
    private var lastPoint: CGPoint?
    private var lastDirection = 0 // -1: left, +1: right
    private var runDistance: CGFloat = 0
    private var swingCount = 0
    private var windowStart   = Date()
    private var lastTriggerAt = Date.distantPast

    func process(point: CGPoint) {
        let now = Date()
        if now.timeIntervalSince(lastTriggerAt) < Config.wiggleCooldownSeconds {
            lastPoint = point
            return
        }
        if now.timeIntervalSince(windowStart) > Config.wiggleWindowSeconds {
            resetWindow(now: now)
        }

        guard let prev = lastPoint else {
            lastPoint = point
            return
        }

        let dx = point.x - prev.x
        guard abs(dx) > 1 else { return }
        let dir = dx > 0 ? 1 : -1

        if lastDirection != 0 && dir != lastDirection {
            if runDistance >= Config.wiggleMinDistance {
                swingCount += 1
                if swingCount >= Config.wiggleThreshold {
                    lastTriggerAt = now
                    resetAll(now: now)
                    onWiggle?(point)
                    return
                }
            }
            runDistance = abs(dx)
        } else {
            runDistance += abs(dx)
        }
        lastDirection = dir
        lastPoint = point
    }

    private func resetWindow(now: Date) {
        windowStart = now
        swingCount = 0
        runDistance = 0
        lastDirection = 0
    }

    private func resetAll(now: Date) {
        resetWindow(now: now)
        lastPoint = nil
    }
}

// ─────────────────────────────────────────────
// MARK: — Context Capturer
// ─────────────────────────────────────────────

final class ContextCapturer {

    func capture(at point: CGPoint, completion: @escaping (CursorContext) -> Void) {
        let hoveredText = mergedHoverContext(at: point)
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        let size = Config.cursorCaptureSize
        let rect = CGRect(
            x: point.x - size / 2,
            y: point.y - size / 2,
            width: size,
            height: size
        )
        captureRegion(rect) { data in
            completion(
                CursorContext(
                    source: .cursor(position: point),
                    hoveredText: hoveredText,
                    appName: appName,
                    screenshotData: data
                )
            )
        }
    }

    func capture(region rect: CGRect, completion: @escaping (CursorContext) -> Void) {
        let hoveredText = mergedHoverContext(at: CGPoint(x: rect.midX, y: rect.midY))
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        captureRegion(rect) { data in
            completion(
                CursorContext(
                    source: .selection(rect: rect),
                    hoveredText: hoveredText,
                    appName: appName,
                    screenshotData: data
                )
            )
        }
    }

    private func mergedHoverContext(at point: CGPoint) -> String? {
        let axText = readAXText(at: point)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let browserSummary = readBrowserPageSummary()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let browserDOM = readBrowserDeepContext()?.trimmingCharacters(in: .whitespacesAndNewlines)

        var browserContext: String?
        if let summary = browserSummary, !summary.isEmpty,
           let dom = browserDOM, !dom.isEmpty {
            browserContext = "Page: \(summary)\nDOM snippet: \(dom)"
        } else if let summary = browserSummary, !summary.isEmpty {
            browserContext = "Page: \(summary)"
        } else if let dom = browserDOM, !dom.isEmpty {
            browserContext = "DOM snippet: \(dom)"
        }

        let hasAX = !(axText ?? "").isEmpty
        let hasBrowser = !(browserContext ?? "").isEmpty
        if hasAX && hasBrowser {
            if axText == browserContext { return clipped(axText) }
            return clipped("\(axText!)\n\nWeb context: \(browserContext!)")
        }
        return clipped(hasAX ? axText : browserContext)
    }

    private func readAXText(at point: CGPoint) -> String? {
        let sys = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sys, Float(point.x), Float(point.y), &hitElement) == .success,
              let axEl = hitElement else { return nil }
        for attr in [kAXValueAttribute, kAXSelectedTextAttribute, kAXTitleAttribute] {
            var val: CFTypeRef?
            AXUIElementCopyAttributeValue(axEl, attr as CFString, &val)
            if let s = val as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private func readBrowserPageSummary() -> String? {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }

        let script: String?
        switch bundleID {
        case "com.apple.Safari":
            script = """
            tell application "Safari"
                if (count of windows) = 0 then return ""
                set t to name of current tab of front window
                set u to URL of current tab of front window
                return t & " | " & u
            end tell
            """
        case "com.google.Chrome":
            script = """
            tell application "Google Chrome"
                if (count of windows) = 0 then return ""
                set t to title of active tab of front window
                set u to URL of active tab of front window
                return t & " | " & u
            end tell
            """
        case "com.microsoft.edgemac":
            script = """
            tell application "Microsoft Edge"
                if (count of windows) = 0 then return ""
                set t to title of active tab of front window
                set u to URL of active tab of front window
                return t & " | " & u
            end tell
            """
        case "company.thebrowser.Browser":
            script = """
            tell application "Arc"
                if (count of windows) = 0 then return ""
                set t to title of active tab of front window
                set u to URL of active tab of front window
                return t & " | " & u
            end tell
            """
        default:
            script = nil
        }
        guard let script else { return nil }
        return runAppleScript(script)
    }

    private func readBrowserDeepContext() -> String? {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        guard let script = browserDeepScript(for: bundleID) else { return nil }
        return runAppleScript(script)
    }

    private func browserDeepScript(for bundleID: String) -> String? {
        let js = """
        (function() {
          const clean = (s) => (s || '').replace(/\\s+/g, ' ').trim();
          const selected = clean((window.getSelection && window.getSelection().toString()) || '');
          if (selected.length > 0) return selected.slice(0, 600);
          const cand = [];
          const push = (v) => { const c = clean(v); if (c.length > 20) cand.push(c); };
          push(document.title || '');
          push((document.querySelector('h1') || {}).innerText || '');
          const nodes = document.querySelectorAll('main p, article p, p');
          for (let i = 0; i < nodes.length && cand.join(' ').length < 900; i++) push(nodes[i].innerText);
          if (cand.length === 0) push(document.body ? document.body.innerText : '');
          return cand.join(' | ').slice(0, 1000);
        })();
        """
        let escapedJS = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        switch bundleID {
        case "com.apple.Safari":
            return """
            tell application "Safari"
                if (count of windows) = 0 then return ""
                set dom to do JavaScript "\(escapedJS)" in current tab of front window
                return dom
            end tell
            """
        case "com.google.Chrome":
            return """
            tell application "Google Chrome"
                if (count of windows) = 0 then return ""
                return execute active tab of front window javascript "\(escapedJS)"
            end tell
            """
        case "com.microsoft.edgemac":
            return """
            tell application "Microsoft Edge"
                if (count of windows) = 0 then return ""
                return execute active tab of front window javascript "\(escapedJS)"
            end tell
            """
        default:
            return nil
        }
    }

    private func runAppleScript(_ script: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty == false) ? text : nil
        } catch {
            return nil
        }
    }

    private func clipped(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let maxChars = 1400
        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars)) + "…"
    }

    func captureRegion(_ rect: CGRect, completion: @escaping (Data?) -> Void) {
        if #unavailable(macOS 14.0) {
            completion(nil)
            return
        }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) })
                        ?? content.displays.first else {
                    await MainActor.run { completion(nil) }
                    return
                }

                let displayRelativeRect = CGRect(
                    x: rect.origin.x - display.frame.origin.x,
                    y: rect.origin.y - display.frame.origin.y,
                    width: rect.width,
                    height: rect.height
                ).integral

                let config = SCStreamConfiguration()
                config.sourceRect = displayRelativeRect
                config.width = Int(displayRelativeRect.width)
                config.height = Int(displayRelativeRect.height)
                config.showsCursor = false

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                await MainActor.run { completion(data) }
            } catch {
                await MainActor.run { completion(nil) }
            }
        }
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = false
        rebuild()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 14
        rebuild()
    }

    private func rebuild() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        glowLayer?.removeFromSuperlayer()

        let gl = CALayer()
        gl.frame = bounds
        gl.cornerRadius = 14
        gl.backgroundColor = NSColor.clear.cgColor
        gl.borderWidth = 3.8
        gl.borderColor = llm.glowColor.withAlphaComponent(1.0).cgColor
        gl.shadowColor = llm.glowColor.cgColor
        gl.shadowRadius = 26
        gl.shadowOpacity = 0.95
        gl.shadowOffset = .zero
        gl.shadowPath = CGPath(
            roundedRect: gl.bounds,
            cornerWidth: gl.cornerRadius,
            cornerHeight: gl.cornerRadius,
            transform: nil
        )
        layer?.insertSublayer(gl, at: 0)
        glowLayer = gl

        let pulseOpacity = CABasicAnimation(keyPath: "shadowOpacity")
        pulseOpacity.fromValue = 0.7
        pulseOpacity.toValue = 1.0
        pulseOpacity.duration = 0.95
        pulseOpacity.autoreverses = true
        pulseOpacity.repeatCount = .infinity
        gl.add(pulseOpacity, forKey: "pulseOpacity")

        let pulseWidth = CABasicAnimation(keyPath: "borderWidth")
        pulseWidth.fromValue = 3.4
        pulseWidth.toValue = 5.8
        pulseWidth.duration = 0.95
        pulseWidth.autoreverses = true
        pulseWidth.repeatCount = .infinity
        gl.add(pulseWidth, forKey: "pulseWidth")
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
            (window as? SelectionOverlayWindow)?.deactivate()
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
        (window as? SelectionOverlayWindow)?.deactivate()
        onSelection?(cgRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = activeLLM.glowColor

        if !dragging && currentRect.equalTo(.zero) {
            NSColor.black.withAlphaComponent(0.18).setFill()
            bounds.fill()

            let hint = "Drag to select  •  Esc to cancel"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.95),
            ]
            let sz = (hint as NSString).size(withAttributes: attrs)
            let hx = bounds.midX - (sz.width + 20) / 2
            let hy = bounds.maxY - 56
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: NSRect(x: hx, y: hy, width: sz.width + 20, height: sz.height + 10),
                         xRadius: 7, yRadius: 7).fill()
            (hint as NSString).draw(at: NSPoint(x: hx + 10, y: hy + 5), withAttributes: attrs)
            return
        }

        // Scrim outside selection
        let scrim = NSBezierPath(rect: bounds)
        let hole  = NSBezierPath(rect: currentRect)
        scrim.append(hole)
        scrim.windingRule = .evenOdd
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

// MARK: — Overlay Panel
// ─────────────────────────────────────────────

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DraggableVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}

// ─────────────────────────────────────────────
// MARK: — Overlay View Controller
// ─────────────────────────────────────────────

final class OverlayViewController: NSViewController {
    private let glowView      = GlowBorderView()
    private let container     = DraggableVisualEffectView()
    private let llmPicker     = NSSegmentedControl()
    private let textField     = NSTextField()
    private let responseLabel = NSTextField()
    private let modeLabel     = NSTextField()
    private let hotkeyHint    = NSTextField()

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
        let inner = NSRect(x: 6, y: 6,
                           width: Config.overlayWidth - 12,
                           height: Config.overlayHeight - 12)

        glowView.frame = inner.insetBy(dx: -2, dy: -2)
        glowView.wantsLayer = true
        glowView.layer?.cornerRadius = 14
        glowView.layer?.masksToBounds = false
        view.addSubview(glowView)

        container.frame = inner
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.blendingMode = .behindWindow
        container.material = .underWindowBackground
        container.state = .active
        container.layer?.backgroundColor = NSColor(calibratedRed: 0.33, green: 0.56, blue: 0.92, alpha: 0.16).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        view.addSubview(container)

        modeLabel.frame = NSRect(x: 20, y: inner.height - 26, width: 300, height: 16)
        modeLabel.isEditable = false; modeLabel.isBordered = false
        modeLabel.backgroundColor = .clear
        modeLabel.textColor = .white.withAlphaComponent(0.88)
        modeLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        modeLabel.stringValue = "MagicPointer  ·  cursor context"
        container.addSubview(modeLabel)

        hotkeyHint.frame = NSRect(x: inner.width - 190, y: inner.height - 26, width: 170, height: 16)
        hotkeyHint.isEditable = false
        hotkeyHint.isBordered = false
        hotkeyHint.backgroundColor = .clear
        hotkeyHint.textColor = .white.withAlphaComponent(0.75)
        hotkeyHint.font = NSFont.systemFont(ofSize: 10)
        hotkeyHint.alignment = .right
        hotkeyHint.stringValue = "⌘⇧Space: select"
        container.addSubview(hotkeyHint)

        llmPicker.frame = NSRect(x: 18, y: inner.height - 52, width: Config.overlayWidth - 36, height: 22)
        llmPicker.segmentCount = LLM.allCases.count
        for (i, llm) in LLM.allCases.enumerated() {
            llmPicker.setLabel("\(llm.icon) \(llm.displayName)", forSegment: i)
        }
        llmPicker.selectedSegment = 0
        llmPicker.trackingMode = .selectOne
        llmPicker.target = self; llmPicker.action = #selector(pickerChanged)
        container.addSubview(llmPicker)

        textField.frame = NSRect(x: 18, y: inner.height - 82, width: Config.overlayWidth - 36, height: 24)
        textField.placeholderString = "Ask about what's under your cursor…"
        textField.isBordered = false; textField.backgroundColor = .clear
        textField.textColor = .white; textField.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        textField.focusRingType = .none; textField.delegate = self
        container.addSubview(textField)

        let sep2 = NSBox(); sep2.boxType = .separator
        sep2.frame = NSRect(x: 18, y: inner.height - 86, width: Config.overlayWidth - 36, height: 1)
        container.addSubview(sep2)

        responseLabel.frame = NSRect(x: 18, y: 10, width: Config.overlayWidth - 36, height: 22)
        responseLabel.isEditable = false; responseLabel.isBordered = false
        responseLabel.backgroundColor = .clear; responseLabel.textColor = .white.withAlphaComponent(0.78)
        responseLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        responseLabel.lineBreakMode = .byWordWrapping
        responseLabel.cell?.wraps = true; responseLabel.cell?.isScrollable = false
        responseLabel.stringValue = "Ask anything about what you are looking at"
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
        let pageSummary = extractedPageSummary(from: context.hoveredText)

        switch context.source {
        case .cursor:
            modeLabel.stringValue = pageSummary == nil ? "MagicPointer  ·  cursor context"
                                                       : "MagicPointer  ·  web context"
            if let pageSummary, !pageSummary.isEmpty {
                let summary = "\(String(pageSummary.prefix(80)))\(pageSummary.count > 80 ? "…" : "")"
                textField.placeholderString = "About page: \(summary)"
            } else if let t = context.hoveredText, !t.isEmpty {
                let summary = "\(String(t.prefix(80)))\(t.count > 80 ? "…" : "")"
                textField.placeholderString = "About: \(summary)"
            } else {
                textField.placeholderString = context.appName.map { "Ask about \($0)…" }
                    ?? "Ask about what's under your cursor…"
            }
        case .selection(let rect):
            modeLabel.stringValue = pageSummary == nil
                ? "selected region  \(Int(rect.width)) × \(Int(rect.height)) px"
                : "selected region  \(Int(rect.width)) × \(Int(rect.height)) px  ·  web context"
            if let pageSummary, !pageSummary.isEmpty {
                let summary = "\(String(pageSummary.prefix(80)))\(pageSummary.count > 80 ? "…" : "")"
                textField.placeholderString = "About selected page area: \(summary)"
            } else if let t = context.hoveredText, !t.isEmpty {
                let summary = "\(String(t.prefix(80)))\(t.count > 80 ? "…" : "")"
                textField.placeholderString = "About selection: \(summary)"
            } else {
                textField.placeholderString = "Ask about the selected region…"
            }
        }
    }

    private func extractedPageSummary(from hoverText: String?) -> String? {
        guard let hoverText, !hoverText.isEmpty else { return nil }
        for line in hoverText.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Page: ") {
                let val = String(trimmed.dropFirst("Page: ".count)).trimmingCharacters(in: .whitespaces)
                return val.isEmpty ? nil : val
            }
        }
        return nil
    }

    func focus() { view.window?.makeFirstResponder(textField) }

    func updatePersistentCaptureStatus(contextCount: Int, latest: String?) {
        hotkeyHint.stringValue = "Esc: close  ·  Context \(contextCount)"
        if let latest, !latest.isEmpty {
            let text = String(latest.prefix(72))
            responseLabel.stringValue = "Captured #\(contextCount): \(text)\(latest.count > 72 ? "…" : "")"
            responseLabel.textColor = .white.withAlphaComponent(0.86)
        } else {
            responseLabel.stringValue = "Shift+Click to add context, or press ⌘C to add copied text."
            responseLabel.textColor = .white.withAlphaComponent(0.78)
        }
    }

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
    private var contextPickMonitor: Any?
    private var escKeyMonitor: Any?
    private var escGlobalMonitor: Any?
    private var copyKeyLocalMonitor: Any?
    private var copyKeyGlobalMonitor: Any?
    private var lastClipboardString: String?
    private var capturedContextSnippets: [String] = []
    var onContextPick: ((CGPoint) -> Void)?
    var onLLMChange: ((LLM) -> Void)?

    init() {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: Config.overlayWidth, height: Config.overlayHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 14
        panel.contentView?.layer?.masksToBounds = false
        panel.invalidateShadow()
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.contentViewController = vc
        vc.onLLMChange = { [weak self] llm in self?.onLLMChange?(llm) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(at screenPoint: CGPoint, context: CursorContext, llm: LLM, requireEscToDismiss: Bool = false) {
        guard let screen = NSScreen.main else { return }
        let origin = NSPoint(
            x: screenPoint.x - Config.overlayWidth / 2,
            y: screen.frame.height - screenPoint.y - Config.overlayHeight / 2 - 70
        )
        window?.setFrameOrigin(origin)
        vc.reset(context: context, llm: llm)
        resetCapturedContext(with: context)
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFront(nil)
        window?.makeKey()
        DispatchQueue.main.async { [weak self] in self?.vc.focus() }

        if let m = contextPickMonitor {
            NSEvent.removeMonitor(m)
            contextPickMonitor = nil
        }
        if let m = escKeyMonitor {
            NSEvent.removeMonitor(m)
            escKeyMonitor = nil
        }
        if let m = escGlobalMonitor {
            NSEvent.removeMonitor(m)
            escGlobalMonitor = nil
        }
        if let m = copyKeyLocalMonitor {
            NSEvent.removeMonitor(m)
            copyKeyLocalMonitor = nil
        }
        if let m = copyKeyGlobalMonitor {
            NSEvent.removeMonitor(m)
            copyKeyGlobalMonitor = nil
        }
        lastClipboardString = NSPasteboard.general.string(forType: .string)

        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 {
                self.dismiss()
                return nil
            }
            return e
        }
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return }
            if e.keyCode == 53 {
                DispatchQueue.main.async { self.dismiss() }
            }
        }
        copyKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            let mods = e.modifierFlags.intersection([.command, .shift, .control, .option])
            if e.keyCode == 8 && mods.contains(.command) && !mods.contains(.shift) && !mods.contains(.control) && !mods.contains(.option) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.captureClipboardContextIfNeeded()
                }
            }
            return e
        }
        copyKeyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return }
            let mods = e.modifierFlags.intersection([.command, .shift, .control, .option])
            if e.keyCode == 8 && mods.contains(.command) && !mods.contains(.shift) && !mods.contains(.control) && !mods.contains(.option) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.captureClipboardContextIfNeeded()
                }
            }
        }

        contextPickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            guard let self, let w = self.window else { return }
            let mods = e.modifierFlags.intersection([.command, .shift, .control, .option])
            guard mods.contains(.shift) else { return }
            let pt = NSEvent.mouseLocation
            if w.frame.contains(pt) { return }
            self.onContextPick?(pt)
        }
    }

    func dismiss() {
        if let m = contextPickMonitor {
            NSEvent.removeMonitor(m)
            contextPickMonitor = nil
        }
        if let m = escKeyMonitor {
            NSEvent.removeMonitor(m)
            escKeyMonitor = nil
        }
        if let m = escGlobalMonitor {
            NSEvent.removeMonitor(m)
            escGlobalMonitor = nil
        }
        if let m = copyKeyLocalMonitor {
            NSEvent.removeMonitor(m)
            copyKeyLocalMonitor = nil
        }
        if let m = copyKeyGlobalMonitor {
            NSEvent.removeMonitor(m)
            copyKeyGlobalMonitor = nil
        }
        lastClipboardString = nil
        capturedContextSnippets.removeAll()
        window?.orderOut(nil)
    }

    func addCapturedContext(_ context: CursorContext) {
        guard let snippet = contextSnippet(from: context) else { return }
        appendCapturedSnippet(snippet)
    }

    func queryWithCapturedContext(_ query: String) -> String {
        guard !capturedContextSnippets.isEmpty else { return query }
        let list = capturedContextSnippets.enumerated().map { idx, item in
            "\(idx + 1). \(item)"
        }.joined(separator: "\n")
        return """
        \(query)

        Additional pointer contexts collected across windows:
        \(list)
        """
    }

    private func resetCapturedContext(with context: CursorContext) {
        capturedContextSnippets.removeAll()
        if let snippet = contextSnippet(from: context) {
            capturedContextSnippets = [snippet]
        }
        vc.updatePersistentCaptureStatus(
            contextCount: max(capturedContextSnippets.count, 1),
            latest: capturedContextSnippets.last
        )
    }

    private func contextSnippet(from context: CursorContext) -> String? {
        if let hover = context.hoveredText?.trimmingCharacters(in: .whitespacesAndNewlines), !hover.isEmpty {
            return String(hover.replacingOccurrences(of: "\n", with: " ").prefix(180))
        }
        if let app = context.appName, !app.isEmpty {
            return "App: \(app)"
        }
        return nil
    }

    private func captureClipboardContextIfNeeded() {
        guard window?.isVisible == true else { return }
        guard let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }
        guard raw != lastClipboardString else { return }
        lastClipboardString = raw
        appendCapturedSnippet("Copied: \(String(raw.prefix(220)))")
    }

    private func appendCapturedSnippet(_ snippet: String) {
        guard !snippet.isEmpty else { return }
        if capturedContextSnippets.last != snippet {
            capturedContextSnippets.append(snippet)
        }
        vc.updatePersistentCaptureStatus(
            contextCount: max(capturedContextSnippets.count, 1),
            latest: snippet
        )
    }

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let wiggle    = WiggleDetector()
    private let capturer  = ContextCapturer()
    private let tars      = TARSClient()
    private let overlay   = OverlayWindowController()
    private let selWindow = SelectionOverlayWindow()

    private var eventTap:  CFMachPort?
    private var lastCtx:   CursorContext?
    private var activeLLM: LLM = .claude
    private var wiggleRequestID = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let logURL = URL(fileURLWithPath: "/tmp/magicpointer.log")
        func log(_ msg: String) {
            let line = "\(Date()): \(msg)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logURL.path) {
                    let handle = try? FileHandle(forWritingTo: logURL)
                    handle?.seekToEndOfFile()
                    handle?.write(data)
                    handle?.closeFile()
                } else {
                    try? data.write(to: logURL)
                }
            }
        }

        NSApp.setActivationPolicy(.accessory)
        log("startup begin")

        let trusted = AXIsProcessTrusted()
        log("AX trusted = \(trusted)")
        requestAX()

        setupEventTap()
        log("event tap = \(eventTap != nil ? "OK" : "FAILED")")

        wireWiggle()
        log("wiggle wired")
        wireSelection()
        log("selection wired")
        wireOverlay()
        log("overlay wired")
        registerHotkey()
        log("hotkey registered")
        log("startup complete")
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

    private func handleMouse(_ event: CGEvent) {
        guard !selWindow.isVisible else { return }
        guard overlay.window?.isVisible != true else { return }
        let point = event.location
        wiggle.process(point: point)
    }

    private func wireWiggle() {
        wiggle.onWiggle = { [weak self] pt in
            guard let self else { return }
            DispatchQueue.main.async {
                self.wiggleRequestID += 1
                let requestID = self.wiggleRequestID
                guard !self.selWindow.isVisible else { return }

                let provisional = CursorContext(
                    source: .cursor(position: pt),
                    hoveredText: nil,
                    appName: NSWorkspace.shared.frontmostApplication?.localizedName,
                    screenshotData: nil
                )
                self.lastCtx = provisional
                self.overlay.show(at: pt, context: provisional, llm: self.activeLLM)
                self.overlay.addCapturedContext(provisional)
                self.capturer.capture(at: pt) { ctx in
                    guard self.wiggleRequestID == requestID else { return }
                    self.lastCtx = ctx
                    self.overlay.addCapturedContext(ctx)
                }
            }
        }
    }

    private func wireSelection() {
        selWindow.onSelection = { [weak self] rect in
            guard let self else { return }
            DispatchQueue.main.async {
                let anchor = CGPoint(x: rect.midX, y: rect.maxY + 20)
                let provisional = CursorContext(
                    source: .selection(rect: rect),
                    hoveredText: nil,
                    appName: NSWorkspace.shared.frontmostApplication?.localizedName,
                    screenshotData: nil
                )
                self.lastCtx = provisional
                self.overlay.show(at: anchor, context: provisional, llm: self.activeLLM)
                self.overlay.addCapturedContext(provisional)
                self.capturer.capture(region: rect) { ctx in
                    self.lastCtx = ctx
                    self.overlay.addCapturedContext(ctx)
                }
            }
        }
    }

    private func wireOverlay() {
        overlay.onLLMChange = { [weak self] llm in
            self?.activeLLM = llm
            self?.selWindow.activeLLM = llm
        }
        overlay.onContextPick = { [weak self] point in
            guard let self else { return }
            self.capturer.capture(at: point) { ctx in
                self.lastCtx = ctx
                self.overlay.addCapturedContext(ctx)
            }
        }
        overlay.vc.onSubmit = { [weak self] query in
            guard let self, let ctx = self.lastCtx else { return }
            let enrichedQuery = self.overlay.queryWithCapturedContext(query)
            self.overlay.submit(query: enrichedQuery, context: ctx, tars: self.tars)
        }
    }

    private func registerHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
            guard event.keyCode == Config.selectModeKeyCode else { return }
            guard mods.contains(.command), mods.contains(.shift), !mods.contains(.control), !mods.contains(.option) else { return }
            DispatchQueue.main.async {
                if self.selWindow.isVisible {
                    self.selWindow.deactivate(); return
                }
                self.wiggleRequestID += 1
                if self.overlay.window?.isVisible == true {
                    self.overlay.dismiss()
                }
                self.selWindow.activate(llm: self.activeLLM)
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
