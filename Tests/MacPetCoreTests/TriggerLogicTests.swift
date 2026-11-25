import XCTest
@testable import MacPetCore

final class TriggerLogicTests: XCTestCase {
    func testDefaultsChange() {
        let ig = ["0", "1"]
        XCTAssertTrue(defaultsChangeFired(old: ["a": nil], new: ["a": "5"], ignoreValues: ig, to: nil))
        XCTAssertTrue(defaultsChangeFired(old: ["a": "2"], new: ["a": "5"], ignoreValues: ig, to: nil))
        XCTAssertFalse(defaultsChangeFired(old: ["a": "5"], new: ["a": "5"], ignoreValues: ig, to: nil))
        XCTAssertFalse(defaultsChangeFired(old: ["a": "5"], new: ["a": nil], ignoreValues: ig, to: nil))
        XCTAssertFalse(defaultsChangeFired(old: ["a": "5"], new: ["a": "1"], ignoreValues: ig, to: nil))
        XCTAssertFalse(defaultsChangeFired(old: ["a": nil], new: ["a": "0"], ignoreValues: ig, to: nil))
        XCTAssertTrue(defaultsChangeFired(old: ["a": "5", "b": "1"], new: ["a": "5", "b": "4"], ignoreValues: ig, to: nil))
    }

    func testDefaultsChangeTo() {
        // to 가 있으면 그 값으로 바뀔 때만
        XCTAssertTrue(defaultsChangeFired(old: ["autohide": nil], new: ["autohide": "1"], ignoreValues: [], to: "1"))
        XCTAssertTrue(defaultsChangeFired(old: ["autohide": "0"], new: ["autohide": "1"], ignoreValues: [], to: "1"))
        XCTAssertFalse(defaultsChangeFired(old: ["autohide": "1"], new: ["autohide": "0"], ignoreValues: [], to: "1"))
        XCTAssertFalse(defaultsChangeFired(old: ["autohide": "1"], new: ["autohide": "1"], ignoreValues: [], to: "1"))
        // 문자열 값
        XCTAssertTrue(defaultsChangeFired(old: ["orientation": "right"], new: ["orientation": "left"], ignoreValues: [], to: nil))
        XCTAssertFalse(defaultsChangeFired(old: ["orientation": "left"], new: ["orientation": "left"], ignoreValues: [], to: nil))
    }

    func testCanonicalDefaultsValue() {
        XCTAssertEqual(canonicalDefaultsValue(NSNumber(value: true)), "1")
        XCTAssertEqual(canonicalDefaultsValue(NSNumber(value: false)), "0")
        XCTAssertEqual(canonicalDefaultsValue(NSNumber(value: 14)), "14")
        XCTAssertEqual(canonicalDefaultsValue(NSNumber(value: 1.5)), "1.5")
        XCTAssertEqual(canonicalDefaultsValue("right"), "right")
        XCTAssertNil(canonicalDefaultsValue(nil))
        XCTAssertNil(canonicalDefaultsValue([1, 2]))
    }

    func testAccessibility() {
        XCTAssertTrue(accessibilityFired(old: false, new: true, to: true))
        XCTAssertFalse(accessibilityFired(old: true, new: true, to: true))
        XCTAssertFalse(accessibilityFired(old: true, new: false, to: true))
        XCTAssertTrue(accessibilityFired(old: true, new: false, to: false))
    }

    func testHitTest() {
        let rects = [HitRect(x: 100, y: 100, w: 50, h: 50)]
        XCTAssertTrue(hitTest(x: 120, y: 120, rects: rects, padding: 0))
        XCTAssertFalse(hitTest(x: 96, y: 120, rects: rects, padding: 0))
        XCTAssertTrue(hitTest(x: 96, y: 120, rects: rects, padding: 6))
        XCTAssertFalse(hitTest(x: 0, y: 0, rects: rects, padding: 6))
        XCTAssertFalse(hitTest(x: 120, y: 120, rects: [], padding: 6))
    }

    func testSettingsURL() {
        XCTAssertTrue(isAllowedSettingsURL("x-apple.systempreferences:com.apple.Appearance-Settings.extension"))
        XCTAssertFalse(isAllowedSettingsURL("https://example.com"))
        XCTAssertFalse(isAllowedSettingsURL("file:///etc/passwd"))
    }

