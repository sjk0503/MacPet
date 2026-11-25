import AppKit
import MacPetCore

/// 명령줄 옵션
struct Options {
    var debug = false
    var regular = false // 점검용: Dock 에 보이는 일반 앱으로 띄운다
    var qa: String? // 점검용: 이 JSON 스크립트의 단계를 실행하고 끝낸다 (QARunner)
    var savePath: String?
    var simulate: String?
    var command: String? // 점검용: ready 1초 뒤 메뉴 명령을 대신 보낸다 (예: toggleMissions)
    var selfTap = 0 // 점검용: ready 1초 뒤부터 0.7초 간격으로 펫을 이 횟수만큼 누른다
    var point: String? // 점검용: ready 1초 뒤 이 JSON 을 가리킬 대상으로 정한다
    var snapshot: String?
    var snapshotDelay = 2.0

    init(_ args: [String]) {
        var i = 1
        while i < args.count {
            switch args[i] {
            case "--debug": debug = true
            case "--regular": regular = true
            case "--qa":
                // 경로가 없으면(맨 끝이거나 다음이 다른 옵션) 빈 경로로 둔다 → 평소 앱으로 뜨지 않고 QARunner 가 오류로 끝낸다
                if i + 1 < args.count, !args[i + 1].hasPrefix("--") { i += 1; qa = args[i] } else { qa = "" }
            case "--save-path": i += 1; if i < args.count { savePath = args[i] }
            case "--simulate": i += 1; if i < args.count { simulate = args[i] }
            case "--command": i += 1; if i < args.count { command = args[i] }
            case "--self-tap": i += 1; if i < args.count { selfTap = min(max(Int(args[i]) ?? 0, 0), 100) }
            case "--point": i += 1; if i < args.count { point = args[i] }
            case "--snapshot": i += 1; if i < args.count { snapshot = args[i] }
            case "--snapshot-delay": i += 1; if i < args.count { let d = Double(args[i]) ?? 2.0; snapshotDelay = d.isFinite ? min(max(d, 0), 600) : 2.0 }
            default: break
            }
            i += 1
        }
    }
}

