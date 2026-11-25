import CoreGraphics
import XCTest
@testable import MacPetCore

final class PointGeometryTests: XCTestCase {
    func testPointTargetFromDictionary() {
        let t = PointTarget(["app": "com.apple.systempreferences", "label": " 핫 코너... ", "role": "AXButton"])
        XCTAssertEqual(t?.app, "com.apple.systempreferences")
        XCTAssertEqual(t?.label, "핫 코너…") // 점 세 개는 말줄임표로, 공백은 떼고
        XCTAssertEqual(t?.role, "AXButton")
        XCTAssertEqual(t?.area, .window)
        XCTAssertNil(t?.window)

        let m = PointTarget(["app": "com.apple.finder", "in": "menubar", "label": "보기"])
        XCTAssertEqual(m?.area, .menubar)
        XCTAssertEqual(PointTarget(["app": "com.apple.dock", "in": "dock", "label": "Finder"])?.area, .dock)
        XCTAssertEqual(PointTarget(["app": "a", "in": "어딘가", "label": "b"])?.area, .window) // 모르는 값은 window

        XCTAssertNil(PointTarget(["app": "com.apple.finder"]))
        XCTAssertNil(PointTarget(["label": "보기"]))
        XCTAssertNil(PointTarget(["app": "", "label": "보기"]))
    }

    // 값은 macOS 27.2 시스템 설정에서 실제로 읽은 위치
    func testVisibleFrame() {
        let window = CGRect(x: 1468, y: 654, width: 740, height: 625)
        XCTAssertTrue(isVisibleFrame(CGRect(x: 1730, y: 994, width: 154, height: 16), in: window))
        XCTAssertFalse(isVisibleFrame(CGRect(x: 2084, y: 2259, width: 72, height: 24), in: window)) // 스크롤 아래
        XCTAssertFalse(isVisibleFrame(CGRect(x: 0, y: 1440, width: 0, height: 0), in: nil))        // 닫힌 메뉴의 항목
        XCTAssertTrue(isVisibleFrame(CGRect(x: 189, y: 0, width: 44, height: 30), in: nil))
    }

    func testAppKitRect() {
        // 높이 1440 화면에서 맨 위 메뉴 막대 항목
        XCTAssertEqual(appKitRect(fromAX: CGRect(x: 189, y: 0, width: 44, height: 30), primaryScreenHeight: 1440),
                       CGRect(x: 189, y: 1410, width: 44, height: 30))
        // 왼쪽 보조 화면(음수 x)도 x 는 그대로
        XCTAssertEqual(appKitRect(fromAX: CGRect(x: -2000, y: 100, width: 10, height: 20), primaryScreenHeight: 1440),
                       CGRect(x: -2000, y: 1320, width: 10, height: 20))
    }

    func testPointerLayout() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        // 화면 가운데: 화살표는 위
        let a = pointerLayout(target: CGRect(x: 1000, y: 500, width: 100, height: 20), screen: screen, margin: 6, arrow: 44, minWidth: 44)
        XCTAssertFalse(a.arrowBelow)
        XCTAssertEqual(a.windowFrame, CGRect(x: 994, y: 494, width: 112, height: 76))
        // 화면 맨 위(메뉴 막대): 위에 자리가 없으니 화살표는 아래
        let b = pointerLayout(target: CGRect(x: 189, y: 1410, width: 44, height: 30), screen: screen, margin: 6, arrow: 44, minWidth: 44)
        XCTAssertTrue(b.arrowBelow)
        XCTAssertEqual(b.windowFrame, CGRect(x: 183, y: 1360, width: 56, height: 86))
        // 좁은 대상: 화살표 폭만큼 가운데 기준으로 넓힌다
        let c = pointerLayout(target: CGRect(x: 100, y: 100, width: 10, height: 10), screen: screen, margin: 6, arrow: 44, minWidth: 44)
        XCTAssertEqual(c.windowFrame, CGRect(x: 83, y: 94, width: 44, height: 66))
    }

    func testClampFrame() {
        let bounds = CGRect(x: 0, y: 0, width: 2503, height: 1410)
        let size = CGSize(width: 400, height: 560)
        XCTAssertEqual(clampFrame(CGRect(origin: CGPoint(x: 100, y: 100), size: size), into: bounds).origin, CGPoint(x: 100, y: 100))
        XCTAssertEqual(clampFrame(CGRect(origin: CGPoint(x: 2400, y: -50), size: size), into: bounds).origin, CGPoint(x: 2103, y: 0))
        XCTAssertEqual(clampFrame(CGRect(origin: CGPoint(x: -300, y: 1200), size: size), into: bounds).origin, CGPoint(x: 0, y: 850))
    }
}
