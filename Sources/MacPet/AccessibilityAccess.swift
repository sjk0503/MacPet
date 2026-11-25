import ApplicationServices
import Foundation

/// 손쉬운 사용 권한 상태. 바뀌면 관찰자에게 알린다. 메인 스레드 전용.
/// 시스템이 권한 변경을 알리는 분산 알림을 먼저 듣고, 알림이 없는 OS 를 위해 느린 폴링을 함께 둔다.
final class AccessibilityAccess {
    static let shared = AccessibilityAccess()

    private(set) var isTrusted = AXIsProcessTrusted()
    private var observers: [(token: Int, f: (Bool) -> Void)] = []
    private var nextToken = 0
    private var timer: Timer?
    private var notificationObserver: NSObjectProtocol?

    private let fallbackInterval: TimeInterval = 2

    func start() {
        guard timer == nil else { return }
        isTrusted = AXIsProcessTrusted()
        print("[access] accessibility trusted: \(isTrusted)")
        // 알림은 문서화된 이름이 아니라 OS 가 바꿔도 폴링이 받쳐 준다.
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            // 알림이 신뢰 목록 갱신보다 먼저 올 수 있어 잠깐 뒤에 읽는다
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.recheck() }
        }
        let t = Timer(timeInterval: fallbackInterval, repeats: true) { [weak self] _ in self?.recheck() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let o = notificationObserver { DistributedNotificationCenter.default().removeObserver(o) }
        notificationObserver = nil
    }

    private func recheck() {
        let now = AXIsProcessTrusted()
        guard now != isTrusted else { return }
        isTrusted = now
        print("[access] accessibility trusted: \(now)")
        observers.map(\.f).forEach { $0(now) }
    }

    /// 값이 바뀔 때만 호출된다(등록 시점에는 호출하지 않음). 돌려주는 토큰으로 removeObserver 할 수 있다.
    @discardableResult
    func addObserver(_ f: @escaping (Bool) -> Void) -> Int {
        nextToken += 1
        observers.append((nextToken, f))
        return nextToken
    }

    func removeObserver(_ token: Int) {
        observers.removeAll { $0.token == token }
    }

    /// 시스템 안내 창을 띄운다. 설정 앱은 따로 열지 않는다.
    func request() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
