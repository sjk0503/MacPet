import AppKit
import WebKit
import MacPetCore

/// 키 창이 될 수 있는 투명 패널.
///
/// 점검(qaIsolated)에서는 사람의 입력과 완전히 끊는다: 키 창이 되지 않고(사용자가 치던 글자를 가로채지 않는다),
/// 운영체제가 보내 온 마우스·키 이벤트는 버리며, 점검 실행기가 `inject` 로 직접 넣은 이벤트만 받는다.
final class PetPanel: NSPanel {
    /// 만든 직후 한 번만 정한다. 켜면 되돌리지 않는다.
    var qaIsolated = false
    private var injecting = false

    override var canBecomeKey: Bool { !qaIsolated }
    override var canBecomeMain: Bool { false }

    /// 점검에서 만든 이벤트를 창으로 직접 보낸다. 점검이 아닐 때는 그냥 sendEvent 와 같다.
    func inject(_ event: NSEvent) {
        let was = injecting
        injecting = true
        defer { injecting = was }
        super.sendEvent(event)
    }

    override func sendEvent(_ event: NSEvent) {
        if qaIsolated, !injecting, Self.isUserInput(event.type) { return }
        super.sendEvent(event)
    }

    /// 단축키는 sendEvent 를 거치지 않고 들어오므로 따로 막는다.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if qaIsolated, !injecting { return false }
        return super.performKeyEquivalent(with: event)
    }

    private static func isUserInput(_ type: NSEvent.EventType) -> Bool {
        switch type {
        case .keyDown, .keyUp, .flagsChanged,
             .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged,
             .mouseMoved, .mouseEntered, .mouseExited, .scrollWheel,
             .gesture, .magnify, .swipe, .rotate, .smartMagnify, .pressure:
            return true
        default:
            return false
        }
    }
}

/// 비활성 상태에서도 첫 클릭이 먹는 웹뷰.
final class PetWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// WKUserContentController 는 핸들러를 강하게 붙든다. 컨트롤러를 직접 넘기면 컨트롤러 ↔ 웹뷰 순환이 생기므로 약하게 전달하는 중개자를 쓴다.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

