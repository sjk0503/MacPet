#!/bin/bash
# qa/ 폴더의 점검 시나리오를 차례로 실행한다.
# 매번 임시 폴더에 ad-hoc 서명으로 앱을 증분 빌드해서 쓰므로 build/MacPet.app 이나 실제 저장은 건드리지 않는다.
# 점검 중에는 실제 미션 감지를 끈다. 클릭과 키 입력은 펫 창으로 직접 보내서 실제 마우스·키보드는 움직이지 않는다.
# 펫 창이 화면에 잠깐 떴다 사라진다. 같은 이름의 `<시나리오>.save.json` 이 있으면 그 저장 상태에서 시작한다.
# 환경변수: MACPET_QA_TIMEOUT 시나리오당 제한 시간(초, 기본 150. qa/advanced.json 하나만 약 65초 걸린다). MACPET_SIGN_ID 를 명시하면 그 인증서로 서명(기본 ad-hoc).
# 앱 실행 파일을 직접 띄운다: 이 스크립트가 만든 그 프로세스(PID)만 기다리고, 시간이 넘거나 중단되면 그 PID 에만 신호를 보낸다.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

TIMEOUT="${MACPET_QA_TIMEOUT:-150}"
# 앞자리 0 을 막아 bash 산술이 8진수로 읽는 일을 피한다. 자릿수도 제한한다.
[[ $TIMEOUT =~ ^[1-9][0-9]{0,5}$ ]] || { echo "error: MACPET_QA_TIMEOUT 은 앞자리 0 없는 1 이상의 10진 정수(초)" >&2; exit 2; }

TMP=$(mktemp -d)
CHILD=""   # 지금 우리가 띄운 앱의 PID. 끝나면 비워서 PID 재사용으로 엉뚱한 프로세스를 건드리지 않는다.

stop_child() {
    [ -n "$CHILD" ] || return 0
    if kill -0 "$CHILD" 2>/dev/null; then
        kill -TERM "$CHILD" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$CHILD" 2>/dev/null || break; sleep 0.2; done
        kill -0 "$CHILD" 2>/dev/null && kill -KILL "$CHILD" 2>/dev/null || true
    fi
    wait "$CHILD" 2>/dev/null || true
    CHILD=""
}
trap 'stop_child; rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 증분 빌드: SwiftPM 캐시(.build)를 재사용하고, 앱 번들만 임시 폴더에 새로 조립한다.
echo "== build (staging, incremental)"
if ! env -u MACPET_RELEASE_SIGN -u MACPET_RELEASES_URL MACPET_BUILD_DIR="$TMP/build" MACPET_SIGN_ID="${MACPET_SIGN_ID:--}" \
        bash scripts/build-app.sh >"$TMP/build.log" 2>&1; then
    cat "$TMP/build.log" >&2
    echo "빌드 실패" >&2
    exit 1
fi
BIN="$TMP/build/MacPet.app/Contents/MacOS/MacPet"
[ -x "$BIN" ] || { echo "error: $BIN 이 없다" >&2; exit 1; }

fail=0
for s in qa/*.json; do
    case "$s" in *.save.json) continue ;; esac
    name=$(basename "$s" .json)
    save="$TMP/$name.save.json"   # 시나리오마다 따로 둬서 서로 영향을 주지 않는다
    [ -f "qa/$name.save.json" ] && cp "qa/$name.save.json" "$save"
    log="$TMP/$name.log"
    echo "== $name"

    env -u MACPET_WEB_DIR "$BIN" --qa "$ROOT/$s" --save-path "$save" >"$log" 2>"$log.err" &
    CHILD=$!
    timed_out=0
    ticks=0
    while kill -0 "$CHILD" 2>/dev/null; do
        if [ "$ticks" -ge $((TIMEOUT * 5)) ]; then timed_out=1; stop_child; break; fi
        sleep 0.2
        ticks=$((ticks + 1))
    done
    rc=0
    if [ -n "$CHILD" ]; then wait "$CHILD" || rc=$?; CHILD=""; fi

    grep -E "FAIL|\[qa\] done|\[web\]" "$log" || true
    ok=1
    [ "$timed_out" = 0 ] || { echo "시간 초과 (${TIMEOUT}초)"; ok=0; }
    [ "$timed_out" = 1 ] || [ "$rc" = 0 ] || { echo "비정상 종료 (exit $rc)"; ok=0; }
    grep -q "\[qa\] done: .* 0 failed" "$log" || { echo "'[qa] done ... 0 failed' 를 찾지 못함"; ok=0; }
    if [ "$ok" = 0 ]; then
        fail=1
        echo "-- stdout (끝 40줄)"; tail -n 40 "$log" || true
        echo "-- stderr (끝 40줄)"; tail -n 40 "$log.err" || true
    fi
done
[ "$fail" = 0 ] && echo "모두 통과" || echo "실패한 항목이 있음"
exit "$fail"