    func testCatalogDecoding() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("web/missions.json")
        // 기본 정의(raw)를 직접 읽는다. 지금 OS 로 해석하면 앞으로 추가될 osOverrides 가 아래 기본 트리거 확인을 깨뜨린다.
        // (해석 경로는 MissionCatalogTests 가 본다)
        let ms = try JSONDecoder().decode([Mission].self, from: Data(contentsOf: url))
        XCTAssertEqual(ms.count, 17)
        XCTAssertEqual(Set(ms.map(\.id)).count, 17)
        func t(_ id: String) -> Trigger { ms.first { $0.id == id }!.trigger }
        XCTAssertEqual(t("spotlight-calc"), .appOpen(bundleId: "com.apple.calculator"))
        XCTAssertEqual(t("screenshot"), .screenshot)
        XCTAssertEqual(t("copy"), .clipboardChange)
        XCTAssertEqual(t("appearance"), .appearanceChange)
        XCTAssertEqual(t("mission-control"), .spaceChange)
        XCTAssertEqual(t("hot-corner"), .defaultsChange(
            domain: "com.apple.dock",
            keys: ["wvous-tl-corner", "wvous-tr-corner", "wvous-bl-corner", "wvous-br-corner"],
            ignoreValues: ["0", "1"], to: nil))
        XCTAssertEqual(t("dock-position"), .defaultsChange(
            domain: "com.apple.dock", keys: ["orientation"], ignoreValues: [], to: nil))
        XCTAssertEqual(t("dock-autohide"), .defaultsChange(
            domain: "com.apple.dock", keys: ["autohide"], ignoreValues: [], to: "1"))
        XCTAssertEqual(t("finder-pathbar"), .defaultsChange(
            domain: "com.apple.finder", keys: ["ShowPathbar"], ignoreValues: [], to: "1"))
        XCTAssertEqual(t("reduce-transparency"), .accessibility(flag: "reduceTransparency", to: true))
        XCTAssertEqual(t("reduce-motion"), .accessibility(flag: "reduceMotion", to: true))
        XCTAssertEqual(t("increase-contrast"), .accessibility(flag: "increaseContrast", to: true))
        XCTAssertEqual(t("grant-accessibility"), .accessibilityPermission)
        XCTAssertEqual(ms.first { $0.id == "grant-accessibility" }!.permission, "accessibility")
        let keysByID = ["shortcut-app-switch": "cmd+tab", "shortcut-close-window": "cmd+w",
                        "shortcut-quit": "cmd+q", "shortcut-force-quit": "cmd+option+escape"]
        for (id, keys) in keysByID {
            XCTAssertEqual(t(id), .shortcut(keys: keys))
            XCTAssertEqual(ms.first { $0.id == id }!.needs, "accessibility")
            XCTAssertNotNil(parseShortcut(keys))
        }
        let ap = ms.first { $0.id == "appearance" }!
        XCTAssertEqual(ap.settingsURL, "x-apple.systempreferences:com.apple.Appearance-Settings.extension")
        XCTAssertEqual(ap.group, "기본기")
        XCTAssertNotNil(ap.after)
        XCTAssertNil(ms.first { $0.id == "screenshot" }!.settingsURL)
        XCTAssertEqual(ms.first { $0.id == "reduce-transparency" }!.xp, 50)
    }

    func testFlexibleValuesAndManual() throws {
        let json = """
        [{"id":"m","title":"t","why":"w","steps":["a",{"text":"b","point":{"x":1}}],"xp":1,"trigger":{"type":"manual"}},
         {"id":"d","title":"t","why":"w","steps":["a",{"text":"b","point":{"x":1}}],"xp":1,"trigger":
           {"type":"defaultsChange","domain":"x","keys":["k"],"ignoreValues":[14,true,false,"right"],"to":true}}]
        """
        let ms = try JSONDecoder().decode([Mission].self, from: Data(json.utf8))
        XCTAssertEqual(ms[0].trigger, .manual)
        XCTAssertEqual(ms[1].trigger, .defaultsChange(domain: "x", keys: ["k"], ignoreValues: ["14", "1", "0", "right"], to: "1"))
        // 인코딩 왕복
        let back = try JSONDecoder().decode([Mission].self, from: JSONEncoder().encode(ms))
        XCTAssertEqual(back, ms)
    }

    func testUnknownTrigger() throws {
        let json = """
        [{"id":"x","title":"t","why":"w","steps":["a",{"text":"b","point":{"x":1}}],"xp":1,"trigger":{"type":"warp"}}]
        """
        let ms = try JSONDecoder().decode([Mission].self, from: Data(json.utf8))
        XCTAssertEqual(ms[0].trigger, .unknown("warp"))
    }

    func testNewTriggersRoundTrip() throws {
        let json = """
        [{"id":"a","title":"t","xp":1,"permission":"accessibility","trigger":{"type":"accessibilityPermission"}},
         {"id":"b","title":"t","xp":1,"needs":"accessibility","trigger":{"type":"shortcut","keys":"cmd+q"}}]
        """
        let ms = try JSONDecoder().decode([Mission].self, from: Data(json.utf8))
        XCTAssertEqual(ms[1].trigger, .shortcut(keys: "cmd+q"))
        let back = try JSONDecoder().decode([Mission].self, from: JSONEncoder().encode(ms))
        XCTAssertEqual(back, ms)
    }

    // 플래그 값은 macOS 27.2 에서 screencapture 가 데스크탑에 저장할 때 실제로 온 값
    func testScreenshotFileEvent() {
        XCTAssertTrue(isScreenshotFileEvent(ext: "png", flags: 0x10800))   // 최종 이름으로 바뀜
        XCTAssertTrue(isScreenshotFileEvent(ext: "PNG", flags: 0x18800))   // 이름 바뀜 + 속성 기록
        XCTAssertTrue(isScreenshotFileEvent(ext: "jpg", flags: 0x10100))   // 새로 생김
        XCTAssertFalse(isScreenshotFileEvent(ext: "png", flags: 0x18000))  // 속성만 바뀜
        XCTAssertFalse(isScreenshotFileEvent(ext: "png", flags: 0x10200))  // 지워짐
        XCTAssertFalse(isScreenshotFileEvent(ext: "docx", flags: 0x10800)) // 그림 파일 아님
        XCTAssertFalse(isScreenshotFileEvent(ext: "png", flags: 0x20100))  // 폴더
    }
}
