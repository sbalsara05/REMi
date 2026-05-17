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
//   Wiggle / ⌥Space     → open overlay
//   ⌥C (no overlay)     → silent pre-capture at cursor
//   ⌥C (overlay open)   → add context at cursor
//   ⌥Click (overlay)    → add context at click point
//   ⌘C (overlay)        → append clipboard text to session context

import Cocoa
import CoreGraphics
import ApplicationServices
import ScreenCaptureKit
import Security

// ─────────────────────────────────────────────
// MARK: — Config
// ─────────────────────────────────────────────

enum Config {
    static let remiBaseURL                = "http://localhost:3080/api/remi"
    /// Chat UI for handoff. API uses remiBaseURL (3080). Override with REMI_LIBRECHAT_WEB_URL (e.g. Docker 3080).
    static let librechatWebURL            = ProcessInfo.processInfo.environment["REMI_LIBRECHAT_WEB_URL"]
        ?? "http://localhost:3090"
    static let wiggleThreshold: Int       = 3
    static let wiggleWindowSeconds        = 1.2
    static let wiggleMinDistance: CGFloat = 28
    static let wiggleCooldownSeconds      = 1.0
    static let overlayWidth: CGFloat      = 420
    static let overlayMinWidth: CGFloat   = 300
    static let overlayMaxWidth: CGFloat   = 560
    static var overlayMinHeight: CGFloat  { OverlayLayout.minimumPanelHeight }
    static let overlayMaxHeight: CGFloat  = 520
    static let overlayCollapsedHeight: CGFloat = 48
    static var overlayHeight: CGFloat     { overlayMinHeight }
    static let overlayStreamLineHeight: CGFloat = 18
    static let overlayCornerRadius: CGFloat = 18
    static let cursorCaptureSize: CGFloat = 360
    static let selectModeKeyCode: UInt16  = 49   // Space
    static let selectModeModifiers: NSEvent.ModifierFlags = [.command, .shift]
    static let contextCaptureKeyCode: UInt16 = 8 // C
    static let contextCaptureModifiers: NSEvent.ModifierFlags = [.option]
    static let contextCaptureHint = "⌥C"
    /// Max images sent per query (1 primary + extras) to stay within model limits.
    static let maxScreenshotsPerQuery = 4
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

    var logoResourceName: String {
        switch self {
        case .claude:  return "llm-claude"
        case .chatgpt: return "llm-chatgpt"
        case .gemini:  return "llm-gemini"
        }
    }

    var monochromeLogo: NSImage? {
        guard let url = Bundle.main.url(forResource: logoResourceName, withExtension: "png"),
              let img = NSImage(contentsOf: url)?.copy() as? NSImage else { return nil }
        img.size = NSSize(width: 16, height: 16)
        img.isTemplate = true
        return img
    }
}

private enum OverlayLayout {
    static let margin: CGFloat = 14
    static let topInset: CGFloat = 8
    static let titleBarH: CGFloat = 28
    static let trafficLightSize: CGFloat = 12
    static let trafficLightGap: CGFloat = 6
    static let contextPillW: CGFloat = 88
    static let pickerH: CGFloat = 28
    static let rowGap: CGFloat = 6
    static let inputH: CGFloat = 32
    /// Raises sprite to align with NSTextField cap height (sheet art sits low in its frame).
    static let inputSpriteRaise: CGFloat = 9
    static let separatorH: CGFloat = 1
    static let contextRowH: CGFloat = 32
    static let handoffRowH: CGFloat = 30
    static let nudgeRowH: CGFloat = 52
    static let minimumResponseHeight: CGFloat = 40
    static let bottomPad: CGFloat = 8
    static let containerInset: CGFloat = 12

    static var chromeAboveContext: CGFloat {
        topInset + titleBarH + rowGap + pickerH + rowGap + inputH + rowGap + separatorH + rowGap
    }

    static var minimumInnerHeight: CGFloat {
        let handoffChrome = handoffRowH + rowGap
        return max(
            chromeAboveContext + contextRowH + handoffChrome + bottomPad,
            chromeAboveContext + minimumResponseHeight + handoffChrome + bottomPad
        )
    }

    static var minimumPanelHeight: CGFloat {
        minimumInnerHeight + containerInset
    }

    static func llmPickerWidth(segmentCount: Int) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var total: CGFloat = 8
        for llm in LLM.allCases.prefix(segmentCount) {
            let textW = (llm.displayName as NSString).size(withAttributes: attrs).width
            total += ceil(textW) + 20
        }
        return total
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
    let interactionId: String
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
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let captureSize = CGSize(width: 800, height: 600)
        let rawRect = CGRect(
            x: point.x - captureSize.width / 2,
            y: point.y - captureSize.height / 2,
            width: captureSize.width,
            height: captureSize.height
        )
        let clampedRect = rawRect.intersection(screen)
        captureRegion(clampedRect) { data in
            completion(
                CursorContext(
                    interactionId: UUID().uuidString,
                    source: .cursor(position: point),
                    hoveredText: hoveredText,
                    appName: appName,
                    screenshotData: data
                )
            )
        }
    }

    func previewHover(at point: CGPoint) -> String? {
        mergedHoverContext(at: point)
    }

    func capture(region rect: CGRect, completion: @escaping (CursorContext) -> Void) {
        let hoveredText = mergedHoverContext(at: CGPoint(x: rect.midX, y: rect.midY))
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        captureRegion(rect) { data in
            completion(
                CursorContext(
                    interactionId: UUID().uuidString,
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
// MARK: — REMi Auth (Keychain + device login)
// ─────────────────────────────────────────────

enum RemiAuth {
    private static let accessKey = "remi.accessToken"
    private static let refreshKey = "remi.refreshToken"

    static var accessToken: String? {
        KeychainHelper.read(key: accessKey)
    }

    static func saveSession(access: String, refresh: String) {
        KeychainHelper.write(key: accessKey, value: access)
        KeychainHelper.write(key: refreshKey, value: refresh)
    }

    static func clearSession() {
        KeychainHelper.delete(key: accessKey)
        KeychainHelper.delete(key: refreshKey)
    }

    static func ensureLoggedIn(completion: @escaping (Error?) -> Void) {
        if accessToken != nil {
            completion(nil)
            return
        }
        promptLogin(completion: completion)
    }

    static func promptLogin(completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Sign in to REMi"
            alert.informativeText = "Use your LibreChat account credentials."
            alert.addButton(withTitle: "Sign In")
            alert.addButton(withTitle: "Cancel")

            let fields = makeCredentialFields()
            alert.accessoryView = fields.container
            alert.window.initialFirstResponder = fields.email

            guard alert.runModal() == .alertFirstButtonReturn else {
                completion(URLError(.cancelled))
                return
            }

            let email = fields.email.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = fields.password.stringValue
            guard !email.isEmpty, !password.isEmpty else {
                completion(NSError(domain: "RemiAuth", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: "Enter your email and password.",
                ]))
                return
            }

            login(email: email, password: password, completion: completion)
        }
    }

    private static func makeCredentialFields() -> (container: NSView, email: NSTextField, password: NSSecureTextField) {
        let width: CGFloat = 280
        let height: CGFloat = 56
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let email = NSTextField(frame: NSRect(x: 0, y: 28, width: width, height: 24))
        email.placeholderString = "Email"
        email.isEditable = true
        email.isSelectable = true
        email.isBezeled = true
        email.bezelStyle = .roundedBezel

        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        password.placeholderString = "Password"
        password.isEditable = true
        password.isSelectable = true
        password.isBezeled = true
        password.bezelStyle = .roundedBezel

        container.addSubview(email)
        container.addSubview(password)
        return (container, email, password)
    }

    static func login(email: String, password: String, completion: @escaping (Error?) -> Void) {
        guard !email.isEmpty, !password.isEmpty else {
            completion(NSError(domain: "RemiAuth", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Enter your email and password.",
            ]))
            return
        }
        guard let url = URL(string: "\(Config.remiBaseURL)/device/login") else {
            completion(URLError(.badURL)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["email": email, "password": password])

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0

            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (200...299).contains(status) {
                if json["twoFAPending"] as? Bool == true,
                   let tempToken = json["tempToken"] as? String {
                    DispatchQueue.main.async {
                        promptTwoFactor(tempToken: tempToken, completion: completion)
                    }
                    return
                }
                if let token = json["token"] as? String,
                   let refresh = json["refreshToken"] as? String {
                    saveSession(access: token, refresh: refresh)
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
            }

            let message = loginErrorMessage(data: data, status: status)
            DispatchQueue.main.async {
                completion(NSError(domain: "RemiAuth", code: status, userInfo: [
                    NSLocalizedDescriptionKey: message,
                ]))
            }
        }.resume()
    }

    static func promptTwoFactor(tempToken: String, completion: @escaping (Error?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Two-factor authentication"
        alert.informativeText = "Enter the 6-digit code from your authenticator app."
        alert.addButton(withTitle: "Verify")
        alert.addButton(withTitle: "Cancel")

        let codeField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        codeField.placeholderString = "123456"
        codeField.isEditable = true
        codeField.isBezeled = true
        codeField.bezelStyle = .roundedBezel
        alert.accessoryView = codeField
        alert.window.initialFirstResponder = codeField

        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(URLError(.cancelled))
            return
        }

        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            completion(NSError(domain: "RemiAuth", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Enter your authenticator code.",
            ]))
            return
        }

        verifyTwoFactor(tempToken: tempToken, code: code, completion: completion)
    }

    static func verifyTwoFactor(tempToken: String, code: String, completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: "\(Config.remiBaseURL)/device/login/2fa") else {
            completion(URLError(.badURL)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["tempToken": tempToken, "token": code])

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0

            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (200...299).contains(status),
               let token = json["token"] as? String,
               let refresh = json["refreshToken"] as? String {
                saveSession(access: token, refresh: refresh)
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let message = loginErrorMessage(data: data, status: status)
            DispatchQueue.main.async {
                completion(NSError(domain: "RemiAuth", code: status, userInfo: [
                    NSLocalizedDescriptionKey: message,
                ]))
            }
        }.resume()
    }

    private static func loginErrorMessage(data: Data?, status: Int) -> String {
        if let data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["message"] as? String, !message.isEmpty {
                if message == "Missing credentials" {
                    return "Enter your email and password."
                }
                return message
            }
            if let error = json["error"] as? String, !error.isEmpty { return error }
        }
        switch status {
        case 403:
            return "Two-factor authentication is enabled. Turn off 2FA in LibreChat settings or complete login in the web app first."
        case 400:
            return "Enter your email and password."
        case 404, 401, 422:
            return "Invalid email or password."
        case 0:
            return "Cannot reach REMi at \(Config.remiBaseURL). Is the API running on port 3080?"
        default:
            return "Login failed (HTTP \(status))."
        }
    }
}

