import AppKit
import MacPetCore

/// 점검용 스크립트 실행기. JSON 배열로 적은 단계를 차례로 실행하고 결과를 `[qa]` 로그로 남긴다.
/// 누르기는 요소의 위치를 웹 화면에 물어 그 자리에 마우스 이벤트를 창으로 보내므로, 실제 커서는 움직이지 않는다.
///
/// 단계:
///   {"tap": "CSS 선택자", "count": 3, "gap": 0.6, "hold": 0.06}   요소 가운데를 누른다. 다른 요소에 가려져 있으면 실패로 적는다.
///   {"type": "글자"}                                 키 입력으로 보낸다
///   {"wait": 1.5}                                    기다린다(초)
///   {"native": {"type": "mission", "id": "copy"}}    네이티브 이벤트를 웹 화면에 보낸다
///   {"expect": "JS 식", "name": "설명"}              식이 참이면 PASS, 아니면 FAIL
///   {"expectSave": "JS 식", "name": "설명"}          그 순간 디스크의 점검용 저장 파일을 직접 읽어 `s` 로 묶고, 식이 참이면 PASS. 파일이 없거나 JSON 이 아니면 FAIL
///   {"eval": "JS 식"}                                값을 로그에 찍는다
///   {"snapshot": "/경로.png"}                        화면을 그림으로 저장
///   {"panelVisible": true}                           펫 창을 controller.show() / false 면 hide() 한다
///   {"until": "JS 식", "timeout": 5, "name": "설명"}  식이 참이 될 때까지 0.1초마다 확인한다. 참이 되면 PASS, timeout(초, 기본 5, 최대 60) 안에 안 되면 FAIL
final class QARunner {
    private let controller: PetPanelController
    private let steps: [[String: Any]]
    /// 이번 점검 실행의 격리된 저장 파일. expectSave 단계에서만 읽는다(쓰지 않는다).
    private let saveURL: URL
    private var index = 0
    private var passed = 0
    private var failed = 0

