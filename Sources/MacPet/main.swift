import AppKit

// 로그가 줄 단위로 바로 나오게
setvbuf(stdout, nil, _IOLBF, 0)

let options = Options(CommandLine.arguments)
let app = NSApplication.shared
// 평소에는 Dock 아이콘 없이 뜬다. --regular 는 점검용: 자동 조작 도구가 일반 앱만 찾을 수 있어서 일반 앱으로 띄운다.
app.setActivationPolicy(options.regular ? .regular : .accessory)
let delegate = AppDelegate(options: options)
app.delegate = delegate
app.run()
