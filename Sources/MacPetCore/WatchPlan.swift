import Foundation

/// 같이 켜고 끄는 감시 묶음. 트리거 종류 하나가 한 묶음이다(스크린샷은 Spotlight + 폴더 감시를 함께).
public enum WatchFamily: String, CaseIterable, Hashable {
    case appearance, screenshot, defaults, accessibility, appOpen, clipboard, space, shortcut, permission
}

/// 트리거가 속한 묶음. 네이티브가 감지하지 않는 것(manual, unknown)은 nil.
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
    case .accessibilityPermission: return .permission
    case .manual, .unknown: return nil
    }
}

/// JS 가 저장할 때마다 보내는 상태에서 감시 선택에 필요한 것만 뽑은 값(부화 여부 + 끝낸 미션 id).
public struct SaveProgress: Equatable {
    public var hatched: Bool
    public var done: Set<String>

    public init(hatched: Bool, done: Set<String>) {
        self.hatched = hatched
        self.done = done
    }

    /// `state` 는 JS 의 저장 객체. 모양이 다르면 nil(= 감시를 바꾸지 않는다).
    /// hatched 는 불리언 true 일 때만 참. done 은 값이 참인(true · 0 아닌 수 · 빈 문자열 아닌 문자열) 키만 센다.
    public init?(state: Any?) {
        guard let obj = state as? [String: Any] else { return nil }
        let h = obj["hatched"]
        hatched = (h as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
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

/// 묶음별로 지금 지켜봐야 할 미션 id(카탈로그 순서). 비어 있는 묶음은 넣지 않는다.
public typealias WatchPlan = [WatchFamily: [String]]

/// 아직 안 끝난 미션만 묶음별로 모은다. 부화 전에는 어떤 미션도 완료되지 않으므로(웹이 무시) 아무것도 감시하지 않는다.
public func makeWatchPlan(missions: [Mission], progress: SaveProgress) -> WatchPlan {
    guard progress.hatched else { return [:] }
    var plan: WatchPlan = [:]
    for m in missions where !progress.done.contains(m.id) {
        guard let f = watchFamily(of: m.trigger) else { continue }
        plan[f, default: []].append(m.id)
    }
    return plan
}

public enum WatchAction: Equatable {
    case start   // 꺼져 있던 묶음을 켠다
    case stop    // 할 일이 없어진 묶음을 끈다
    case retarget // 돌고 있는 감시는 그대로 두고 대상 id 만 줄인다(재시작 없음)
    case restart // 새 id 가 생겼다(초기화 등). 다시 만든다
}

/// 돌고 있는 상태에서 원하는 상태로 가기 위한 일. 바뀐 묶음만 돌려준다.
/// 끝난 미션이 늘어 id 가 줄기만 한 묶음은 재시작하지 않고(진행 중인 감지·스냅샷을 지킨다) 대상만 줄인다.
public func diffWatchPlan(running: WatchPlan, desired: WatchPlan) -> [(family: WatchFamily, action: WatchAction)] {
    var out: [(WatchFamily, WatchAction)] = []
    for f in WatchFamily.allCases {
        let old = running[f] ?? [], new = desired[f] ?? []
        if old == new { continue }
        if new.isEmpty { out.append((f, .stop)) }
        else if old.isEmpty { out.append((f, .start)) }
        else if Set(new).isSubset(of: Set(old)) { out.append((f, .retarget)) }
        else { out.append((f, .restart)) }
    }
    return out.map { (family: $0.0, action: $0.1) }
}
