import XCTest
@testable import MacPetCore

final class WatchPlanTests: XCTestCase {
    private func m(_ id: String, _ t: Trigger) -> Mission {
        Mission(id: id, group: nil, after: nil, title: id, needs: nil, permission: nil, settingsURL: nil, xp: 10, trigger: t)
    }
    private lazy var missions: [Mission] = [
        m("calc", .manual),
        m("shot", .screenshot),
        m("copy", .clipboardChange),
        m("copy2", .clipboardChange),
        m("perm", .accessibilityPermission),
        m("tab", .shortcut(keys: "cmd+tab")),
        m("dock", .defaultsChange(domain: "com.apple.dock", keys: ["autohide"], ignoreValues: [], to: nil)),
        m("odd", .unknown("future")),
    ]

    private let ok = SaveProgress(hatched: true, named: true, done: [])

    /// 준비됨 + 보임 + 주어진 진행
    private func live(_ p: SaveProgress?) -> WatchEnrollment {
        var e = WatchEnrollment(missions: missions)
        e.setReady(true)
        e.setVisible(true)
        e.setProgress(p)
        return e
    }
    private func reg(_ id: String, _ attempt: Int) -> WatchRegistration { .init(id: id, attempt: attempt) }

    func testProgressParsing() {
        let p = SaveProgress(state: ["v": 2, "hatched": true, "name": "모찌",
                                     "done": ["a": "2026-01-01T00:00:00Z", "b": "", "c": true, "d": false, "e": 0, "f": 1, "g": NSNull()]])
        XCTAssertEqual(p, SaveProgress(hatched: true, named: true, done: ["a", "c", "f"]))
        XCTAssertEqual(SaveProgress(state: ["hatched": 1])?.hatched, false) // 불리언 true 만 부화
        XCTAssertEqual(SaveProgress(state: ["hatched": "true"])?.hatched, false)
        XCTAssertEqual(SaveProgress(state: ["name": ""])?.named, false)
        XCTAssertEqual(SaveProgress(state: ["name": "  "])?.named, false)
        XCTAssertEqual(SaveProgress(state: ["name": 3])?.named, false)
        XCTAssertEqual(SaveProgress(state: [:]), SaveProgress(hatched: false, named: false, done: []))
        XCTAssertNil(SaveProgress(state: "x"))
        XCTAssertNil(SaveProgress(state: nil))
    }

    func testProgressIgnoresGuide() {
        // 저장에 남은 안내(권하기만 했거나 지난 실행의 것)는 등록이 아니다
        let state: [String: Any] = ["hatched": true, "name": "모찌", "done": [String: Any](), "guide": ["id": "copy", "step": 2]]
        var e = live(SaveProgress(state: state))
        XCTAssertNil(e.current)
        e.setProgress(SaveProgress(state: state))
        XCTAssertNil(e.current)
    }

    func testRegistrationMessageParsing() {
        XCTAssertEqual(WatchRegistration(message: ["type": "watchMission", "id": "copy", "attempt": 3]), reg("copy", 3))
        XCTAssertEqual(WatchRegistration(message: ["id": "copy", "attempt": 2.0]), reg("copy", 2))
        XCTAssertNil(WatchRegistration(message: ["type": "watchMission", "id": NSNull()])) // 그만 보기
        XCTAssertNil(WatchRegistration(message: ["id": NSNull(), "attempt": 3]))
        XCTAssertNil(WatchRegistration(message: ["id": "copy"]))
        XCTAssertNil(WatchRegistration(message: ["id": "", "attempt": 1]))
        for bad: Any in [0, -1, 1.5, true, "1", NSNull(), Double.nan, Double.infinity, 1e300] {
            XCTAssertNil(WatchRegistration(message: ["id": "copy", "attempt": bad]), "\(bad)")
        }
    }

    func testPermissionManualUnknownHaveNoNativeDetector() {
        XCTAssertNil(watchFamily(of: .accessibilityPermission)) // 이미 허용돼 있다는 것만으로 완료를 알리지 않는다
        XCTAssertNil(watchFamily(of: .manual))
        XCTAssertNil(watchFamily(of: .unknown("future")))
        XCTAssertEqual(watchFamily(of: .clipboardChange), .clipboard)
        XCTAssertEqual(watchFamily(of: .shortcut(keys: "cmd+tab")), .shortcut)
    }

