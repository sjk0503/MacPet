import Foundation

/// missions.json 읽기·검증·OS 버전별 해석.
///
/// 스키마(기존 JSON 은 그대로 동작한다 — 모든 OS 버전에서 기본 정의를 쓴다):
///
///     {
///       "id": "dock-autohide", "xp": 40, "title": "...", "steps": [...], "trigger": {...},
///       "osOverrides": [
///         { "minOS": 14, "maxOS": 15, "steps": ["14~15 에서만 다른 안내"], "settingsURL": "x-apple.systempreferences:..." },
///         { "minOS": "16.4", "maxOS": "27.2.1", "trigger": { "type": "defaultsChange", ... } }
///       ]
///     }
///
/// ## OS 범위 (`minOS` / `maxOS`)
/// - 둘 중 하나는 반드시 있고, 하나만 쓰면 열린 범위다. 양끝 포함.
/// - 값은 **정수**(메이저만. 예: `27`) 또는 **점으로 나눈 문자열**(`"27"`, `"27.2"`, `"27.2.1"`).
///   `27.2` 같은 소수는 `27.20` 과 구별되지 않으므로 받지 않는다 — 문자열 `"27.2"` 로 쓴다.
/// - 각 자리는 0~999 의 10진수, 앞자리 0 없음(`"07"` ✗), 최대 3자리(major.minor.patch), major 는 1 이상.
///   불리언·음수·빈 자리(`"27."`)·공백·접두어(`"v27"`)·4자리 이상은 오류다.
/// - **minOS** 는 적은 자리 아래를 0 으로 본다: `27` = 27.0.0 부터, `"27.2"` = 27.2.0 부터.
/// - **maxOS** 는 적은 자리까지가 같은 모든 버전을 포함한다:
///   - `27` → 27.x.y 전부(27.0, 27.2, 27.99.9 …). 28.0 부터 제외.
///   - `"27.2"` → 27.2.x 전부. 27.3 부터 제외.
///   - `"27.2.1"` → 27.2.1 에서 멈춘다. 27.2.2 부터 제외.
/// - 한 미션의 범위끼리는 겹칠 수 없다(오류). 어느 범위에도 안 걸리는 OS 는 기본 정의로 돌아간다.
///
/// ## 덮어쓰기
/// - 덮어쓸 수 있는 필드: title, why, steps, after, settingsURL, trigger (필드 단위로 통째 교체. 안 적은 필드는 기본 정의 유지).
/// - id·xp 는 덮어쓸 수 없다(오류). group·needs·permission 등 나머지도 불가.
/// - 해석 결과에서는 `osOverrides` 를 지우고, 웹 전용 필드(steps, why, point …)는 그대로 둔다.
///
/// ## 웹 쪽 필드 검증 (있을 때만)
/// - `why`, `after`, `group`: 문자열.
/// - `steps`: 배열. 각 원소는 비어 있지 않은 문자열, 또는 `{ "text": 비어 있지 않은 문자열, "point": {...} }`.
///   `point` 는 선택이며 있으면 `app`·`label`(비어 있지 않은 문자열)이 필요하고, `role`·`window` 는 문자열,
///   `in` 은 `window`/`menubar`/`dock` 중 하나. 그 밖의 선택 필드는 그대로 둔다.
/// - `needs`, `permission`: 지원하는 값(`accessibility`)만.
/// - 트리거 `accessibility` 의 `flag`: reduceMotion, increaseContrast, reduceTransparency, invertColors, differentiateWithoutColor.
///
/// ## 검증 범위
/// `validate` 는 기본 정의와 **모든** 덮어쓰기를 합친 결과를 각각 직접 검사한다(OS 를 훑어 보지 않는다).
/// `resolve` 는 범위 구조 오류와 지금 OS 에 적용되는 정의만 검사한다. 파일은 둘 다 한 번만 읽는다.
public struct CatalogDiagnostic: Equatable, CustomStringConvertible {
    /// 어디가 문제인지. 예: `copy`, `copy.osOverrides[1].trigger.keys`, `missions[3]`
    public let path: String
    public let message: String
    public var description: String { "missions.json \(path): \(message)" }
}