enum KeychainHelper {
    static func write(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.remi.magicpointer",
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.remi.magicpointer",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.remi.magicpointer",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// ─────────────────────────────────────────────
// MARK: — REMi catalog
// ─────────────────────────────────────────────

struct RemiCatalog: Decodable {
    let agents: [RemiCatalogAgent]
    let skills: [RemiCatalogSkill]
}

struct RemiCatalogAgent: Decodable {
    let id: String
    let name: String
    let description: String?
}

struct RemiCatalogSkill: Decodable {
    let name: String
    let displayName: String?
    let description: String?
}

// ─────────────────────────────────────────────
// MARK: — REMi SSE stream handler
// ─────────────────────────────────────────────

private final class RemiSSEStreamHandler: NSObject, URLSessionDataDelegate {
    private var lineBuffer = ""
    private var finished = false
    private var onToken: ((String) -> Void)?
    private var onComplete: ((Error?) -> Void)?

    func configure(onToken: @escaping (String) -> Void, onComplete: @escaping (Error?) -> Void) {
        lineBuffer = ""
        finished = false
        self.onToken = onToken
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lineBuffer += chunk
        drainLines()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as NSError).domain == NSURLErrorDomain,
           (error as NSError).code == NSURLErrorCancelled {
            return
        }
        drainLines()
        if let http = task.response as? HTTPURLResponse, http.statusCode == 401 {
            RemiAuth.clearSession()
            finish(NSError(domain: "RemiClient", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Session expired — sign in again",
            ]))
            return
        }
        finish(error)
    }

    private func drainLines() {
        while let newline = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<newline])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newline)...])
            handleSSELine(line)
        }
    }

    private func handleSSELine(_ line: String) {
        guard line.hasPrefix("data: ") else { return }
        let payload = String(line.dropFirst(6))
        if payload == "[DONE]" {
            finish(nil)
            return
        }
        if payload.hasPrefix("[ERROR]") {
            finish(NSError(domain: "RemiClient", code: 502, userInfo: [
                NSLocalizedDescriptionKey: String(payload.dropFirst(8)),
            ]))
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onToken?(payload)
        }
    }

    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true
        DispatchQueue.main.async { [weak self] in
            self?.onComplete?(error)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: — REMi Client
// ─────────────────────────────────────────────

final class RemiClient {

    struct Payload: Encodable {
        let interactionId: String
        let query: String
        let llm: String
        let captureMode: String
        let cursorX, cursorY: Double
        let selectionRect: SelectionRect?
        let hoveredText: String?
        let appName: String?
        let screenshotBase64: String?
        let additionalScreenshotsBase64: [String]?
        let mergedContextText: String?
        let screenshotCount: Int?
        let agentId: String?
        let manualSkills: [String]?

        struct SelectionRect: Encodable {
            let x, y, width, height: Double
        }
    }

    struct IndexPayload: Encodable {
        let interactionId: String
        let text: String
        let appName: String?
    }

    struct HandoffResponse: Decodable {
        let conversationId: String
        let alreadySynced: Bool?
    }

    struct HandoffPayload: Encodable {
        let interactionId: String
        let response_so_far: String?

        enum CodingKeys: String, CodingKey {
            case interactionId
            case response_so_far
        }
    }

    struct ContextPayload: Encodable {
        let interactionId: String
        let prompt: String?
        let response_so_far: String?

        enum CodingKeys: String, CodingKey {
            case interactionId
            case prompt
            case response_so_far
        }
    }

    private let baseURL = "http://localhost:3080"
    private var authToken: String?
    private var contextUpdateWorkItem: DispatchWorkItem?

    func setToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ignore placeholder/empty tokens so normal RemiAuth flow can still work.
        if trimmed.isEmpty || trimmed == "YOUR_JWT_HERE" {
            authToken = nil
            return
        }
        authToken = trimmed
    }

    func fetchCatalog(completion: @escaping (Result<RemiCatalog, Error>) -> Void) {
        resolveToken { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            case .success(let token):
                guard let url = URL(string: "\(self.baseURL)/api/remi/catalog") else {
                    DispatchQueue.main.async { completion(.failure(URLError(.badURL))) }
                    return
                }
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                URLSession.shared.dataTask(with: req) { data, response, error in
                    if let error {
                        DispatchQueue.main.async { completion(.failure(error)) }
                        return
                    }
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                          let data else {
                        DispatchQueue.main.async { completion(.failure(URLError(.badServerResponse))) }
                        return
                    }
                    do {
                        let catalog = try JSONDecoder().decode(RemiCatalog.self, from: data)
                        DispatchQueue.main.async { completion(.success(catalog)) }
                    } catch {
                        DispatchQueue.main.async { completion(.failure(error)) }
                    }
                }.resume()
            }
        }
    }

    func indexContext(interactionId: String, text: String, appName: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        resolveToken { [weak self] result in
            guard let self, case .success(let token) = result else { return }
            guard let url = URL(string: "\(self.baseURL)/api/remi/index") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try? JSONEncoder().encode(
                IndexPayload(interactionId: interactionId, text: trimmed, appName: appName)
            )
            URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
        }
    }

    private let streamHandler = RemiSSEStreamHandler()
    private lazy var streamSession: URLSession = {
        URLSession(configuration: .default, delegate: streamHandler, delegateQueue: nil)
    }()
    private var activeStreamTask: URLSessionDataTask?

    func cancelActiveStream() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
    }

    func send(
        query: String, llm: LLM, context: CursorContext,
        sessionInteractionId: String,
        mergedContextText: String? = nil,
        screenshotCount: Int? = nil,
        additionalScreenshots: [Data] = [],
        agentId: String? = nil,
        manualSkills: [String] = [],
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        resolveToken { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { onComplete(err) }
            case .success(let token):
                self.performQuery(
                    query: query,
                    llm: llm,
                    context: context,
                    sessionInteractionId: sessionInteractionId,
                    mergedContextText: mergedContextText,
                    screenshotCount: screenshotCount,
                    additionalScreenshots: additionalScreenshots,
                    agentId: agentId,
                    manualSkills: manualSkills,
                    token: token,
                    onToken: onToken,
                    onComplete: onComplete
                )
            }
        }
    }

    func scheduleContextUpdate(interactionId: String, prompt: String?, responseSoFar: String?) {
        contextUpdateWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.updateContext(interactionId: interactionId, prompt: prompt, responseSoFar: responseSoFar)
        }
        contextUpdateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func updateContext(interactionId: String, prompt: String?, responseSoFar: String?) {
        guard !interactionId.isEmpty else { return }
        resolveToken { [weak self] result in
            guard let self, case .success(let token) = result else { return }
            guard let url = URL(string: "\(self.baseURL)/api/remi/context") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try? JSONEncoder().encode(
                ContextPayload(
                    interactionId: interactionId,
                    prompt: prompt,
                    response_so_far: responseSoFar
                )
            )
            URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
        }
    }

    func handoff(
        interactionId: String,
        responseSoFar: String? = nil,
        completion: @escaping (Result<HandoffResponse, Error>) -> Void
    ) {
        resolveToken { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            case .success(let token):
                guard let url = URL(string: "\(self.baseURL)/api/remi/handoff") else {
                    DispatchQueue.main.async { completion(.failure(URLError(.badURL))) }
                    return
                }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let trimmedResponse = responseSoFar?.trimmingCharacters(in: .whitespacesAndNewlines)
                req.httpBody = try? JSONEncoder().encode(
                    HandoffPayload(
                        interactionId: interactionId,
                        response_so_far: (trimmedResponse?.isEmpty == false) ? trimmedResponse : nil
                    )
                )
                URLSession.shared.dataTask(with: req) { data, response, error in
                    if let error {
                        DispatchQueue.main.async { completion(.failure(error)) }
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        DispatchQueue.main.async { completion(.failure(URLError(.badServerResponse))) }
                        return
                    }
                    guard (200...299).contains(http.statusCode), let data else {
                        let message = data.flatMap { RemiClient.parseErrorMessage(from: String(data: $0, encoding: .utf8) ?? "") }
                            ?? "Handoff failed (\(http.statusCode))"
                        DispatchQueue.main.async {
                            completion(.failure(NSError(
                                domain: "RemiClient",
                                code: http.statusCode,
                                userInfo: [NSLocalizedDescriptionKey: message]
                            )))
                        }
                        return
                    }
                    do {
                        let handoff = try JSONDecoder().decode(HandoffResponse.self, from: data)
                        DispatchQueue.main.async { completion(.success(handoff)) }
                    } catch {
                        DispatchQueue.main.async { completion(.failure(error)) }
                    }
                }.resume()
            }
        }
    }

    static func openChat(conversationId: String) {
        guard let url = URL(string: "\(Config.librechatWebURL)/c/\(conversationId)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func resolveToken(completion: @escaping (Result<String, Error>) -> Void) {
        if let token = authToken {
            completion(.success(token))
            return
        }
        RemiAuth.ensureLoggedIn { authError in
            if let authError {
                DispatchQueue.main.async { completion(.failure(authError)) }
                return
            }
            guard let token = RemiAuth.accessToken else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "RemiClient",
                        code: 401,
                        userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
                    )))
                }
                return
            }
            completion(.success(token))
        }
    }

    private func performQuery(
        query: String, llm: LLM, context: CursorContext,
        sessionInteractionId: String,
        mergedContextText: String?, screenshotCount: Int?, additionalScreenshots: [Data],
        agentId: String?, manualSkills: [String],
        token: String,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        guard let url = URL(string: "\(Config.remiBaseURL)/query") else {
            DispatchQueue.main.async { onComplete(URLError(.badURL)) }
            return
        }

        cancelActiveStream()

        var selRect: Payload.SelectionRect?
        if case .selection(let r) = context.source {
            selRect = .init(x: r.minX, y: r.minY, width: r.width, height: r.height)
        }

        let cappedExtras = Array(additionalScreenshots.suffix(max(0, Config.maxScreenshotsPerQuery - 1)))
        let screenshotDataURI = context.screenshotData
            .map { "data:image/png;base64," + $0.base64EncodedString() }
        let extraDataURIs = cappedExtras.isEmpty
            ? nil
            : cappedExtras.map { "data:image/png;base64," + $0.base64EncodedString() }

        let skills = manualSkills.isEmpty ? nil : manualSkills
        let payload = Payload(
            interactionId: sessionInteractionId,
            query: query,
            llm: llm.rawValue,
            captureMode: selRect != nil ? "selection" : "cursor",
            cursorX: Double(context.cursorPosition.x),
            cursorY: Double(context.cursorPosition.y),
            selectionRect: selRect,
            hoveredText: context.hoveredText,
            appName: context.appName,
            screenshotBase64: screenshotDataURI,
            additionalScreenshotsBase64: extraDataURIs,
            mergedContextText: mergedContextText,
            screenshotCount: screenshotCount,
            agentId: agentId,
            manualSkills: skills
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let bodyData = try? JSONEncoder().encode(payload) else {
            DispatchQueue.main.async {
                onComplete(NSError(
                    domain: "RemiClient",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Request too large — try fewer context snapshots"]
                ))
            }
            return
        }
        req.httpBody = bodyData
        req.timeoutInterval = 120

        streamHandler.configure(onToken: onToken, onComplete: { [weak self] error in
            self?.activeStreamTask = nil
            onComplete(error)
        })

        activeStreamTask = streamSession.dataTask(with: req)
        activeStreamTask?.resume()
    }

    private static func parseErrorMessage(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? String, !err.isEmpty {
            return err
        }
        if trimmed.count <= 280 { return trimmed }
        return String(trimmed.prefix(280)) + "…"
    }
}

