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
//   Shift (no overlay)  → silent pre-capture
//   Shift (overlay open)→ hover target, tap Shift to add context

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

    private let baseURL = "http://localhost:3080"
    private var authToken: String?

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

    func send(
        query: String, llm: LLM, context: CursorContext,
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
        mergedContextText: String?, screenshotCount: Int?, additionalScreenshots: [Data],
        agentId: String?, manualSkills: [String],
        token: String,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/api/remi/query") else {
            onComplete(URLError(.badURL))
            return
        }

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
            interactionId: context.interactionId,
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

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let e = error {
                DispatchQueue.main.async { onComplete(e) }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { onComplete(URLError(.badServerResponse)) }
                return
            }
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            if http.statusCode == 401 {
                self.authToken = nil
                RemiAuth.clearSession()
                DispatchQueue.main.async {
                    onComplete(NSError(
                        domain: "RemiClient",
                        code: 401,
                        userInfo: [NSLocalizedDescriptionKey: "Session expired — please log in again"]
                    ))
                }
                return
            }

            guard (200...299).contains(http.statusCode) else {
                let msg = Self.parseErrorMessage(from: text)
                    ?? "Request failed (HTTP \(http.statusCode))"
                DispatchQueue.main.async {
                    onComplete(NSError(
                        domain: "RemiClient",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: msg]
                    ))
                }
                return
            }

            var tokenCount = 0
            var streamError: Error?
            for line in text.components(separatedBy: "\n") {
                guard line.hasPrefix("data: ") else { continue }
                let ssePayload = String(line.dropFirst(6))
                if ssePayload == "[DONE]" { break }
                if ssePayload.hasPrefix("[ERROR]") {
                    let msg = String(ssePayload.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    streamError = NSError(
                        domain: "RemiClient",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "Inference failed" : msg]
                    )
                    break
                }
                tokenCount += 1
                DispatchQueue.main.async { onToken(ssePayload) }
            }

            DispatchQueue.main.async {
                if let streamError {
                    onComplete(streamError)
                } else if tokenCount == 0 {
                    onComplete(NSError(
                        domain: "RemiClient",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "No response from the model. Try fewer snapshots or a different model."]
                    ))
                } else {
                    onComplete(nil)
                }
            }
        }.resume()
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
    private let glowView = GlowBorderView()
    private let container     = DraggableVisualEffectView()
    private let llmPicker = NSSegmentedControl()
    fileprivate let textField = NSTextField()
    private let responseLabel = NSTextField()
    private let modeLabel     = NSTextField()
    private let hotkeyHint    = NSTextField()

    var currentLLM: LLM = .claude
    var onSubmit: ((String) -> Void)?
    var onLLMChange: ((LLM) -> Void)?
    var onTextChanged: ((String) -> Void)?

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
        hotkeyHint.stringValue = "@ agent  ·  / skill  ·  Shift: context"
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

    func reset(
        context: CursorContext,
        llm: LLM,
        interactionNumber: Int,
        mergedTexts: String?,
        screenshotCount: Int
    ) {
        textField.stringValue = ""; responseLabel.stringValue = ""
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
        hotkeyHint.stringValue = "Esc: close  ·  Context \(contextCount)"
        if let latest, !latest.isEmpty {
            let text = String(latest.prefix(72))
            responseLabel.stringValue = "Captured #\(contextCount): \(text)\(latest.count > 72 ? "…" : "")"
            responseLabel.textColor = .white.withAlphaComponent(0.86)
        } else {
            responseLabel.stringValue = "Hover, then Shift to add context. ⌘C for clipboard."
            responseLabel.textColor = .white.withAlphaComponent(0.78)
        }
    }

    func updateHoverPreview(_ text: String?) {
        if let text, !text.isEmpty {
            let flat = text.replacingOccurrences(of: "\n", with: " ")
            let preview = String(flat.prefix(72))
            responseLabel.stringValue = "Hovering: \(preview)\(flat.count > 72 ? "…" : "")"
        } else {
            responseLabel.stringValue = "Hovering: (no text detected)"
        }
        responseLabel.textColor = .white.withAlphaComponent(0.78)
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

    func showLoading() {
        textField.isEditable = false
        responseLabel.stringValue = ""
        responseLabel.textColor = .tertiaryLabelColor
    }
    func appendToken(_ t: String)   { responseLabel.stringValue += t; responseLabel.textColor = .labelColor }
    func finishResponse(error: Error?) {
        if let e = error {
            responseLabel.stringValue = "Error: \(e.localizedDescription)"
            responseLabel.textColor = .systemRed
        }
        textField.isEditable = true
        textField.stringValue = ""
        textField.window?.makeFirstResponder(textField)
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

final class OverlayWindowController: NSWindowController {
    let vc = OverlayViewController()
    private var hoverMonitor: Any?
    private var escKeyMonitor: Any?
    private var escGlobalMonitor: Any?
    private var copyKeyLocalMonitor: Any?
    private var copyKeyGlobalMonitor: Any?
    private var lastClipboardString: String?
    private var capturedContextSnippets: [String] = []
    private var sessionContexts: [CursorContext] = []
    private var mergedContextText: String?
    private var screenshotCount: Int = 0
    private var additionalScreenshots: [Data] = []
    private var storedInteractionNumber: Int = 0
    private var lastHoverPreviewTime = Date.distantPast
    private var showingCaptureStatus = false
    private var catalog: RemiCatalog?
    private(set) var selectedAgentId: String?
    private(set) var selectedSkillNames: [String] = []
    var hoverPreviewProvider: ((CGPoint) -> String?)?
    var onLLMChange: ((LLM) -> Void)?

    var sessionContextCount: Int { sessionContexts.count }

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
        vc.onTextChanged = { [weak self] text in self?.handleCommandTextChange(text) }
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

    func show(
        at screenPoint: CGPoint,
        sessionContexts: [CursorContext],
        llm: LLM,
        interactionNumber: Int,
        requireEscToDismiss: Bool = false
    ) {
        guard let screen = NSScreen.main else { return }
        guard let primary = sessionContexts.last else { return }
        let origin = NSPoint(
            x: screenPoint.x - Config.overlayWidth / 2,
            y: screen.frame.height - screenPoint.y - Config.overlayHeight / 2 - 70
        )
        window?.setFrameOrigin(origin)
        self.sessionContexts = sessionContexts
        self.storedInteractionNumber = interactionNumber
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
        resetCapturedContext(with: primary)
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
        lastClipboardString = nil
        capturedContextSnippets.removeAll()
        sessionContexts.removeAll()
        mergedContextText = nil
        screenshotCount = 0
        additionalScreenshots = []
        showingCaptureStatus = false
        selectedAgentId = nil
        selectedSkillNames = []
        catalog = nil
        window?.orderOut(nil)
    }

    func appendContext(_ context: CursorContext) {
        sessionContexts.append(context)
        rebuildMergedContext()
        showingCaptureStatus = true
        vc.updateSnapshotHeader(
            interactionNumber: storedInteractionNumber,
            context: context,
            mergedTexts: mergedContextText,
            screenshotCount: screenshotCount
        )
        if let snippet = contextSnippet(from: context) {
            appendCapturedSnippet(snippet)
        }
    }

    func finishInitialCapture(_ context: CursorContext) {
        if sessionContexts.count == 1, sessionContexts[0].screenshotData == nil {
            sessionContexts[0] = context
        } else {
            sessionContexts.append(context)
        }
        rebuildMergedContext()
        vc.updateSnapshotHeader(
            interactionNumber: storedInteractionNumber,
            context: context,
            mergedTexts: mergedContextText,
            screenshotCount: screenshotCount
        )
        if let snippet = contextSnippet(from: context) {
            capturedContextSnippets = [snippet]
            vc.updatePersistentCaptureStatus(
                contextCount: max(capturedContextSnippets.count, 1),
                latest: snippet
            )
        }
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
            contextCount: max(sessionContexts.count, 1),
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
        showingCaptureStatus = true
        vc.updatePersistentCaptureStatus(
            contextCount: sessionContexts.count,
            latest: snippet
        )
    }

    func submit(
        query: String,
        context: CursorContext,
        remi: RemiClient,
        onComplete: ((Error?) -> Void)? = nil
    ) {
        vc.showLoading()
        remi.send(
            query: query,
            llm: vc.currentLLM,
            context: context,
            mergedContextText: mergedContextText,
            screenshotCount: screenshotCount,
            additionalScreenshots: additionalScreenshots,
            agentId: selectedAgentId,
            manualSkills: selectedSkillNames,
            onToken:    { [weak self] t   in self?.vc.appendToken(t) },
            onComplete: { [weak self] err in
                self?.vc.finishResponse(error: err)
                self?.selectedAgentId = nil
                self?.selectedSkillNames = []
                onComplete?(err)
            }
        )
    }

    func indexCapture(_ context: CursorContext, remi: RemiClient) {
        guard let snippet = contextSnippet(from: context) else { return }
        remi.indexContext(
            interactionId: context.interactionId,
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
    private var lastOverlayShiftTime = Date.distantPast
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
        let shiftHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            guard event.keyCode == 56 || event.keyCode == 60 else { return }
            guard event.modifierFlags.contains(.shift) else { return }
            guard !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.option) else { return }
            if self.overlay.window?.isVisible == true {
                self.captureContextInOverlay(at: self.lastCursorPosition)
                return
            }
            self.captureContextSilently(at: self.lastCursorPosition)
        }

        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            DispatchQueue.main.async { shiftHandler(event) }
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            DispatchQueue.main.async { shiftHandler(event) }
            return event
        }

        let optionSpaceHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            guard event.keyCode == 49 else { return }
            guard event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.shift) else { return }
            if let last = self.lastOpenTime, Date().timeIntervalSince(last) < 0.35 { return }
            self.lastOpenTime = Date()
            self.openOverlay(at: self.lastCursorPosition)
        }

        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            DispatchQueue.main.async { optionSpaceHandler(event) }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            DispatchQueue.main.async { optionSpaceHandler(event) }
            return event
        }
    }

    private func captureContextInOverlay(at point: CGPoint) {
        let now = Date()
        guard now.timeIntervalSince(lastOverlayShiftTime) >= 0.35 else { return }
        lastOverlayShiftTime = now
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
        overlay.indexCapture(context, remi: remi)
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
        overlay.onLLMChange = { [weak self] llm in
            self?.activeLLM = llm
            self?.selWindow.activeLLM = llm
        }
        overlay.vc.onSubmit = { [weak self] query in
            guard let self, let ctx = self.lastCtx else { return }
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
