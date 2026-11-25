import Foundation

/// Info.plist 의 MacPetReleasesURL 값을 검증한다. `https://github.com/OWNER/REPO/releases` 모양만 허용
/// (경로 끝 `/` 하나는 허용). 계정 정보·포트·쿼리·프래그먼트가 있거나 다른 호스트면 nil.
public func validatedReleasesURL(_ s: String?) -> URL? {
    guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
          let c = URLComponents(string: s),
          c.scheme == "https", c.host == "github.com",
          c.user == nil, c.password == nil, c.port == nil, c.query == nil, c.fragment == nil else { return nil }
    var parts = c.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if parts.count == 5, parts[4].isEmpty { parts.removeLast() }
    let name = try! NSRegularExpression(pattern: "^[A-Za-z0-9](?:[A-Za-z0-9._-]*)$")
    func valid(_ p: String) -> Bool {
        p != "." && p != ".." && name.firstMatch(in: p, range: NSRange(p.startIndex..., in: p)) != nil
    }
    guard parts.count == 4, parts[0].isEmpty, valid(parts[1]), valid(parts[2]), parts[3] == "releases" else { return nil }
    return c.url
}