    /// 스크립트를 읽고 모든 단계를 미리 검사한다. 파일이 없거나, JSON 이 아니거나, 비었거나, 모르는 단계가 있으면 던진다(바로 실패시키려고).
    static func loadSteps(path: String) throws -> [[String: Any]] {
        struct Bad: Error, CustomStringConvertible { let description: String }
        guard !path.isEmpty else { throw Bad(description: "--qa 에는 점검 스크립트 경로가 필요함 (예: --qa qa/first-run.json)") }
        guard let data = FileManager.default.contents(atPath: path) else { throw Bad(description: "스크립트를 읽을 수 없음: \(path)") }
        guard let steps = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw Bad(description: "스크립트는 단계 객체의 JSON 배열이어야 함: \(path)")
        }
        guard !steps.isEmpty else { throw Bad(description: "스크립트에 단계가 없음: \(path)") }
        for (i, s) in steps.enumerated() {
            let ok: Bool
            if s["tap"] is String { ok = true }
            else if s["type"] is String { ok = true }
            else if s["wait"] is NSNumber { ok = true }
            else if s["native"] is [String: Any] { ok = true }
            else if s["expect"] is String { ok = true }
            else if s["expectSave"] is String { ok = true }
            else if s["eval"] is String { ok = true }
            else if s["snapshot"] is String { ok = true }
            else if let n = s["panelVisible"] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { ok = true }
            else if s["until"] is String { ok = true }
            else { ok = false }
            if !ok { throw Bad(description: "\(path): \(i + 1)번째 단계를 알 수 없음 (키: \(s.keys.sorted()))") }
        }
        return steps
    }

    init(steps: [[String: Any]], controller: PetPanelController, saveURL: URL) {
        self.controller = controller
        self.saveURL = saveURL
        self.steps = steps
    }

    func run() { next() }

    private func after(_ seconds: Double, _ f: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: f)
    }

    private func next() {
        guard index < steps.count else {
            print("[qa] done: \(steps.count) steps, \(passed) passed, \(failed) failed")
            exit(failed == 0 ? 0 : 1)
        }
        let step = steps[index]
        index += 1

        if let sel = step["tap"] as? String {
            let count = step["count"] as? Int ?? 1
            let gap = (step["gap"] as? NSNumber)?.doubleValue ?? 0.5
            let hold = (step["hold"] as? NSNumber)?.doubleValue ?? 0.06
            tap(sel, remaining: count, gap: gap, hold: hold)
        } else if let text = step["type"] as? String {
            controller.typeText(text)
            print("[qa] type \(text.count) chars")
            after(0.3) { self.next() }
        } else if let w = (step["wait"] as? NSNumber)?.doubleValue {
            after(w) { self.next() }
        } else if let ev = step["native"] as? [String: Any] {
            controller.send(ev)
            print("[qa] native \(ev["type"] ?? "?") \(ev["id"] ?? ev["name"] ?? "")")
            after(0.2) { self.next() }
        } else if let expr = step["expect"] as? String {
            let name = step["name"] as? String ?? expr
            controller.evaluate("(function(){ try { return !!(\(expr)); } catch (e) { return 'error: ' + e; } })()") { v in
                if (v as? Bool) == true { self.passed += 1; print("[qa] PASS \(name)") }
                else { self.failed += 1; print("[qa] FAIL \(name) → \(v.map { "\($0)" } ?? "nil")") }
                self.next()
            }
        } else if let expr = step["expectSave"] as? String {
            expectSave(expr, name: step["name"] as? String ?? expr)
        } else if let expr = step["eval"] as? String {
            controller.evaluate("(function(){ try { return JSON.stringify(\(expr)); } catch (e) { return 'error: ' + e; } })()") { v in
                print("[qa] eval → \(v.map { "\($0)" } ?? "nil")")
                self.next()
            }
        } else if let n = step["panelVisible"] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
            if n.boolValue { controller.show() } else { controller.hide() }
            print("[qa] panelVisible \(n.boolValue)")
            after(0.2) { self.next() }
        } else if let expr = step["until"] as? String {
            let timeout = min(max((step["timeout"] as? NSNumber)?.doubleValue ?? 5, 0.1), 60)
            until(expr, name: step["name"] as? String ?? expr, deadline: Date().addingTimeInterval(timeout))
        } else if let path = step["snapshot"] as? String {
            controller.savePNG(to: path) { ok in
                if ok { print("[qa] snapshot \((path as NSString).lastPathComponent)") }
                else { self.failed += 1; print("[qa] FAIL snapshot \(path) → 저장하지 못함") }
                self.next()
            }
        } else {
            failed += 1
            print("[qa] FAIL 모르는 단계: \(step.keys.sorted())")
            next()
        }
    }

    /// 웹이 보낸 메시지가 아니라 디스크에 실제로 적힌 저장 파일을 지금 읽어 `s` 로 넘기고 식을 평가한다.
    /// 파일 글자는 JSON 문자열 리터럴로 감싸 넘기므로(JSONSerialization) 따옴표·줄바꿈·</script> 같은 내용이 식에 섞이지 않는다.
    private func expectSave(_ expr: String, name: String) {
        func fail(_ why: String) { failed += 1; print("[qa] FAIL \(name) → \(why)"); next() }
        let data: Data
        do { data = try Data(contentsOf: saveURL) } catch {
            return fail("저장 파일을 읽을 수 없음 (\(saveURL.lastPathComponent)): \(error.localizedDescription)")
        }
        guard (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil,
              let text = String(data: data, encoding: .utf8),
              let quoted = (try? JSONSerialization.data(withJSONObject: [text])).flatMap({ String(data: $0, encoding: .utf8) }) else {
            return fail("저장 파일이 올바른 UTF-8 JSON 이 아님 (\(saveURL.lastPathComponent), \(data.count)바이트)")
        }
        controller.evaluate("(function(s){ try { return !!(\(expr)); } catch (e) { return 'error: ' + e; } })(JSON.parse(\(quoted)[0]))") { v in
            if (v as? Bool) == true { self.passed += 1; print("[qa] PASS \(name)") }
            else { self.failed += 1; print("[qa] FAIL \(name) → \(v.map { "\($0)" } ?? "nil")") }
            self.next()
        }
    }

    /// 식이 참이 될 때까지 기다린다. 프레임 수 같은 정확한 값이 아니라 "결국 그렇게 된다"를 본다.
    private func until(_ expr: String, name: String, deadline: Date) {
        controller.evaluate("(function(){ try { return !!(\(expr)); } catch (e) { return 'error: ' + e; } })()") { v in
            if (v as? Bool) == true { self.passed += 1; print("[qa] PASS \(name)"); self.next() }
            else if Date() >= deadline { self.failed += 1; print("[qa] FAIL \(name) → 시간 안에 참이 되지 않음 (\(v.map { "\($0)" } ?? "nil"))"); self.next() }
            else { self.after(0.1) { self.until(expr, name: name, deadline: deadline) } }
        }
    }

    /// 요소 가운데 좌표와, 그 자리에서 실제로 맨 위에 있는 요소가 그 요소(또는 그 안쪽)인지 확인한다.
    /// 또 그 자리가 네이티브가 클릭을 받는 영역(hitRects) 안인지도 본다. 밖이면 실제 마우스로는 눌리지 않는다.
    private func tap(_ sel: String, remaining: Int, gap: Double, hold: Double) {
        guard remaining > 0 else { next(); return }
        let quoted = String(data: (try? JSONSerialization.data(withJSONObject: [sel])) ?? Data(), encoding: .utf8) ?? "[]"
        let js = """
        (function(){
          const e = document.querySelector(\(quoted)[0]);
          if (!e) return null;
          const r = e.getBoundingClientRect();
          if (!r.width || !r.height) return [0, 0, 'hidden'];
          const x = r.left + r.width / 2, y = r.top + r.height / 2;
          const top = document.elementFromPoint(x, y);
          const ok = top && (top === e || e.contains(top));
          return [x, y, ok ? '' : (top ? top.tagName + '.' + top.className : 'nothing')];
        })()
        """
        controller.evaluate(js) { v in
            guard let a = v as? [Any], a.count == 3,
                  let x = (a[0] as? NSNumber)?.doubleValue, let y = (a[1] as? NSNumber)?.doubleValue else {
                self.failed += 1
                print("[qa] FAIL tap \(sel) → 요소 없음")
                self.next()
                return
            }
            let cover = a[2] as? String ?? ""
            if !cover.isEmpty {
                self.failed += 1
                print("[qa] FAIL tap \(sel) → \(cover == "hidden" ? "보이지 않음" : "가려짐: \(cover)")")
                self.next()
                return
            }
            if !hitTest(x: x, y: y, rects: self.controller.currentHitRects, padding: 6) {
                self.failed += 1
                print("[qa] FAIL tap \(sel) → 클릭을 받는 영역 밖 (\(Int(x)),\(Int(y)))")
            }
            self.controller.click(webX: x, webY: y, hold: hold)
            print("[qa] tap \(sel) at \(Int(x)),\(Int(y))")
            self.after(gap + hold) { self.tap(sel, remaining: remaining - 1, gap: gap, hold: hold) }
        }
    }
}
