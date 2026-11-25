import Foundation

/// 웹뷰가 열어도 되는 주소인지: 번들(또는 개발 중 web 폴더) 안의 파일 URL 만 허용한다.
/// 심볼릭 링크·`..` 는 풀어서 비교하고, 폴더 이름만 같은 이웃(`web-evil`)은 통과시키지 않는다.
public func isBundledFileURL(_ url: URL?, root: URL) -> Bool {
    guard let url = url, url.isFileURL else { return false }
    let base = root.resolvingSymlinksInPath().standardizedFileURL.path
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    let prefix = base.hasSuffix("/") ? base : base + "/"
    return path.hasPrefix(prefix)
}

/// 웹뷰가 열어도 되는 유일한 주소: 번들(또는 개발 중 web 폴더) 바로 아래의 `index.html` 하나.
/// 로컬 파일 URL(호스트 없음/localhost)만, 다른 파일·하위 폴더·`..`·이웃 폴더는 거부한다.
/// 심볼릭 링크는 풀어서 비교하므로 루트 밖을 가리키는 `index.html` 링크도 거부한다.
public func isBundledIndexURL(_ url: URL?, root: URL) -> Bool {
    guard let url = url, url.isFileURL else { return false }
    if let host = url.host, !host.isEmpty, host.lowercased() != "localhost" { return false }
    let index = root.appendingPathComponent("index.html")
    guard isBundledFileURL(index, root: root) else { return false } // 루트 밖으로 향하는 링크
    let expected = index.resolvingSymlinksInPath().standardizedFileURL.path
    return url.resolvingSymlinksInPath().standardizedFileURL.path == expected
}

/// 시스템 설정 링크를 열지 못했을 때 보여 줄 손으로 찾아가는 방법.
public func settingsFallbackInstructions(for settingsURL: String) -> String {
    let route: String
    if settingsURL.contains("Privacy_Accessibility") {
        route = "개인정보 보호 및 보안 → 손쉬운 사용"
    } else if settingsURL.contains("Accessibility-Settings") {
        route = "손쉬운 사용 → " + (settingsURL.contains("Motion") ? "동작" : "디스플레이")
    } else if settingsURL.contains("Appearance-Settings") {
        route = "외관"
    } else if settingsURL.contains("Desktop-Settings") {
        route = "데스크탑 및 Dock"
    } else {
        route = "필요한 항목"
    }
    return "시스템 설정 앱을 직접 열고 왼쪽 목록에서 ‘\(route)’을(를) 찾아 주세요."
}
