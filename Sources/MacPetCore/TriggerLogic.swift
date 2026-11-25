import Foundation

/// defaults 값을 비교용 정규 문자열로. 불리언 "1"/"0", 정수는 정수 문자열, 문자열은 그대로, 나머지는 nil.
public func canonicalDefaultsValue(_ v: Any?) -> String? {
    if let s = v as? String { return s }
    guard let n = v as? NSNumber else { return nil }
    if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "1" : "0" }
    switch CFNumberGetType(n) {
    case .floatType, .float32Type, .float64Type, .doubleType, .cgFloatType:
        return n.stringValue
    default:
        return String(n.int64Value)
    }
}

/// 값이 바뀌었고, 새 값이 nil 이 아니며 무시 목록에 없고, to 가 있으면 그 값과 같을 때 true.
public func defaultsChangeFired(old: [String: String?], new: [String: String?], ignoreValues: [String], to: String?) -> Bool {
    for key in Set(old.keys).union(new.keys) {
        let o: String? = old[key] ?? nil
        let n: String? = new[key] ?? nil
        if o != n, let n = n, !ignoreValues.contains(n), to == nil || to == n { return true }
    }
    return false
}

/// 손쉬운 사용 플래그가 목표 값으로 바뀌었는지.
public func accessibilityFired(old: Bool, new: Bool, to: Bool) -> Bool {
    old != new && new == to
}

public struct HitRect: Equatable {
    public var x, y, w, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// 점이 (padding 만큼 넓힌) 사각형 중 하나 안에 있는지.
public func hitTest(x: Double, y: Double, rects: [HitRect], padding: Double) -> Bool {
    rects.contains { r in
        x >= r.x - padding && x <= r.x + r.w + padding &&
        y >= r.y - padding && y <= r.y + r.h + padding
    }
}

/// 스크린샷 폴더의 파일 변경 알림이 "새 그림 파일이 생김"인지. flags 는 FSEvents 플래그 값.
/// 파일을 열어 보지 않고 판정한다(데스크탑 접근 권한 없이 쓰려고).
public func isScreenshotFileEvent(ext: String, flags: Int) -> Bool {
    let created = 0x100, removed = 0x200, renamed = 0x800, isFile = 0x10000
    let images: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "pdf"]
    guard images.contains(ext.lowercased()), flags & isFile != 0, flags & removed == 0 else { return false }
    return flags & (created | renamed) != 0
}

/// 시스템 설정 URL 만 허용.
public func isAllowedSettingsURL(_ s: String) -> Bool {
    s.hasPrefix("x-apple.systempreferences:")
}
