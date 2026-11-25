import Foundation

/// 네이티브 감지기 종류. 트리거 종류 하나가 한 묶음이다(스크린샷은 Spotlight + 폴더 감시를 함께).
public enum WatchFamily: String, CaseIterable, Hashable {
    case appearance, screenshot, defaults, accessibility, appOpen, clipboard, space, shortcut
}

/// 트리거를 감지하는 네이티브 감지기. 네이티브가 감지하지 않는 것(manual, unknown, 권한)은 nil.
/// 손쉬운 사용 권한 미션은 여기서 완료를 알리지 않는다: 이미 허용돼 있다는 사실만으로 끝난 것이 되면 안 되므로,
/// 웹이 계속 받는 권한 상태(true/false)와 사용자의 권한 요청 동작으로 스스로 판단한다.
public func watchFamily(of trigger: Trigger) -> WatchFamily? {
    switch trigger {
    case .appearanceChange: return .appearance
    case .screenshot: return .screenshot
    case .defaultsChange: return .defaults
    case .appOpen: return .appOpen
    case .clipboardChange: return .clipboard
    case .spaceChange: return .space
    case .accessibility: return .accessibility
    case .shortcut: return .shortcut
    case .accessibilityPermission, .manual, .unknown: return nil
    }
}

/// JS 가 저장할 때마다 보내는 상태에서 감시 자격 판단에 필요한 것만 뽑은 값(부화 여부 + 이름 지음 + 끝낸 미션 id).
/// 안내 상태(save.guide)는 일부러 읽지 않는다: 권하기만 한 것이나 지난 실행에서 남은 안내가 섞여 있어 "지금 따라 하는 중"의 근거가 못 된다.
public struct SaveProgress: Equatable {
    public var hatched: Bool
    public var named: Bool
    public var done: Set<String>

    public init(hatched: Bool, named: Bool, done: Set<String>) {
        self.hatched = hatched
        self.named = named
        self.done = done
    }

    /// `state` 는 JS 의 저장 객체. 모양이 다르면 nil(= 자격 없음).
    /// hatched 는 불리언 true 일 때만 참. named 는 공백 아닌 글자가 있는 문자열일 때만 참.
    /// done 은 값이 참인(true · 0 아닌 수 · 빈 문자열 아닌 문자열) 키만 센다.
    public init?(state: Any?) {
        guard let obj = state as? [String: Any] else { return nil }
        let h = obj["hatched"]
        hatched = (h as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
        named = (obj["name"] as? String).map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        var ids = Set<String>()
        if let d = obj["done"] as? [String: Any] {
            for (k, v) in d {
                if let s = v as? String { if !s.isEmpty { ids.insert(k) } }
                else if let n = v as? NSNumber { if n.doubleValue != 0 { ids.insert(k) } }
            }
        }
        done = ids
    }
}

/// 웹이 "지금 이 미션을 따라 하겠다"고 알린 등록. attempt 는 웹이 매기는 양의 정수이고, 감지 결과에 그대로 돌려준다.
public struct WatchRegistration: Equatable {
    public var id: String
    public var attempt: Int

    public init(id: String, attempt: Int) {
        self.id = id
        self.attempt = attempt
    }

    /// `{type:'watchMission', id:<미션 id>, attempt:<양의 정수>}` 만 등록으로 읽는다.
    /// `id:null` (그만 보기)과 모양이 어긋난 메시지(빈 id, attempt 없음·0·음수·소수·불리언·문자열)는 모두 nil = 감시 해제.
    public init?(message: [String: Any]) {
        guard let id = message["id"] as? String, !id.isEmpty,
              let n = message["attempt"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        guard d >= 1, d <= 9_007_199_254_740_991, d == d.rounded() else { return nil }
        self.id = id
        attempt = Int(d)
    }
}

/// 지금 걸려 있는 감시 하나. serial 은 걸 때마다 새로 매겨, 같은 미션·같은 attempt 로 다시 걸어도 앞선 것과 구별된다.
public struct WatchArming: Equatable {
    public let mission: Mission
    public let attempt: Int
    public let serial: Int

    public var registration: WatchRegistration { WatchRegistration(id: mission.id, attempt: attempt) }
}

/// 감시 등록 상태. 한 번에 미션 하나만 걸린다. 디스크에 남기지 않는다(실행 중에만 있는 값).
///
/// 걸리는 조건(전부): 웹이 준비됨 · 펫 창이 보임 · 쓸 수 있는 저장의 진행이 부화 + 이름 지음 + 그 미션을 아직 안 끝냄 ·
/// 카탈로그에 있고 트리거를 아는 미션. 하나라도 깨지면 바로 풀리고, 조건이 돌아와도 스스로 다시 걸리지 않는다
/// (웹이 새 등록을 보내야 한다).
public struct WatchEnrollment {
    private let missions: [String: Mission]
    public private(set) var current: WatchArming?
    private var serial = 0
    private var progress: SaveProgress?
    private var visible = false
    private var ready = false

    public init(missions: [Mission]) {
        self.missions = Dictionary(missions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func eligible(_ id: String) -> Mission? {
        guard ready, visible, let p = progress, p.hatched, p.named, !p.done.contains(id),
              let m = missions[id] else { return nil }
        if case .unknown = m.trigger { return nil } // 이 버전이 모르는(앞으로 생길) 트리거
        return m
    }

    private mutating func recheck() {
        if let c = current, eligible(c.mission.id) == nil { current = nil }
    }

    /// 웹의 등록 요청. nil 은 해제. 자격이 없으면 걸지 않고 앞선 등록도 푼다(새 요청이 앞선 것을 대신한다).
    /// 같은 미션을 다시 걸어도 항상 새 serial 이다 = 감지기를 새로 만들어 기준값을 다시 잡는다.
    public mutating func request(_ registration: WatchRegistration?) {
        current = nil
        guard let r = registration, let m = eligible(r.id) else { return }
        serial += 1
        current = WatchArming(mission: m, attempt: r.attempt, serial: serial)
    }

    /// 저장할 때마다. 쓸 수 없는(읽기 전용 보호) 저장이면 nil 을 넘긴다. 여전히 자격이 있으면 걸린 감시를 그대로 둔다(serial 유지).
    public mutating func setProgress(_ p: SaveProgress?) {
        progress = p
        recheck()
    }

    /// 창을 숨기면 바로 풀린다. 다시 보여도 풀린 채로 있다.
    public mutating func setVisible(_ v: Bool) {
        visible = v
        recheck()
    }

    /// 웹 화면이 준비됐거나(true) 사라졌을 때(false). 어느 쪽이든 앞선 화면의 등록은 버린다.
    public mutating func setReady(_ r: Bool) {
        ready = r
        current = nil
    }
}

/// 점검·개발용으로 직접 넣는 이벤트 전용. attempt 가 없는 mission 이벤트에, 그 미션이 지금 등록돼 있으면 등록된 attempt 를 붙인다.
/// attempt 를 직접 적은 이벤트(지난 번호 포함)와 다른 미션·다른 종류의 이벤트는 그대로 둔다.
/// 실제 감지 결과를 보내는 길에서는 쓰지 않는다(그쪽은 걸 때 잡아 둔 attempt 를 쓴다).
public func decorateInjectedMission(_ event: [String: Any], registration: WatchRegistration?) -> [String: Any] {
    guard event["type"] as? String == "mission", event["attempt"] == nil,
          let r = registration, event["id"] as? String == r.id else { return event }
    var out = event
    out["attempt"] = r.attempt
    return out
}
