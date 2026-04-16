import Foundation
import AppKit
import CoreGraphics

enum SystemControl {
    enum Application {
        // 按 bundleIdentifier 存储各应用已记录的输入框坐标（持久化）
        private static var recordedLocations: [String: CGPoint] = {
            guard let data = UserDefaults.standard.data(forKey: "vibemove.inputLocations"),
                  let dict = try? JSONDecoder().decode([String: [Double]].self, from: data)
            else { return [:] }
            return dict.compactMapValues { arr in
                guard arr.count == 2 else { return nil }
                return CGPoint(x: arr[0], y: arr[1])
            }
        }()

        static func recordInputLocation(bundleId: String, at point: CGPoint) {
            recordedLocations[bundleId] = point
            let encoded = recordedLocations.mapValues { [$0.x, $0.y] }
            if let data = try? JSONEncoder().encode(encoded) {
                UserDefaults.standard.set(data, forKey: "vibemove.inputLocations")
            }
            print("[focusInput] 已记录 \(bundleId) → \(String(format: "%.0f, %.0f", point.x, point.y))")
        }

        static func scrollDown() {
            // AppleScript to scroll active tab in Chrome or Safari.
            // We try Chrome first, then Safari.
            let scriptSource = """
            if application "Google Chrome" is running then
                tell application "Google Chrome"
                    if (count of windows) > 0 then
                        execute active tab of window 1 javascript "window.scrollBy({top: 300, behavior: 'smooth'})"
                    end if
                end tell
            else if application "Safari" is running then
                tell application "Safari"
                    if (count of documents) > 0 then
                        do JavaScript "window.scrollBy({top: 300, behavior: 'smooth'})" in document 1
                    end if
                end tell
            end if
            """

            if let script = NSAppleScript(source: scriptSource) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                if let err = error {
                    print("[SystemControl] AppleScript error: \(err)")
                }
            }
        }

        static func scrollUp() {
            // AppleScript to scroll up in active tab in Chrome or Safari.
            let scriptSource = """
            if application "Google Chrome" is running then
                tell application "Google Chrome"
                    if (count of windows) > 0 then
                        execute active tab of window 1 javascript "window.scrollBy({top: -300, behavior: 'smooth'})"
                    end if
                end tell
            else if application "Safari" is running then
                tell application "Safari"
                    if (count of documents) > 0 then
                        do JavaScript "window.scrollBy({top: -300, behavior: 'smooth'})" in document 1
                    end if
                end tell
            end if
            """

            if let script = NSAppleScript(source: scriptSource) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                if let err = error {
                    print("[SystemControl] AppleScript error: \(err)")
                }
            }
        }

        static func focusInput() {
            // Get the frontmost application
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                print("[focusInput] No frontmost application found")
                return
            }

            let appName = frontApp.localizedName ?? "Unknown"
            print("[focusInput] Target App: \(appName)")

            focusInputByClickingAXElement(frontApp)
        }

        private static func focusInputByClickingAXElement(_ app: NSRunningApplication) {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            // 方案 A：Try to find and click a text input element
            if let textElement = findTextElement(appElement),
               let frame = frameOf(textElement) {
                let clickPoint = CGPoint(x: frame.midX, y: frame.midY)
                print("[focusInput] Clicking text element at \(String(format: "%.0f, %.0f", clickPoint.x, clickPoint.y))")
                Keyboard.mouseClick(at: clickPoint)
                return
            }

            // 方案 B：Use already recorded input location for this app
            let bundleId = app.bundleIdentifier ?? ""
            if let savedPoint = recordedLocations[bundleId] {
                print("[focusInput] Using recorded location for \(bundleId) → \(String(format: "%.0f, %.0f", savedPoint.x, savedPoint.y))")
                Keyboard.mouseClick(at: savedPoint)
                return
            }

            // 兜底：Just activate the app window and hope focus is preserved
            print("[focusInput] No text element or recorded location found, activating app")
            app.activate(options: .activateIgnoringOtherApps)
        }

        private static func findTextElement(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
            // Prevent infinite recursion
            guard depth < 20 else { return nil }

            // Check if current element is a text input
            if isTextInputElement(element) {
                return element
            }

            // Search children
            var children: AnyObject?
            let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

            guard childrenResult == .success, let childrenArray = children as? [AXUIElement] else {
                return nil
            }

            for child in childrenArray {
                if let found = findTextElement(child, depth: depth + 1) {
                    return found
                }
            }

            return nil
        }

        private static func isTextInputElement(_ element: AXUIElement) -> Bool {
            var role: AnyObject?
            let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

            guard result == .success, let roleStr = role as? String else {
                return false
            }

            // Check for common text input roles
            let textRoles = [
                kAXTextAreaRole,
                kAXTextFieldRole,
                kAXComboBoxRole
            ]

            return textRoles.contains(roleStr)
        }

        private static func frameOf(_ element: AXUIElement) -> CGRect? {
            var value: AnyObject?
            let frameAttribute = "AXFrame" as CFString
            guard AXUIElementCopyAttributeValue(element, frameAttribute, &value) == .success,
                  let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
                return nil
            }

            var frame = CGRect.zero
            AXValueGetValue(axValue as! AXValue, .cgRect, &frame)
            return frame
        }

        static func switchDesktop(direction: String) {
            // Uses System Events to send Control + Arrow keys.
            // 123 is Left Arrow, 124 is Right Arrow.
            let keyCode = (direction == "left") ? 123 : 124
            let scriptSource = """
            tell application "System Events"
                key code \(keyCode) using control down
            end tell
            """
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(nil)
            }
        }
    }
}
