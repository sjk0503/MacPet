import XCTest
@testable import MacPetCore

final class MissionCatalogTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private var shippedData: Data { try! Data(contentsOf: root.appendingPathComponent("web/missions.json")) }

    private func catalog(_ missions: [[String: Any]]) -> Data { try! JSONSerialization.data(withJSONObject: missions) }
    private func base(_ id: String = "m", extra: [String: Any] = [:]) -> [String: Any] {
        var m: [String: Any] = ["id": id, "title": "t", "xp": 30, "steps": ["기본"], "trigger": ["type": "clipboardChange"]]
        for (k, v) in extra { m[k] = v }
        return m
    }
    private func diagnostics(_ missions: [[String: Any]]) -> [String] {
        MissionCatalog.validate(data: catalog(missions)).map(\.description)
    }
    private func steps(_ c: ResolvedCatalog, _ id: String = "m") -> [String]? {
        let arr = try! JSONSerialization.jsonObject(with: c.webData) as! [[String: Any]]
        return arr.first { $0["id"] as? String == id }?["steps"] as? [String]
    }

    // MARK: 실제 배포 카탈로그

    func testShippedCatalogIsValid() {
        let d = MissionCatalog.validate(data: shippedData)
        XCTAssertTrue(d.isEmpty, "web/missions.json 문제:\n" + d.map(\.description).joined(separator: "\n"))
    }

    /// 실제 카탈로그는 버전별로 다른 안내를 가질 수 있으므로 "모든 OS 가 같다"고 단정하지 않는다.
    /// 대신 지금 OS 로 해석되고, 해석 결과의 id 가 겹치지 않는지만 본다. (덮어쓰기 검증은 testShippedCatalogIsValid 가 전부 한다)
    func testShippedCatalogResolvesForCurrentOS() throws {
        let c = try MissionCatalog.resolve(data: shippedData)
        XCTAssertEqual(c.os, OSVersion.current)
        XCTAssertFalse(c.missions.isEmpty)
        XCTAssertEqual(Set(c.missions.map(\.id)).count, c.missions.count)
    }

    /// 픽스처 전용: 어느 범위에도 안 걸리는 OS 는 기본 정의로 돌아간다. 덮어쓰기가 없는 미션은 어느 OS 에서도 같다.
    func testNoMatchingOverrideFallsBackToBase() throws {
        let d = catalog([base("plain"), base("versioned", extra: ["osOverrides": [["minOS": 20, "maxOS": "21.4", "steps": ["다름"]]]])])
        let fallback = try MissionCatalog.resolve(data: d, os: 13)
        for os: OSVersion in [14, 19, OSVersion(21, 5), 22, 99] {
            let c = try MissionCatalog.resolve(data: d, os: os)
            XCTAssertEqual(c.missions, fallback.missions, "os \(os)")
            XCTAssertEqual(steps(c, "versioned"), ["기본"], "os \(os)")
        }
        XCTAssertEqual(steps(try MissionCatalog.resolve(data: d, os: OSVersion(21, 4, 9)), "versioned"), ["다름"])
    }

    func testShippedPermissionMissionRequiresRealPermissionOnAllVersions() throws {
        for os: OSVersion in [13, 14, 15, 26, 27, 99] {
            let c = try MissionCatalog.resolve(data: shippedData, os: os)
            let m = try XCTUnwrap(c.missions.first { $0.id == "grant-accessibility" })
            XCTAssertEqual(m.permission, "accessibility")
            XCTAssertEqual(m.trigger, .accessibilityPermission)
        }
    }

    func testWebAndNativeSeeIdenticalSet() throws {
        let c = try MissionCatalog.resolve(data: shippedData, os: 15)
        let web = try JSONSerialization.jsonObject(with: c.webData) as! [[String: Any]]
        XCTAssertEqual(web.map { $0["id"] as? String }, c.missions.map(\.id))
        XCTAssertEqual(web.map { $0["xp"] as? Int }, c.missions.map(\.xp))
        XCTAssertNotNil(web.first?["steps"], "웹 전용 필드(steps)가 남아 있어야 함")
        XCTAssertNil(web.first?["osOverrides"])
        // 웹 데이터를 다시 읽어도 네이티브 모델과 같다
        XCTAssertEqual(try JSONDecoder().decode([Mission].self, from: c.webData), c.missions)
    }

    func testQAScriptsReferenceExistingMissions() throws {
        let ids = Set(try MissionCatalog.resolve(data: shippedData, os: 15).missions.map(\.id))
        let dir = root.appendingPathComponent("qa")
        for f in try FileManager.default.contentsOfDirectory(atPath: dir.path) where f.hasSuffix(".json") && !f.hasSuffix(".save.json") {
            let steps = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(f))) as! [[String: Any]]
            for s in steps {
                if let n = s["native"] as? [String: Any], n["type"] as? String == "mission" {
                    XCTAssertTrue(ids.contains(n["id"] as? String ?? ""), "\(f): 없는 미션 \(n["id"] ?? "?")")
                }
            }
        }
    }

    func testLoadAPIStillWorks() throws {
        let m = try MissionCatalog.load(from: root.appendingPathComponent("web/missions.json"))
        XCTAssertTrue(m.contains { $0.id == "copy" })
    }

    // MARK: OS 버전 덮어쓰기

    func testOverrideBoundaries() throws {
        let m = base(extra: ["osOverrides": [
            ["minOS": 14, "maxOS": 15, "steps": ["중간"]],
            ["minOS": 17, "steps": ["새것"]],
        ]])
        let d = catalog([m])
        let expect: [(OSVersion, String)] = [(13, "기본"), (14, "중간"), (15, "중간"), (16, "기본"), (17, "새것"), (40, "새것")]
        for (os, want) in expect {
            let c = try MissionCatalog.resolve(data: d, os: os)
            XCTAssertEqual(steps(c), [want], "os \(os)")
            XCTAssertEqual(c.missions[0].xp, 30)
            XCTAssertEqual(c.missions[0].id, "m")
        }
        XCTAssertTrue(MissionCatalog.validate(data: d).isEmpty)
    }

    func testOverrideReplacesDetector() throws {
        let m = base(extra: ["osOverrides": [["maxOS": 14, "trigger": ["type": "spaceChange"]]]])
        XCTAssertEqual(try MissionCatalog.resolve(data: catalog([m]), os: 14).missions[0].trigger, .spaceChange)
        XCTAssertEqual(try MissionCatalog.resolve(data: catalog([m]), os: 15).missions[0].trigger, .clipboardChange)
    }

    func testInvalidRanges() {
        func o(_ r: [String: Any]) -> [String] { diagnostics([base(extra: ["osOverrides": [r.merging(["steps": ["x"]]) { a, _ in a }]])]) }
        XCTAssertTrue(o(["minOS": 15, "maxOS": 14]).joined().contains("보다 큼"))
        XCTAssertTrue(o([:]).joined().contains("minOS 나 maxOS"))
        XCTAssertTrue(o(["minOS": "14.x"]).joined().contains("정수"))
        XCTAssertTrue(o(["minOS": 0]).joined().contains("정수"))
        XCTAssertTrue(o(["minOS": 14.5]).joined().contains("정수"))
        XCTAssertTrue(o(["minOS": true]).joined().contains("정수"))
        XCTAssertTrue(diagnostics([base(extra: ["osOverrides": [["minOS": 14]]])]).joined().contains("바꿀 필드가 없음"))
        XCTAssertTrue(diagnostics([base(extra: ["osOverrides": "x"])]).joined().contains("배열"))
    }

    func testOverlappingRanges() {
        let touching = base(extra: ["osOverrides": [["minOS": 14, "maxOS": 15, "steps": ["a"]], ["minOS": 15, "steps": ["b"]]]])
        XCTAssertTrue(diagnostics([touching]).joined().contains("겹침"))
        let openOpen = base(extra: ["osOverrides": [["maxOS": 14, "steps": ["a"]], ["maxOS": 16, "steps": ["b"]]]])
        XCTAssertTrue(diagnostics([openOpen]).joined().contains("겹침"))
        let adjacent = base(extra: ["osOverrides": [["minOS": 14, "maxOS": 15, "steps": ["a"]], ["minOS": 16, "steps": ["b"]]]])
        XCTAssertTrue(diagnostics([adjacent]).isEmpty)
    }

    func testForbiddenOverrideFields() {
        for key in ["id", "xp", "group", "permission", "needs"] {
            let d = diagnostics([base(extra: ["osOverrides": [["minOS": 14, key: key == "xp" ? 99 : "x", "steps": ["s"]]]])])
            XCTAssertTrue(d.contains { $0.contains("osOverrides[0].\(key)") }, "\(key): \(d)")
        }
    }

    func testOverrideCannotWeakenPermissionMission() {
        let m = base("grant", extra: ["permission": "accessibility", "trigger": ["type": "accessibilityPermission"],
                                       "osOverrides": [["minOS": 14, "trigger": ["type": "manual"]]]])
        XCTAssertTrue(diagnostics([m]).joined().contains("accessibilityPermission"))
        let noPerm = base("grant", extra: ["trigger": ["type": "accessibilityPermission"]])
        XCTAssertTrue(diagnostics([noPerm]).joined().contains("permission"))
    }

    // MARK: 버전 범위 (정수 메이저 / 점 문자열)

    private func resolvedSteps(_ ov: [String: Any], at os: OSVersion) throws -> [String]? {
        let m = base(extra: ["osOverrides": [ov.merging(["steps": ["적용"]]) { a, _ in a }]])
        return steps(try MissionCatalog.resolve(data: catalog([m]), os: os))
    }

    func testMaxIsInclusiveAtItsOwnPrecision() throws {
        let hit = ["적용"], miss = ["기본"]
        // maxOS 27 → 27 전체
        for (v, want) in [(OSVersion(27), hit), (OSVersion(27, 2), hit), (OSVersion(27, 99, 999), hit), (OSVersion(28), miss)] {
            XCTAssertEqual(try resolvedSteps(["minOS": 14, "maxOS": 27], at: v), want, "max 27 @ \(v)")
        }
        // maxOS "27.2" → 27.2 전체
        for (v, want) in [(OSVersion(27, 2, 0), hit), (OSVersion(27, 2, 999), hit), (OSVersion(27, 3), miss)] {
            XCTAssertEqual(try resolvedSteps(["minOS": 14, "maxOS": "27.2"], at: v), want, "max 27.2 @ \(v)")
        }
        // maxOS "27.2.1" → 거기서 멈춤
        for (v, want) in [(OSVersion(27, 2, 1), hit), (OSVersion(27, 2, 2), miss), (OSVersion(27, 3), miss)] {
            XCTAssertEqual(try resolvedSteps(["minOS": 14, "maxOS": "27.2.1"], at: v), want, "max 27.2.1 @ \(v)")
        }
    }

    func testMinFillsMissingComponentsWithZero() throws {
        XCTAssertEqual(try resolvedSteps(["minOS": 27], at: OSVersion(27, 0, 0)), ["적용"])
        XCTAssertEqual(try resolvedSteps(["minOS": 27], at: OSVersion(26, 99, 99)), ["기본"])
        XCTAssertEqual(try resolvedSteps(["minOS": "27.2"], at: OSVersion(27, 1, 9)), ["기본"])
        XCTAssertEqual(try resolvedSteps(["minOS": "27.2"], at: OSVersion(27, 2, 0)), ["적용"])
        XCTAssertEqual(try resolvedSteps(["minOS": "27.2.1"], at: OSVersion(27, 2, 0)), ["기본"])
        XCTAssertEqual(try resolvedSteps(["minOS": "27.2.1"], at: OSVersion(27, 2, 1)), ["적용"])
    }

    func testPatchLevelRangesDoNotOverlapWhenAdjacent() {
        let adjacent = base(extra: ["osOverrides": [["maxOS": "27.2.1", "steps": ["a"]], ["minOS": "27.2.2", "steps": ["b"]]]])
        XCTAssertTrue(diagnostics([adjacent]).isEmpty, "\(diagnostics([adjacent]))")
        let overlap = base(extra: ["osOverrides": [["maxOS": "27.2", "steps": ["a"]], ["minOS": "27.2.5", "steps": ["b"]]]])
        XCTAssertTrue(diagnostics([overlap]).joined().contains("겹침"))
        let major = base(extra: ["osOverrides": [["minOS": 14, "maxOS": 15, "steps": ["a"]], ["minOS": "15.9", "steps": ["b"]]]])
        XCTAssertTrue(diagnostics([major]).joined().contains("겹침"))
    }

    func testRejectsBadBounds() {
        func bad(_ v: Any, _ key: String = "minOS") -> Bool {
            let d = diagnostics([base(extra: ["osOverrides": [[key: v, "steps": ["x"]]]])])
            return d.contains { $0.contains("osOverrides[0].\(key)") && $0.contains("정수") }
        }
        let rejected: [Any] = [true, false, -1, 0, 1000, 14.5, 1e30, "", "27.", ".2", "27..1", "27.2.1.0", "v27", " 27", "27 ", "+27",
                               "-1", "027", "27.02", "27.1000", "27.-1", "0", "0.5", "２７", "27.x", NSNull(), [27], ["a": 1]]
        for v in rejected { XCTAssertTrue(bad(v), "\(v)") }
        XCTAssertTrue(bad("99999999999999999999", "maxOS"))
        for ok: Any in [1, 999, "1", "999.999.999", "27.0", "27.0.0", "27.10.100"] {
            XCTAssertFalse(diagnostics([base(extra: ["osOverrides": [["minOS": ok, "steps": ["x"]]]])]).joined().contains("정수"), "\(ok)")
        }
    }

    func testMinGreaterThanMaxAcrossPrecisions() {
        func d(_ lo: Any, _ hi: Any) -> String { diagnostics([base(extra: ["osOverrides": [["minOS": lo, "maxOS": hi, "steps": ["x"]]]])]).joined() }
        XCTAssertTrue(d("27.2.1", "27.2.0").contains("보다 큼"))
        XCTAssertTrue(d("27.2", "27.1").contains("보다 큼"))
        XCTAssertTrue(d(28, "27.9.9").contains("보다 큼"))
        XCTAssertTrue(d("27.2", 27).isEmpty)          // 27 전체가 최대이므로 27.2 부터 27 끝까지
        XCTAssertTrue(d("27.2.1", "27.2").isEmpty)
        XCTAssertTrue(d("27.2.1", "27.2.1").isEmpty)  // 한 점짜리 범위
    }

    func testOSVersionOrdering() {
        XCTAssertLessThan(OSVersion(27, 2, 1), OSVersion(27, 10))
        XCTAssertLessThan(OSVersion(26, 99, 99), 27)
        XCTAssertEqual(OSVersion(14), 14)
    }

    // MARK: 합친 덮어쓰기 직접 검증

    func testEveryMergedOverrideIsValidatedWithItsPath() {
        let m = base(extra: ["osOverrides": [
            ["minOS": 14, "maxOS": 14, "trigger": ["type": "shortcut", "keys": "cmd+banana"]],
            ["minOS": 15, "maxOS": 15, "trigger": ["type": "appOpen"]],
            ["minOS": 16, "maxOS": 16, "settingsURL": "https://evil.example"],
            ["minOS": 17, "steps": ["ok"]],
        ]])
        let d = diagnostics([m])
        XCTAssertTrue(d.contains { $0.contains("m.osOverrides[0].trigger.keys") }, "\(d)")
        XCTAssertTrue(d.contains { $0.contains("m.osOverrides[1].trigger.bundleId") }, "\(d)")
        XCTAssertTrue(d.contains { $0.contains("m.osOverrides[2].settingsURL") }, "\(d)")
        XCTAssertFalse(d.contains { $0.contains("osOverrides[3]") }, "\(d)")
    }

    func testBaseProblemIsReportedOnceOnTheBase() {
        let m = base(extra: ["title": "", "osOverrides": [["minOS": 14, "steps": ["x"]], ["maxOS": 12, "steps": ["y"]]]])
        let d = diagnostics([m])
        XCTAssertEqual(d.filter { $0.contains("title") }.count, 1, "\(d)")
        XCTAssertTrue(d[0].contains("m.title"))
    }

    func testOverrideCanIntroduceWebFieldProblem() {
        let d = diagnostics([base(extra: ["osOverrides": [["minOS": 14, "steps": ["ok", ["text": ""]]]]])])
        XCTAssertTrue(d.contains { $0.contains("m.osOverrides[0].steps[1].text") }, "\(d)")
    }

    // MARK: 웹 필드 스키마

    func testWebFieldSchema() {
        func has(_ extra: [String: Any], _ needle: String) -> Bool {
            let d = diagnostics([base(extra: extra)])
            return d.contains { $0.contains(needle) }
        }
        XCTAssertTrue(has(["steps": "한 줄"], "m.steps"))
        XCTAssertTrue(has(["steps": [1]], "m.steps[0]"))
        XCTAssertTrue(has(["steps": [""]], "m.steps[0]"))
        XCTAssertTrue(has(["steps": [["point": ["app": "a", "label": "b"]]]], "m.steps[0].text"))
        XCTAssertTrue(has(["steps": [["text": 3]]], "m.steps[0].text"))
        XCTAssertTrue(has(["steps": [["text": "t", "point": "x"]]], "m.steps[0].point"))
        XCTAssertTrue(has(["steps": [["text": "t", "point": ["label": "b"]]]], "m.steps[0].point.app"))
        XCTAssertTrue(has(["steps": [["text": "t", "point": ["app": "a", "label": ""]]]], "m.steps[0].point.label"))
        XCTAssertTrue(has(["steps": [["text": "t", "point": ["app": "a", "label": "b", "in": "desktop"]]]], "m.steps[0].point.in"))
        XCTAssertTrue(has(["steps": [["text": "t", "point": ["app": "a", "label": "b", "in": 3]]]], "m.steps[0].point.in"))
        XCTAssertTrue(has(["steps": [["text": "t", "point": ["app": "a", "label": "b", "role": 3]]]], "m.steps[0].point.role"))
        XCTAssertTrue(has(["why": 1], "m.why"))
        XCTAssertTrue(has(["after": ["x"]], "m.after"))
        XCTAssertTrue(has(["group": 2], "m.group"))
        XCTAssertTrue(has(["needs": "camera"], "m.needs"))
        XCTAssertTrue(has(["permission": 1], "m.permission"))
        XCTAssertTrue(has(["trigger": ["type": "accessibility", "flag": "sparkle"]], "m.trigger.flag"))
    }

    func testValidWebFieldsAndExistingOptionalsAreKept() throws {
        let m = base(extra: [
            "why": "w", "after": "a", "group": "g", "needs": "accessibility", "extraFutureField": 1,
            "steps": ["문자열", ["text": "객체"], ["text": "가리키기", "hint": "x",
                      "point": ["app": "com.apple.dock", "in": "dock", "label": "Finder", "role": "AXDockItem", "window": "w"]]],
            "trigger": ["type": "accessibility", "flag": "reduceMotion", "to": true],
        ])
        XCTAssertEqual(diagnostics([m]), [])
        let c = try MissionCatalog.resolve(data: catalog([m]), os: 15)
        let web = try JSONSerialization.jsonObject(with: c.webData) as! [[String: Any]]
        XCTAssertEqual(web[0]["extraFutureField"] as? Int, 1)
        XCTAssertEqual((web[0]["steps"] as! [Any]).count, 3)
        for flag in ["reduceMotion", "increaseContrast", "reduceTransparency", "invertColors", "differentiateWithoutColor"] {
            XCTAssertEqual(diagnostics([base(extra: ["trigger": ["type": "accessibility", "flag": flag]])]), [], flag)
        }
        XCTAssertEqual(diagnostics([base(extra: ["steps": []])]), [])
    }

    // MARK: QA 시나리오

    func testPanelVisibilityScenarioIsWellFormed() throws {
        let url = root.appendingPathComponent("qa/panel-visibility.json")
        let steps = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        let flags = steps.compactMap { s -> Bool? in
            guard let n = s["panelVisible"] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
            return n.boolValue
        }
        XCTAssertTrue(flags.contains(true) && flags.contains(false))
        XCTAssertTrue(steps.contains { $0["until"] is String })
    }

    // MARK: 일반 검증

    func testDuplicateIDs() {
        XCTAssertTrue(diagnostics([base("a"), base("a")]).joined().contains("중복"))
    }

    /// osOverrides 를 잘못 적으면 조용히 무시되므로 validate 가 알린다. 실행(resolve)은 모르는 필드를 그대로 받아 보존한다.
    func testMisspelledOverridesKeyIsReportedButUnrelatedMetadataIsKept() throws {
        let ov: [[String: Any]] = [["minOS": 14, "steps": ["다름"]]]
        for key in ["osOverride", "osoverrides", "OSOverrides", "osOverrides ", " osOverrides", "os_overrides", "osOverides", "osOverridess"] {
            let d = diagnostics([base(extra: [key: ov])])
            XCTAssertEqual(d.count, 1, "\(key): \(d)")
            XCTAssertTrue(d.first?.contains("m.\"\(key)\"") == true && d.first?.contains("오타") == true, "\(key): \(d)")
            // 실행 중에는 막지 않는다: 기본 정의로 해석되고 필드는 남는다
            let c = try MissionCatalog.resolve(data: catalog([base(extra: [key: ov])]), os: 15)
            XCTAssertEqual(steps(c), ["기본"], key)
            let web = try JSONSerialization.jsonObject(with: c.webData) as! [[String: Any]]
            XCTAssertNotNil(web[0][key], key)
        }
        // 관계없는 메타데이터는 받아들이고 그대로 둔다
        let future: [String: Any] = ["overrides": ["a": 1], "osNotes": "x", "osSupport": [14, 15], "platformOverrides": [], "tags": ["new"]]
        let m = base(extra: future.merging(["osOverrides": ov]) { a, _ in a })
        XCTAssertEqual(diagnostics([m]), [])
        let web = try JSONSerialization.jsonObject(with: MissionCatalog.resolve(data: catalog([m]), os: 15).webData) as! [[String: Any]]
        for key in future.keys { XCTAssertNotNil(web[0][key], key) }
        XCTAssertEqual(web[0]["steps"] as? [String], ["다름"])
    }

    func testBadShortcut() {
        let d = diagnostics([base(extra: ["trigger": ["type": "shortcut", "keys": "cmd+banana"]])])
        XCTAssertTrue(d.joined().contains("단축키"), "\(d)")
    }

    func testBadShortcutInsideOverrideOnlyForThatRange() throws {
        let m = base(extra: ["osOverrides": [["minOS": 16, "trigger": ["type": "shortcut", "keys": "a"]]]])
        XCTAssertTrue(diagnostics([m]).joined().contains("단축키"))   // validate 는 모든 구간을 본다
        XCTAssertThrowsError(try MissionCatalog.resolve(data: catalog([m]), os: 16))
        XCTAssertNoThrow(try MissionCatalog.resolve(data: catalog([m]), os: 15)) // 해당 없는 OS 는 기본 정의
    }

    func testMalformedAndUnsupportedTriggers() {
        XCTAssertTrue(diagnostics([base(extra: ["trigger": ["type": "appOpen"]])]).joined().contains("bundleId"))
        XCTAssertTrue(diagnostics([base(extra: ["trigger": ["type": "teleport"]])]).joined().contains("지원하지 않는 트리거"))
        XCTAssertTrue(diagnostics([base(extra: ["trigger": "clipboardChange"])]).count >= 1)
        var noTrigger = base(); noTrigger.removeValue(forKey: "trigger")
        XCTAssertTrue(diagnostics([noTrigger]).joined().contains("trigger"))
        XCTAssertTrue(diagnostics([base(extra: ["trigger": ["type": "defaultsChange", "domain": "d", "keys": []]])]).joined().contains("keys"))
    }

    func testBadSettingsURLAndStructure() {
        XCTAssertTrue(diagnostics([base(extra: ["settingsURL": "https://evil.example"])]).joined().contains("settingsURL"))
        XCTAssertThrowsError(try MissionCatalog.resolve(data: Data("{".utf8), os: 15))
        XCTAssertThrowsError(try MissionCatalog.resolve(data: Data("{}".utf8), os: 15))
        XCTAssertTrue(diagnostics([["title": "no id"]]).joined().contains("id"))
    }

    func testErrorCollectsEveryProblem() {
        do { _ = try MissionCatalog.resolve(data: catalog([base("a"), base("a"), base("b", extra: ["xp": "many"])]), os: 15); XCTFail() }
        catch let e as CatalogError { XCTAssertGreaterThanOrEqual(e.diagnostics.count, 2) }
        catch { XCTFail("\(error)") }
    }

    // MARK: 릴리스 URL

    func testReleasesURL() {
        XCTAssertEqual(validatedReleasesURL("https://github.com/acme/mac-pet/releases")?.absoluteString, "https://github.com/acme/mac-pet/releases")
        XCTAssertNotNil(validatedReleasesURL("https://github.com/acme/mac.pet_x/releases/"))
        for bad in ["", "http://github.com/a/b/releases", "https://github.com.evil.io/a/b/releases", "https://github.com/a/b/releases/tag/v1",
                    "https://github.com/a/b/releases?x=1", "https://github.com/a/b/releases#f", "https://u@github.com/a/b/releases",
                    "https://github.com:444/a/b/releases", "https://github.com/a/b", "https://github.com/OWNER/../releases",
                    "https://github.com/a//releases", "file:///a/b/releases", "https://gitlab.com/a/b/releases"] {
            XCTAssertNil(validatedReleasesURL(bad), bad)
        }
        XCTAssertNil(validatedReleasesURL(nil))
    }
}