final class PetPanelController: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static let size = NSSize(width: 400, height: 560) // web/style.css 의 무대 크기와 같아야 한다

    let panel: PetPanel
    private let webView: PetWebView
    private let save: SaveStore
    private let debug: Bool
    private var isReady = false
    private var queue: [[String: Any]] = []
    private var hitRects: [HitRect] = []
    private var ignoring = true
    private var shown = false // show()/hide() 로 정한 상태. 숨겨진 동안은 클릭 통과·가리키기를 멈춘다
    private var clickTimer: Timer?
    private var clickInterval: TimeInterval = 0
    private var mouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var accessToken: Int?
    private let userContent: WKUserContentController
    private let webRoot: URL? // 이 폴더 안의 파일만 로드·메시지 허용
    private var settingsHelpShowing = false
    private let mover: PanelMover
    private let pointer = PointerController()
    private let isolated: Bool
    var onReady: (() -> Void)?
    /// 웹이 등록한 미션 감시(한 번에 하나). 저장하지 않으며, 숨기기·다시 로드·자격 상실 때 풀리고 웹이 새로 등록해야 다시 걸린다.
    private var enrollment: WatchEnrollment
    private var notifiedSerial: Int?
    /// 걸린 감시가 바뀔 때(새로 걸림·풀림)만 부른다. 실제 감지기는 받는 쪽(AppDelegate)이 만든다. 점검 실행에서는 아무도 받지 않는다.
    var onWatchChange: ((WatchArming?) -> Void)?
    /// 지금 걸린 감시 (점검용 이벤트 넣기에서 attempt 를 찾을 때도 쓴다)
    var currentWatch: WatchArming? { enrollment.current }

    /// isolated: 점검 스크립트를 돌릴 때 켠다. 실제 권한 상태를 웹 화면에 알리지 않아(항상 '권한 없음') 결과가 환경에 따라 달라지지 않는다.
    init(webDir: URL?, missionsData: Data?, missions: [Mission] = [], save: SaveStore, debug: Bool, isolated: Bool = false) {
        self.isolated = isolated
        enrollment = WatchEnrollment(missions: missions)
        self.save = save
        self.debug = debug

        let ucc = WKUserContentController()
        userContent = ucc
        webRoot = webDir
        let config = WKWebViewConfiguration()
        config.userContentController = ucc
        webView = PetWebView(frame: NSRect(origin: .zero, size: Self.size), configuration: config)
        let p = PetPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.qaIsolated = isolated
        panel = p
        mover = PanelMover(panel: p, save: save)
        super.init()

        ucc.add(WeakScriptHandler(self), name: "pet")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        pointer.log = debug

        // 손쉬운 사용 권한 상태를 웹 화면에 알려 준다 (시작할 때 한 번, 바뀔 때마다)
        if !isolated {
            AccessibilityAccess.shared.start()
            // 이 관찰은 미션 감시(MissionWatcher)와 무관하게 끝까지 둔다: 권한 미션을 끝낸 뒤에도 취소·복구를 웹에 알려야 한다
            accessToken = AccessibilityAccess.shared.addObserver { [weak self] _ in self?.sendPermission() }
        }

        // 투명 배경
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        if debug { webView.isInspectable = true }

        // 초기 데이터 주입 (JSON 은 JSONSerialization 으로)
        let webMissions = missionsData.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? []
        let loaded = save.load()
        // 웹이 첫 저장을 보내기 전의 진행. 읽기 전용(보호) 저장이면 자격 없음으로 둔다.
        enrollment.setProgress(save.protectedReason == nil ? SaveProgress(state: loaded) : nil)
        let payload: [String: Any] = [
            "save": loaded ?? NSNull(),
            "missions": webMissions,
            "debug": debug,
            // 개발용 명령(devCompleteNext)은 디버그 실행이나 격리된 점검에서만 웹이 받아들인다
            "allowDevCommands": debug || isolated,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            ucc.addUserScript(WKUserScript(source: "window.__MACPET__ = \(json);",
                                           injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.contentView = webView

        if let webDir = webDir {
            let index = webDir.appendingPathComponent("index.html")
            if isBundledIndexURL(index, root: webDir), FileManager.default.fileExists(atPath: index.path) {
                webView.loadFileURL(index, allowingReadAccessTo: webDir)
            } else {
                print("[pet] index.html 없음 — 웹 로드 생략")
            }
        } else {
            print("[pet] web dir 없음 — 웹 로드 생략")
        }

        mover.place()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.mover.place()
        }
    }

    deinit {
        stopClickThrough()
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        if let t = accessToken { AccessibilityAccess.shared.removeObserver(t) }
        userContent.removeScriptMessageHandler(forName: "pet")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    // MARK: 웹뷰 탐색 제한 (번들된 index.html 만)

    private func isBundled(_ url: URL?) -> Bool {
        guard let root = webRoot else { return false }
        return isBundledIndexURL(url, root: root)
    }

    /// 메인 프레임에서 번들된 index.html 로 가는 탐색만 허용한다. 끌어다 놓은 링크·파일, 링크 클릭, 새 창, 하위 프레임은 모두 막는다(밖으로 열지도 않는다).
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let ok = navigationAction.targetFrame?.isMainFrame == true && isBundled(navigationAction.request.url)
        if !ok, debug { print("[pet] navigation blocked: \(navigationAction.request.url?.absoluteString ?? "-")") }
        decisionHandler(ok ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func show() {
        guard !shown || !panel.isVisible else { return }
        shown = true
        panel.orderFrontRegardless()
        pointer.setPaused(false)
        refreshClickThrough()
        enrollment.setVisible(true) // 보이게 됐다고 감시가 다시 걸리지는 않는다. 웹이 새로 등록한다
        send(["type": "visibility", "visible": true])
    }

    func hide() {
        let was = shown
        shown = false
        enrollment.setVisible(false) // 숨기는 즉시 감시를 끈다
        syncWatch()
        panel.orderOut(nil)
        pointer.setPaused(true)
        refreshClickThrough() // 타이머·감시를 끄고 클릭을 통과시킨다
        if was { send(["type": "visibility", "visible": false]) }
    }

    var isVisible: Bool { panel.isVisible }

    private func sendPermission() {
        send(["type": "permission", "name": "accessibility", "granted": !isolated && AccessibilityAccess.shared.isTrusted])
    }

    /// 점검용: 웹 화면을 거치지 않고 가리킬 대상을 직접 정한다.
    func pointTest(_ target: [String: Any]?) { pointer.setTarget(target) }

    // MARK: 클릭 통과

    /// 클릭 통과 갱신은 보이고(shown) 눌리는 영역이 있을 때만 돈다. 아니면 타이머도 마우스 감시도 없다.
    /// 점검(isolated)에서는 늘 통과시킨다: 실제 마우스는 이 창에 닿지 않고, 점검 클릭은 창으로 직접 들어간다.
    private func refreshClickThrough() {
        if shown, !hitRects.isEmpty, !isolated {
            startClickThrough()
            updateClickThrough()
        } else {
            stopClickThrough()
            setIgnoring(true)
        }
    }

    private func startClickThrough() {
        if mouseMonitor == nil {
            // 마우스가 창 근처로 들어오는 순간 바로 반응한다. 다른 앱 위의 움직임만 받으며 권한이 필요 없다.
            // 못 만들어도(nil) 아래 타이머가 같은 일을 한다.
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                self?.updateClickThrough()
            }
        }
        scheduleClickTimer(Self.farInterval)
    }

    private func stopClickThrough() {
        clickTimer?.invalidate()
        clickTimer = nil
        clickInterval = 0
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        mouseMonitor = nil
    }

    /// 창 근처에서는 30Hz, 멀리 있을 때는 느린 안전 확인(마우스 감시가 놓쳤을 때를 위해)만 한다.
    private static let nearInterval: TimeInterval = 1.0 / 30.0
    private static let farInterval: TimeInterval = 0.25

    private func scheduleClickTimer(_ interval: TimeInterval) {
        if clickTimer != nil, clickInterval == interval { return }
        clickTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.updateClickThrough() }
        if interval >= Self.farInterval { t.tolerance = interval * 0.3 }
        RunLoop.main.add(t, forMode: .common)
        clickTimer = t
        clickInterval = interval
    }

    private func setIgnoring(_ v: Bool) {
        guard v != ignoring else { return }
        ignoring = v
        panel.ignoresMouseEvents = v
    }

    private func updateClickThrough() {
        guard shown, !hitRects.isEmpty else { return }
        let m = NSEvent.mouseLocation
        let f = panel.frame
        let near = f.insetBy(dx: -24, dy: -24).contains(m)
        var shouldIgnore = true
        if near { shouldIgnore = !hitTest(x: m.x - f.minX, y: f.maxY - m.y, rects: hitRects, padding: 6) }
        setIgnoring(shouldIgnore)
        scheduleClickTimer(near ? Self.nearInterval : Self.farInterval)
    }

    // MARK: 미션 감시 등록

    /// 걸린 감시가 실제로 바뀌었을 때만 알린다(저장이 와도 그대로면 감지기를 건드리지 않는다).
    private func syncWatch() {
        let serial = enrollment.current?.serial
        guard serial != notifiedSerial else { return }
        notifiedSerial = serial
        if debug { print("[watch] \(enrollment.current.map { "armed \($0.mission.id) #\($0.attempt)" } ?? "disarmed")") }
        onWatchChange?(enrollment.current)
    }

    /// 감지기가 부른다. 그 감지기를 건 등록이 아직 그대로일 때만, 걸 때 받은 attempt 를 붙여 웹에 알린다.
    func deliverMission(serial: Int) {
        guard let w = enrollment.current, w.serial == serial else { return }
        send(["type": "mission", "id": w.mission.id, "attempt": w.attempt])
    }

    /// 다시 로드되면 앞선 화면의 등록은 버린다.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        enrollment.setReady(false)
        syncWatch()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        enrollment.setReady(false)
        syncWatch()
    }

    // MARK: 네이티브 -> JS

    func send(_ event: [String: Any]) {
        guard isReady else {
            // 준비 전에는 가장 최근 보임 상태만 의미가 있다
            if event["type"] as? String == "visibility" { queue.removeAll { $0["type"] as? String == "visibility" } }
            queue.append(event)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.MacPet && window.MacPet.onNative(\(json))", completionHandler: nil)
    }

    // MARK: JS -> 네이티브

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        // 번들된 페이지의 메인 프레임에서 온 메시지만 믿는다
        guard message.frameInfo.isMainFrame, isBundled(message.frameInfo.request.url) else {
            if debug { print("[pet] message from untrusted frame ignored") }
            return
        }
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            enrollment.setReady(true)
            enrollment.setVisible(shown && panel.isVisible)
            syncWatch()
            print("[pet] ready")
            let pending = queue
            queue.removeAll()
            sendPermission()
            pending.filter { $0["type"] as? String != "visibility" }.forEach(send)
            send(["type": "visibility", "visible": shown && panel.isVisible]) // 로드되는 동안 바뀌었을 수 있으니 지금 상태를 알린다
            onReady?()
        case "save":
            if let state = body["state"] as? [String: Any] {
                save.write(state)
                // 보호(읽기 전용) 저장은 감시 자격이 없다. 실행 중 보호로 넘어간 순간에도 돌던 감시를 끈다.
                // 자격이 그대로면 걸린 감시를 건드리지 않는다. (권한 상태 보고는 별도 관찰이라 그대로 유지된다)
                enrollment.setProgress(save.protectedReason == nil ? SaveProgress(state: state) : nil)
                syncWatch()
            }
        case "watchMission":
            // 사용자가 안내를 따라 하기로 한 미션 하나만 건다. id:null 이나 모양이 어긋난 요청은 해제.
            enrollment.setVisible(shown && panel.isVisible)
            enrollment.request(WatchRegistration(message: body))
            syncWatch()
        case "hitRects":
            let raw = body["rects"] as? [[String: Any]] ?? []
            func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
            hitRects = raw.map { HitRect(x: num($0["x"]), y: num($0["y"]), w: num($0["w"]), h: num($0["h"])) }
            refreshClickThrough()
        case "openSettings":
            // 점검(isolated)에서는 시스템 설정 앱을 열지 않는다
            if isolated { if debug { print("[settings] skipped (isolated)") }; break }
            if let s = body["url"] as? String, isAllowedSettingsURL(s), let url = URL(string: s) {
                let opened = NSWorkspace.shared.open(url)
                if debug { print("[settings] open=\(opened) url=\(s)") }
                if !opened { openSettingsFallback(for: s) }
            }
        case "requestPermission":
            // 점검(isolated)에서는 시스템 권한 안내 창을 띄우지 않는다
            if isolated { if debug { print("[permission] request skipped (isolated)") }; break }
            if body["name"] as? String == "accessibility" { AccessibilityAccess.shared.request() }
        case "point":
            // 점검(isolated)에서는 다른 앱의 화면 요소를 읽지 않는다. 직접 정하는 pointTest 만 허용한다.
            if isolated { break }
            pointer.setTarget(body["target"] as? [String: Any])
        case "dragStart":
            // 점검(isolated)에서는 실제 마우스를 따라 창을 옮기지 않는다
            if isolated { break }
            mover.beginDrag()
        case "log":
            print("[web] \(body["msg"] ?? body["message"] ?? "")")
        default:
            break
        }
    }

    // MARK: 시스템 설정 열기 대체 경로

    private static let settingsBundleID = "com.apple.systempreferences"

    /// 링크로 못 열면 시스템 설정 앱 자체를 번들 ID 로 열고, 그것도 안 되면 찾아가는 방법을 알려 준다.
    private func openSettingsFallback(for settingsURL: String) {
        let showHelp = { [weak self] in self?.showSettingsHelp(for: settingsURL) }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.settingsBundleID) else {
            showHelp(); return
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            DispatchQueue.main.async {
                if self?.debug == true { print("[settings] fallback app open error=\(String(describing: error))") }
                // 앱만 열렸다면 원하는 화면까지는 못 갔으니 어디로 가야 하는지도 알려 준다
                showHelp()
            }
        }
    }

    private func showSettingsHelp(for settingsURL: String) {
        guard !settingsHelpShowing, !isolated else { return }
        settingsHelpShowing = true
        defer { settingsHelpShowing = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "설정 화면을 바로 열지 못했어요"
        alert.informativeText = settingsFallbackInstructions(for: settingsURL)
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    // MARK: 점검 실행기(QARunner)가 쓰는 통로

    /// 점검·개발용으로 직접 넣는 이벤트. attempt 없는 mission 이벤트에만, 그 미션이 지금 등록돼 있으면 등록된 attempt 를 붙인다.
    func sendInjected(_ event: [String: Any]) {
        send(decorateInjectedMission(event, registration: enrollment.current?.registration))
    }

    func evaluate(_ js: String, completion: @escaping (Any?) -> Void) {
        webView.evaluateJavaScript(js) { value, error in
            if let error = error { print("[qa] js error: \(error.localizedDescription)") }
            completion(value)
        }
    }

    /// 웹 화면 좌표(왼쪽 위 원점)에 클릭을 창으로 직접 보낸다. 실제 커서는 움직이지 않는다.
    /// hold 는 누르고 있는 시간(초). 실제 클릭처럼 0.06초쯤 두는 것이 기본이다:
    /// 0 으로 두면 입력 칸에 커서가 있을 때 웹뷰가 누름과 뗌을 뒤바뀐 순서로 받는다(입력기를 거치는 누름이 늦게 도착).
    func click(webX: Double, webY: Double, hold: Double = 0.06) {
        let p = NSPoint(x: webX, y: Double(panel.frame.height) - webY)
        func send(_ type: NSEvent.EventType, _ pressure: Float) {
            if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: panel.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: pressure) {
                panel.inject(e)
            }
        }
        send(.leftMouseDown, 1)
        if hold <= 0 { send(.leftMouseUp, 0); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { send(.leftMouseUp, 0) }
    }

    /// 글자를 키 입력으로 보낸다. 실제 사용에서는 입력 칸을 누르면 창이 키 창이 되므로 여기서도 키 창으로 만든다.
    /// 점검(isolated)에서는 키 창으로 만들지 않고(사용자의 실제 키 입력을 끌어오지 않도록) 창 안의 첫 응답자만 웹뷰로 맞춘 뒤,
    /// 키 창 여부와 무관하게 웹뷰의 keyDown/keyUp 으로 직접 넣는다.
    func typeText(_ text: String) {
        if !isolated { panel.makeKey() }
        panel.makeFirstResponder(webView)
        for ch in text {
            let s = String(ch)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                            timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: panel.windowNumber, context: nil,
                                            characters: s, charactersIgnoringModifiers: s,
                                            isARepeat: false, keyCode: 0) {
                    if !isolated { panel.sendEvent(e) }
                    else if type == .keyDown { webView.keyDown(with: e) }
                    else { webView.keyUp(with: e) }
                }
            }
        }
    }

    func savePNG(to path: String, completion: @escaping (Bool) -> Void) {
        webView.takeSnapshot(with: nil) { image, _ in
            guard let tiff = image?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                completion(false); return
            }
            completion((try? png.write(to: URL(fileURLWithPath: path))) != nil)
        }
    }

    var currentHitRects: [HitRect] { hitRects }

    // MARK: 점검용 클릭

    /// 첫 번째 눌림 영역(펫) 가운데에 클릭 이벤트를 창으로 직접 보낸다. 실제 마우스는 움직이지 않는다.
    func selfTap() {
        guard let r = hitRects.first else { print("[tap] 눌림 영역 없음"); return }
        let p = NSPoint(x: r.x + r.w / 2, y: Double(panel.frame.height) - (r.y + r.h / 2)) // 창 좌표는 아래가 원점
        for (type, pressure) in [(NSEvent.EventType.leftMouseDown, Float(1)), (.leftMouseUp, Float(0))] {
            if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: panel.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: pressure) {
                panel.inject(e)
            }
        }
        print("[tap] sent at \(Int(p.x)),\(Int(p.y))")
    }

    // MARK: 스냅샷

    func snapshot(to path: String) {
        webView.takeSnapshot(with: nil) { image, error in
            guard let image = image, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("[snapshot] failed: \(String(describing: error))")
                exit(1)
            }
            do {
                try png.write(to: URL(fileURLWithPath: path))
                print("[snapshot] wrote \(path)")
                exit(0)
            } catch {
                print("[snapshot] write failed: \(error)")
                exit(1)
            }
        }
    }
}
