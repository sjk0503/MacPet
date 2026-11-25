import XCTest
@testable import MacPetCore

final class ShortcutTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(parseShortcut("cmd+tab"), Shortcut(keyCode: 48, modifiers: [.command]))
        XCTAssertEqual(parseShortcut("CMD + Shift + 4"), Shortcut(keyCode: 21, modifiers: [.command, .shift]))
        XCTAssertEqual(parseShortcut("cmd+option+escape"), Shortcut(keyCode: 53, modifiers: [.command, .option]))
        XCTAssertEqual(parseShortcut(" 4 + shift+cmd "), Shortcut(keyCode: 21, modifiers: [.command, .shift]))
    }

    func testAliases() {
        XCTAssertEqual(parseShortcut("command+w"), parseShortcut("cmd+w"))
        XCTAssertEqual(parseShortcut("cmd+opt+esc"), parseShortcut("cmd+option+escape"))
        XCTAssertEqual(parseShortcut("cmd+alt+esc"), parseShortcut("cmd+option+escape"))
        XCTAssertEqual(parseShortcut("control+enter"), Shortcut(keyCode: 36, modifiers: [.control]))
        XCTAssertEqual(parseShortcut("ctrl+backspace")?.keyCode, 51)
        XCTAssertEqual(parseShortcut("cmd+backtick"), parseShortcut("cmd+grave"))
    }

    func testInvalid() {
        XCTAssertNil(parseShortcut("a"))
        XCTAssertNil(parseShortcut("shift+a"))
        XCTAssertNil(parseShortcut("cmd+banana"))
        XCTAssertNil(parseShortcut("cmd+a+b"))
        XCTAssertNil(parseShortcut("cmd+shift"))
        XCTAssertNil(parseShortcut(""))
    }

    func testMatches() {
        let s = parseShortcut("cmd+w")!
        XCTAssertTrue(shortcutMatches(keyCode: 13, modifiers: [.command], s))
        XCTAssertFalse(shortcutMatches(keyCode: 13, modifiers: [.command, .shift], s))
        XCTAssertFalse(shortcutMatches(keyCode: 13, modifiers: [], s))
        XCTAssertFalse(shortcutMatches(keyCode: 12, modifiers: [.command], s))
    }

    func testCGEventFlags() {
        XCTAssertEqual(ShortcutModifiers(cgEventFlags: 0x100000), [.command])
        XCTAssertEqual(ShortcutModifiers(cgEventFlags: 0x100000 | 0x80000), [.command, .option])
        XCTAssertEqual(ShortcutModifiers(cgEventFlags: 0x20000 | 0x40000), [.shift, .control])
        // caps lock(0x10000)·fn(0x800000)·숫자패드(0x200000) 는 무시
        XCTAssertEqual(ShortcutModifiers(cgEventFlags: 0x100000 | 0x10000 | 0x800000 | 0x200000), [.command])
        XCTAssertEqual(ShortcutModifiers(cgEventFlags: 0x10000), [])
    }
}