    func testArmsOnlyTheRequestedMission() {
        var e = live(ok)
        XCTAssertNil(e.current) // 등록 전에는 아무것도 걸리지 않는다
        e.request(reg("copy", 1))
        XCTAssertEqual(e.current?.mission.id, "copy")
        XCTAssertEqual(e.current?.mission.trigger, .clipboardChange)
        XCTAssertEqual(e.current?.attempt, 1)
        // 다른 미션으로 바꾸면 그 하나만 남는다(같은 종류의 copy2, 단축키 tab 은 대상이 아니다)
        e.request(reg("tab", 2))
        XCTAssertEqual(e.current?.registration, reg("tab", 2))
        XCTAssertEqual(e.current?.mission.trigger, .shortcut(keys: "cmd+tab"))
    }

    func testRearmingSameIDIsAFreshArming() {
        var e = live(ok)
        e.request(reg("copy", 1))
        let first = e.current
        e.request(reg("copy", 2))
        let second = e.current
        XCTAssertNotEqual(first?.serial, second?.serial)
        XCTAssertEqual(second?.attempt, 2)
        // 번호까지 같아도(웹이 같은 값을 다시 보내도) 앞선 것과 같은 감시로 치지 않는다
        e.request(reg("copy", 2))
        XCTAssertNotEqual(e.current?.serial, second?.serial)
        // A → 해제 → A: 앞선 A 의 serial 로 돌아가지 않는다
        e.request(nil)
        XCTAssertNil(e.current)
        e.request(reg("copy", 3))
        XCTAssertFalse([first?.serial, second?.serial].contains(e.current?.serial))
    }

    func testRejectsEggUnnamedDoneUnknownAndMissing() {
        var egg = live(SaveProgress(hatched: false, named: false, done: []))
        egg.request(reg("copy", 1)); XCTAssertNil(egg.current)
        var unnamed = live(SaveProgress(hatched: true, named: false, done: []))
        unnamed.request(reg("copy", 1)); XCTAssertNil(unnamed.current)
        var done = live(SaveProgress(hatched: true, named: true, done: ["copy"]))
        done.request(reg("copy", 1)); XCTAssertNil(done.current)
        done.request(reg("copy2", 1)); XCTAssertEqual(done.current?.mission.id, "copy2")
        var e = live(ok)
        e.request(reg("odd", 1)); XCTAssertNil(e.current) // 모르는(앞으로 생길) 트리거
        e.request(reg("nope", 1)); XCTAssertNil(e.current) // 카탈로그에 없는 id
        var noSave = live(nil) // 읽기 전용(보호) 저장이거나 진행을 모름
        noSave.request(reg("copy", 1)); XCTAssertNil(noSave.current)
    }

    func testRejectedRequestAlsoDropsPreviousRegistration() {
        var e = live(ok)
        e.request(reg("copy", 1))
        e.request(reg("odd", 2))
        XCTAssertNil(e.current)
    }

    func testRejectsWhenHiddenOrNotReady() {
        var hidden = WatchEnrollment(missions: missions)
        hidden.setReady(true); hidden.setProgress(ok)
        hidden.request(reg("copy", 1)); XCTAssertNil(hidden.current)
        var notReady = WatchEnrollment(missions: missions)
        notReady.setVisible(true); notReady.setProgress(ok)
        notReady.request(reg("copy", 1)); XCTAssertNil(notReady.current)
    }

    func testHideDisarmsAndShowDoesNotRearm() {
        var e = live(ok)
        e.request(reg("copy", 1))
        let serial = e.current?.serial
        e.setVisible(false)
        XCTAssertNil(e.current)
        e.setVisible(true)
        XCTAssertNil(e.current) // 웹이 새로 등록해야 한다
        e.request(reg("copy", 2))
        XCTAssertEqual(e.current?.attempt, 2)
        XCTAssertNotEqual(e.current?.serial, serial)
    }

    func testReloadDisarmsUntilFreshRequest() {
        var e = live(ok)
        e.request(reg("copy", 1))
        e.setReady(false)
        XCTAssertNil(e.current)
        e.setReady(true)
        XCTAssertNil(e.current)
        var again = live(ok)
        again.request(reg("copy", 1))
        again.setReady(true) // 새 화면의 ready 만 와도 앞선 등록은 버린다
        XCTAssertNil(again.current)
    }

    func testOrdinarySaveKeepsSameArmingWhileEligible() {
        var e = live(ok)
        e.request(reg("copy", 4))
        let before = e.current
        e.setProgress(SaveProgress(hatched: true, named: true, done: ["shot"])) // XP·다른 미션 완료
        XCTAssertEqual(e.current, before) // serial 그대로 = 감지기·기준값을 건드리지 않는다
    }

    func testSaveThatEndsEligibilityDisarmsForGood() {
        for p: SaveProgress? in [SaveProgress(hatched: true, named: true, done: ["copy"]), // 끝냄
                                 SaveProgress(hatched: false, named: false, done: []),      // 초기화·졸업
                                 SaveProgress(hatched: true, named: false, done: []),
                                 nil] {                                                     // 보호로 넘어감
            var e = live(ok)
            e.request(reg("copy", 1))
            e.setProgress(p)
            XCTAssertNil(e.current)
            e.setProgress(ok) // 자격이 돌아와도 스스로 다시 걸리지 않는다
            XCTAssertNil(e.current)
        }
    }

