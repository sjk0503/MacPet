import CoreGraphics
import Foundation

/// 화면에서 가리킬 대상. missions.json 의 단계에 붙는 `point` 객체와 같은 모양이다.
public struct PointTarget: Equatable {
    public enum Area: String { case window, menubar, dock }

    public var app: String      // 대상 앱의 번들 ID
    public var label: String    // 요소의 이름(제목·설명·값 중 하나와 같아야 한다)
    public var role: String?    // 있으면 이 역할의 요소만 (예: AXButton)
    public var area: Area       // 어디서 찾을지 (JSON 의 "in", 없으면 window)
    public var window: String?  // 있으면 앞 창의 제목이 이것일 때만

    public init?(_ d: [String: Any]) {
        guard let app = d["app"] as? String, !app.isEmpty,
              let label = d["label"] as? String, !label.isEmpty else { return nil }
        self.app = app
        self.label = normalizeLabel(label)
        self.role = d["role"] as? String
        self.area = (d["in"] as? String).flatMap(Area.init(rawValue:)) ?? .window
        self.window = (d["window"] as? String).map(normalizeLabel)
    }
}

/// 이름 비교용 정규화: 앞뒤 공백을 떼고 점 세 개를 말줄임표 한 글자로.
public func normalizeLabel(_ s: String) -> String {
    s.replacingOccurrences(of: "...", with: "…").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 요소가 실제로 보이는 자리에 있는지: 크기가 있고, (container 가 있으면) 가운데가 그 안에 있어야 한다.
/// 스크롤해야 나오는 요소는 창 밖 좌표를 돌려주므로 여기서 걸러진다.
public func isVisibleFrame(_ f: CGRect, in container: CGRect?) -> Bool {
    guard f.width >= 2, f.height >= 2 else { return false }
    guard let c = container else { return true }
    return c.contains(CGPoint(x: f.midX, y: f.midY))
}

/// 손쉬운 사용 좌표(주 화면 왼쪽 위가 원점, 아래로 증가) → AppKit 화면 좌표(주 화면 왼쪽 아래가 원점, 위로 증가).
public func appKitRect(fromAX r: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
    CGRect(x: r.minX, y: primaryScreenHeight - r.maxY, width: r.width, height: r.height)
}

/// 표시 창의 자리. 대상에 여백을 두르고 화살표 자리를 위에 더한다. 위로 화면을 벗어나면 화살표를 아래에 둔다.
public struct PointerLayout: Equatable {
    public var windowFrame: CGRect  // AppKit 화면 좌표
    public var arrowBelow: Bool
}

public func pointerLayout(target: CGRect, screen: CGRect, margin: CGFloat, arrow: CGFloat, minWidth: CGFloat) -> PointerLayout {
    var box = target.insetBy(dx: -margin, dy: -margin)
    if box.width < minWidth { box = box.insetBy(dx: -(minWidth - box.width) / 2, dy: 0) } // 화살표가 잘리지 않게
    let below = box.maxY + arrow > screen.maxY
    let frame = CGRect(x: box.minX, y: below ? box.minY - arrow : box.minY,
                       width: box.width, height: box.height + arrow)
    return PointerLayout(windowFrame: frame, arrowBelow: below)
}

/// 창을 bounds 안으로 밀어 넣는다(크기는 그대로). 창이 더 크면 왼쪽 아래를 맞춘다.
public func clampFrame(_ frame: CGRect, into bounds: CGRect) -> CGRect {
    var f = frame
    f.origin.x = max(bounds.minX, min(f.minX, bounds.maxX - f.width))
    f.origin.y = max(bounds.minY, min(f.minY, bounds.maxY - f.height))
    return f
}
