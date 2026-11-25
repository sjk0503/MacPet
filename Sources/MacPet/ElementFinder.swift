import AppKit
import ApplicationServices
import MacPetCore

/// 다른 앱의 화면 요소를 이름으로 찾아 화면 위치를 읽는다. 손쉬운 사용 권한이 있어야 동작한다.
/// 읽는 것은 요소의 역할·이름·위치뿐이다. 아무것도 누르거나 바꾸지 않고, 읽은 내용을 저장하지 않는다.
final class ElementFinder {
    /// 지금 훑고 있는 자리: 어느 대상을, 어느 앱의, 어느 창(또는 메뉴 막대·앱)에서 찾는지.
    /// 이 중 하나라도 바뀌면 이어 가던 탐색·캐시·재시도 간격을 모두 버리고 새로 시작한다.
    private struct Scope {
        let target: PointTarget
        let pid: pid_t
        let anchor: AXUIElement
        func isSame(_ o: Scope) -> Bool { target == o.target && pid == o.pid && CFEqual(anchor, o.anchor) }
    }

    private var scope: Scope?
    private var cache: AXUIElement?                // scope 안에서 찾아 둔 요소
    private var walk: ResumableWalk<AXUIElement>?  // 다 못 훑고 멈춘 탐색. 다음 호출에서 이어 간다
    private var lastWalkEnd = Date.distantPast
    private var failedWalks = 0                    // 끝까지 훑고도 못 찾은 횟수(중간에 멈춘 것은 세지 않는다)

    private let maxVisit = 1500
    private let maxDepth = 14
    private let walkInterval: TimeInterval = 0.8 // 끝까지 훑고 못 찾았을 때, 처음부터 다시 훑기까지의 최소 간격(연속 실패하면 늘어난다)
    // 시간 한도는 "읽기 사이에서만" 확인하는 목표치다. 손쉬운 사용 읽기는 도중에 끊을 수 없어서,
    // 호출 한 번이 실제로 걸리는 시간은 대략 sliceBudget + 읽기 두 번(속성·자식)의 응답 대기까지 늘 수 있고,
    // 그 앞의 준비 읽기(창·제목·위치·캐시 확인)도 저마다 readTimeout 까지 기다릴 수 있다.
    private let sliceBudget: TimeInterval = 0.4  // 호출 한 번에 훑는 시간 목표. 넘으면 멈추고 다음 호출에서 이어 간다
    private let readTimeout: Float = 0.25        // 읽기 한 번이 응답을 기다리는 최대 시간(요소마다 따로 건다)

    /// 대상의 화면 위치(손쉬운 사용 좌표). 앱이 꺼져 있거나, 앞에 나와 있지 않거나, 스크롤 밖이면 nil.
    /// 느린 앱에서는 여러 번 불려야 찾을 수 있다: 한 번에 다 못 훑으면 nil 을 돌려주고 다음 호출에서 이어 훑는다.
    func locate(_ t: PointTarget) -> CGRect? {
        let deadline = Date().addingTimeInterval(sliceBudget)
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: t.app).first else { reset(); return nil }
        // Dock 은 늘 보이지만, 창과 메뉴는 그 앱이 앞에 나와 있을 때만 보이는 자리다
        if t.area != .dock, !app.isActive { reset(); return nil }
        let pid = app.processIdentifier
        let root = bounded(AXUIElementCreateApplication(pid))

        // 아래에서 읽기에 실패해 nil 을 돌려줄 때는 상태를 그대로 둔다. 느린 앱이 한 번 대답을 못 했다고
        // 이어 가던 탐색을 버리면 다시 처음부터 훑게 된다. 바뀐 것이 확인됐을 때만 버린다.
        var container: CGRect?
        let anchor: AXUIElement
        switch t.area {
        case .window:
            guard let win = focusedWindow(of: root) else { return nil }
            if let want = t.window {
                guard let title = string(win, kAXTitleAttribute) else { return nil }
                if normalizeLabel(title) != want { reset(); return nil }
            }
            guard let wf = frame(of: win) else { return nil }
            container = wf
            anchor = win
        case .menubar:
            guard let bar = element(root, kAXMenuBarAttribute) else { return nil }
            anchor = bar
        case .dock:
            anchor = root
        }

        let now = Scope(target: t, pid: pid, anchor: anchor)
        if scope.map({ !$0.isSame(now) }) ?? true {
            reset()
            scope = now
        }