// ─────────────────────────────────────────────
// MARK: — Glow Border View
// ─────────────────────────────────────────────

final class GlowBorderView: NSView {
    var llm: LLM = .claude { didSet { applyColors() } }
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()
    private var isStreaming = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = false
        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.locations = [0, 0.25, 0.5, 0.75, 1]
        maskLayer.fillRule = .evenOdd
        gradientLayer.mask = maskLayer
        layer?.addSublayer(gradientLayer)
        applyColors()
    }

    func setStreaming(_ active: Bool) {
        guard isStreaming != active else { return }
        isStreaming = active
        if active {
            startRotation()
        } else {
            stopRotation()
        }
        applyColors()
    }

    override func layout() {
        super.layout()
        let radius: CGFloat = 14
        layer?.cornerRadius = radius
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = radius

        let ringWidth: CGFloat = isStreaming ? 3.5 : 2.5
        let outer = bounds.insetBy(dx: 0.5, dy: 0.5)
        let inner = outer.insetBy(dx: ringWidth, dy: ringWidth)
        let path = CGMutablePath()
        path.addPath(CGPath(roundedRect: outer, cornerWidth: radius, cornerHeight: radius, transform: nil))
        path.addPath(CGPath(
            roundedRect: inner,
            cornerWidth: max(radius - ringWidth, 2),
            cornerHeight: max(radius - ringWidth, 2),
            transform: nil
        ))
        maskLayer.path = path
        maskLayer.frame = bounds
    }

    private func applyColors() {
        let colors = llm.shimmerColors
        gradientLayer.colors = (colors + [colors[0]]).map { $0.withAlphaComponent(isStreaming ? 0.95 : 0.55).cgColor }
        gradientLayer.opacity = isStreaming ? 1 : 0.75
    }

    private func startRotation() {
        guard gradientLayer.animation(forKey: "streamRotate") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 2.4
        spin.repeatCount = .infinity
        gradientLayer.add(spin, forKey: "streamRotate")
    }

    private func stopRotation() {
        gradientLayer.removeAnimation(forKey: "streamRotate")
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

/// Bottom-right grip — resizes the panel; layout follows via `NSWindowDelegate`.
final class OverlayResizeHandle: NSView {
    weak var targetWindow: NSWindow?
    var onResizeEnded: (() -> Void)?

    private var initialFrame: NSRect = .zero
    private var initialMouse = NSPoint.zero

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor.crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = targetWindow else { return }
        initialFrame = window.frame
        initialMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = targetWindow else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - initialMouse.x
        let dy = mouse.y - initialMouse.y

        var frame = initialFrame
        frame.size.width = min(
            Config.overlayMaxWidth,
            max(Config.overlayMinWidth, initialFrame.width + dx)
        )
        let newHeight = min(
            Config.overlayMaxHeight,
            max(Config.overlayMinHeight, initialFrame.height + dy)
        )
        frame.origin.y = initialFrame.origin.y
        frame.size.height = newHeight
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        onResizeEnded?()
    }
}

// ─────────────────────────────────────────────
// MARK: — Context inspector (popover)
// ─────────────────────────────────────────────

private enum ContextCaptureFormatting {
    static func chipLabel(for context: CursorContext, index: Int) -> String {
        let base: String
        if let hover = context.hoveredText?.trimmingCharacters(in: .whitespacesAndNewlines), !hover.isEmpty {
            let flat = hover.replacingOccurrences(of: "\n", with: " ")
            base = String(flat.prefix(48))
        } else if let app = context.appName, !app.isEmpty {
            base = app
        } else {
            switch context.source {
            case .selection(let r):
                base = "\(Int(r.width))×\(Int(r.height))"
            case .cursor:
                base = "Screen"
            }
        }
        return "#\(index + 1) \(base)"
    }

    static func metadataLine(for context: CursorContext) -> String {
        var parts: [String] = []
        if let app = context.appName, !app.isEmpty { parts.append(app) }
        switch context.source {
        case .cursor:
            parts.append("Cursor capture")
        case .selection(let r):
            parts.append("Selection \(Int(r.width))×\(Int(r.height))")
        }
        return parts.joined(separator: " · ")
    }
}

private final class ContextCaptureRowView: NSView {
    private let headerLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private var imageHeightConstraint: CGFloat = 120

    init(context: CursorContext, index: Int, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 80))
        headerLabel.stringValue = ContextCaptureFormatting.chipLabel(for: context, index: index)
        headerLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        headerLabel.textColor = .white.withAlphaComponent(0.92)
        addSubview(headerLabel)

        metaLabel.stringValue = ContextCaptureFormatting.metadataLine(for: context)
        metaLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        metaLabel.textColor = .white.withAlphaComponent(0.62)
        addSubview(metaLabel)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        if let data = context.screenshotData, let img = NSImage(data: data) {
            imageView.image = img
            let aspect = img.size.height / max(img.size.width, 1)
            imageHeightConstraint = min(200, max(72, width * aspect))
        } else {
            imageView.image = nil
            imageHeightConstraint = 0
        }
        addSubview(imageView)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .white.withAlphaComponent(0.86)
        textView.font = NSFont.systemFont(ofSize: 11)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = true
        if let hover = context.hoveredText?.trimmingCharacters(in: .whitespacesAndNewlines), !hover.isEmpty {
            textView.string = hover
        } else {
            textView.string = "No text captured for this snapshot."
        }
        scrollView.documentView = textView

        layoutSubtree(width: width)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func layoutSubtree(width: CGFloat) {
        var y = bounds.height
        let pad: CGFloat = 8
        let textBlockH: CGFloat = 72

        y -= textBlockH
        scrollView.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: textBlockH)

        if imageHeightConstraint > 0 {
            y -= 6
            y -= imageHeightConstraint
            imageView.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: imageHeightConstraint)
            imageView.isHidden = false
        } else {
            imageView.isHidden = true
        }

        y -= 18
        metaLabel.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: 14)
        y -= 18
        headerLabel.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: 16)
    }

    static func preferredHeight(for context: CursorContext, width: CGFloat) -> CGFloat {
        let hasImage = context.screenshotData != nil
        let imgH: CGFloat
        if hasImage, let data = context.screenshotData, let img = NSImage(data: data) {
            let aspect = img.size.height / max(img.size.width, 1)
            imgH = min(200, max(72, width * aspect)) + 6
        } else {
            imgH = 0
        }
        return 8 + 16 + 14 + imgH + 72 + 12
    }
}

private final class ContextInspectorViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let stackView = NSView()
    private let emptyLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 280))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

        emptyLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        emptyLabel.textColor = .white.withAlphaComponent(0.72)
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 3
        emptyLabel.lineBreakMode = .byWordWrapping

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
    }

    func setContexts(_ contexts: [CursorContext]) {
        stackView.subviews.forEach { $0.removeFromSuperview() }
        let width = max(280, view.bounds.width - 16)
        guard !contexts.isEmpty else {
            emptyLabel.stringValue = "\(Config.contextCaptureHint) adds a screen snapshot · ⌘C pastes clipboard text"
            emptyLabel.frame = NSRect(x: 12, y: 80, width: width, height: 48)
            stackView.addSubview(emptyLabel)
            stackView.frame = NSRect(x: 0, y: 0, width: width + 16, height: 140)
            return
        }

        var y: CGFloat = 0
        for (idx, ctx) in contexts.enumerated() {
            let rowH = ContextCaptureRowView.preferredHeight(for: ctx, width: width)
            let row = ContextCaptureRowView(context: ctx, index: idx, width: width)
            row.frame = NSRect(x: 8, y: y, width: width, height: rowH)
            stackView.addSubview(row)
            y += rowH + 8
        }
        stackView.frame = NSRect(x: 0, y: 0, width: width + 16, height: max(y, 120))
    }
}

private final class ContextInspectorController: NSObject, NSPopoverDelegate {
    private let popover: NSPopover
    private let inspectorVC: ContextInspectorViewController

    override init() {
        popover = NSPopover()
        inspectorVC = ContextInspectorViewController()
        super.init()
        popover.contentViewController = inspectorVC
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
    }

    var isShown: Bool { popover.isShown }

    func show(relativeTo positioningRect: NSRect, of positioningView: NSView, contexts: [CursorContext]) {
        inspectorVC.setContexts(contexts)
        let count = max(contexts.count, 1)
        let height = min(420, max(160, CGFloat(count) * 140))
        inspectorVC.view.setFrameSize(NSSize(width: 360, height: height))
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: .maxY)
    }

    func refresh(contexts: [CursorContext]) {
        guard isShown else { return }
        inspectorVC.setContexts(contexts)
    }

    func close() {
        popover.performClose(nil)
    }
}

private final class TrafficLightButton: NSButton {
    enum Kind { case close, minimize }

    init(kind: Kind) {
        super.init(frame: .zero)
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = OverlayLayout.trafficLightSize / 2
        switch kind {
        case .close:
            layer?.backgroundColor = NSColor(red: 1, green: 0.38, blue: 0.35, alpha: 1).cgColor
            toolTip = "Close overlay (Esc)"
        case .minimize:
            layer?.backgroundColor = NSColor(red: 1, green: 0.74, blue: 0.18, alpha: 1).cgColor
            toolTip = "Minimize panel"
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: OverlayLayout.trafficLightSize, height: OverlayLayout.trafficLightSize)
    }
}

