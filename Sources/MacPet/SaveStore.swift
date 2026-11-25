import Foundation

/// 펫의 진행 상태와 창 위치를 저장한다.
final class SaveStore {
    let url: URL
    private let panelOriginURL: URL?
    private let panelOriginKey = "panelOrigin"

    init(path: String?) {
        if let path = path {
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            panelOriginURL = url.appendingPathExtension("panelOrigin")
        } else {
            url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/MacPetGuide/save.json")
            panelOriginURL = nil
        }
    }

    /// 읽기 전용으로 보호 중인 이유. nil 이면 쓰기 가능 (저장 파일이 없거나 정상).
    /// 보호 중에는 write/delete 가 원본 파일을 건드리지 않는다.
    private(set) var protectedReason: String?
    private var inspected = false
    /// JS 에 "이 저장은 읽기 전용으로 다뤄라" 를 알리는 표식 키 (web/app.js 의 PROT_KEY 와 같다)
    static let protectedKey = "__macpetProtected"

    /// 마지막으로 읽거나 쓴 원본 바이트 (저장이 없으면 nil). 실행 중에 바깥에서 바뀌었는지 비교하는 데만 쓴다
    private var seen: Data?
    /// web/app.js 의 KNOWN 과 같다: 버전 없는 예전 저장은 이 중 하나라도 있어야 우리 저장으로 본다
    private static let knownFields = ["species", "shiny", "hatched", "crack", "name", "level", "exp", "done", "manual", "guide", "petDay", "pets", "lastSeen"]

    /// 저장 없음(처음 실행) → nil. 정상 → 파싱한 JSON.
    /// 읽을 수 없음·파싱 실패·알 수 없는 버전/모양 → [protectedKey: 이유] 를 돌려주고, 이후 쓰기·삭제를 막는다.
    func load() -> Any? {
        inspected = true
        protectedReason = nil
        seen = nil
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if isNotFound(error) { return nil }
            return protect("unreadable")
        }
        seen = data
        if let reason = problem(in: data) { return protect(reason) }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// 건드리면 안 되는 저장이면 그 이유, 아니면 nil
    private func problem(in data: Data) -> String? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return "unparseable" }
        guard let obj = raw as? [String: Any] else { return "shape" }
        if obj[Self.protectedKey] != nil { return "reserved" }
        if let v = obj["v"] {
            // 쓰는 버전은 예전 앱이 읽는 v:1 하나뿐이다. 불리언·v:2 등 그 밖의 명시 버전은 건드리지 않는다
            guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == 1 else { return "version" }
            return nil
        }
        return Self.knownFields.contains { obj[$0] != nil } ? nil : "shape"
    }

    @discardableResult
    private func protect(_ reason: String) -> [String: Any] {
        protectedReason = reason
        print("[save] 보호: \(reason) — 이번 실행에서는 저장 파일을 쓰거나 지우지 않는다")
        return [Self.protectedKey: reason]
    }

    private func isNotFound(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError) { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT) { return true }
        if let u = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isNotFound(u) }
        return false
    }

    /// 쓰기·삭제 직전 확인. load() 를 거치지 않았으면 먼저 읽고, 이미 읽었다면 마지막으로 본 바이트와 지금 파일을 비교한다.
    /// 실행 중에 더 새로운 버전·깨진 파일로 바뀌었다면 그 순간부터 재실행 전까지 보호한다 (읽을 수 있는 다른 저장이면 그대로 이어서 쓴다)
    private var writable: Bool {
        if !inspected { _ = load(); return protectedReason == nil }
        guard protectedReason == nil else { return false }
        let now: Data?
        do {
            now = try Data(contentsOf: url)
        } catch {
            if isNotFound(error) { seen = nil; return true }
            protect("unreadable")
            return false
        }
        if now != seen {
            if let now, let reason = problem(in: now) { protect(reason); return false }
            seen = now
        }
        return true
    }

    func write(_ state: Any) {
        guard writable else { print("[save] 보호 중이라 저장하지 않음"); return }
        guard JSONSerialization.isValidJSONObject(state),
              let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) else {
            print("[save] invalid state")
            return
        }
        // 읽은 원본과 내용이 같으면(공백·키 순서만 다른 경우 포함) 디스크를 건드리지 않는다.
        // v 가 없던 예전 저장은 다르다고 보아 v:1 로 쓴다. NSDictionary 비교는 1 과 true 를 같게 보므로 키를 정렬해 다시 직렬화한 바이트로 비교한다
        if let seen, let old = try? JSONSerialization.jsonObject(with: seen),
           let oldCanon = try? JSONSerialization.data(withJSONObject: old, options: [.sortedKeys]),
           let newCanon = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
           oldCanon == newCanon { return }
        if write(data, to: url) { seen = data }
    }

    func loadPanelOrigin() -> String? {
        if let panelOriginURL {
            return try? String(contentsOf: panelOriginURL, encoding: .utf8)
        }
        return UserDefaults.standard.string(forKey: panelOriginKey)
    }

    func writePanelOrigin(_ origin: String) {
        if let panelOriginURL {
            write(Data(origin.utf8), to: panelOriginURL)
        } else {
            UserDefaults.standard.set(origin, forKey: panelOriginKey)
        }
    }

    @discardableResult
    private func write(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            print("[save] write failed: \(error)")
            return false
        }
    }

    func delete() {
        guard writable else { print("[save] 보호 중이라 지우지 않음"); return }
        if (try? FileManager.default.removeItem(at: url)) != nil { seen = nil }
    }
}