        // 캐시된 요소는 속성 한 번 읽기로 확인한다
        if let c = cache {
            let a = attributes(c).values
            if let f = a.frame, isVisibleFrame(f, in: container), matches(a, t) { return f }
            cache = nil
        }

        if walk == nil {
            let wait = walkInterval * Double(1 + min(failedWalks, 2))
            guard Date().timeIntervalSince(lastWalkEnd) >= wait else { return nil }
            let starts = t.area == .dock ? children(of: root).elements ?? [] : [anchor]
            walk = ResumableWalk(starts: starts, maxVisit: maxVisit, maxDepth: maxDepth)
        }

        var foundFrame: CGRect?
        let outcome = walk!.resume(shouldPause: { Date() > deadline }) { e, canExpand in
            let a = attributes(bounded(e))
            if matches(a.values, t), let f = a.values.frame, isVisibleFrame(f, in: container) {
                foundFrame = f
                return .match
            }
            if a.error == .cannotComplete { return .retry } // 대답이 없었다. 건너뛰지 않고 다음 호출에서 다시 묻는다
            guard canExpand else { return .expand([]) }
            let kids = children(of: e)
            if kids.error == .cannotComplete { return .retry }
            return .expand(kids.elements ?? [])
        }
        switch outcome {
        case .found(let e):
            guard let f = foundFrame else { return nil }
            finishWalk(failed: false)
            cache = e
            return f
        case .exhausted:
            finishWalk(failed: true)
            return nil
        case .paused:
            return nil // 남은 줄은 walk 가 들고 있다
        }
    }

    /// 이어 가던 탐색과 캐시를 버리고(붙잡고 있던 다른 앱의 요소 참조도 놓는다) 재시도 간격을 처음으로 돌린다.
    func reset() { scope = nil; cache = nil; walk = nil; lastWalkEnd = .distantPast; failedWalks = 0 }

    private func finishWalk(failed: Bool) {
        walk = nil
        lastWalkEnd = Date()
        failedWalks = failed ? failedWalks + 1 : 0
    }

    // MARK: 속성 읽기

    /// 이 요소에 대한 읽기가 readTimeout 넘게 기다리지 않게 한다. 시간 제한은 요소 참조마다 따로 걸리며
    /// 같은 요소를 가리키는 다른 참조로는 넘어가지 않으므로, 읽을 참조마다 건다(앱 전역 값은 건드리지 않는다).
    @discardableResult
    private func bounded(_ e: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(e, readTimeout)
        return e
    }

    private struct Attributes {
        var role: String?
        var texts: [String] = []
        var frame: CGRect?
    }

    private static let attributeNames = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
                                         kAXPositionAttribute, kAXSizeAttribute] as CFArray

    /// 요소마다 속성 6개를 따로 묻지 않고 한 번에 가져온다(다른 앱과 주고받는 횟수가 1/6).
    private func attributes(_ e: AXUIElement) -> (values: Attributes, error: AXError) {
        var out: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(e, Self.attributeNames, [], &out)
        guard err == .success, let arr = out as? [AnyObject], arr.count == 6 else { return (Attributes(), err) }
        var a = Attributes()
        a.role = arr[0] as? String
        a.texts = [arr[1], arr[2], arr[3]].compactMap { $0 as? String }
        a.frame = rect(position: arr[4], size: arr[5])
        return (a, .success)
    }

    private func rect(position p: AnyObject?, size s: AnyObject?) -> CGRect? {
        guard let p = p, let s = s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    private func matches(_ a: Attributes, _ t: PointTarget) -> Bool {
        if let role = t.role, a.role != role { return false }
        return a.texts.contains { normalizeLabel($0) == t.label }
    }

    private func value(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(bounded(e), name as CFString, &v) == .success ? v : nil
    }

    private func string(_ e: AXUIElement, _ name: String) -> String? { value(e, name) as? String }

    private func element(_ e: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(e, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private func children(of e: AXUIElement) -> (elements: [AXUIElement]?, error: AXError) {
        var v: AnyObject?
        let err = AXUIElementCopyAttributeValue(bounded(e), kAXChildrenAttribute as CFString, &v)
        return (err == .success ? v as? [AXUIElement] : nil, err)
    }

    private func focusedWindow(of root: AXUIElement) -> AXUIElement? {
        element(root, kAXFocusedWindowAttribute) ?? (value(root, kAXWindowsAttribute) as? [AXUIElement])?.first
    }

    private func frame(of e: AXUIElement) -> CGRect? { rect(position: value(e, kAXPositionAttribute), size: value(e, kAXSizeAttribute)) }
}