/// --qa 인데 --save-path 가 없으면 쓰는 임시 저장 위치(창 위치 포함). 실제 저장은 읽지도 쓰지도 않는다.
private var qaTempDir: String?

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let options: Options
    private let save: SaveStore
    private var controller: PetPanelController?
    private var watcher: MissionWatcher?
    private var qaRunner: QARunner?
    private var statusItem: NSStatusItem?
    private var toggleItem: NSMenuItem?
    private var releasesURL: URL?
    private var readySeen = false

    init(options: Options) {
        self.options = options
        var path = options.savePath
        if path == nil, options.qa != nil {
            let dir = NSTemporaryDirectory() + "macpet-qa-\(UUID().uuidString)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            qaTempDir = dir
            atexit { if let d = qaTempDir { try? FileManager.default.removeItem(atPath: d) } }
            path = dir + "/save.json"
            print("[qa] 임시 저장소 사용: \(path!)")
        }
        self.save = SaveStore(path: path)
    }

    /// 시작할 수 없을 때. 저장 데이터는 건드리지 않고(컨트롤러를 만들기 전이다) 알린 뒤 끝낸다.
    private func abortLaunch(_ message: String) {
        FileHandle.standardError.write(Data("[pet] \(message)\n".utf8))
        if options.qa != nil { exit(2) }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "펫을 시작할 수 없어요"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var qaSteps: [[String: Any]]?
        if let path = options.qa {
            do { qaSteps = try QARunner.loadSteps(path: path) } catch { return abortLaunch("\(error)") }
        }

        let web: WebAssets
        switch locateWebAssets() {
        case .success(let w): web = w
        case .failure(let e): return abortLaunch(e.message)
        }
        print("[pet] web dir: \(web.dir.path)")

        // missions.json 은 한 번만 읽어 현재 OS 용으로 해석하고, 웹과 감지가 같은 결과를 쓴다
        let catalog: ResolvedCatalog
        do {
            catalog = try MissionCatalog.resolve(data: web.missionsData, os: .current)
        } catch let e as CatalogError {
            return abortLaunch("missions.json 에 문제가 있어요. 앱을 다시 설치해 주세요.\n\n\(e)")
        } catch {
            return abortLaunch("missions.json 을 해석하지 못했어요: \(error)")
        }

        let c = PetPanelController(webDir: web.dir, missionsData: catalog.webData, save: save, debug: options.debug,
                                    isolated: options.qa != nil)
        controller = c
        c.onReady = { [weak self] in self?.handleReady() }
        c.show()

        let w = MissionWatcher(missions: catalog.missions) { [weak c] id in
            c?.send(["type": "mission", "id": id])
        }
        w.logFileEvents = options.debug
        watcher = w
        // 감시는 웹이 저장하며 알리는 진행(부화 여부 + 끝낸 미션)에 맞춰 필요한 묶음만 켜진다.
        // 점검 스크립트를 돌릴 때는 실제 감지를 끈다 (점검 중 사용자의 복사·스크린샷 등이 끼어들지 않게)
        if options.qa == nil {
            c.onProgress = { [weak w] progress in w?.apply(progress) }
        }

        if let steps = qaSteps {
            qaRunner = QARunner(steps: steps, controller: c, saveURL: save.url)
            // 웹이 끝내 준비되지 않으면 멈춰 있지 말고 실패로 끝낸다
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard self?.readySeen == false else { return }
                print("[qa] FAIL 웹 화면이 20초 안에 준비되지 않음")
                exit(1)
            }
        }

        releasesURL = configuredReleasesURL()
        setupStatusItem()
    }

    /// Info.plist 의 MacPetReleasesURL. 없으면 메뉴 항목을 만들지 않는다. 있는데 올바르지 않으면 알리고 무시한다.
    private func configuredReleasesURL() -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MacPetReleasesURL") as? String else { return nil }
        if let url = validatedReleasesURL(raw) { return url }
        print("[pet] MacPetReleasesURL 이 https://github.com/OWNER/REPO/releases 모양이 아니라 무시함")
        return nil
    }

    private func handleReady() {
        readySeen = true
        if let id = options.simulate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.controller?.send(["type": "mission", "id": id])
            }
        }
        if let name = options.command {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.controller?.send(["type": "command", "name": name])
            }
        }
        if let runner = qaRunner {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { runner.run() }
        }
        if let json = options.point, let target = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.controller?.pointTest(target)
            }
        }
        for n in 0..<options.selfTap {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(n) * 0.7) { [weak self] in
                self?.controller?.selfTap()
            }
        }
        if let path = options.snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + options.snapshotDelay) { [weak self] in
                self?.controller?.snapshot(to: path)
            }
        }
    }

    // MARK: 웹 폴더 찾기

    private struct WebAssets { let dir: URL; let missionsData: Data }
    private struct LaunchError: Error { let message: String }

    /// 배포된 앱(.app)은 번들 안의 web 만 쓴다. 번들이 망가졌다고 해서 작업 폴더나 환경변수의 web 으로 조용히 넘어가지 않는다.
    /// 개발 중(swift run 등)에만 MACPET_WEB_DIR, 현재 폴더·실행 파일 위쪽의 web 을 찾는다.
    private func locateWebAssets() -> Result<WebAssets, LaunchError> {
        let fm = FileManager.default
        func has(_ dir: URL, _ file: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(file).path) }
        func assets(_ dir: URL) -> Result<WebAssets, LaunchError>? {
            guard has(dir, "index.html"), has(dir, "missions.json") else { return nil }
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("missions.json")) else { return nil }
            return .success(WebAssets(dir: dir, missionsData: data))
        }

        if Bundle.main.bundleURL.pathExtension == "app" {
            let res = Bundle.main.resourceURL?.appendingPathComponent("web")
            if let res, let ok = assets(res) { return ok }
            return .failure(LaunchError(message: "앱 안의 화면 파일(web/index.html, web/missions.json)을 찾을 수 없어요. 앱이 손상된 것 같아요. 다시 설치해 주세요."))
        }

        // 우선순위: MACPET_WEB_DIR → 현재 폴더와 그 위쪽 → 실행 파일 폴더와 그 위쪽. 찾는 즉시 돌려준다.
        if let env = ProcessInfo.processInfo.environment["MACPET_WEB_DIR"], !env.isEmpty,
           let ok = assets(URL(fileURLWithPath: env)) { return ok }
        let starts = [URL(fileURLWithPath: fm.currentDirectoryPath),
                      Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        for start in starts {
            var dir = start.standardizedFileURL
            while true {
                if let ok = assets(dir.appendingPathComponent("web")) { return ok }
                // 루트("/")나 빈 경로에서 분명히 멈춘다. 루트의 부모가 "/" 가 아니라 "/.." 로 나오는 Foundation 에서도
                // 끝없이 돌지 않게, 부모 경로가 실제로 짧아질 때만 올라간다.
                let path = dir.path
                if path.isEmpty || path == "/" { break }
                let parent = dir.deletingLastPathComponent().standardizedFileURL
                if parent.path.count >= path.count { break }
                dir = parent
            }
        }
        return .failure(LaunchError(message: "web 폴더(index.html, missions.json)를 찾을 수 없어요."))
    }

    // MARK: 메뉴 막대

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "펫") {
            item.button?.image = img
        } else {
            item.button?.title = "펫"
        }

        let menu = NSMenu()
        menu.delegate = self
        func add(_ title: String, _ action: Selector) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: "")
            m.target = self
            menu.addItem(m)
            return m
        }
        _ = add("미션 보기", #selector(showMissions))
        _ = add("펫 도감", #selector(showCollection))
        toggleItem = add("펫 숨기기", #selector(togglePet))
        if releasesURL != nil { _ = add("새 버전 보기…", #selector(openReleases)) }
        menu.addItem(.separator())
        _ = add("처음부터 다시 시작…", #selector(restartFromScratch))
        if options.debug { _ = add("개발: 다음 미션 완료 처리", #selector(devCompleteNext)) }
        menu.addItem(.separator())
        _ = add("종료", #selector(quit))
        item.menu = menu
        statusItem = item
        syncToggleTitle()
    }

    private func syncToggleTitle() {
        toggleItem?.title = (controller?.isVisible ?? false) ? "펫 숨기기" : "펫 보이기"
    }

    /// 창이 다른 경로로 보이거나 숨겨졌어도 메뉴를 열 때마다 실제 상태에 맞춘다.
    func menuNeedsUpdate(_ menu: NSMenu) { syncToggleTitle() }

    /// 펫이 숨겨져 있어도 보이게 한 뒤 미션 카드를 연다. showMissions 는 이미 열려 있어도 닫지 않는다(웹 쪽에서 멱등).
    @objc private func showMissions() {
        guard let c = controller else { return }
        c.show()
        c.send(["type": "command", "name": "showMissions"])
        syncToggleTitle()
    }

    /// 펫이 숨겨져 있어도 보이게 한 뒤 도감을 연다. 보이든 숨겨져 있었든 메뉴 제목은 실제 상태에 맞춘다.
    @objc private func showCollection() {
        guard let c = controller else { return }
        c.show()
        c.send(["type": "command", "name": "showCollection"])
        syncToggleTitle()
    }

    @objc private func togglePet() {
        guard let c = controller else { return }
        if c.isVisible { c.hide() } else { c.show() }
        syncToggleTitle()
    }

    @objc private func openReleases() {
        if let url = releasesURL { NSWorkspace.shared.open(url) }
    }

    @objc private func devCompleteNext() {
        guard options.debug else { return }
        controller?.send(["type": "command", "name": "devCompleteNext"])
    }

    /// 되돌릴 수 없는 초기화이므로 먼저 묻는다. 저장 데이터는 여기서 지우지 않고, 지우는 일은 웹이 기존 reset 명령으로 처리한다.
    @objc private func restartFromScratch() {
        guard let c = controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "처음부터 다시 시작할까요?"
        alert.informativeText = "지금까지 키운 펫과 끝낸 미션, 그리고 졸업한 펫을 모아 둔 도감까지 모두 지워지고, 되돌릴 수 없어요."
        alert.addButton(withTitle: "취소") // 기본 버튼
        let go = alert.addButton(withTitle: "모두 지우고 다시 시작")
        go.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        c.show()
        c.send(["type": "command", "name": "reset", "confirmed": true])
        syncToggleTitle()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
