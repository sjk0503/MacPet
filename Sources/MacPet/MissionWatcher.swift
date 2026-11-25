import AppKit
import MacPetCore

/// 웹이 등록한 미션 하나의 조건을 감지해 onFire 를 부른다. 전부 메인 스레드.
/// 등록(시도) 한 번에 인스턴스 하나: 만들 때 그 미션의 감지기 하나만 켜고 기준값(클립보드 횟수·설정값 등)을 그 순간 새로 잡는다.
/// 같은 미션을 다시 등록해도 새 인스턴스를 만들므로 앞선 시도의 기준값·늦은 알림이 넘어오지 않는다.
/// 손쉬운 사용 권한 상태 알림(AccessibilityAccess → 웹)은 PetPanelController 가 따로 지키며, 여기서는 권한 미션을 감지하지 않는다.
final class MissionWatcher {
    private let mission: Mission
    private let onFire: () -> Void
    private var armed = false
    private var teardown: (() -> Void)?
    var logFileEvents = false

    init(mission: Mission, onFire: @escaping () -> Void) {
        self.mission = mission
        self.onFire = onFire
    }

    deinit { stop() }

    /// 이 미션의 감지기를 켠다. 네이티브가 감지하지 않는 트리거면 아무것도 켜지 않는다. 한 번만 켜진다(stop 뒤에는 새로 만든다).
    func start() {
        guard !armed, teardown == nil else { return }
        let td: () -> Void
        switch mission.trigger {
        case .appearanceChange: td = startAppearance()
        case .screenshot: td = startScreenshot()
        case let .defaultsChange(domain, keys, ignore, to): td = startDefaultsPolling(domain: domain, keys: keys, ignore: ignore, to: to)
        case let .accessibility(flag, to): td = startAccessibility(flag: flag, to: to)
        case let .appOpen(bundleId): td = startAppOpen(bundleId)
        case .clipboardChange: td = startClipboard()
        case .spaceChange: td = startSpaceChange()
        case let .shortcut(keys): td = startShortcut(keys)
        case .accessibilityPermission, .manual, .unknown: return
        }
        armed = true
        teardown = td
    }

    /// 감시를 멈추고 자원을 돌려준다. 여러 번 불러도 안전하다. 멈춘 뒤에 도착한 알림은 버린다.
    func stop() {
        armed = false
        teardown?()
        teardown = nil
    }

    private func fire() {
        guard armed else { return } // 멈춘 뒤의 늦은 알림은 버린다
        print("[mission] fired \(mission.id)")
        onFire()
    }