public struct CatalogError: Error, CustomStringConvertible {
    public let diagnostics: [CatalogDiagnostic]
    public var description: String { diagnostics.map(\.description).joined(separator: "\n") }
}

/// macOS 버전. 정수 리터럴은 메이저만 쓴 것(`14` = 14.0.0).
public struct OSVersion: Comparable, Hashable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major; self.minor = minor; self.patch = patch
    }
    public init(integerLiteral value: Int) { self.init(value) }

    /// 실행 중인 OS. 한 번만 읽는다.
    public static let current: OSVersion = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return OSVersion(v.majorVersion, v.minorVersion, v.patchVersion)
    }()

    public static func < (a: OSVersion, b: OSVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
    public var description: String { "\(major).\(minor).\(patch)" }
}

/// 현재 OS 용으로 한 번 해석한 미션 목록. 네이티브 감지(missions)와 웹(webData)이 같은 결과를 쓴다.
public struct ResolvedCatalog {
    public let os: OSVersion
    public let missions: [Mission]
    /// 웹에 주입할 JSON 배열(웹 전용 필드 포함, osOverrides 제거).
    public let webData: Data
}

public enum MissionCatalog {
    public static let overridesKey = "osOverrides"
    static let patchable: Set<String> = ["title", "why", "steps", "after", "settingsURL", "trigger"]
    static let maxComponent = 999
    static let accessibilityFlags: Set<String> = ["reduceMotion", "increaseContrast", "reduceTransparency", "invertColors", "differentiateWithoutColor"]
    static let privileges: Set<String> = ["accessibility"]

    /// 기존 API. 파일을 한 번 읽어 해당 OS 로 해석한 미션을 돌려준다.
    public static func load(from url: URL, os: OSVersion = .current) throws -> [Mission] {
        try resolve(data: Data(contentsOf: url), os: os).missions
    }

    /// 데이터를 해석하고 검증한다. 문제가 하나라도 있으면 전부 모아 CatalogError 로 던진다.
    public static func resolve(data: Data, os: OSVersion = .current) throws -> ResolvedCatalog {
        let parsed = parse(data)
        var diags = parsed.diags
        var missions: [Mission] = []
        var web: [[String: Any]] = []
        for e in parsed.entries {
            let o = e.overrides.first { $0.covers(os) }
            let merged = o.map { e.base.merging($0.patch) { _, new in new } } ?? e.base
            let result = checkMission(merged)
            // 기본 정의의 문제를 덮어쓰기 탓으로 돌리지 않으려고, 덮어쓰기가 적용될 때만 기본 정의의 문제를 따로 구한다
            diags += report(result.issues, id: e.id, override: o?.index, inherited: o == nil ? [] : Set(checkMission(e.base).issues))
            if let m = result.mission { missions.append(m) }
            web.append(merged)
        }
        guard diags.isEmpty else { throw CatalogError(diagnostics: diags) }
        return ResolvedCatalog(os: os, missions: missions, webData: try JSONSerialization.data(withJSONObject: web))
    }

    /// 기본 정의와 모든 덮어쓰기(합친 결과)를 각각 직접 검증한다. CI 용. 빈 배열이면 문제 없음.
    public static func validate(data: Data) -> [CatalogDiagnostic] {
        let parsed = parse(data)
        var diags = parsed.diags
        for e in parsed.entries {
            let base = checkMission(e.base).issues
            diags += report(base, id: e.id, override: nil, inherited: [])
            // 작성 도우미: 모르는 최상위 필드는 그대로 통과시키지만(resolve 는 건드리지 않는다), osOverrides 의 오타로 보이면 알린다
            for key in e.base.keys.sorted() where looksLikeOverridesKey(key) {
                diags.append(.init(path: "\(e.id).\"\(key)\"", message: "'\(overridesKey)' 의 오타로 보임 — 이 이름으로는 OS 별 덮어쓰기가 적용되지 않음"))
            }
            for o in e.overrides {
                let merged = e.base.merging(o.patch) { _, new in new }
                diags += report(checkMission(merged).issues, id: e.id, override: o.index, inherited: Set(base))
            }
        }
        return diags
    }

