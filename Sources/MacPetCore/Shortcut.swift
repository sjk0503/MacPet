import Foundation

public struct ShortcutModifiers: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let shift = ShortcutModifiers(rawValue: 1 << 1)
    public static let option = ShortcutModifiers(rawValue: 1 << 2)
    public static let control = ShortcutModifiers(rawValue: 1 << 3)

    /// CGEventFlags 원시값에서 네 조합키 비트만 읽는다(caps lock, fn, 숫자패드 등은 무시).
    public init(cgEventFlags raw: UInt64) {
        var m: ShortcutModifiers = []
        if raw & 0x20000 != 0 { m.insert(.shift) }
        if raw & 0x40000 != 0 { m.insert(.control) }
        if raw & 0x80000 != 0 { m.insert(.option) }
        if raw & 0x100000 != 0 { m.insert(.command) }
        self = m
    }
}

public struct Shortcut: Equatable {
    public let keyCode: UInt16
    public let modifiers: ShortcutModifiers
}

private let keyCodes: [String: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
    "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    "comma": 43, "slash": 44, "period": 47, "grave": 50, "backtick": 50,
    "return": 36, "enter": 36, "tab": 48, "space": 49,
    "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
]

private let modifierNames: [String: ShortcutModifiers] = [
    "cmd": .command, "command": .command, "shift": .shift,
    "option": .option, "opt": .option, "alt": .option,
    "ctrl": .control, "control": .control,
]

/// "cmd+shift+4" 같은 문자열을 해석한다. command·control·option 이 없거나 모르는 이름이면 nil.
public func parseShortcut(_ s: String) -> Shortcut? {
    var mods: ShortcutModifiers = []
    var code: UInt16?
    for raw in s.split(separator: "+", omittingEmptySubsequences: false) {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let m = modifierNames[name] {
            mods.insert(m)
        } else if let k = keyCodes[name], code == nil {
            code = k
        } else {
            return nil
        }
    }
    guard let code = code, !mods.isDisjoint(with: [.command, .control, .option]) else { return nil }
    return Shortcut(keyCode: code, modifiers: mods)
}

public func shortcutMatches(keyCode: UInt16, modifiers: ShortcutModifiers, _ s: Shortcut) -> Bool {
    keyCode == s.keyCode && modifiers == s.modifiers
}
