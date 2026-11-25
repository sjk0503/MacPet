// 개인정보 규칙: 이 감시자는 키 입력을 "미션 단축키와 일치하는지"만 본다.
// 일치하지 않는 키 입력은 그 자리에서 버린다. 어떤 키 코드·글자도 변수에 쌓거나,
// 로그로 찍거나, 다른 곳으로 넘기지 않는다. 일치했을 때도 로그에는 미션 id 만 남긴다.
import AppKit
import CoreGraphics
import Foundation
import MacPetCore

final class ShortcutWatcher {
    private let shortcuts: [(id: String, shortcut: Shortcut)]
    private let onFire: (String) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var monitor: Any? // 이벤트 탭을 못 만들 때 쓰는 대체 경로(NSEvent 전역 감시)

    init(shortcuts: [(id: String, shortcut: Shortcut)], onFire: @escaping (String) -> Void) {
        self.shortcuts = shortcuts
        self.onFire = onFire
    }

    deinit { stop() }

    func start() -> Bool {
        guard tap == nil, monitor == nil else { return true }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let cb: CGEventTapCallBack = { _, type, event, info in
            guard let info = info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<ShortcutWatcher>.fromOpaque(info).takeUnretainedValue()
            me.handle(type: type, event: event)
            return Unmanaged.passUnretained(event) // 듣기 전용: 항상 그대로 통과
        }
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: cb,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return startMonitorFallback() }
        let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
        source = s
        return true
    }

    /// 같은 개인정보 규칙: 일치 여부만 보고 나머지는 버린다.
    private func startMonitorFallback() -> Bool {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, !e.isARepeat else { return }
            self.dispatchMatches(code: e.keyCode, mods: ShortcutModifiers(cgEventFlags: UInt64(e.modifierFlags.rawValue)))
        }
        if monitor != nil { print("[shortcut] event tap unavailable, using global monitor") }
        return monitor != nil
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return
        }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        dispatchMatches(code: code, mods: ShortcutModifiers(cgEventFlags: event.flags.rawValue))
    }

    private func dispatchMatches(code: UInt16, mods: ShortcutModifiers) {
        // 일치하는 것만 쓰고 나머지는 여기서 버린다. 대부분의 키는 일치하지 않으므로 배열을 만들지 않고 먼저 확인한다.
        guard shortcuts.contains(where: { shortcutMatches(keyCode: code, modifiers: mods, $0.shortcut) }) else { return }
        let ids = shortcuts.filter { shortcutMatches(keyCode: code, modifiers: mods, $0.shortcut) }.map(\.id)
        DispatchQueue.main.async { [onFire] in
            ids.forEach { id in
                print("[shortcut] matched \(id)")
                onFire(id)
            }
        }
    }
}