    /// `osOverrides` 를 잘못 적은 것으로 보이는 최상위 필드 이름인지. 대소문자·공백·`_`/`-` 를 무시하고
    /// 한 글자 차이(빠짐·더함·바뀜. 단수형 `osOverride` 포함)까지만 본다. 그 밖의 이름은 앞으로 쓸 메타데이터로 보고 통과시킨다.
    static func looksLikeOverridesKey(_ key: String) -> Bool {
        guard key != overridesKey else { return false }
        let a = Array(key.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" })
        let b = Array(overridesKey.lowercased())
        guard abs(a.count - b.count) <= 1 else { return false }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        guard let i = short.indices.first(where: { short[$0] != long[$0] }) else { return true }
        return short.count == long.count ? short[(i + 1)...] == long[(i + 1)...] : short[i...] == long[(i + 1)...]
    }

    // MARK: 구조 읽기 (한 번)

    private struct Override {
        let index: Int
        let lo: OSVersion
        let hiExclusive: OSVersion? // nil = 열린 끝
        let patch: [String: Any]
        func covers(_ v: OSVersion) -> Bool { v >= lo && (hiExclusive.map { v < $0 } ?? true) }
        func overlaps(_ o: Override) -> Bool {
            (hiExclusive.map { o.lo < $0 } ?? true) && (o.hiExclusive.map { lo < $0 } ?? true)
        }
    }

    private struct Entry {
        let id: String
        let base: [String: Any]
        let overrides: [Override]
    }

    private struct Issue: Hashable {
        let field: String // 미션 안의 경로. 예: `trigger.keys`, `steps[1].point.in`. 미션 전체면 빈 문자열
        let message: String
    }

    /// 한 번 읽어서 구조(id, osOverrides 모양·범위·겹침)를 확인한다.
    private static func parse(_ data: Data) -> (entries: [Entry], diags: [CatalogDiagnostic]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return ([], [CatalogDiagnostic(path: "(file)", message: "JSON 으로 읽을 수 없음")])
        }
        guard let arr = root as? [Any] else {
            return ([], [CatalogDiagnostic(path: "(file)", message: "최상위는 미션 배열이어야 함")])
        }
        var diags: [CatalogDiagnostic] = []
        var entries: [Entry] = []
        var seen = Set<String>()
        for (i, item) in arr.enumerated() {
            guard var m = item as? [String: Any] else {
                diags.append(.init(path: "missions[\(i)]", message: "객체여야 함")); continue
            }
            guard let id = m["id"] as? String, !id.isEmpty else {
                diags.append(.init(path: "missions[\(i)]", message: "id(비어 있지 않은 문자열)가 필요함")); continue
            }
            if !seen.insert(id).inserted { diags.append(.init(path: id, message: "id 가 중복됨")) }
            var overrides: [Override] = []
            if let raw = m.removeValue(forKey: overridesKey) {
                let r = parseOverrides(raw, id: id)
                overrides = r.overrides
                diags += r.diags
            }
            entries.append(Entry(id: id, base: m, overrides: overrides))
        }
        return (entries, diags)
    }

    private static func parseOverrides(_ raw: Any, id: String) -> (overrides: [Override], diags: [CatalogDiagnostic]) {
        guard let list = raw as? [Any] else {
            return ([], [.init(path: "\(id).\(overridesKey)", message: "배열이어야 함")])
        }
        var diags: [CatalogDiagnostic] = []
        var accepted: [Override] = []
        for (i, item) in list.enumerated() {
            let p = "\(id).\(overridesKey)[\(i)]"
            guard let o = item as? [String: Any] else { diags.append(.init(path: p, message: "객체여야 함")); continue }
            var ok = true
            for key in o.keys.sorted() where key != "minOS" && key != "maxOS" && !patchable.contains(key) {
                let why = (key == "id" || key == "xp") ? "\(key) 는 OS 별로 바꿀 수 없음" :
                    "덮어쓸 수 없는 필드 (가능: \(patchable.sorted().joined(separator: ", ")))"
                diags.append(.init(path: "\(p).\(key)", message: why)); ok = false
            }
            var bounds: [String: Bound] = [:]
            for key in ["minOS", "maxOS"] {
                guard let raw = o[key] else { continue }
                if let b = parseBound(raw) { bounds[key] = b } else {
                    diags.append(.init(path: "\(p).\(key)", message: "정수(예: 27) 또는 \"27.2.1\" 같은 문자열이어야 함 (각 자리 0~\(maxComponent), 최대 3자리, 앞자리 0·불리언·음수 불가): \(raw)"))
                    ok = false
                }
            }
            if o["minOS"] == nil && o["maxOS"] == nil { diags.append(.init(path: p, message: "minOS 나 maxOS 중 하나는 필요함")); ok = false }
            let lo = bounds["minOS"]?.version ?? OSVersion(0)
            let hi = bounds["maxOS"]?.upperExclusive
            if let min = bounds["minOS"], let max = bounds["maxOS"], let hi, lo >= hi {
                diags.append(.init(path: p, message: "minOS(\(min.version)) 가 maxOS(\(max.version) 포함 범위) 보다 큼")); ok = false
            }
            let patch = o.filter { patchable.contains($0.key) }
            if patch.isEmpty { diags.append(.init(path: p, message: "바꿀 필드가 없음")); ok = false }
            guard ok else { continue }
            let cand = Override(index: i, lo: lo, hiExclusive: hi, patch: patch)
            if let other = accepted.first(where: { $0.overlaps(cand) }) {
                diags.append(.init(path: p, message: "OS 범위가 osOverrides[\(other.index)] 와 겹침")); continue
            }
            accepted.append(cand)
        }
        return (accepted, diags)
    }

