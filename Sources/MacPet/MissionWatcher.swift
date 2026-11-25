import AppKit
import MacPetCore

/// 미션 조건을 감지해 매번 onFire(id) 호출. 전부 메인 스레드.
/// 저장 진행(apply)에 따라 "아직 안 끝난 미션이 있는 트리거 묶음"만 켠다. 창이 숨겨진 동안에도 계속 돈다.
/// 손쉬운 사용 권한 상태 알림(AccessibilityAccess → 웹)은 PetPanelController 가 따로 지키므로 여기서 끄지 않는다.
final class MissionWatcher {
    private let missions: [Mission]
    private let onFire: (String) -> Void
    /// 묶음별로 돌고 있는 감시와 그 대상 id. 불이 나는 시점에 이 값을 읽으므로 재시작 없이 대상만 줄일 수 있다.
    private var running: WatchPlan = [:]
    /// 묶음별 자원 정리. 묶음 하나가 쓴 것만 돌려준다.
    private var teardowns: [WatchFamily: () -> Void] = [:]
    private var defaultsSnapshots: [String: [String: String?]] = [:]
    var logFileEvents = false

    init(missions: [Mission], onFire: @escaping (String) -> Void) {
        self.missions = missions
        self.onFire = onFire
    }

    deinit { stop() }

    /// 켜져 있는 묶음 (진단용)
    var activeFamilies: Set<WatchFamily> { Set(running.keys) }

    /// 저장 진행에 맞춰 바뀐 묶음만 켜고 끈다. 같은 진행을 여러 번 받아도(XP 만 바뀐 저장) 아무것도 다시 시작하지 않는다.
    func apply(_ progress: SaveProgress) {
        let desired = makeWatchPlan(missions: missions, progress: progress)
        for (family, action) in diffWatchPlan(running: running, desired: desired) {
            switch action {
            case .stop:
                stopFamily(family)
            case .retarget:
                running[family] = desired[family]
            case .start, .restart:
                stopFamily(family)
                running[family] = desired[family]
                startFamily(family)
            }
        }
    }

    /// 모든 감시를 멈추고 자원을 돌려준다. 여러 번 불러도 안전하다.
    func stop() {
        for f in WatchFamily.allCases { stopFamily(f) }
    }

    private func stopFamily(_ family: WatchFamily) {
        running[family] = nil
        teardowns.removeValue(forKey: family)?()
    }

    private func startFamily(_ family: WatchFamily) {
        guard let ids = running[family], !ids.isEmpty else { return }
        let td: () -> Void
        switch family {
        case .appearance: td = startAppearance()
        case .screenshot: td = startScreenshot()
        case .defaults: td = startDefaultsPolling(ids)
        case .accessibility: td = startAccessibility(ids)
        case .appOpen: td = startAppOpen(ids)
        case .clipboard: td = startClipboard()
        case .space: td = startSpaceChange()
        case .shortcut: td = startShortcuts(ids)
        case .permission: td = startAccessibilityPermission()
        }
        teardowns[family] = td
    }

    /// 이 묶음의 아직 안 끝난 미션 중 트리거가 맞는 것
    private func missionsOf(_ family: WatchFamily, _ ids: [String]) -> [Mission] {
        let set = Set(ids)
        return missions.filter { set.contains($0.id) && watchFamily(of: $0.trigger) == family }
    }

    private func fire(_ family: WatchFamily, _ id: String) {
        guard running[family]?.contains(id) == true else { return } // 끝났거나 꺼진 묶음의 늦은 알림은 버린다
        print("[mission] fired \(id)")
        onFire(id)
    }

