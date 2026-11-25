import XCTest
@testable import MacPetCore

final class ResumableWalkTests: XCTestCase {
    /// 노드 n 의 자식은 n*fanout+1 ... n*fanout+fanout (0 이 뿌리인 완전 트리).
    private func kids(_ n: Int, fanout: Int) -> [Int] { (1...fanout).map { n * fanout + $0 } }

    /// 호출마다 `perSlice` 개만 방문하게 하며 끝까지 돌린다. 방문 순서와 호출 횟수를 돌려준다.
    private func run(_ walk: inout ResumableWalk<Int>, perSlice: Int, fanout: Int, target: Int?,
                     maxSlices: Int = 10_000) -> (order: [Int], slices: Int, found: Int?) {
        var order: [Int] = []
        for slice in 1...maxSlices {
            var n = 0
            let out = walk.resume(shouldPause: { n >= perSlice }) { node, canExpand in
                n += 1
                order.append(node)
                if node == target { return .match }
                return .expand(canExpand ? kids(node, fanout: fanout) : [])
            }
            switch out {
            case .found(let f): return (order, slice, f)
            case .exhausted: return (order, slice, nil)
            case .paused: continue
            }
        }
        XCTFail("끝나지 않았다")
        return (order, maxSlices, nil)
    }

    func testResumesWhereItStoppedInsteadOfRestarting() {
        // 한 번에 3개씩만 훑어도 깊은 노드까지 닿고, 같은 노드를 두 번 방문하지 않는다
        var walk = ResumableWalk(starts: [0], maxVisit: 1500, maxDepth: 14)
        let r = run(&walk, perSlice: 3, fanout: 3, target: 100)
        XCTAssertEqual(r.found, 100)
        XCTAssertEqual(r.order, Array(0...100)) // 너비 우선 순서 그대로, 중복 없이
        XCTAssertEqual(r.slices, 34)            // 101개를 3개씩
    }

    func testSameOrderAsOneShotWalk() {
        var whole = ResumableWalk(starts: [0], maxVisit: 200, maxDepth: 14)
        var sliced = ResumableWalk(starts: [0], maxVisit: 200, maxDepth: 14)
        let a = run(&whole, perSlice: .max, fanout: 4, target: nil)
        let b = run(&sliced, perSlice: 1, fanout: 4, target: nil)
        XCTAssertEqual(a.slices, 1)
        XCTAssertEqual(a.order, b.order)
    }

    func testVisitBoundAndRetainedNodesBound() {
        var walk = ResumableWalk(starts: [0], maxVisit: 50, maxDepth: 14)
        var seen = 0
        var out = ResumableWalk<Int>.Outcome.paused
        while case .paused = out {
            var n = 0
            out = walk.resume(shouldPause: { n >= 7 }) { node, _ in
                n += 1; seen += 1
                return .expand(self.kids(node, fanout: 10))
            }
            XCTAssertLessThanOrEqual(walk.visited + walk.pendingCount, 50) // 방문 못 할 노드는 들고 있지 않는다
        }
        guard case .exhausted = out else { return XCTFail() }
        XCTAssertEqual(seen, 50)
        XCTAssertEqual(walk.visited, 50)
        XCTAssertTrue(walk.isExhausted)
    }

    func testDepthBound() {
        // 깊이 2까지만: 1 + 2 + 4 = 7개. 깊이 한도의 노드는 canExpand 가 false 다
        var walk = ResumableWalk(starts: [0], maxVisit: 1500, maxDepth: 2)
        var leavesAsked = 0
        let out = walk.resume(shouldPause: { false }) { node, canExpand in
            if !canExpand { leavesAsked += 1 }
            return .expand(self.kids(node, fanout: 2)) // 한도에서 자식을 돌려줘도 무시된다
        }
        guard case .exhausted = out else { return XCTFail() }
        XCTAssertEqual(walk.visited, 7)
        XCTAssertEqual(leavesAsked, 4)
    }

    func testAlwaysVisitsAtLeastOneNodePerCall() {
        // 시간이 이미 다 됐어도 호출마다 한 노드는 나아간다
        var walk = ResumableWalk(starts: [0], maxVisit: 1500, maxDepth: 14)
        let r = run(&walk, perSlice: 0, fanout: 2, target: 6)
        XCTAssertEqual(r.found, 6)
        XCTAssertEqual(r.slices, 7)
    }

    func testRetryKeepsNodeThenSkipsAfterLimit() {
        var walk = ResumableWalk(starts: [0], maxVisit: 1500, maxDepth: 14, maxRetries: 2)
        var failuresLeft = 2
        var order: [Int] = []
        let visit: (Int, Bool) -> ResumableWalk<Int>.Step = { node, _ in
            order.append(node)
            if node == 1, failuresLeft > 0 { failuresLeft -= 1; return .retry }
            return node == 4 ? .match : .expand(node < 2 ? self.kids(node, fanout: 2) : [])
        }
        // 못 읽으면 그 자리에서 멈추고, 다음 호출에서 같은 노드부터 다시 읽는다
        guard case .paused = walk.resume(shouldPause: { false }, visit: visit) else { return XCTFail() }
        guard case .paused = walk.resume(shouldPause: { false }, visit: visit) else { return XCTFail() }
        guard case .found(4) = walk.resume(shouldPause: { false }, visit: visit) else { return XCTFail() }
        XCTAssertEqual(order, [0, 1, 1, 1, 2, 3, 4]) // 1의 자식(3, 4)을 잃지 않았다

        // 끝내 못 읽는 노드는 한도 뒤에 건너뛰고 나머지를 마저 훑는다
        var stuck = ResumableWalk(starts: [0, 1], maxVisit: 1500, maxDepth: 14, maxRetries: 2)
        var calls = 0
        var out = ResumableWalk<Int>.Outcome.paused
        while case .paused = out {
            calls += 1
            out = stuck.resume(shouldPause: { false }) { node, _ in node == 0 ? .retry : .expand([]) }
        }
        guard case .exhausted = out else { return XCTFail() }
        XCTAssertEqual(calls, 4) // 0을 세 번 시도하고 건너뛴 뒤, 1을 훑고 끝
        XCTAssertEqual(stuck.visited, 2)
    }

    func testEmptyStartsIsExhausted() {
        var walk = ResumableWalk<Int>(starts: [], maxVisit: 1500, maxDepth: 14)
        guard case .exhausted = walk.resume(shouldPause: { false }, visit: { _, _ in .expand([]) }) else { return XCTFail() }
    }
}
