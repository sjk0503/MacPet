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

    func testProgressParsing() {
        let p = SaveProgress(state: ["v": 2, "hatched": true,
                                     "done": ["a": "2026-01-01T00:00:00Z", "b": "", "c": true, "d": false, "e": 0, "f": 1, "g": NSNull()]])
        XCTAssertEqual(p, SaveProgress(hatched: true, done: ["a", "c", "f"]))
        XCTAssertEqual(SaveProgress(state: ["hatched": 1])?.hatched, false) // 불리언 true 만 부화
        XCTAssertEqual(SaveProgress(state: ["hatched": "true"])?.hatched, false)
        XCTAssertEqual(SaveProgress(state: [:]), SaveProgress(hatched: false, done: []))
        XCTAssertNil(SaveProgress(state: "x"))
        XCTAssertNil(SaveProgress(state: nil))
    }

    func testEggWatchesNothing() {
        XCTAssertTrue(makeWatchPlan(missions: missions, progress: .init(hatched: false, done: [])).isEmpty)
    }

    func testHatchedGroupsUnfinishedByFamilySkippingManualAndUnknown() {
        let plan = makeWatchPlan(missions: missions, progress: .init(hatched: true, done: ["copy2"]))
        XCTAssertEqual(plan[.clipboard], ["copy"])
        XCTAssertEqual(plan[.screenshot], ["shot"])
        XCTAssertEqual(plan[.permission], ["perm"])
        XCTAssertEqual(Set(plan.keys), [.clipboard, .screenshot, .permission, .shortcut, .defaults])
    }

    func testAllDoneWatchesNothing() {
        let all = Set(missions.map(\.id))
        XCTAssertTrue(makeWatchPlan(missions: missions, progress: .init(hatched: true, done: all)).isEmpty)
    }

    func testXPOnlySaveChangesNothing() {
        let p = SaveProgress(hatched: true, done: ["shot"])
        let plan = makeWatchPlan(missions: missions, progress: p)
        XCTAssertTrue(diffWatchPlan(running: plan, desired: makeWatchPlan(missions: missions, progress: p)).isEmpty)
    }

    func testFinishingUnrelatedMissionDoesNotTouchOtherFamilies() {
        let before = makeWatchPlan(missions: missions, progress: .init(hatched: true, done: []))
        let after = makeWatchPlan(missions: missions, progress: .init(hatched: true, done: ["shot"]))
        let d = diffWatchPlan(running: before, desired: after)
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d[0].family, .screenshot)
        XCTAssertEqual(d[0].action, .stop)
    }

    func testPartialFinishInFamilyRetargetsWithoutRestart() {
        let before = makeWatchPlan(missions: missions, progress: .init(hatched: true, done: []))
        let after = makeWatchPlan(missions: missions, progress: .init(hatched: true, done: ["copy"]))
        let d = diffWatchPlan(running: before, desired: after)
        XCTAssertEqual(d.map(\.family), [.clipboard])
        XCTAssertEqual(d.map(\.action), [.retarget])
    }

    func testResetStopsEverythingThenHatchStartsEverything() {
        let full = makeWatchPlan(missions: missions, progress: .init(hatched: true, done: []))
        var running: WatchPlan = [:]
        for _ in 0..<3 { // 반복 초기화
            let start = diffWatchPlan(running: running, desired: full)
            XCTAssertEqual(Set(start.map(\.family)), Set(full.keys))
            XCTAssertTrue(start.allSatisfy { $0.action == .start })
            running = full
            let egg = makeWatchPlan(missions: missions, progress: .init(hatched: false, done: []))
            let stop = diffWatchPlan(running: running, desired: egg)
            XCTAssertEqual(Set(stop.map(\.family)), Set(full.keys))
            XCTAssertTrue(stop.allSatisfy { $0.action == .stop })
            running = egg
        }
    }

    func testResetWhileRunningRestartsFamiliesGainingIDs() {
        let some = makeWatchPlan(missions: missions, progress: .init(hatched: true, done: ["copy"]))
        let full = makeWatchPlan(missions: missions, progress: .init(hatched: true, done: []))
        let d = diffWatchPlan(running: some, desired: full)
        XCTAssertTrue(d.contains { $0.family == .clipboard && $0.action == .restart })
        XCTAssertTrue(d.contains { $0.family == .screenshot && $0.action == .start } == false) // 이미 돌고 있다
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