    private func fireAll(_ family: WatchFamily) {
        (running[family] ?? []).forEach { fire(family, $0) }
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
            self?.fireAll(.appearance)
        }
    }

    private func startAppOpen(_ ids: [String]) -> () -> Void {
        let targets: [(id: String, bundleId: String)] = missionsOf(.appOpen, ids).compactMap {
            if case let .appOpen(b) = $0.trigger { return ($0.id, b) }
            return nil
        }
        return observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let bid = app?.bundleIdentifier else { return }
            targets.filter { $0.bundleId == bid }.forEach { self?.fire(.appOpen, $0.id) }
        }
    }

    private func startClipboard() -> () -> Void {
        var last = NSPasteboard.general.changeCount // 내용은 읽지 않고 횟수만 본다
        let t = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            let now = NSPasteboard.general.changeCount
            guard now != last else { return }
            last = now
            self?.fireAll(.clipboard)
        }
        t.tolerance = 0.3 // 시스템이 다른 타이머와 묶어 깨울 수 있게 한다
        RunLoop.main.add(t, forMode: .common)
        return { t.invalidate() }
    }

    private func startSpaceChange() -> () -> Void {
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in
            self?.fireAll(.space)
        }
    }

    // MARK: 손쉬운 사용 권한 / 단축키

    /// 권한 미션이 아직 안 끝났을 때만 켠다. 끝난 뒤의 권한 상태 알림은 컨트롤러가 계속 웹에 보낸다.
    private func startAccessibilityPermission() -> () -> Void {
        let access = AccessibilityAccess.shared
        access.start()
        if access.isTrusted {
            DispatchQueue.main.async { [weak self] in
                if AccessibilityAccess.shared.isTrusted { self?.fireAll(.permission) }
            }
        }
        let token = access.addObserver { [weak self] trusted in
            if trusted { self?.fireAll(.permission) }
        }
        return { access.removeObserver(token) }
    }

    private func startShortcuts(_ ids: [String]) -> () -> Void {
        var list: [(id: String, shortcut: Shortcut)] = []
        for m in missionsOf(.shortcut, ids) {
            guard case let .shortcut(keys) = m.trigger else { continue }
            if let s = parseShortcut(keys) { list.append((m.id, s)) }
            else { print("[mission] bad shortcut for \(m.id)") }
        }
        guard !list.isEmpty else { return {} }
        let watcher = ShortcutWatcher(shortcuts: list) { [weak self] id in self?.fire(.shortcut, id) }
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
        guard running[.screenshot] != nil, Date().timeIntervalSince(lastShot) > 3 else { return }
        lastShot = Date()
        fireAll(.screenshot)
    }

    // MARK: defaults 폴링

    private func readDefaults(domain: String, keys: [String], sync: Bool = true) -> [String: String?] {
        if sync { CFPreferencesAppSynchronize(domain as CFString) }
        var result: [String: String?] = [:]
        for key in keys {
            let v = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
            result[key] = canonicalDefaultsValue(v)
        }
        return result
    }

    private func startDefaultsPolling(_ ids: [String]) -> () -> Void {
        var targets: [(id: String, domain: String, keys: [String], ignore: [String], to: String?)] = []
        for m in missionsOf(.defaults, ids) {
            if case let .defaultsChange(domain, keys, ignore, to) = m.trigger {
                targets.append((m.id, domain, keys, ignore, to))
                defaultsSnapshots[m.id] = readDefaults(domain: domain, keys: keys)
            }
        }
        guard !targets.isEmpty else { return {} }
        let domains = Set(targets.map(\.domain))
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // 같은 도메인은 틱마다 한 번만 동기화한다
            domains.forEach { CFPreferencesAppSynchronize($0 as CFString) }
            for t in targets {
                let new = self.readDefaults(domain: t.domain, keys: t.keys, sync: false)
                let old = self.defaultsSnapshots[t.id] ?? [:]
                self.defaultsSnapshots[t.id] = new
                if defaultsChangeFired(old: old, new: new, ignoreValues: t.ignore, to: t.to) { self.fire(.defaults, t.id) }
            }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        let tids = targets.map(\.id)
        return { [weak self] in
            t.invalidate()
            tids.forEach { self?.defaultsSnapshots[$0] = nil }
        }
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

    private func startAccessibility(_ ids: [String]) -> () -> Void {
        let targets: [(id: String, flag: String, to: Bool)] = missionsOf(.accessibility, ids).compactMap {
            if case let .accessibility(flag, to) = $0.trigger { return ($0.id, flag, to) }
            return nil
        }
        guard !targets.isEmpty else { return {} }
        var state = currentA11y()
        return observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] _ in
            guard let self = self else { return }
            let new = self.currentA11y()
            let old = state
            state = new
            for t in targets {
                guard let o = old[t.flag], let n = new[t.flag] else { continue }
                if accessibilityFired(old: o, new: n, to: t.to) { self.fire(.accessibility, t.id) }
            }
        }
    }
}
