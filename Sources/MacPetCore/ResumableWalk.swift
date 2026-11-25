import Foundation

/// 여러 번에 나눠 이어 가는 너비 우선 탐색의 남은 일.
/// 한 번에 다 못 훑으면 멈춘 자리를 기억했다가 다음 호출에서 이어서 훑는다(처음부터 다시 훑지 않는다).
/// 들고 있는 노드는 아직 방문하지 않은 것뿐이고, 그 수는 `maxVisit - visited` 를 넘지 않는다.
public struct ResumableWalk<Node> {
    /// 노드 하나를 방문한 결과.
    public enum Step {
        case match            // 찾았다. 탐색 끝
        case expand([Node])   // 아니다. 자식을 뒤에 줄 세운다(없으면 빈 배열)
        case retry            // 이번에는 읽지 못했다. 자리를 지켰다가 다음 호출에서 다시 읽는다
    }

    public enum Outcome {
        case found(Node)
        case paused      // 남은 노드가 있다. 다음 호출에서 이어 간다
        case exhausted   // 한도 안에서 다 훑었고 없었다
    }

    public let maxVisit: Int
    public let maxDepth: Int
    public let maxRetries: Int // 같은 노드를 이만큼 다시 읽어도 안 되면 건너뛴다
    public private(set) var visited = 0

    private var pending: [(node: Node, depth: Int)]
    private var retries = 0

    public init(starts: [Node], maxVisit: Int, maxDepth: Int, maxRetries: Int = 2) {
        self.maxVisit = maxVisit
        self.maxDepth = maxDepth
        self.maxRetries = maxRetries
        pending = starts.prefix(max(0, maxVisit)).map { ($0, 0) }
    }

    public var pendingCount: Int { pending.count }
    public var isExhausted: Bool { pending.isEmpty }

    /// 멈춘 자리부터 이어서 훑는다. `shouldPause` 는 노드 사이에서만 묻고, 호출마다 적어도 한 노드는 방문한다
    /// (그래야 아무리 느려도 조금씩은 나아간다). `canExpand` 가 false 면 깊이 한도라 자식을 읽을 필요가 없다.
    public mutating func resume(shouldPause: () -> Bool, visit: (_ node: Node, _ canExpand: Bool) -> Step) -> Outcome {
        var head = 0
        defer { pending.removeFirst(head) } // 방문을 마친 노드는 놓아 준다
        while head < pending.count {
            if head > 0, shouldPause() { return .paused }
            let (node, depth) = pending[head]
            let canExpand = depth < maxDepth
            switch visit(node, canExpand) {
            case .match:
                head = pending.count
                return .found(node)
            case .retry:
                retries += 1
                if retries <= maxRetries { return .paused }
                retries = 0
                head += 1
                visited += 1
                return head < pending.count ? .paused : .exhausted
            case .expand(let kids):
                retries = 0
                head += 1
                visited += 1
                if canExpand {
                    // 방문 한도를 넘겨 줄 선 노드는 어차피 방문하지 못한다. 들고 있지 않는다
                    let room = maxVisit - visited - (pending.count - head)
                    if room > 0 { for k in kids.prefix(room) { pending.append((k, depth + 1)) } }
                }
            }
        }
        return .exhausted
    }
}
