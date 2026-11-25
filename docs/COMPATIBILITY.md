# macOS 호환성 확인

새 macOS가 나와도 GitHub 러너가 늦게 따라오기 때문에, CI만으로는 알아채기 어렵습니다.
그래서 Apple 공식 피드를 매일 보고, 처음 보는 macOS 빌드가 있으면 워크플로를 **실패**시켜 메인테이너가 확인하게 합니다.

- [Apple Developer Releases RSS](https://developer.apple.com/news/releases/rss/releases.rss)와 [macOS 릴리스 노트](https://developer.apple.com/documentation/macos-release-notes)
- [GitHub 워크플로](../.github/workflows/apple-releases.yml)는 매일 12:17 KST에 예약되어 있으며 수동 실행도 지원합니다. 공개 포크에서는 Actions를 켜야 예약 실행을 시작합니다. [GitHub 예약 실행 조건](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
- [피드 검사기](../scripts/check-apple-releases.py)와 [확인한 빌드 목록](../scripts/apple-macos-releases.baseline.txt)

## 기준선의 뜻

처음 목록에는 2026-11-24에 피드에서 관찰한 macOS 빌드 4개를 담았습니다. 각 버전에서 앱을 실행한 결과는 호환성 변경 PR에 별도로 기록하세요.

## 실패했을 때

종료 코드로 원인을 구분합니다.

| 코드 | 뜻 | 할 일 |
|---|---|---|
| 1 | 기준선에 없는 새 macOS 빌드 | 아래 순서대로 처리 |
| 2 | 피드가 비었거나 XML이 깨짐, macOS 항목을 해석 못 함 | 피드를 직접 열어 형식이 바뀌었는지 확인하고 스크립트 수정 |
| 3 | 피드를 가져오지 못함(재시도 4회 후) | 대개 일시 장애. 다음날까지 계속되면 확인 |
| 4 | 입력 파일 또는 기준선 오류 | 파일 경로와 읽기 권한 확인 |

새 빌드 처리 순서:

1. 로그에 나온 빌드의 Apple 릴리스 노트를 읽습니다(위 링크).
2. 아래 실기기 점검을 하고 `swift test`, `bash scripts/qa.sh`를 돌립니다.
3. 새 항목의 제목(`macOS …`부터 빌드 번호까지)을 기준선 파일에 한 줄씩 추가하세요. 변경 PR에 실행한 OS 빌드·아키텍처·언어와 미검증 항목을 기록합니다.

오프라인으로 시험하려면 `python3 -I scripts/check-apple-releases.py --input 파일.xml`,
스크립트 테스트는 `python3 -I scripts/tests/test_check_apple_releases.py` 입니다.

## 실기기 스모크 점검

새 macOS에서 `bash scripts/build-app.sh`로 빌드하세요. 실제 펫과 구분하려면 시험용 저장 위치를 지정해 실행합니다. 같은 경로를 계속 쓰면 업그레이드 전후를 비교할 수 있습니다.

```sh
trial_dir="$(mktemp -d)"
open -n build/MacPet.app --args --save-path "$trial_dir/save.json"
```

1. **설정 변경 감지**: 시스템 설정 → 외관에서 라이트/다크를 바꾸고, 데스크탑을 하나 더 만들어 넘어가 봅니다. `appearanceChange`·`spaceChange` 미션이 완료되는지 봅니다. 설정값을 보는 `defaultsChange` 미션(예: Dock 자동 숨김)도 하나 켜 봅니다.
2. **손쉬운 사용 표시 옵션**: 시스템 설정 → 손쉬운 사용 → 디스플레이에서 "투명도 줄이기"를 켜고 끕니다. 해당 미션이 완료되는지 봅니다.
3. **손쉬운 사용 권한**: 권한 미션에서 허용 → 단축키 미션(`cmd+tab`)이 감지되는지, 권한을 끄면 다시 막히는지 봅니다. "눌러야 할 곳 표시" 화살표가 시스템 설정의 버튼 위에 뜨는지도 봅니다.
4. **저장된 펫 유지**. 이전 버전에서 시험용 펫을 부화시키고 창을 옮긴 뒤 종료합니다. 같은 저장 경로로 새 버전을 열고 펫 단계, 경험치, 완료한 미션, 창 위치를 확인하세요. 시험용 진행 파일과 창 위치는 각각 `$trial_dir/save.json`, `$trial_dir/save.json.panelOrigin`입니다.

## 한계

- 피드에 올라온 시점부터 알 수 있습니다. Apple이 피드에 안 올리는 빌드는 놓칩니다.
- 제목 형식(`macOS <버전> [beta N|RC] (<빌드>)`)에 의존합니다. 형식이 바뀌면 코드 2로 따로 알립니다.
- 이 점검은 새 빌드를 **알려 줄 뿐**, 호환성을 검증하지 않습니다.
- 피드 속 링크는 가져오지 않고, 해석되지 않은 제목은 로그에 출력하지 않습니다(워크플로 명령·제어문자 주입 방지).
