import AppKit
import MacPetCore

/// 펫 창의 자리를 정하고, 마우스로 끌어 옮기며, 옮긴 자리를 기억한다.
final class PanelMover {
    private let panel: NSPanel
    private let save: SaveStore
    private var timer: Timer?
    private var grab = NSPoint.zero // 창 왼쪽 아래에서 잡은 곳까지의 거리

    init(panel: NSPanel, save: SaveStore) {
        self.panel = panel
        self.save = save
    }

    /// 기억해 둔 자리가 있으면 거기(화면 안으로 보정), 없으면 주 화면 오른쪽 아래.
    func place() {
        if let origin = savedOrigin() {
            let f = NSRect(origin: origin, size: panel.frame.size)
            if let screen = NSScreen.screens.first(where: { $0.frame.intersects(f) }) {
                panel.setFrame(clampFrame(f, into: screen.visibleFrame), display: true)
                return
            }
        }
        guard let vf = NSScreen.main?.visibleFrame else { return }
        let s = panel.frame.size
        panel.setFrame(NSRect(x: vf.maxX - s.width, y: vf.minY, width: s.width, height: s.height), display: true)
    }

    /// 마우스 버튼을 뗄 때까지 창이 마우스를 따라간다.
    func beginDrag() {
        guard timer == nil, NSEvent.pressedMouseButtons & 1 != 0 else { return }
        let m = NSEvent.mouseLocation
        grab = NSPoint(x: m.x - panel.frame.minX, y: m.y - panel.frame.minY)
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.follow() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func follow() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { endDrag(); return }
        let m = NSEvent.mouseLocation
        var f = NSRect(x: m.x - grab.x, y: m.y - grab.y, width: panel.frame.width, height: panel.frame.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(m) }) ?? NSScreen.main {
            f = clampFrame(f, into: screen.visibleFrame)
        }
        if f.origin != panel.frame.origin { panel.setFrameOrigin(f.origin) }
    }

    private func endDrag() {
        timer?.invalidate()
        timer = nil
        let o = panel.frame.origin
        save.writePanelOrigin("\(Int(o.x)),\(Int(o.y))")
    }

    private func savedOrigin() -> NSPoint? {
        guard let s = save.loadPanelOrigin() else { return nil }
        let p = s.split(separator: ",").compactMap { Double($0) }
        return p.count == 2 ? NSPoint(x: p[0], y: p[1]) : nil
    }
}
