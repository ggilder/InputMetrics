import Foundation
import Carbon.HIToolbox

struct KeyCodeMapping {
    private static let printableKeyCodes: Set<Int> = [
        kVK_ANSI_Grave, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
        kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0, kVK_ANSI_Minus, kVK_ANSI_Equal,
        kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_U,
        kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket,
        kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_J,
        kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon, kVK_ANSI_Quote, kVK_ANSI_Backslash,
        kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M,
        kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash,
    ]

    /// Label for a physical key under the active keyboard layout.
    private static func layoutLabel(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    static func keyName(for keyCode: Int) -> String {
        if printableKeyCodes.contains(keyCode), let label = layoutLabel(for: keyCode) {
            return label
        }

        switch keyCode {
        // Special keys
        case kVK_Space: return "Space"
        case kVK_Return: return "↵"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_CapsLock: return "⇪"

        // Modifiers
        case kVK_Shift: return "⇧"
        case kVK_RightShift: return "⇧"
        case kVK_Control: return "⌃"
        case kVK_RightControl: return "⌃"
        case kVK_Option: return "⌥"
        case kVK_RightOption: return "⌥"
        case kVK_Command: return "⌘"
        case kVK_RightCommand: return "⌘"
        case kVK_Function: return "fn"

        // Arrow keys
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"

        // Function keys
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"

        default:
            return "Key\(keyCode)"
        }
    }

    typealias KeyboardKey = (keyCode: Int, width: CGFloat)

    /// ANSI keyboard rows; widths are in key units (1 = standard key).
    static let ansiRows: [[KeyboardKey]] = [
        [(kVK_ANSI_Grave, 1), (kVK_ANSI_1, 1), (kVK_ANSI_2, 1), (kVK_ANSI_3, 1), (kVK_ANSI_4, 1),
         (kVK_ANSI_5, 1), (kVK_ANSI_6, 1), (kVK_ANSI_7, 1), (kVK_ANSI_8, 1), (kVK_ANSI_9, 1),
         (kVK_ANSI_0, 1), (kVK_ANSI_Minus, 1), (kVK_ANSI_Equal, 1), (kVK_Delete, 2)],
        [(kVK_Tab, 1.5), (kVK_ANSI_Q, 1), (kVK_ANSI_W, 1), (kVK_ANSI_E, 1), (kVK_ANSI_R, 1),
         (kVK_ANSI_T, 1), (kVK_ANSI_Y, 1), (kVK_ANSI_U, 1), (kVK_ANSI_I, 1), (kVK_ANSI_O, 1),
         (kVK_ANSI_P, 1), (kVK_ANSI_LeftBracket, 1), (kVK_ANSI_RightBracket, 1), (kVK_ANSI_Backslash, 1.5)],
        [(kVK_CapsLock, 1.75), (kVK_ANSI_A, 1), (kVK_ANSI_S, 1), (kVK_ANSI_D, 1), (kVK_ANSI_F, 1),
         (kVK_ANSI_G, 1), (kVK_ANSI_H, 1), (kVK_ANSI_J, 1), (kVK_ANSI_K, 1), (kVK_ANSI_L, 1),
         (kVK_ANSI_Semicolon, 1), (kVK_ANSI_Quote, 1), (kVK_Return, 2.25)],
        [(kVK_Shift, 2.25), (kVK_ANSI_Z, 1), (kVK_ANSI_X, 1), (kVK_ANSI_C, 1), (kVK_ANSI_V, 1),
         (kVK_ANSI_B, 1), (kVK_ANSI_N, 1), (kVK_ANSI_M, 1), (kVK_ANSI_Comma, 1), (kVK_ANSI_Period, 1),
         (kVK_ANSI_Slash, 1), (kVK_RightShift, 2.75)],
        [(kVK_Function, 1), (kVK_Control, 1), (kVK_Option, 1), (kVK_Command, 1.25), (kVK_Space, 5.5),
         (kVK_RightCommand, 1.25), (kVK_RightOption, 1), (kVK_LeftArrow, 0.75), (kVK_UpArrow, 0.75),
         (kVK_DownArrow, 0.75), (kVK_RightArrow, 0.75)],
    ]
}
