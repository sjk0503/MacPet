#!/usr/bin/env python3
"""Apple Developer Releases RSS에서 새 macOS 빌드(정식/RC/베타)를 찾아 알린다.

표준 라이브러리만 쓴다. 피드 내용은 데이터로만 다룬다:
  - 피드 안의 URL은 가져오지 않는다(고정 URL 하나만 접속).
  - macOS 제목은 엄격한 정규식과 ASCII 허용 문자만 통과시킨다. 통과 못 하면 출력하지 않고 개수만 센다.
  - DOCTYPE/ENTITY가 있는 XML은 파싱 전에 거절한다.

종료 코드:
  0  모두 기준선(baseline)에 있음
  1  기준선에 없는 macOS 빌드가 있음 (사람이 확인)
  2  피드가 비었거나 형식이 깨짐 / macOS 항목을 해석할 수 없음
  3  피드를 가져오지 못함 (네트워크·HTTP)
  4  사용법/기준선 파일 오류

기준선은 "확인함(acknowledged)" 목록이지 "테스트함"이 아니다.
"""
import argparse
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

FEED_URL = "https://developer.apple.com/news/releases/rss/releases.rss"
NOTES_URL = "https://developer.apple.com/documentation/macos-release-notes"
DEFAULT_BASELINE = Path(__file__).resolve().parent / "apple-macos-releases.baseline.txt"
MAX_BYTES = 2 * 1024 * 1024
TIMEOUT = 20
ATTEMPTS = 4

EXIT_OK, EXIT_UNSEEN, EXIT_MALFORMED, EXIT_FETCH, EXIT_USAGE = 0, 1, 2, 3, 4

# 예: "macOS 27.3 beta 2 (26C5047e)", "macOS 27.2.1 (26B131)", "macOS Tahoe 26.1 RC (25B77)"
MACOS_TITLE = re.compile(
    r"^macOS(?: [A-Za-z]{2,20})? [0-9]{1,3}(?:\.[0-9]{1,3}){0,3}"
    r"(?: [A-Za-z0-9]{1,12}){0,4} \([A-Za-z0-9]{3,12}\)$"
)


class FeedError(Exception):
    pass


class FetchError(Exception):
    pass


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None  # 리다이렉트는 따라가지 않는다


def fetch(url=FEED_URL, attempts=ATTEMPTS, timeout=TIMEOUT, sleep=time.sleep):
    if not url.startswith("https://"):
        raise FetchError("HTTPS URL만 허용합니다")
    opener = urllib.request.build_opener(_NoRedirect)
    last = None
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "mac-pet-guide-release-check"})
            with opener.open(req, timeout=timeout) as r:
                if r.status != 200:
                    raise FetchError(f"HTTP {r.status}")
                data = r.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                raise FeedError(f"피드가 {MAX_BYTES} 바이트를 넘습니다")
            return data
        except FeedError:
            raise
        except (urllib.error.URLError, OSError, FetchError) as e:
            last = e
            if i + 1 < attempts:
                sleep(2 ** i)
    raise FetchError(f"{attempts}회 시도 실패: {type(last).__name__}")


def parse_macos_titles(data):
    """(정상 제목 집합, 해석 못 한 macOS 항목 수, 전체 item 수)를 돌려준다."""
    if not data or not data.strip():
        raise FeedError("피드가 비어 있습니다")
    if len(data) > MAX_BYTES:
        raise FeedError("피드가 너무 큽니다")
    head = data.upper()
    if b"<!DOCTYPE" in head or b"<!ENTITY" in head:
        raise FeedError("DOCTYPE/ENTITY가 있는 XML은 받지 않습니다")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as e:
        raise FeedError(f"XML 파싱 실패: {e}")
    if root.tag != "rss":
        raise FeedError("RSS 루트가 아닙니다")
    items = root.findall("./channel/item")
    if not items:
        raise FeedError("item이 하나도 없습니다")
    good, bad = set(), 0
    for item in items:
        title = item.findtext("title")
        if title is None:
            continue
        title = " ".join(title.split())
        if not title.startswith("macOS"):
            continue
        if title.isascii() and MACOS_TITLE.match(title):
            good.add(title)
        else:
            bad += 1
    if not good and not bad:
        raise FeedError("macOS 항목이 하나도 없습니다 (피드 형식이 바뀌었을 수 있음)")
    return good, bad, len(items)


def load_baseline(path):
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as e:
        raise FeedError(f"기준선 파일을 읽을 수 없습니다: {e}")
    out = set()
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.add(" ".join(line.split()))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--input", help="네트워크 대신 읽을 로컬 RSS 파일 (오프라인 테스트용)")
    ap.add_argument("--baseline", default=str(DEFAULT_BASELINE))
    a = ap.parse_args(argv)

    try:
        if a.input:
            data = Path(a.input).read_bytes()
        else:
            data = fetch()
    except OSError as e:
        print(f"입력 파일 오류: {e}", file=sys.stderr)
        return EXIT_USAGE
    except FetchError as e:
        print(f"[가져오기 실패] {e}", file=sys.stderr)
        return EXIT_FETCH
    except FeedError as e:
        print(f"[피드 이상] {e}", file=sys.stderr)
        return EXIT_MALFORMED

    try:
        good, bad, total = parse_macos_titles(data)
    except FeedError as e:
        print(f"[피드 이상] {e}", file=sys.stderr)
        return EXIT_MALFORMED

    try:
        baseline = load_baseline(a.baseline)
    except FeedError as e:
        print(f"[기준선 오류] {e}", file=sys.stderr)
        return EXIT_USAGE

    unseen = sorted(good - baseline)
    print(f"피드 item {total}개, macOS 빌드 {len(good)}개, 기준선 {len(baseline)}개")
    if bad:
        print(f"[피드 이상] 형식을 해석하지 못한 macOS 항목 {bad}개 (내용은 출력하지 않음). "
              f"피드를 직접 확인하세요: {NOTES_URL}", file=sys.stderr)
        return EXIT_MALFORMED
    if unseen:
        print(f"기준선에 없는 새 macOS 빌드 {len(unseen)}개:")
        for t in unseen:
            print(f"  + {t}")
        print(f"\n다음 순서로 처리하세요 (docs/COMPATIBILITY.md):\n"
              f"  1. Apple 릴리스 노트 확인: {NOTES_URL}\n"
              f"  2. 실기기 스모크 점검과 테스트 실행\n"
              f"  3. 위 줄을 scripts/apple-macos-releases.baseline.txt 에 추가하는 PR 작성\n"
              f"(기준선 추가 = 확인함이지 테스트 통과 보증이 아닙니다)")
        return EXIT_UNSEEN
    print("새 macOS 빌드 없음")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