    func testManualAndPermissionRegisterWithoutDetector() {
        // 등록(attempt)은 기억하지만 네이티브 감지기는 없다
        var e = live(ok)
        e.request(reg("perm", 1))
        XCTAssertEqual(e.current?.registration, reg("perm", 1))
        XCTAssertNil(e.current.flatMap { watchFamily(of: $0.mission.trigger) })
        e.request(reg("calc", 2))
        XCTAssertEqual(e.current?.registration, reg("calc", 2))
        XCTAssertNil(e.current.flatMap { watchFamily(of: $0.mission.trigger) })
    }

    func testInjectedMissionDecoration() {
        let r = reg("copy", 7)
        func attempt(_ ev: [String: Any], _ r: WatchRegistration?) -> Int? {
            (decorateInjectedMission(ev, registration: r)["attempt"] as? NSNumber)?.intValue
        }
        XCTAssertEqual(attempt(["type": "mission", "id": "copy"], r), 7)
        XCTAssertEqual(attempt(["type": "mission", "id": "copy", "attempt": 3], r), 3) // 적은 번호(지난 것 포함)는 그대로
        XCTAssertNil(attempt(["type": "mission", "id": "shot"], r)) // 다른 미션
        XCTAssertNil(attempt(["type": "mission", "id": "copy"], nil)) // 등록 없음
        XCTAssertNil(attempt(["type": "command", "id": "copy", "name": "x"], r)) // 다른 종류
        let explicitNull = decorateInjectedMission(["type": "mission", "id": "copy", "attempt": NSNull()], registration: r)
        XCTAssertTrue(explicitNull["attempt"] is NSNull)
        XCTAssertEqual(decorateInjectedMission(["type": "mission", "id": "copy"], registration: r).count, 3)
    }

    func testBundledURLPolicy() {
        let root = URL(fileURLWithPath: "/tmp/macpet-web-test/web")
        XCTAssertTrue(isBundledFileURL(root.appendingPathComponent("index.html"), root: root))
        XCTAssertFalse(isBundledFileURL(URL(fileURLWithPath: "/tmp/macpet-web-test/web-evil/index.html"), root: root))
        XCTAssertFalse(isBundledFileURL(root.appendingPathComponent("../secret.html"), root: root))
        XCTAssertFalse(isBundledFileURL(URL(string: "https://example.com/"), root: root))
        XCTAssertFalse(isBundledFileURL(nil, root: root))
    }

    func testBundledIndexURLPolicy() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("macpet-index-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let root = base.appendingPathComponent("web")
        try fm.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("sub/index.html"), atomically: true, encoding: .utf8)
        let index = root.appendingPathComponent("index.html")
        XCTAssertTrue(isBundledIndexURL(index, root: root))
        XCTAssertTrue(isBundledIndexURL(URL(string: "file://localhost" + index.path), root: root))
        XCTAssertFalse(isBundledIndexURL(URL(string: "file://evil.example" + index.path), root: root))
        XCTAssertFalse(isBundledIndexURL(root.appendingPathComponent("app.js"), root: root))
        XCTAssertFalse(isBundledIndexURL(root.appendingPathComponent("sub/index.html"), root: root))
        XCTAssertFalse(isBundledIndexURL(root, root: root))
        XCTAssertFalse(isBundledIndexURL(URL(string: "https://example.com/index.html"), root: root))
        XCTAssertFalse(isBundledIndexURL(nil, root: root))
        // 루트 밖을 가리키는 index.html 링크
        let outside = base.appendingPathComponent("outside.html")
        try "x".write(to: outside, atomically: true, encoding: .utf8)
        let root2 = base.appendingPathComponent("web2")
        try fm.createDirectory(at: root2, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root2.appendingPathComponent("index.html"), withDestinationURL: outside)
        XCTAssertFalse(isBundledIndexURL(root2.appendingPathComponent("index.html"), root: root2))
        XCTAssertFalse(isBundledIndexURL(outside, root: root2))
    }

    func testSettingsFallbackInstructions() {
        XCTAssertTrue(settingsFallbackInstructions(for: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility").contains("손쉬운 사용"))
        XCTAssertTrue(settingsFallbackInstructions(for: "x-apple.systempreferences:com.apple.Desktop-Settings.extension").contains("데스크탑"))
        XCTAssertFalse(settingsFallbackInstructions(for: "x-apple.systempreferences:unknown").isEmpty)
    }
}