// ─────────────────────────────────────────────
// MARK: — Overlay View Controller
// ─────────────────────────────────────────────

final class OverlayViewController: NSViewController {
    private let glowView = GlowBorderView()
    private let container = DraggableVisualEffectView()
    private let titleBar = NSView()
    private let closeTrafficButton = TrafficLightButton(kind: .close)
    private let minimizeTrafficButton = TrafficLightButton(kind: .minimize)
    private let llmPicker = NSSegmentedControl()
    private let remiSprite = RemiSpriteView()
    fileprivate let textField = NSTextField()
    private let contextPillButton = NSButton()
    private let contextBadgeLabel = NSTextField(labelWithString: "0")
    private let contextLabel = NSTextField()
    private let responseScrollView = NSScrollView()
    private let responseTextView = NSTextView()
    private let modeLabel = NSTextField()
    private let hotkeyHint = NSTextField()
    private let resizeHandle = OverlayResizeHandle()
    private let separator = NSBox()
    private let openInChatButton = NSButton()
    private let complexityNudgeContainer = NSView()
    private let complexityNudgeLabel = NSTextField()
    private let complexityNudgeOpenButton = NSButton()
    private let complexityNudgeDismissButton = NSButton()
    private var showsComplexityNudge = false
    private var contextSnapshotCount = 0

    private var isStreamingResponse = false
    private var streamedCharCount = 0
    private(set) var isCollapsed = false
    private(set) var userManualLayout = false
    private var expandedSize: NSSize?