    // MARK: 알림 센터 관찰 도우미

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: Any? = nil,
                         _ handler: @escaping (Notification) -> Void) -> () -> Void {
        let token = center.addObserver(forName: name, object: object, queue: .main, using: handler)
        return { center.removeObserver(token) }
    }

    // MARK: 모양 바뀜 / 앱 열기 / 클립보드 / 데스크탑 전환

    private func startAppearance() -> () -> Void {
        observe(DistributedNotificationCenter.default(), Notification.Name("AppleInterfaceThemeChangedNotification")) { [weak self] _ in
            self?.fire()
        }
    }

    private func startAppOpen(_ bundleId: String) -> () -> Void {
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == bundleId { self?.fire() }
        }
    }

    private func startClipboard() -> () -> Void {
        var last = NSPasteboard.general.changeCount // 내용은 읽지 않고 횟수만 본다
        let t = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            let now = NSPasteboard.general.changeCount
            guard now != last else { return }
            last = now
            self?.fire()
        }
        t.tolerance = 0.3 // 시스템이 다른 타이머와 묶어 깨울 수 있게 한다
        RunLoop.main.add(t, forMode: .common)
        return { t.invalidate() }
    }

    private func startSpaceChange() -> () -> Void {
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in
            self?.fire()
        }
    }

    // MARK: 단축키

    /// 등록된 이 미션의 단축키 하나만 본다. 다른 미션의 단축키는 탭에 넣지 않는다.
    private func startShortcut(_ keys: String) -> () -> Void {
        guard let s = parseShortcut(keys) else {
            print("[mission] bad shortcut for \(mission.id)")
            return {}
        }
        let watcher = ShortcutWatcher(shortcuts: [(mission.id, s)]) { [weak self] _ in self?.fire() }
        let access = AccessibilityAccess.shared
        access.start()
        let begin = {
            if !watcher.start() { print("[mission] shortcut tap failed") }
        }
        if access.isTrusted { begin() }
        let token = access.addObserver { trusted in
            if trusted { begin() } else { watcher.stop() }
        }
        return {
            access.removeObserver(token)
            watcher.stop()
        }
    }

    // MARK: 스크린샷 (Spotlight + 스크린샷 폴더 감시. Spotlight 이 색인하지 않는 데스크탑용)

    private var fsStream: FSEventStreamRef?
    private var shotDirs: Set<String> = []
    private var lastShot = Date.distantPast

    private func startScreenshot() -> () -> Void {
        let q = NSMetadataQuery()
        var gathered = false // 처음 수집 결과는 무시
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        let nc = NotificationCenter.default
        let t1 = nc.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { _ in
            gathered = true
        }
        let t2 = nc.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] n in
            guard gathered else { return }
            let added = n.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [Any] ?? []
            if !added.isEmpty { self?.fireScreenshot() }
        }
        q.notificationBatchingInterval = 1.0 // 업데이트를 모아서 받아 깨어나는 횟수를 줄인다
        q.enableUpdates()
        if !q.start() { print("[mission] screenshot query failed to start") }
        startScreenshotFolderWatch()
        return { [weak self] in
            nc.removeObserver(t1)
            nc.removeObserver(t2)
            q.stop()
            self?.stopScreenshotFolderWatch()
        }
    }

    /// 스크린샷이 저장되는 폴더: 설정된 위치 + 데스크탑. 폴더 안은 건드리지 않는다(접근 권한 팝업을 띄우지 않으려고).
    private func screenshotDirs() -> Set<String> {
        var dirs: Set<String> = []
        if let loc = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String {
            dirs.insert(URL(fileURLWithPath: (loc as NSString).expandingTildeInPath).standardizedFileURL.path)
        }
        if let desk = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            dirs.insert(desk.standardizedFileURL.path)
        }
        return dirs
    }

    private func startScreenshotFolderWatch() {
        shotDirs = screenshotDirs()
        guard !shotDirs.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info = info else { return }
            let me = Unmanaged<MissionWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            for i in 0..<min(count, list.count) { me.handleFileEvent(path: list[i], flags: flags[i]) }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, cb, &ctx, Array(shotDirs) as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else {
            print("[mission] screenshot folder watch failed to start")
            return
        }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
        fsStream = s
    }

    private func stopScreenshotFolderWatch() {
        if let s = fsStream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            fsStream = nil
        }
        shotDirs = []
    }

    private func handleFileEvent(path: String, flags: FSEventStreamEventFlags) {
        let ns = path as NSString
        let name = ns.lastPathComponent
        let dir = URL(fileURLWithPath: ns.deletingLastPathComponent).standardizedFileURL.path
        let f = Int(flags)
        if logFileEvents { print("[fs] 0x\(String(f, radix: 16)) .\(ns.pathExtension) dot=\(name.hasPrefix(".")) inWatched=\(shotDirs.contains(dir))") }
        guard shotDirs.contains(dir), !name.hasPrefix(".") else { return }
        if isScreenshotFileEvent(ext: ns.pathExtension, flags: f) { fireScreenshot() }
    }

    /// 스크린샷 한 장에 알림이 여러 번 오므로(이름 바꾸기 → 속성 쓰기, Spotlight) 3초 안의 중복은 버린다.
    private func fireScreenshot() {
        guard armed, Date().timeIntervalSince(lastShot) > 3 else { return }
        lastShot = Date()
        fire()
    }

    // MARK: defaults 폴링

    private func readDefaults(domain: String, keys: [String]) -> [String: String?] {
        CFPreferencesAppSynchronize(domain as CFString)
        var result: [String: String?] = [:]
        for key in keys {
            let v = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
            result[key] = canonicalDefaultsValue(v)
        }
        return result
    }

    private func startDefaultsPolling(domain: String, keys: [String], ignore: [String], to: String?) -> () -> Void {
        var snapshot = readDefaults(domain: domain, keys: keys) // 기준값은 켜는 순간 새로 잡는다
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let new = self.readDefaults(domain: domain, keys: keys)
            let old = snapshot
            snapshot = new
            if defaultsChangeFired(old: old, new: new, ignoreValues: ignore, to: to) { self.fire() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        return { t.invalidate() }
    }

    // MARK: 손쉬운 사용 설정(화면 옵션)

    private func currentA11y() -> [String: Bool] {
        let w = NSWorkspace.shared
        return [
            "reduceMotion": w.accessibilityDisplayShouldReduceMotion,
            "increaseContrast": w.accessibilityDisplayShouldIncreaseContrast,
            "reduceTransparency": w.accessibilityDisplayShouldReduceTransparency,
            "invertColors": w.accessibilityDisplayShouldInvertColors,
            "differentiateWithoutColor": w.accessibilityDisplayShouldDifferentiateWithoutColor,
        ]
    }

    private func startAccessibility(flag: String, to: Bool) -> () -> Void {
        var state = currentA11y()
        return observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] _ in
            guard let self = self else { return }
            let new = self.currentA11y()
            let old = state
            state = new
            guard let o = old[flag], let n = new[flag] else { return }
            if accessibilityFired(old: o, new: n, to: to) { self.fire() }
        }
    }
}
