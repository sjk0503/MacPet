import AppKit
import ApplicationServices
import MacPetCore

/// 대상 둘레의 도트 테두리와, 대상을 가리키는 도트 화살표를 그린다.
final class PointerView: NSView {
    static let margin: CGFloat = 6       // 대상과 테두리 사이 (테두리 두께와 같다)
    static let arrowSpace: CGFloat = 44  // 화살표가 차지하는 높이
    static let minWidth: CGFloat = 44

    var arrowBelow = false { didSet { if oldValue != arrowBelow { needsDisplay = true } } }
    var bob: CGFloat = 0 { didSet { if oldValue != bob { needsDisplay = true } } }

    private let ink = NSColor(srgbRed: 0x3d / 255.0, green: 0x2c / 255.0, blue: 0x35 / 255.0, alpha: 1)
    private let orange = NSColor(srgbRed: 0xf8 / 255.0, green: 0xa2 / 255.0, blue: 0x4f / 255.0, alpha: 1)
    // 아래를 가리키는 화살표 (o = 칠하는 칸)
    private let arrow = ["..ooo..", "..ooo..", "..ooo..", "ooooooo", ".ooooo.", "..ooo..", "...o..."]
    private let cell: CGFloat = 4

    override func draw(_ dirtyRect: NSRect) {
        let a = Self.arrowSpace
        // 화살표 자리를 뺀 나머지가 대상 상자
        let box = NSRect(x: 0, y: arrowBelow ? a : 0, width: bounds.width, height: bounds.height - a)
        drawBorder(box)
        drawArrow(areaY: arrowBelow ? 0 : box.maxY)
    }

    /// 바깥 3px 잉크, 안쪽 3px 귤색. 모서리 한 칸을 비워 도트처럼 깎는다.
    private func drawBorder(_ b: NSRect) {
        let t: CGFloat = 3
        ink.setFill()
        [NSRect(x: b.minX + t, y: b.maxY - t, width: b.width - 2 * t, height: t),
         NSRect(x: b.minX + t, y: b.minY, width: b.width - 2 * t, height: t),
         NSRect(x: b.minX, y: b.minY + t, width: t, height: b.height - 2 * t),
         NSRect(x: b.maxX - t, y: b.minY + t, width: t, height: b.height - 2 * t)].forEach { $0.fill() }
        orange.setFill()
        [NSRect(x: b.minX + t, y: b.maxY - 2 * t, width: b.width - 2 * t, height: t),
         NSRect(x: b.minX + t, y: b.minY + t, width: b.width - 2 * t, height: t),
         NSRect(x: b.minX + t, y: b.minY + 2 * t, width: t, height: b.height - 4 * t),
         NSRect(x: b.maxX - 2 * t, y: b.minY + 2 * t, width: t, height: b.height - 4 * t)].forEach { $0.fill() }
    }

    /// 화살표를 칸 단위로 찍고, 빈 칸 중 칠한 칸과 맞닿은 곳에 잉크 외곽선을 두른다.
    private func drawArrow(areaY: CGFloat) {
        let rows = arrowBelow ? Array(arrow.reversed()) : arrow // 아래에 있을 때는 위를 가리킨다
        let h = rows.count, w = rows[0].count
        func filled(_ x: Int, _ y: Int) -> Bool {
            guard y >= 0, y < h, x >= 0, x < w else { return false }
            return Array(rows[y])[x] == "o"
        }
        let size = CGFloat(w + 2) * cell // 외곽선 한 칸씩 포함
        let originX = ((bounds.width - size) / 2).rounded()
        // 대상에서 4px 띄우고, bob 만큼 대상에서 멀어진다
        let originY = arrowBelow ? areaY + Self.arrowSpace - 4 - size - bob : areaY + 4 + bob
        for y in -1...h {
            for x in -1...w {
                let on = filled(x, y)
                let edge = !on && (filled(x - 1, y) || filled(x + 1, y) || filled(x, y - 1) || filled(x, y + 1))
                guard on || edge else { continue }
                (on ? orange : ink).setFill()
                // 행 0 이 맨 위 (뷰는 아래가 원점)
                NSRect(x: originX + CGFloat(x + 1) * cell, y: originY + CGFloat(h - y) * cell, width: cell, height: cell).fill()
            }
        }
    }
}

/// 다른 앱 화면 위에 뜨는 표시 창. 클릭은 전부 통과시킨다.
final class PointerOverlay {
    private let window: NSWindow
    private let view = PointerView()
    private var bobTimer: Timer?

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        // 열린 메뉴의 항목도 가리킬 수 있게 메뉴보다 한 단계 위
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = view
    }

    var isShown: Bool { window.isVisible }

    /// target 은 AppKit 화면 좌표.
    func show(at target: CGRect) {
        // 숨은 Dock도 아이콘 좌표를 돌려준다. 다시 화면에 들어오면 다음 조회 때 표시한다.
        guard let screen = NSScreen.screens.first(where: { isVisibleFrame(target, in: $0.frame) }) else {
            hide()
            return
        }
        let layout = pointerLayout(target: target, screen: screen.frame, margin: PointerView.margin,
                                   arrow: PointerView.arrowSpace, minWidth: PointerView.minWidth)
        view.arrowBelow = layout.arrowBelow
        if window.frame != layout.windowFrame { window.setFrame(layout.windowFrame, display: true) }
        if !window.isVisible {
            window.orderFrontRegardless()
            startBob()
        }
    }

    func hide() {
        guard window.isVisible else { return }
        window.orderOut(nil)
        bobTimer?.invalidate()
        bobTimer = nil
    }

    /// 화살표가 두 칸 사이를 오가며 까딱인다. '동작 줄이기'가 켜져 있으면 가만히 둔다.
    private func startBob() {
        view.bob = 0
        guard bobTimer == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            guard let v = self?.view else { return }
            v.bob = v.bob == 0 ? 4 : 0
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        bobTimer = t
    }
}