    /// 범위 끝 하나. precision 은 적은 자리 수(1~3).
    private struct Bound {
        let version: OSVersion
        let precision: Int
        /// maxOS 용: 적은 자리까지 같은 버전을 모두 포함하는 바로 다음 버전.
        var upperExclusive: OSVersion {
            switch precision {
            case 1: return OSVersion(version.major + 1)
            case 2: return OSVersion(version.major, version.minor + 1)
            default: return OSVersion(version.major, version.minor, version.patch + 1)
            }
        }
    }

    private static func parseBound(_ raw: Any) -> Bound? {
        if let n = raw as? NSNumber {
            guard CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let d = n.doubleValue
            guard d == d.rounded(), d >= 1, d <= Double(maxComponent) else { return nil }
            return Bound(version: OSVersion(Int(d)), precision: 1)
        }
        guard let s = raw as? String else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var nums: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.utf8.count <= 3, p.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
                  p == "0" || p.first != "0", let n = Int(p) else { return nil }
            nums.append(n)
        }
        guard nums[0] >= 1 else { return nil }
        return Bound(version: OSVersion(nums[0], nums.count > 1 ? nums[1] : 0, nums.count > 2 ? nums[2] : 0), precision: nums.count)
    }

    // MARK: 미션 하나 검증

    /// 덮어쓰기를 적용한 미션이라면 기본 정의에서 물려받은 문제(inherited)는 덮어쓰기 경로로 다시 보고하지 않는다.
    private static func report(_ issues: [Issue], id: String, override: Int?, inherited: Set<Issue>) -> [CatalogDiagnostic] {
        var prefix = id
        if let i = override { prefix += ".\(overridesKey)[\(i)]" }
        return issues.filter { !inherited.contains($0) }.map {
            CatalogDiagnostic(path: $0.field.isEmpty ? prefix : "\(prefix).\($0.field)", message: $0.message)
        }
    }

    /// 해석이 끝난 미션 하나(osOverrides 가 없는 딕셔너리)를 검증한다.
    private static func checkMission(_ m: [String: Any]) -> (mission: Mission?, issues: [Issue]) {
        var issues = checkWebFields(m)
        func bad(_ field: String, _ msg: String) { issues.append(Issue(field: field, message: msg)) }

        let mission: Mission
        do {
            let data = try JSONSerialization.data(withJSONObject: m)
            mission = try JSONDecoder().decode(Mission.self, from: data)
        } catch {
            let (field, msg) = describe(error)
            if !issues.contains(where: { $0.field == field }) { bad(field, msg) }
            return (nil, issues)
        }
        if mission.title.isEmpty { bad("title", "비어 있음") }
        if mission.xp < 0 { bad("xp", "음수일 수 없음") }
        if let s = mission.settingsURL, !isAllowedSettingsURL(s) { bad("settingsURL", "x-apple.systempreferences: 로 시작해야 함 (\(s))") }
        switch mission.trigger {
        case let .unknown(t): bad("trigger.type", "지원하지 않는 트리거 '\(t)'")
        case let .shortcut(keys): if parseShortcut(keys) == nil { bad("trigger.keys", "해석할 수 없는 단축키 '\(keys)'") }
        case let .defaultsChange(domain, keys, _, _):
            if domain.isEmpty { bad("trigger.domain", "비어 있음") }
            if keys.isEmpty { bad("trigger.keys", "defaultsChange 는 keys 가 하나 이상 필요함") }
        case let .appOpen(b): if b.isEmpty { bad("trigger.bundleId", "비어 있음") }
        case let .accessibility(flag, _):
            if flag.isEmpty { bad("trigger.flag", "비어 있음") }
            else if !accessibilityFlags.contains(flag) { bad("trigger.flag", "지원하지 않는 플래그 '\(flag)' (가능: \(accessibilityFlags.sorted().joined(separator: ", ")))") }
        default: break
        }
        // 권한 미션은 어느 OS 에서든 실제 권한이 허용돼야 완료된다
        if mission.permission == "accessibility", mission.trigger != .accessibilityPermission {
            bad("trigger", "permission 이 accessibility 인 미션은 accessibilityPermission 트리거여야 함")
        }
        if mission.trigger == .accessibilityPermission, mission.permission != "accessibility" {
            bad("permission", "accessibilityPermission 트리거에는 permission: \"accessibility\" 가 필요함")
        }
        return (mission, issues)
    }

    /// 네이티브 모델에 없는(웹이 쓰는) 필드의 타입 검사. 있을 때만 본다.
    private static func checkWebFields(_ m: [String: Any]) -> [Issue] {
        var out: [Issue] = []
        func bad(_ field: String, _ msg: String) { out.append(Issue(field: field, message: msg)) }
        for key in ["why", "after", "group"] where m[key] != nil && !(m[key] is String) { bad(key, "문자열이어야 함") }
        for key in ["needs", "permission"] {
            guard let v = m[key] else { continue }
            guard let s = v as? String else { bad(key, "문자열이어야 함"); continue }
            if !privileges.contains(s) { bad(key, "지원하지 않는 값 '\(s)' (가능: \(privileges.sorted().joined(separator: ", ")))") }
        }
        guard let raw = m["steps"] else { return out }
        guard let steps = raw as? [Any] else { bad("steps", "배열이어야 함"); return out }
        for (i, st) in steps.enumerated() {
            let p = "steps[\(i)]"
            if let s = st as? String {
                if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { bad(p, "비어 있음") }
                continue
            }
            guard let o = st as? [String: Any] else { bad(p, "문자열 또는 { text, point } 객체여야 함"); continue }
            if let t = o["text"] as? String { if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { bad("\(p).text", "비어 있음") } }
            else { bad("\(p).text", "text(문자열)가 필요함") }
            guard let pt = o["point"] else { continue }
            guard let d = pt as? [String: Any] else { bad("\(p).point", "객체여야 함"); continue }
            for key in ["app", "label"] {
                if let s = d[key] as? String, !s.isEmpty { continue }
                bad("\(p).point.\(key)", "\(key)(비어 있지 않은 문자열)가 필요함")
            }
            for key in ["role", "window"] where d[key] != nil && !(d[key] is String) { bad("\(p).point.\(key)", "문자열이어야 함") }
            if let a = d["in"] {
                if (a as? String).flatMap(PointTarget.Area.init(rawValue:)) == nil { bad("\(p).point.in", "window, menubar, dock 중 하나여야 함") }
            }
        }
        return out
    }

    private static func describe(_ error: Error) -> (field: String, message: String) {
        guard let e = error as? DecodingError else { return ("", "\(error)") }
        func path(_ c: DecodingError.Context, _ extra: CodingKey? = nil) -> String {
            (c.codingPath + (extra.map { [$0] } ?? [])).map(\.stringValue).joined(separator: ".")
        }
        switch e {
        case let .keyNotFound(k, c): return (path(c, k), "필수 필드 '\(path(c, k))' 없음")
        case let .typeMismatch(_, c), let .valueNotFound(_, c), let .dataCorrupted(c): return (path(c), c.debugDescription)
        @unknown default: return ("", "\(e)")
        }
    }
}
