import CoreGraphics
import Foundation

enum Keyboard {
    private static let fnKeyCode: CGKeyCode = 0x3F
    private static let returnKeyCode: CGKeyCode = 0x24
    private static let escapeKeyCode: CGKeyCode = 0x35
    private static let src = CGEventSource(stateID: .hidSystemState)

    // Fn is a modifier: it behaves better as a standard keyDown/keyUp for triggering system shortcuts.
    static func fnDown() {
        guard let ev = CGEvent(keyboardEventSource: src, virtualKey: fnKeyCode, keyDown: true) else { return }
        ev.post(tap: .cghidEventTap)
    }

    static func fnUp() {
        guard let ev = CGEvent(keyboardEventSource: src, virtualKey: fnKeyCode, keyDown: false) else { return }
        ev.post(tap: .cghidEventTap)
    }

    static func tapFn() {
        fnDown()
        usleep(50_000)
        fnUp()
    }

    static func tapReturn() {
        tapKey(returnKeyCode)
    }

    static func tapEscape() {
        tapKey(escapeKeyCode)
    }

    private static let aKeyCode: CGKeyCode = 0x00
    private static let cKeyCode: CGKeyCode = 0x08
    private static let vKeyCode: CGKeyCode = 0x09

    static func tapCmdA() { tapKey(aKeyCode, flags: .maskCommand) }
    static func tapCmdC() { tapKey(cKeyCode, flags: .maskCommand) }
    static func tapCmdV() { tapKey(vKeyCode, flags: .maskCommand) }

    private static let leftArrowKeyCode: CGKeyCode = 0x7B
    private static let rightArrowKeyCode: CGKeyCode = 0x7C
    private static let pageUpKeyCode: CGKeyCode = 0x74
    private static let pageDownKeyCode: CGKeyCode = 0x79
    private static let tabKeyCode: CGKeyCode = 0x30

    static func tapLeft() { tapKey(leftArrowKeyCode) }
    static func tapRight() { tapKey(rightArrowKeyCode) }
    static func tapControlLeft() { tapKey(leftArrowKeyCode, flags: .maskControl) }
    static func tapControlRight() { tapKey(rightArrowKeyCode, flags: .maskControl) }

    static func tapPageUp() { tapKey(pageUpKeyCode) }
    static func tapPageDown() { tapKey(pageDownKeyCode) }

    static func tapControlTab() { tapKey(tabKeyCode, flags: .maskControl) }

    static func tapControlShiftTab() { tapKey(tabKeyCode, flags: [.maskControl, .maskShift]) }

    private static func tapKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(10000) // 10ms delay to ensure system recognizes the shortcut
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Mouse Click

    static func mouseClick(at point: CGPoint) {
        guard let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                                mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                             mouseCursorPosition: point, mouseButton: .left)
        else { return }
        down.post(tap: .cghidEventTap)
        usleep(10_000)
        up.post(tap: .cghidEventTap)
    }
}