/// 가리킬 대상을 받아 주기적으로 위치를 다시 읽고 표시 창을 옮긴다.
/// 위치 읽기는 다른 앱에 묻는 일이라 느릴 수 있어 별도 큐에서 한다.
/// 쉬는 동안에는 아무것도 하지 않는다: 대상이 없거나, 일시정지(펫이 숨겨짐)거나, 손쉬운 사용 권한이 없으면 타이머가 없다.
final class PointerController {
    private let finder = ElementFinder() // queue 에서만 쓴다
    private let overlay = PointerOverlay()
    private let queue = DispatchQueue(label: "macpet.pointer")
    private var target: PointTarget?
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var busy = false
    private var generation = 0
    private var paused = false
    private var misses = 0 // 연속으로 못 찾은 횟수. 많으면 더 느리게 확인한다
    private var activationObserver: NSObjectProtocol?
    private var accessToken: Int?
    var log = false

    private let fastInterval: TimeInterval = 0.4
    private let slowInterval: TimeInterval = 1.2

    deinit {
        timer?.invalidate()
        if let o = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let t = accessToken { AccessibilityAccess.shared.removeObserver(t) }
    }

    func setTarget(_ dict: [String: Any]?) {
        let t = dict.flatMap { PointTarget($0) }
        guard t != target else { return }
        target = t
        generation += 1
        misses = 0
        queue.async { [finder] in finder.reset() }
        guard t != nil else {
            stopTimer()
            removeObservers()
            setShown(nil)
            return
        }
        resumeIfNeeded()
    }

    /// 펫이 숨겨진 동안은 위치 읽기와 표시를 멈춘다. 대상은 기억해 두었다가 다시 보이면 이어서 가리킨다.
    func setPaused(_ p: Bool) {
        guard p != paused else { return }
        paused = p
        generation += 1 // 날아가는 중인 결과를 버린다
        if p {
            stopTimer()
            setShown(nil)
        } else {
            misses = 0
            resumeIfNeeded()
        }
    }

    private func resumeIfNeeded() {
        guard target != nil, !paused else { return }
        installObservers()
        guard AXIsProcessTrusted() else { setShown(nil); return } // 권한이 생기면 관찰자가 깨운다
        schedule(fastInterval)
        tick()
    }

    private func installObservers() {
        if activationObserver == nil {
            // 앞에 나온 앱이 바뀌면 바로 다시 찾는다(느린 확인 주기를 기다리지 않게)
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self = self, self.target != nil, !self.paused else { return }
                self.misses = 0
                self.schedule(self.fastInterval)
                self.tick()
            }
        }
        if accessToken == nil {
            AccessibilityAccess.shared.start()
            accessToken = AccessibilityAccess.shared.addObserver { [weak self] _ in
                guard let self = self else { return }
                self.misses = 0
                self.resumeIfNeeded()
            }
        }
    }

    private func removeObservers() {
        if let o = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        activationObserver = nil
        if let t = accessToken { AccessibilityAccess.shared.removeObserver(t) }
        accessToken = nil
    }

    private func schedule(_ interval: TimeInterval) {
        if timer != nil, timerInterval == interval { return }
        timer?.invalidate()
        let tm = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        tm.tolerance = interval * 0.25
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
        timerInterval = interval
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerInterval = 0
    }

    private func tick() {
        guard let t = target, !paused, !busy else { return }
        guard AXIsProcessTrusted() else { stopTimer(); setShown(nil); return }
        busy = true
        let gen = generation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        queue.async { [weak self] in
            guard let self = self else { return }
            let found = self.finder.locate(t)
            DispatchQueue.main.async {
                self.busy = false
                guard gen == self.generation else { return }
                self.misses = found == nil ? self.misses + 1 : 0
                if self.target != nil, !self.paused { self.schedule(self.misses >= 5 ? self.slowInterval : self.fastInterval) }
                self.setShown(found.map { appKitRect(fromAX: $0, primaryScreenHeight: primaryHeight) })
            }
        }
    }

    private func setShown(_ rect: CGRect?) {
        let was = overlay.isShown
        if let r = rect { overlay.show(at: r) } else { overlay.hide() }
        guard log, was != overlay.isShown else { return }
        if overlay.isShown, let r = rect { print("[point] shown x=\(Int(r.minX)) y=\(Int(r.minY)) w=\(Int(r.width)) h=\(Int(r.height))") }
        else { print("[point] hidden") }
    }
}