    var currentLLM: LLM = .claude
    var onSubmit: ((String) -> Void)?
    var onLLMChange: ((LLM) -> Void)?
    var onTextChanged: ((String) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onWidthChange: ((CGFloat) -> Void)?
    var onOpenInChat: (() -> Void)?
    var onDismissComplexityNudge: (() -> Void)?
    var onContextInspect: (() -> Void)?
    var onCloseOverlay: (() -> Void)?

    var responseTranscript: String { responseTextView.string }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0,
                                    width: Config.overlayWidth,
                                    height: Config.overlayMinHeight))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        applyLayout(collapsed: false)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyLayout(collapsed: isCollapsed)
    }

    private func buildUI() {
        glowView.wantsLayer = true
        glowView.layer?.masksToBounds = false
        view.addSubview(glowView)

        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.blendingMode = .behindWindow
        container.material = .underWindowBackground
        container.state = .active
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        view.addSubview(container)

        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        container.addSubview(titleBar)

        closeTrafficButton.target = self
        closeTrafficButton.action = #selector(closeOverlayPressed)
        titleBar.addSubview(closeTrafficButton)

        minimizeTrafficButton.target = self
        minimizeTrafficButton.action = #selector(toggleCollapsed)
        titleBar.addSubview(minimizeTrafficButton)

        modeLabel.isEditable = false
        modeLabel.isBordered = false
        modeLabel.backgroundColor = .clear
        modeLabel.textColor = .white.withAlphaComponent(0.92)
        modeLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        modeLabel.stringValue = "REMi · cursor"
        titleBar.addSubview(modeLabel)

        hotkeyHint.isEditable = false
        hotkeyHint.isBordered = false
        hotkeyHint.backgroundColor = .clear
        hotkeyHint.textColor = .white.withAlphaComponent(0.75)
        hotkeyHint.font = NSFont.systemFont(ofSize: 10)
        hotkeyHint.alignment = .right
        hotkeyHint.stringValue = "Esc · Context 0"
        titleBar.addSubview(hotkeyHint)

        resizeHandle.targetWindow = view.window
        resizeHandle.onResizeEnded = { [weak self] in
            self?.noteUserResize()
        }
        container.addSubview(resizeHandle)

        llmPicker.segmentCount = LLM.allCases.count
        llmPicker.segmentStyle = .rounded
        llmPicker.segmentDistribution = .fill
        llmPicker.trackingMode = .selectOne
        for (i, llm) in LLM.allCases.enumerated() {
            llmPicker.setImage(nil, forSegment: i)
            llmPicker.setLabel(llm.displayName, forSegment: i)
        }
        llmPicker.selectedSegment = 0
        llmPicker.target = self
        llmPicker.action = #selector(pickerChanged)
        container.addSubview(llmPicker)

        remiSprite.startIdle()
        container.addSubview(remiSprite)

        textField.placeholderString = "Ask about what's under your cursor…"
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.textColor = .white
        textField.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        textField.focusRingType = .none
        textField.delegate = self
        container.addSubview(textField)

        separator.boxType = .separator
        container.addSubview(separator)

        contextLabel.isEditable = false
        contextLabel.isBordered = false
        contextLabel.isBezeled = false
        contextLabel.drawsBackground = false
        contextLabel.textColor = .white.withAlphaComponent(0.78)
        contextLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        contextLabel.lineBreakMode = .byTruncatingTail
        contextLabel.cell?.truncatesLastVisibleLine = true
        contextPillButton.title = "Context"
        contextPillButton.bezelStyle = .rounded
        contextPillButton.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        contextPillButton.target = self
        contextPillButton.action = #selector(contextPillPressed)
        contextPillButton.toolTip = "View attached snapshots and text"
        contextPillButton.isEnabled = false
        container.addSubview(contextPillButton)

        contextBadgeLabel.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        contextBadgeLabel.textColor = .white
        contextBadgeLabel.alignment = .center
        contextBadgeLabel.drawsBackground = true
        contextBadgeLabel.backgroundColor = NSColor.white.withAlphaComponent(0.22)
        contextBadgeLabel.wantsLayer = true
        contextBadgeLabel.layer?.cornerRadius = 7
        contextBadgeLabel.isHidden = true
        container.addSubview(contextBadgeLabel)

        contextLabel.stringValue = "\(Config.contextCaptureHint) to add context, or ⌘C for clipboard."
        container.addSubview(contextLabel)

        responseScrollView.hasVerticalScroller = true
        responseScrollView.drawsBackground = false
        responseScrollView.borderType = .noBorder
        responseScrollView.autohidesScrollers = true
        container.addSubview(responseScrollView)

        responseTextView.isEditable = false
        responseTextView.isSelectable = true
        responseTextView.drawsBackground = false
        responseTextView.textColor = .white.withAlphaComponent(0.88)
        responseTextView.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        responseTextView.textContainerInset = NSSize(width: 4, height: 6)
        responseTextView.textContainer?.widthTracksTextView = true
        responseTextView.string = ""
        responseScrollView.documentView = responseTextView
        responseScrollView.isHidden = true

        openInChatButton.title = "Open in chat"
        openInChatButton.bezelStyle = .rounded
        openInChatButton.isEnabled = false
        openInChatButton.alphaValue = 0.45
        openInChatButton.target = self
        openInChatButton.action = #selector(openInChatPressed)
        openInChatButton.toolTip = "Continue in LibreChat (⌘⇧O)"
        container.addSubview(openInChatButton)

        complexityNudgeContainer.isHidden = true
        complexityNudgeContainer.wantsLayer = true
        complexityNudgeContainer.layer?.cornerRadius = 8
        complexityNudgeContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        container.addSubview(complexityNudgeContainer)

        complexityNudgeLabel.isEditable = false
        complexityNudgeLabel.isBordered = false
        complexityNudgeLabel.drawsBackground = false
        complexityNudgeLabel.textColor = .white.withAlphaComponent(0.88)
        complexityNudgeLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        complexityNudgeLabel.stringValue = "This looks involved — open in chat to continue"
        complexityNudgeLabel.lineBreakMode = .byWordWrapping
        complexityNudgeLabel.maximumNumberOfLines = 2
        complexityNudgeContainer.addSubview(complexityNudgeLabel)

        complexityNudgeOpenButton.title = "Open in chat"
        complexityNudgeOpenButton.bezelStyle = .rounded
        complexityNudgeOpenButton.target = self
        complexityNudgeOpenButton.action = #selector(openInChatPressed)
        complexityNudgeContainer.addSubview(complexityNudgeOpenButton)

        complexityNudgeDismissButton.title = "Dismiss"
        complexityNudgeDismissButton.bezelStyle = .rounded
        complexityNudgeDismissButton.target = self
        complexityNudgeDismissButton.action = #selector(dismissNudgePressed)
        complexityNudgeContainer.addSubview(complexityNudgeDismissButton)
    }

    @objc private func openInChatPressed() {
        onOpenInChat?()
    }

    @objc private func closeOverlayPressed() {
        onCloseOverlay?()
    }

    @objc private func contextPillPressed() {
        onContextInspect?()
    }

    func contextPillFrameForPopover() -> NSRect {
        contextPillButton.convert(contextPillButton.bounds, to: view)
    }

    func updateContextPill(snapshotCount: Int, chipPreview: String?) {
        contextSnapshotCount = snapshotCount
        contextPillButton.isEnabled = snapshotCount > 0
        contextBadgeLabel.isHidden = snapshotCount <= 0
        contextBadgeLabel.stringValue = "\(snapshotCount)"
        if let chipPreview, !chipPreview.isEmpty {
            contextLabel.stringValue = chipPreview
            contextLabel.textColor = .white.withAlphaComponent(0.86)
        } else if snapshotCount == 0 {
            contextLabel.stringValue = "\(Config.contextCaptureHint) adds a screen snapshot · ⌘C pastes clipboard text"
            contextLabel.textColor = .white.withAlphaComponent(0.78)
        } else {
            contextLabel.stringValue = "\(snapshotCount) snapshot\(snapshotCount == 1 ? "" : "s") attached"
            contextLabel.textColor = .white.withAlphaComponent(0.86)
        }
    }

    @objc private func dismissNudgePressed() {
        showComplexityNudge(false)
        onDismissComplexityNudge?()
    }

    func updateHandoffChrome(enabled: Bool, title: String, inFlight: Bool) {
        openInChatButton.title = title
        openInChatButton.isEnabled = enabled && !inFlight
        openInChatButton.alphaValue = (enabled && !inFlight) ? 1 : 0.45
    }

    func showComplexityNudge(_ show: Bool) {
        showsComplexityNudge = show
        complexityNudgeContainer.isHidden = !show
        applyLayout(collapsed: isCollapsed)
        if !userManualLayout, !isCollapsed {
            updateOverlayHeightForContent()
        }
    }

    private func footerChromeHeight() -> CGFloat {
        var height = OverlayLayout.handoffRowH + OverlayLayout.rowGap
        if showsComplexityNudge {
            height += OverlayLayout.nudgeRowH + OverlayLayout.rowGap
        }
        return height
    }

    private var showsResponseArea: Bool {
        isStreamingResponse || !responseTextView.string.isEmpty
    }

    private func relayoutChrome(panelSize: NSSize, innerHeight: CGFloat, collapsed: Bool) {
        let innerW = panelSize.width - OverlayLayout.containerInset
        let titleBarY = innerHeight - OverlayLayout.topInset - OverlayLayout.titleBarH

        titleBar.frame = NSRect(
            x: 0, y: titleBarY,
            width: innerW, height: OverlayLayout.titleBarH
        )
        let lightY = (OverlayLayout.titleBarH - OverlayLayout.trafficLightSize) / 2
        closeTrafficButton.frame = NSRect(
            x: OverlayLayout.margin, y: lightY,
            width: OverlayLayout.trafficLightSize, height: OverlayLayout.trafficLightSize
        )
        minimizeTrafficButton.frame = NSRect(
            x: OverlayLayout.margin + OverlayLayout.trafficLightSize + OverlayLayout.trafficLightGap,
            y: lightY,
            width: OverlayLayout.trafficLightSize, height: OverlayLayout.trafficLightSize
        )
        let titleX = OverlayLayout.margin + (OverlayLayout.trafficLightSize + OverlayLayout.trafficLightGap) * 2 + 8
        hotkeyHint.frame = NSRect(x: innerW - 148, y: 6, width: 136, height: 16)
        modeLabel.frame = NSRect(
            x: titleX, y: 6,
            width: max(80, innerW - titleX - 156), height: 16
        )
        resizeHandle.frame = NSRect(x: innerW - 22, y: 4, width: 18, height: 18)

        let showBody = !collapsed
        titleBar.isHidden = false
        llmPicker.isHidden = !showBody
        textField.isHidden = !showBody
        separator.isHidden = !showBody
        contextPillButton.isHidden = !showBody || showsResponseArea
        contextBadgeLabel.isHidden = !showBody || showsResponseArea || contextSnapshotCount <= 0
        contextLabel.isHidden = !showBody || showsResponseArea
        remiSprite.isHidden = !showBody || showsResponseArea
        responseScrollView.isHidden = !showBody || !showsResponseArea
        openInChatButton.isHidden = !showBody
        complexityNudgeContainer.isHidden = !showBody || !showsComplexityNudge
        resizeHandle.isHidden = collapsed

        guard showBody else { return }

        if innerHeight < OverlayLayout.minimumInnerHeight, !userManualLayout {
            onHeightChange?(OverlayLayout.minimumPanelHeight)
            return
        }

        var y = titleBarY - OverlayLayout.rowGap

        let pickerW = innerW - OverlayLayout.margin * 2
        y -= OverlayLayout.pickerH
        llmPicker.frame = NSRect(
            x: OverlayLayout.margin, y: y, width: pickerW, height: OverlayLayout.pickerH
        )
        y -= OverlayLayout.rowGap

        y -= OverlayLayout.inputH
        let inputY = y
        let spriteColumnW = remiSprite.columnWidth
        let spriteH = remiSprite.intrinsicContentSize.height
        let showSpriteInInput = !showsResponseArea
        if showSpriteInInput {
            remiSprite.frame = NSRect(
                x: 10,
                y: inputY + max(0, (OverlayLayout.inputH - spriteH) / 2 + OverlayLayout.inputSpriteRaise),
                width: spriteColumnW,
                height: spriteH
            )
        }
        let inputX = showSpriteInInput ? 10 + spriteColumnW + 6 : OverlayLayout.margin
        textField.frame = NSRect(
            x: inputX, y: inputY,
            width: max(80, innerW - inputX - OverlayLayout.margin),
            height: OverlayLayout.inputH
        )
        y -= OverlayLayout.rowGap

        y -= OverlayLayout.separatorH
        separator.frame = NSRect(
            x: OverlayLayout.margin, y: y,
            width: innerW - OverlayLayout.margin * 2, height: OverlayLayout.separatorH
        )
        y -= OverlayLayout.rowGap

        var bottomY = OverlayLayout.bottomPad
        openInChatButton.frame = NSRect(
            x: OverlayLayout.margin,
            y: bottomY,
            width: innerW - OverlayLayout.margin * 2,
            height: OverlayLayout.handoffRowH
        )
        bottomY += OverlayLayout.handoffRowH + OverlayLayout.rowGap

        if showsComplexityNudge {
            let nudgeW = innerW - OverlayLayout.margin * 2
            complexityNudgeContainer.frame = NSRect(
                x: OverlayLayout.margin,
                y: bottomY,
                width: nudgeW,
                height: OverlayLayout.nudgeRowH
            )
            complexityNudgeLabel.frame = NSRect(x: 8, y: 26, width: nudgeW - 16, height: 22)
            complexityNudgeOpenButton.frame = NSRect(x: 8, y: 4, width: 96, height: 20)
            complexityNudgeDismissButton.frame = NSRect(x: 110, y: 4, width: 72, height: 20)
            bottomY += OverlayLayout.nudgeRowH + OverlayLayout.rowGap
        }

        if showsResponseArea {
            let available = max(0, y - bottomY)
            let responseH = max(OverlayLayout.minimumResponseHeight, available)
            responseScrollView.frame = NSRect(
                x: OverlayLayout.margin,
                y: bottomY,
                width: innerW - OverlayLayout.margin * 2,
                height: responseH
            )
            if available < OverlayLayout.minimumResponseHeight, !userManualLayout {
                onHeightChange?(OverlayLayout.minimumPanelHeight)
            }
        } else {
            let contextY = y - OverlayLayout.contextRowH
            contextPillButton.frame = NSRect(
                x: OverlayLayout.margin,
                y: contextY + 4,
                width: OverlayLayout.contextPillW,
                height: 24
            )
            contextBadgeLabel.frame = NSRect(
                x: OverlayLayout.margin + OverlayLayout.contextPillW - 18,
                y: contextY + 14,
                width: 16,
                height: 14
            )
            let labelX = OverlayLayout.margin + OverlayLayout.contextPillW + 8
            contextLabel.frame = NSRect(
                x: labelX,
                y: contextY + 8,
                width: max(40, innerW - labelX - OverlayLayout.margin),
                height: 16
            )
        }
    }

    func applyLayout(collapsed: Bool) {
        if let parent = view.superview {
            view.frame = parent.bounds
        }
        let panelSize = view.bounds.size
        let width = min(Config.overlayMaxWidth, max(Config.overlayMinWidth, panelSize.width))
        let height: CGFloat
        if collapsed {
            height = Config.overlayCollapsedHeight
        } else {
            height = min(Config.overlayMaxHeight, max(Config.overlayMinHeight, panelSize.height))
        }

        let innerH = height - OverlayLayout.containerInset
        let inner = NSRect(
            x: OverlayLayout.containerInset / 2, y: OverlayLayout.containerInset / 2,
            width: width - OverlayLayout.containerInset, height: innerH
        )
        glowView.frame = inner.insetBy(dx: -2, dy: -2)
        container.frame = inner
        relayoutChrome(panelSize: NSSize(width: width, height: height), innerHeight: innerH, collapsed: collapsed)

        let fillAlpha = 0.08 + min(0.14, CGFloat(streamedCharCount) / 500)
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(fillAlpha).cgColor

        resizeHandle.targetWindow = view.window
    }

    func syncLayoutToWindow(userInitiated: Bool) {
        if userInitiated {
            userManualLayout = true
        }
        applyLayout(collapsed: isCollapsed)
    }

    func noteUserResize() {
        userManualLayout = true
        if !isCollapsed {
            expandedSize = view.bounds.size
        }
        syncLayoutToWindow(userInitiated: true)
    }

    @objc private func toggleCollapsed() {
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    func collapse() {
        guard !isCollapsed else { return }
        expandedSize = view.bounds.size
        isCollapsed = true
        minimizeTrafficButton.toolTip = "Restore panel"
        onHeightChange?(Config.overlayCollapsedHeight)
        applyLayout(collapsed: true)
    }

    func expand() {
        guard isCollapsed else { return }
        isCollapsed = false
        minimizeTrafficButton.toolTip = "Minimize panel"
        let target = expandedSize ?? NSSize(width: Config.overlayWidth, height: Config.overlayMinHeight)
        onHeightChange?(target.height)
        onWidthChange?(target.width)
        applyLayout(collapsed: false)
    }

    private func setOverlayHeight(_ height: CGFloat) {
        guard !userManualLayout, !isCollapsed else { return }
        let clamped = min(Config.overlayMaxHeight, max(Config.overlayMinHeight, height))
        onHeightChange?(clamped)
    }

    private func updateOverlayHeightForContent() {
        guard !userManualLayout, !isCollapsed else {
            responseTextView.scrollToEndOfDocument(nil)
            return
        }
        let width = responseScrollView.contentSize.width - 8
        guard width > 0,
              let layout = responseTextView.layoutManager,
              let container = responseTextView.textContainer else {
            setOverlayHeight(Config.overlayMinHeight)
            return
        }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        let responseBlock = min(152, max(OverlayLayout.minimumResponseHeight, used + 18))
        let nudgeExtra = showsComplexityNudge ? (OverlayLayout.nudgeRowH + OverlayLayout.rowGap) : 0
        setOverlayHeight(
            OverlayLayout.minimumPanelHeight
                + max(0, responseBlock - OverlayLayout.minimumResponseHeight)
                + nudgeExtra
        )
    }

    private func setChromeDimmed(_ dimmed: Bool) {
        let alpha: CGFloat = dimmed ? 0.45 : 1
        llmPicker.alphaValue = alpha
        textField.alphaValue = alpha
        contextLabel.alphaValue = alpha
        contextPillButton.alphaValue = alpha
        modeLabel.alphaValue = dimmed ? 0.7 : 0.92
    }

    @objc private func pickerChanged() {
        let idx = max(0, llmPicker.selectedSegment)
        let llm = LLM.allCases[idx]
        updateLLM(llm)
        onLLMChange?(llm)
    }

    func updateLLM(_ llm: LLM) {
        currentLLM = llm
        glowView.llm = llm
        if let idx = LLM.allCases.firstIndex(of: llm) {
            llmPicker.selectedSegment = idx
        }
    }

    func reset(
        context: CursorContext,
        llm: LLM,
        interactionNumber: Int,
        mergedTexts: String?,
        screenshotCount: Int
    ) {
        isStreamingResponse = false
        streamedCharCount = 0
        userManualLayout = false
        isCollapsed = false
        expandedSize = nil
        minimizeTrafficButton.toolTip = "Minimize panel"
        glowView.setStreaming(false)
        remiSprite.setStreaming(false)
        remiSprite.startIdle()
        setChromeDimmed(false)
        textField.stringValue = ""
        responseTextView.string = ""
        contextLabel.stringValue = "\(Config.contextCaptureHint) to add context, or ⌘C for clipboard."
        contextLabel.textColor = .white.withAlphaComponent(0.78)
        onHeightChange?(OverlayLayout.minimumPanelHeight)
        onWidthChange?(Config.overlayWidth)
        applyLayout(collapsed: false)
        updateLLM(llm)

        let pageSummary = extractedPageSummary(from: context.hoveredText)
        let prefix = "#\(interactionNumber)  ·  "
        let snapshotSuffix = screenshotCount > 0 ? "  ·  \(screenshotCount) snapshots" : ""

        switch context.source {
        case .cursor:
            modeLabel.stringValue = pageSummary == nil
                ? "\(prefix)cursor context\(snapshotSuffix)"
                : "\(prefix)web context\(snapshotSuffix)"
            if let pageSummary, !pageSummary.isEmpty {
                let summary = "\(String(pageSummary.prefix(80)))\(pageSummary.count > 80 ? "…" : "")"
                textField.placeholderString = "About page: \(summary)"
            } else if let mergedTexts, !mergedTexts.isEmpty {
                let summary = String(mergedTexts.prefix(80)).replacingOccurrences(of: "\n", with: " ")
                textField.placeholderString = "About collected context: \(summary)\(mergedTexts.count > 80 ? "…" : "")"
            } else if let t = context.hoveredText, !t.isEmpty {
                let summary = "\(String(t.prefix(80)))\(t.count > 80 ? "…" : "")"
                textField.placeholderString = "About: \(summary)"
            } else {
                textField.placeholderString = context.appName.map { "Ask about \($0)…" }
                    ?? "Ask about what's under your cursor…"
            }
        case .selection(let rect):
            modeLabel.stringValue = pageSummary == nil
                ? "\(prefix)selected region  \(Int(rect.width)) × \(Int(rect.height)) px\(snapshotSuffix)"
                : "\(prefix)selected region  \(Int(rect.width)) × \(Int(rect.height)) px  ·  web context\(snapshotSuffix)"
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
        guard !isStreamingResponse else { return }
        hotkeyHint.stringValue = "Esc · Context \(contextCount)"
        if let latest, !latest.isEmpty {
            let text = String(latest.prefix(72))
            contextLabel.stringValue = "Captured #\(contextCount): \(text)\(latest.count > 72 ? "…" : "")"
            contextLabel.textColor = .white.withAlphaComponent(0.86)
        } else {
            contextLabel.stringValue = "\(Config.contextCaptureHint) to add context, or ⌘C for clipboard."
            contextLabel.textColor = .white.withAlphaComponent(0.78)
        }
        applyLayout(collapsed: isCollapsed)
    }

    func showLoading() {
        isStreamingResponse = true
        streamedCharCount = 0
        glowView.setStreaming(true)
        remiSprite.setStreaming(true)
        setChromeDimmed(true)
        textField.isEditable = false
        responseTextView.string = ""
        responseTextView.textColor = .white.withAlphaComponent(0.9)
        applyLayout(collapsed: isCollapsed)
    }

    func appendToken(_ token: String) {
        if responseTextView.string.isEmpty {
            responseTextView.string = token
            applyLayout(collapsed: isCollapsed)
        } else {
            responseTextView.string += token
        }
        streamedCharCount += token.count
        responseTextView.textColor = .white.withAlphaComponent(0.92)
        updateOverlayHeightForContent()
        responseTextView.scrollToEndOfDocument(nil)
    }

    func updateHoverPreview(_ text: String?) {
        guard !isStreamingResponse else { return }
        if let text, !text.isEmpty {
            let flat = text.replacingOccurrences(of: "\n", with: " ")
            let preview = String(flat.prefix(72))
            contextLabel.stringValue = "Hovering: \(preview)\(flat.count > 72 ? "…" : "")"
        } else {
            contextLabel.stringValue = "Hovering: (no text detected)"
        }
        contextLabel.textColor = .white.withAlphaComponent(0.78)
    }

    func updateSnapshotHeader(
        interactionNumber: Int,
        context: CursorContext,
        mergedTexts: String?,
        screenshotCount: Int
    ) {
        let prefix = "#\(interactionNumber)  ·  "
        let snapshotSuffix = screenshotCount > 0 ? "  ·  \(screenshotCount) snapshots" : ""
        let pageSummary = extractedPageSummary(from: context.hoveredText)

        switch context.source {
        case .cursor:
            modeLabel.stringValue = pageSummary == nil
                ? "\(prefix)cursor context\(snapshotSuffix)"
                : "\(prefix)web context\(snapshotSuffix)"
        case .selection(let rect):
            modeLabel.stringValue = pageSummary == nil
                ? "\(prefix)selected region  \(Int(rect.width)) × \(Int(rect.height)) px\(snapshotSuffix)"
                : "\(prefix)selected region  \(Int(rect.width)) × \(Int(rect.height)) px  ·  web context\(snapshotSuffix)"
        }
    }

    func finishResponse(error: Error?) {
        isStreamingResponse = false
        glowView.setStreaming(false)
        remiSprite.setStreaming(false)
        remiSprite.startIdle()
        setChromeDimmed(false)
        if let error {
            responseTextView.string = "Error: \(error.localizedDescription)"
            responseTextView.textColor = .systemRed
        }
        textField.isEditable = true
        textField.stringValue = ""
        textField.window?.makeFirstResponder(textField)
        applyLayout(collapsed: isCollapsed)
        updateOverlayHeightForContent()
    }
}

extension OverlayViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        onTextChanged?(textField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            guard textField.isEditable else { return true }
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

final class OverlayWindowController: NSWindowController, NSWindowDelegate {
    let vc = OverlayViewController()
    private var hoverMonitor: Any?
    private weak var remiClient: RemiClient?
    private var isProgrammaticResize = false
    private var contextPickMonitor: Any?
    private var escKeyMonitor: Any?
    private var escGlobalMonitor: Any?
    private var copyKeyLocalMonitor: Any?
    private var copyKeyGlobalMonitor: Any?
    private var lastClipboardString: String?
    private var sessionContexts: [CursorContext] = []
    private var mergedContextText: String?
    private var screenshotCount: Int = 0
    private var additionalScreenshots: [Data] = []
    private var storedInteractionNumber: Int = 0
    private var sessionInteractionId: String = ""
    private var conversationId: String?
    private var hasSubmittedQuery = false
    private var nudgeDismissed = false
    private var turnCount = 0
    private var lastQueryUsedAgentOrSkill = false
    private var isHandoffInFlight = false
    private var lastSubmittedQuery: String = ""
    private var lastHoverPreviewTime = Date.distantPast
    private var showingCaptureStatus = false
    private let contextInspector = ContextInspectorController()
    private var catalog: RemiCatalog?
    private(set) var selectedAgentId: String?
    private(set) var selectedSkillNames: [String] = []
    var hoverPreviewProvider: ((CGPoint) -> String?)?
    var onOptionClickCapture: ((CGPoint) -> Void)?
    var onLLMChange: ((LLM) -> Void)?

    var sessionContextCount: Int { sessionContexts.count }
    var currentPrimaryContext: CursorContext? { sessionContexts.last }

    init() {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: Config.overlayWidth, height: Config.overlayMinHeight),
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
        panel.delegate = self
        panel.contentViewController = vc
        vc.view.autoresizingMask = [.width, .height]
        vc.onLLMChange = { [weak self] llm in self?.onLLMChange?(llm) }
        vc.onTextChanged = { [weak self] text in self?.handleCommandTextChange(text) }
        vc.onOpenInChat = { [weak self] in self?.openInChat() }
        vc.onDismissComplexityNudge = { [weak self] in
            self?.nudgeDismissed = true
        }
        vc.onContextInspect = { [weak self] in
            self?.toggleContextInspector()
        }
        vc.onCloseOverlay = { [weak self] in
            self?.dismiss()
        }
    }

    private func contextChipPreview() -> String? {
        let chips = sessionContexts.enumerated().map { idx, ctx in
            ContextCaptureFormatting.chipLabel(for: ctx, index: idx)
        }
        guard !chips.isEmpty else { return nil }
        let joined = chips.prefix(3).joined(separator: " · ")
        let overflow = chips.count > 3 ? " · +\(chips.count - 3)" : ""
        return joined + overflow
    }

    private func refreshContextChrome() {
        vc.updateContextPill(
            snapshotCount: sessionContexts.count,
            chipPreview: contextChipPreview()
        )
        contextInspector.refresh(contexts: sessionContexts)
    }

    private func toggleContextInspector() {
        guard !sessionContexts.isEmpty else { return }
        if contextInspector.isShown {
            contextInspector.close()
            return
        }
        contextInspector.show(
            relativeTo: vc.contextPillFrameForPopover(),
            of: vc.view,
            contexts: sessionContexts
        )
    }

    private func beginSession() {
        if sessionInteractionId.isEmpty {
            sessionInteractionId = UUID().uuidString
        }
        conversationId = nil
        hasSubmittedQuery = false
        nudgeDismissed = false
        turnCount = 0
        lastQueryUsedAgentOrSkill = false
        isHandoffInFlight = false
        vc.updateHandoffChrome(enabled: false, title: "Open in chat", inFlight: false)
        vc.showComplexityNudge(false)
    }

    func openInChat() {
        guard !sessionInteractionId.isEmpty, let remi = remiClient else { return }
        if let convoId = conversationId {
            RemiClient.openChat(conversationId: convoId)
            return
        }
        isHandoffInFlight = true
        vc.updateHandoffChrome(enabled: false, title: "Opening…", inFlight: true)
        let transcript = vc.responseTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            remi.updateContext(
                interactionId: sessionInteractionId,
                prompt: nil,
                responseSoFar: transcript
            )
        }
        remi.handoff(interactionId: sessionInteractionId, responseSoFar: transcript) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isHandoffInFlight = false
                switch result {
                case .success(let response):
                    self.conversationId = response.conversationId
                    self.vc.updateHandoffChrome(
                        enabled: true,
                        title: "Open chat",
                        inFlight: false
                    )
                    RemiClient.openChat(conversationId: response.conversationId)
                case .failure(let error):
                    self.vc.updateHandoffChrome(
                        enabled: self.hasSubmittedQuery,
                        title: "Open in chat",
                        inFlight: false
                    )
                    self.vc.finishResponse(error: error)
                }
            }
        }
    }

    private func shouldShowComplexityNudge(query: String, responseLength: Int) -> Bool {
        guard !nudgeDismissed, conversationId == nil else { return false }
        var score = 0
        if screenshotCount >= 3 { score += 1 }
        if turnCount >= 2 && responseLength > 500 { score += 1 }
        if responseLength > 1200 { score += 1 }
        if lastQueryUsedAgentOrSkill && responseLength > 600 { score += 1 }
        return score >= 2
    }

    func loadCatalog(using remi: RemiClient) {
        remi.fetchCatalog { [weak self] result in
            if case .success(let cat) = result {
                self?.catalog = cat
            }
        }
    }

    private func handleCommandTextChange(_ text: String) {
        guard let catalog else { return }
        guard let word = text.split(separator: " ").last.map(String.init) else { return }
        if word.hasPrefix("@") {
            let filter = String(word.dropFirst()).lowercased()
            let agents = catalog.agents.filter {
                filter.isEmpty || $0.name.lowercased().contains(filter) || $0.id.lowercased().contains(filter)
            }
            showCommandMenu(
                items: agents.prefix(12).map { ("@\($0.name)", "agent:\($0.id):\($0.name)") }
            )
        } else if word.hasPrefix("/") {
            let filter = String(word.dropFirst()).lowercased()
            let skills = catalog.skills.filter {
                filter.isEmpty || $0.name.lowercased().contains(filter)
            }
            showCommandMenu(
                items: skills.prefix(12).map {
                    let label = $0.displayName ?? $0.name
                    return ("/\(label)", "skill:\($0.name)")
                }
            )
        }
    }

    private func showCommandMenu(items: [(String, String)]) {
        guard !items.isEmpty, let window else { return }
        let menu = NSMenu()
        for (title, token) in items {
            let item = NSMenuItem(title: title, action: #selector(commandMenuSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = token
            menu.addItem(item)
        }
        let fieldFrame = vc.textField.convert(vc.textField.bounds, to: nil)
        let pt = NSPoint(x: fieldFrame.minX, y: fieldFrame.minY - 4)
        menu.popUp(positioning: nil, at: pt, in: window.contentView)
    }

    @objc private func commandMenuSelected(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? String else { return }
        var text = vc.textField.stringValue
        if let range = text.range(of: #"[@/]\S*$"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        if token.hasPrefix("agent:") {
            let parts = token.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count >= 3 else { return }
            selectedAgentId = parts[1]
            vc.textField.stringValue = text.trimmingCharacters(in: .whitespaces) + " @\(parts[2]) "
        } else if token.hasPrefix("skill:") {
            let name = String(token.dropFirst("skill:".count))
            if !selectedSkillNames.contains(name) {
                selectedSkillNames.append(name)
            }
            vc.textField.stringValue = text.trimmingCharacters(in: .whitespaces) + " /\(name) "
        }
        vc.focus()
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowDidResize(_ notification: Notification) {
        guard !isProgrammaticResize else { return }
        vc.syncLayoutToWindow(userInitiated: true)
    }

    private func resizePanel(height: CGFloat?, width: CGFloat?, animated: Bool) {
        guard let panel = window as? OverlayPanel else { return }
        var frame = panel.frame
        if let width {
            frame.size.width = min(Config.overlayMaxWidth, max(Config.overlayMinWidth, width))
        }
        if let height {
            let clamped = min(Config.overlayMaxHeight, max(Config.overlayMinHeight, height))
            let delta = clamped - frame.size.height
            frame.origin.y += delta
            frame.size.height = clamped
        }
        isProgrammaticResize = true
        panel.setFrame(frame, display: true, animate: animated)
        isProgrammaticResize = false
        vc.applyLayout(collapsed: vc.isCollapsed)
    }

    func show(
        at screenPoint: CGPoint,
        sessionContexts: [CursorContext],
        llm: LLM,
        interactionNumber: Int,
        requireEscToDismiss: Bool = false
    ) {
        guard let screen = NSScreen.main, let panel = window else { return }
        guard let primary = sessionContexts.last else { return }

        vc.onHeightChange = { [weak self] height in
            self?.resizePanel(height: height, width: nil, animated: true)
        }
        vc.onWidthChange = { [weak self] width in
            self?.resizePanel(height: nil, width: width, animated: true)
        }

        let panelH = panel.frame.height > 0 ? panel.frame.height : Config.overlayMinHeight
        let panelW = panel.frame.width > 0 ? panel.frame.width : Config.overlayWidth
        let origin = NSPoint(
            x: screenPoint.x - panelW / 2,
            y: screen.frame.height - screenPoint.y - panelH / 2 - 70
        )
        panel.setFrameOrigin(origin)

        self.sessionContexts = sessionContexts
        self.storedInteractionNumber = interactionNumber
        beginSession()
        self.showingCaptureStatus = false
        selectedAgentId = nil
        selectedSkillNames = []
        rebuildMergedContext()
        vc.reset(
            context: primary,
            llm: llm,
            interactionNumber: interactionNumber,
            mergedTexts: mergedContextText,
            screenshotCount: screenshotCount
        )
        updatePersistentCaptureStatusFromSessions()
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFront(nil)
        window?.makeKey()
        DispatchQueue.main.async { [weak self] in self?.vc.focus() }

        if let m = hoverMonitor {
            NSEvent.removeMonitor(m)
            hoverMonitor = nil
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
            let mods = e.modifierFlags.intersection([.command, .shift, .control, .option])
            if e.keyCode == 53 {
                self.dismiss()
                return nil
            }
            if e.keyCode == 31, mods == [.command, .shift] {
                self.openInChat()
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

        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastHoverPreviewTime) >= 0.15 else { return }
            self.lastHoverPreviewTime = now
            guard !self.showingCaptureStatus else { return }
            let pt = NSEvent.mouseLocation
            if let w = self.window, w.frame.contains(pt) { return }
            DispatchQueue.main.async {
                guard !self.showingCaptureStatus else { return }
                let preview = self.hoverPreviewProvider?(pt)
                self.vc.updateHoverPreview(preview)
            }
        }
        installContextPickMonitor()
    }

    private func installContextPickMonitor() {
        removeContextPickMonitor()
        contextPickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return }
            guard self.window?.isVisible == true else { return }
            let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
            guard mods == [.option] else { return }
            let pt = NSEvent.mouseLocation
            if let w = self.window, w.frame.contains(pt) { return }
            DispatchQueue.main.async { [weak self] in
                self?.onOptionClickCapture?(pt)
            }
        }
    }

    private func removeContextPickMonitor() {
        if let m = contextPickMonitor {
            NSEvent.removeMonitor(m)
            contextPickMonitor = nil
        }
    }

    func show(at screenPoint: CGPoint, context: CursorContext, llm: LLM, requireEscToDismiss: Bool = false) {
        show(
            at: screenPoint,
            sessionContexts: [context],
            llm: llm,
            interactionNumber: storedInteractionNumber > 0 ? storedInteractionNumber : 1,
            requireEscToDismiss: requireEscToDismiss
        )
    }

    func dismiss() {
        if let m = hoverMonitor {
            NSEvent.removeMonitor(m)
            hoverMonitor = nil
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
        removeContextPickMonitor()
        lastClipboardString = nil
        sessionContexts.removeAll()
        mergedContextText = nil
        screenshotCount = 0
        additionalScreenshots = []
        sessionInteractionId = ""
        conversationId = nil
        hasSubmittedQuery = false
        nudgeDismissed = false
        turnCount = 0
        lastQueryUsedAgentOrSkill = false
        isHandoffInFlight = false
        lastSubmittedQuery = ""
        showingCaptureStatus = false
        selectedAgentId = nil
        selectedSkillNames = []
        catalog = nil
        remiClient?.cancelActiveStream()
        remiClient = nil
        contextInspector.close()
        vc.showComplexityNudge(false)
        vc.updateHandoffChrome(enabled: false, title: "Open in chat", inFlight: false)
        window?.orderOut(nil)
    }

    func appendContext(_ context: CursorContext) {
        sessionContexts.append(context)
        rebuildMergedContext()
        refreshContextChrome()
        showingCaptureStatus = true
        vc.updateSnapshotHeader(
            interactionNumber: storedInteractionNumber,
            context: context,
            mergedTexts: mergedContextText,
            screenshotCount: screenshotCount
        )
        updatePersistentCaptureStatusFromSessions()
    }

    func finishInitialCapture(_ context: CursorContext) {
        if sessionContexts.count == 1, sessionContexts[0].screenshotData == nil {
            sessionContexts[0] = context
        } else {
            sessionContexts.append(context)
        }
        rebuildMergedContext()
        refreshContextChrome()
        vc.updateSnapshotHeader(
            interactionNumber: storedInteractionNumber,
            context: context,
            mergedTexts: mergedContextText,
            screenshotCount: screenshotCount
        )
        updatePersistentCaptureStatusFromSessions()
    }

    private func rebuildMergedContext() {
        let merged = sessionContexts
            .compactMap { $0.hoveredText?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n---\n")
        mergedContextText = merged.isEmpty ? nil : merged
        screenshotCount = sessionContexts.count
        let extras = Array(sessionContexts.dropLast()).compactMap { $0.screenshotData }
        let maxExtras = max(0, Config.maxScreenshotsPerQuery - 1)
        additionalScreenshots = Array(extras.suffix(maxExtras))
        refreshContextChrome()
    }

    private func updatePersistentCaptureStatusFromSessions() {
        let snippets = sessionContexts.compactMap { contextSnippet(from: $0) }
        vc.updatePersistentCaptureStatus(
            contextCount: max(sessionContexts.count, snippets.isEmpty ? 0 : 1),
            latest: snippets.last
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
        let clipContext = CursorContext(
            interactionId: UUID().uuidString,
            source: .cursor(position: NSEvent.mouseLocation),
            hoveredText: raw,
            appName: NSWorkspace.shared.frontmostApplication?.localizedName,
            screenshotData: nil
        )
        appendContext(clipContext)
    }

    func submit(
        query: String,
        context: CursorContext,
        remi: RemiClient,
        onComplete: ((Error?) -> Void)? = nil
    ) {
        remiClient = remi
        turnCount += 1
        lastSubmittedQuery = query
        lastQueryUsedAgentOrSkill = selectedAgentId != nil
            || !selectedSkillNames.isEmpty
            || query.contains("@")
            || query.contains("/")
        vc.showLoading()
        let sessionId = sessionInteractionId
        remi.send(
            query: query,
            llm: vc.currentLLM,
            context: context,
            sessionInteractionId: sessionId,
            mergedContextText: mergedContextText,
            screenshotCount: screenshotCount,
            additionalScreenshots: additionalScreenshots,
            agentId: selectedAgentId,
            manualSkills: selectedSkillNames,
            onToken: { [weak self] token in
                guard let self else { return }
                self.vc.appendToken(token)
                self.remiClient?.scheduleContextUpdate(
                    interactionId: sessionId,
                    prompt: nil,
                    responseSoFar: self.vc.responseTranscript
                )
            },
            onComplete: { [weak self] err in
                guard let self else { return }
                self.vc.finishResponse(error: err)
                self.selectedAgentId = nil
                self.selectedSkillNames = []
                if err == nil {
                    self.hasSubmittedQuery = true
                    let handoffTitle = self.conversationId != nil ? "Open chat" : "Open in chat"
                    self.vc.updateHandoffChrome(enabled: true, title: handoffTitle, inFlight: false)
                    if self.shouldShowComplexityNudge(
                        query: self.lastSubmittedQuery,
                        responseLength: self.vc.responseTranscript.count
                    ) {
                        self.vc.showComplexityNudge(true)
                    }
                }
                onComplete?(err)
            }
        )
    }

    func indexCapture(_ context: CursorContext, remi: RemiClient, snapshotIndex: Int) {
        guard let snippet = contextSnippet(from: context) else { return }
        let indexId = sessionInteractionId.isEmpty
            ? context.interactionId
            : "\(sessionInteractionId)-\(snapshotIndex)"
        remi.indexContext(
            interactionId: indexId,
            text: snippet,
            appName: context.appName
        )
    }
}

// ─────────────────────────────────────────────
// MARK: — App Delegate
// ─────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let wiggle    = WiggleDetector()
    private let capturer  = ContextCapturer()
    private let remi      = RemiClient()
    private let overlay   = OverlayWindowController()
    private let selWindow = SelectionOverlayWindow()

    private var eventTap:  CFMachPort?
    private var lastCtx:   CursorContext?
    private var activeLLM: LLM = .claude
    private var wiggleRequestID = 0
    private var interactionCount = 0
    private var lastCursorPosition: CGPoint = .zero
    private var lastOpenTime: Date?
    private var lastContextCaptureTime = Date.distantPast
    private var accumulatedContexts: [CursorContext] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        fileLog("startup begin")

        let trusted = AXIsProcessTrusted()
        fileLog("AX trusted = \(trusted)")
        requestAX()

        setupEventTap()
        fileLog("event tap = \(eventTap != nil ? "OK" : "FAILED")")
        registerHotkey()
        fileLog("hotkey registered")

        wireWiggle()
        fileLog("wiggle wired")
        wireSelection()
        fileLog("selection wired")
        wireOverlay()
        fileLog("overlay wired")
        fileLog("hotkey wired")
        fileLog("startup complete")
    }

    private func fileLog(_ msg: String) {
        let logURL = URL(fileURLWithPath: "/tmp/magicpointer.log")
        let line = "\(Date()): \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path) {
            let handle = try? FileHandle(forWritingTo: logURL)
            handle?.seekToEndOfFile()
            handle?.write(data)
            handle?.closeFile()
        } else {
            try? data.write(to: logURL)
        }
    }

    private func requestAX() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private func setupEventTap() {
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, _, event, ref -> Unmanaged<CGEvent>? in
                Unmanaged<AppDelegate>.fromOpaque(ref!).takeUnretainedValue().handleEvent(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap = eventTap else { print("⚠️  Event tap failed"); return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleEvent(_ event: CGEvent) {
        switch event.type {
        case .mouseMoved:
            lastCursorPosition = event.location
            guard !selWindow.isVisible else { return }
            guard overlay.window?.isVisible != true else { return }
            wiggle.process(point: event.location)
        case .leftMouseDown:
            lastCursorPosition = event.location
        default:
            break
        }
    }

    private func registerHotkey() {
        let keyDownHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            guard !event.isARepeat else { return }

            if event.keyCode == Config.selectModeKeyCode,
               event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.control),
               !event.modifierFlags.contains(.shift) {
                if let last = self.lastOpenTime, Date().timeIntervalSince(last) < 0.35 { return }
                self.lastOpenTime = Date()
                self.openOverlay(at: self.lastCursorPosition)
                return
            }

            guard event.keyCode == Config.contextCaptureKeyCode else { return }
            let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
            guard mods == Config.contextCaptureModifiers else { return }

            let now = Date()
            guard now.timeIntervalSince(self.lastContextCaptureTime) >= 0.35 else { return }
            self.lastContextCaptureTime = now

            if self.overlay.window?.isVisible == true {
                self.captureContextInOverlay(at: self.lastCursorPosition)
            } else {
                self.captureContextSilently(at: self.lastCursorPosition)
            }
        }

        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            DispatchQueue.main.async { keyDownHandler(event) }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            DispatchQueue.main.async { keyDownHandler(event) }
            return event
        }
    }

    private func captureContextInOverlay(at point: CGPoint) {
        capturer.capture(at: point) { [weak self] ctx in
            guard let self else { return }
            self.lastCtx = ctx
            DispatchQueue.main.async {
                self.overlay.appendContext(ctx)
                self.indexContextForRAG(ctx)
                let count = self.overlay.sessionContextCount
                self.showContextFlash(at: point, count: count)
                self.fileLog("overlay context captured #\(count) at \(point)")
            }
        }
    }

    private func captureContextSilently(at point: CGPoint) {
        capturer.capture(at: point) { [weak self] ctx in
            guard let self else { return }
            self.accumulatedContexts.append(ctx)
            self.lastCtx = ctx
            let count = self.accumulatedContexts.count
            self.fileLog("context captured #\(count) at \(point)")
            self.indexContextForRAG(ctx)
            DispatchQueue.main.async {
                self.showContextFlash(at: point, count: count)
            }
        }
    }

    private func openOverlay(at point: CGPoint) {
        guard overlay.window?.isVisible != true else { return }
        let contexts = accumulatedContexts
        if !contexts.isEmpty {
            presentOverlay(at: point, sessionContexts: contexts)
            return
        }

        let provisional = CursorContext(
            interactionId: UUID().uuidString,
            source: .cursor(position: point),
            hoveredText: nil,
            appName: NSWorkspace.shared.frontmostApplication?.localizedName,
            screenshotData: nil
        )
        presentOverlay(at: point, sessionContexts: [provisional])
        capturer.capture(at: point) { [weak self] ctx in
            guard let self else { return }
            self.lastCtx = ctx
            DispatchQueue.main.async {
                self.overlay.finishInitialCapture(ctx)
                self.indexContextForRAG(ctx)
            }
        }
    }

    private func presentOverlay(at point: CGPoint, sessionContexts: [CursorContext]) {
        guard let primary = sessionContexts.last else { return }
        interactionCount += 1
        lastCtx = primary
        fileLog("overlay opened at \(point) with \(sessionContexts.count) context point(s)")
        overlay.show(
            at: point,
            sessionContexts: sessionContexts,
            llm: activeLLM,
            interactionNumber: interactionCount
        )
        overlay.loadCatalog(using: remi)
    }

    private func indexContextForRAG(_ context: CursorContext) {
        let index = max(0, overlay.sessionContextCount - 1)
        overlay.indexCapture(context, remi: remi, snapshotIndex: index)
    }

    private func showContextFlash(at point: CGPoint, count: Int) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        let label = NSTextField(labelWithString: "  ✦ Context \(count) added  ")
        label.frame = NSRect(x: 0, y: 0, width: 140, height: 28)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = activeLLM.glowColor
        label.alignment = .center
        label.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        label.layer?.masksToBounds = true
        panel.contentView?.addSubview(label)

        let screenHeight = NSScreen.main?.frame.height ?? 0
        panel.setFrameOrigin(NSPoint(x: point.x + 12, y: screenHeight - point.y - 14))
        panel.orderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }

    private func wireWiggle() {
        wiggle.onWiggle = { [weak self] pt in
            guard let self else { return }
            DispatchQueue.main.async {
                guard !self.selWindow.isVisible else { return }
                self.openOverlay(at: pt)
            }
        }
    }

    private func wireSelection() {
        selWindow.onSelection = { [weak self] rect in
            guard let self else { return }
            DispatchQueue.main.async {
                let anchor = CGPoint(x: rect.midX, y: rect.maxY + 20)
                let provisional = CursorContext(
                    interactionId: UUID().uuidString,
                    source: .selection(rect: rect),
                    hoveredText: nil,
                    appName: NSWorkspace.shared.frontmostApplication?.localizedName,
                    screenshotData: nil
                )
                self.interactionCount += 1
                self.lastCtx = provisional
                self.overlay.show(
                    at: anchor,
                    sessionContexts: [provisional],
                    llm: self.activeLLM,
                    interactionNumber: self.interactionCount
                )
                self.overlay.loadCatalog(using: self.remi)
                self.capturer.capture(region: rect) { ctx in
                    self.lastCtx = ctx
                    self.overlay.finishInitialCapture(ctx)
                    self.indexContextForRAG(ctx)
                }
            }
        }
    }

    private func wireOverlay() {
        overlay.hoverPreviewProvider = { [weak self] point in
            self?.capturer.previewHover(at: point)
        }
        overlay.onOptionClickCapture = { [weak self] point in
            self?.captureContextInOverlay(at: point)
        }
        overlay.onLLMChange = { [weak self] llm in
            self?.activeLLM = llm
            self?.selWindow.activeLLM = llm
        }
        overlay.vc.onSubmit = { [weak self] query in
            guard let self else { return }
            guard let ctx = self.overlay.currentPrimaryContext ?? self.lastCtx else { return }
            self.lastCtx = ctx
            let snapshots = self.overlay.sessionContextCount
            self.fileLog("submit query=\(query.prefix(60)) snapshots=\(snapshots) llm=\(self.activeLLM.rawValue)")
            self.overlay.submit(query: query, context: ctx, remi: self.remi) { [weak self] err in
                guard let self else { return }
                if let err {
                    self.fileLog("submit failed: \(err.localizedDescription)")
                    return
                }
                self.accumulatedContexts.removeAll()
                self.fileLog("submit succeeded, cleared accumulated contexts")
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
