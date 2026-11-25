# 릴리스 가이드

MacPet 을 빌드하고 [공식 저장소](https://github.com/sjk0503/MacPet)에 릴리스를 내는 방법입니다. `vX.Y.Z` 태그를 push 하면 `release.yml` 이 소스 ZIP 과 체크섬만 있는 초안(draft) 릴리스를 준비하고, 공개(Publish release)와 공증 앱 첨부는 사람이 합니다. 순서는 [게시](#게시)에 있습니다.

## 버전

저장소 루트의 `VERSION` 이 유일한 출처이며, 정확히 두 줄입니다.

```
0.2.2
4
```

- 1줄: `X.Y.Z`(앞자리 0 금지, 0 자체는 가능). `CFBundleShortVersionString` 과 ZIP 파일 이름에 쓰입니다.
- 2줄: 1 이상의 정수 빌드 번호(앞자리 0 금지). `CFBundleVersion` 이 되며 릴리스마다 올립니다.

형식이 틀리면 `build-app.sh` 가 중단합니다. 올릴 때는 이 파일만 고칩니다.

## 스크립트

| 명령 | 결과 |
|---|---|
| `scripts/build-app.sh` | 현재 아키텍처용 앱 `$MACPET_BUILD_DIR/MacPet.app` (기본 `build/MacPet.app`) |
| `scripts/build-app.sh --universal` | arm64 + x86_64 앱 `$MACPET_BUILD_DIR/universal/MacPet.app` |
| `scripts/release.sh` | 유니버설 앱 + `$MACPET_BUILD_DIR/release/MacPet-<VERSION>-macos-universal.zip` 와 `.zip.sha256` |
| `scripts/release.sh --native` | 네이티브 앱 + `MacPet-<VERSION>-macos-<arch>.zip` 와 `.zip.sha256` |
| `python3 -I scripts/source-release.py` | 소스 ZIP `MacPet-<VERSION>-source.zip`과 `.zip.sha256` |
| `scripts/qa.sh` | 임시 폴더에 ad-hoc 앱을 새로 빌드해 `qa/*.json` 시나리오 실행 |

| 환경변수 | 설명 |
|---|---|
| `MACPET_BUILD_DIR` | 산출물 폴더. 기본 `build`, 상대 경로는 저장소 루트 기준 |
| `MACPET_SIGN_ID` | 서명 ID(인증서 이름 전체 또는 SHA-1). `-` 는 ad-hoc |
| `MACPET_RELEASE_SIGN=1` | Developer ID + hardened runtime + 보안 타임스탬프 서명. `MACPET_SIGN_ID` 필수 |
| `MACPET_NOTARY_PROFILE` | 공증용 Keychain 프로필 이름. `release.sh` 전용이며 `MACPET_RELEASE_SIGN=1` 필요 |
| `MACPET_RELEASES_URL` | 선택. 메뉴 **새 버전 보기…**가 여는 주소(`Info.plist` 의 `MacPetReleasesURL`). 값이 있으면 `https://github.com/OWNER/REPO/releases` 형식인지 검증한 뒤 그대로 쓰고, 빈 값이면 키를 넣지 않습니다. 지정하지 않았을 때의 규칙은 [새 버전 보기 주소와 포크](#새-버전-보기-주소와-포크) 참고 |
| `MACPET_QA_TIMEOUT` | `qa.sh` 시나리오당 제한 시간(초). 기본 150, 앞자리 0 없는 양의 정수 |

서명 ID 우선순위(`build-app.sh`)는 명시한 `MACPET_SIGN_ID` → 이 맥의 `.signing-id`(저장소 미포함) → ad-hoc 입니다. `release.sh` 와 `qa.sh` 는 `MACPET_SIGN_ID` 를 명시하지 않으면 `.signing-id` 를 무시하고 ad-hoc 으로 만듭니다.

## 빌드 동작

- `assets/AppIcon.png`가 아이콘 원본입니다. 빌드할 때 1024×1024 PNG에서 표준 크기별 이미지를 생성해 `Contents/Resources/MacPet.icns`로 넣고 `CFBundleIconFile`로 지정합니다. 아이콘까지 조립한 앱에 서명합니다.
- 배포용 실행 파일을 번들에 복사한 뒤 디버그 심볼을 제거합니다. SwiftPM의 빌드 캐시는 개발용 디버깅에 사용할 수 있습니다.
- 소스 ZIP은 `scripts/source-release.py`의 `FILES`에 적힌 파일로 만듭니다. 새 소스·테스트·이미지를 추가하면 목록에도 추가하세요. 패키저는 목록에 없는 파일을 발견하면 해당 경로를 알려 줍니다. ZIP을 풀면 최상위 폴더에서 `bash scripts/build-app.sh`로 빌드할 수 있습니다.
- 네이티브는 `.build`, 유니버설은 `.build/universal-arm64`, `.build/universal-x86_64` 를 쓰므로 서로의 산출물을 덮어쓰지 않습니다. 유니버설은 두 triple(`<arch>-apple-macosx14.0`)로 빌드해 `lipo -create` 로 합칩니다.
- 빌드 후 아키텍처 목록과 슬라이스별 최소 macOS(`vtool` 의 `minos`)가 14.0 인지 검사합니다(네이티브도 동일). 서명 후에는 `codesign --verify --deep --strict` 를 실행하고, `release.sh` 는 ZIP 을 풀어 한 번 더 검증합니다.
- 앱과 ZIP 은 임시 폴더(`.macpet-build.*`, `release/.stage.*`)에서 만들고, 모든 검증을 통과한 뒤에만 이전 산출물을 교체합니다. 중간에 실패하면 이전 앱과 ZIP + SHA 가 그대로 남습니다.
- 같은 산출물 폴더(`MACPET_BUILD_DIR`)를 쓰는 `build-app.sh` 와 `release.sh` 는 `.macpet-package.lock` 잠금으로 Swift 빌드 전부터 종료까지 한 번에 하나씩만 실행되고, 폴더가 다르면 동시에 실행됩니다.
- 웹 자산은 `web/` 의 html, css, js, json, svg, png, jpg, webp, woff2 만 포함합니다.

## 체크섬과 재현성

체크섬 파일에는 파일 이름만 있으므로 ZIP 과 같은 폴더에서 확인합니다.

```sh
cd build/release
shasum -a 256 -c MacPet-0.2.2-macos-universal.zip.sha256
shasum -a 256 -c MacPet-0.2.2-source.zip.sha256
```

- **ad-hoc**: 같은 체크아웃 경로, 같은 툴체인, 같은 소스와 설정으로 두 번 다시 실행했을 때 SHA 가 같음을 확인했습니다. 임시 트리의 mtime 을 2000-01-01 UTC 로 고정하고 C 로케일 순서로 정렬해 `/usr/bin/zip -X` 로 묶습니다. 다른 머신이나 다른 환경에서의 동일성은 약속하지 않습니다.
- **Developer ID(공증 포함)**: `ditto -c -k --keepParent` 로 묶습니다. 서명 타임스탬프와 공증 티켓이 들어가므로 같은 해시를 약속하지 않습니다.

[릴리스 페이지](https://github.com/sjk0503/MacPet/releases)의 v0.2.2 첫 공개에는 `MacPet-0.2.2-source.zip`과 `MacPet-0.2.2-source.zip.sha256` 두 파일만 올립니다. 소스 ZIP에는 루트의 MIT [LICENSE](../LICENSE)가 들어갑니다. 앱 ZIP(`MacPet-0.2.2-macos-universal.zip`과 `.zip.sha256`)은 공증을 마친 것만 같은 릴리스에 추가합니다([공증 앱 추가](#2-공증-앱-추가)). 버전별 설명은 [변경 내역](../CHANGELOG.md)에 있습니다.

## ad-hoc 빌드 (개발용)

ad-hoc 빌드는 **개발용 산출물**이며 이 맥에서 시험하는 용도입니다. 공증하지 않았으므로 다른 사용자에게 배포하지 않습니다. 빌드마다 서명이 달라 손쉬운 사용 권한도 다시 허용해야 합니다.

```sh
MACPET_BUILD_DIR=/tmp/macpet-try scripts/release.sh
```

다른 사용자가 쓰려면 소스를 받아 자기 맥에서 직접 빌드하거나, Developer ID 로 서명하고 공증한 릴리스를 받아야 합니다.

## 공증 릴리스 (선택)

다른 사용자에게 앱 ZIP을 주려면 Developer ID로 서명하고 Apple 공증을 받아야 합니다. 준비 1~4는 배포할 Mac에서 한 번만 하면 됩니다. `<...>`는 직접 채웁니다.

개인 키, 앱 암호, API 키는 저장소·채팅·이슈에 올리지 않고 이 Mac의 키체인이나 본인만 읽을 수 있는 로컬 위치에 보관합니다. 스크립트는 인증서와 비밀번호를 읽거나 출력하지 않습니다.

### 준비 1. Apple Developer Program 가입

Developer ID 인증서는 Apple Developer Program(유료) 멤버십의 Account Holder가 만듭니다. 개인으로 가입하면 본인이 Account Holder이고, 조직은 가입을 진행한 사람이 Account Holder입니다. 이미 팀 구성원이라면 계정 담당자(Account Holder)에게 인증서 발급 방법을 확인하세요([프로그램 가입](https://developer.apple.com/help/account/membership/program-enrollment/)).

### 준비 2. Developer ID Application 인증서

1. 배포할 Mac에서 **키체인 접근**을 열고 메뉴의 키체인 접근 > 인증서 지원 > **인증 기관에서 인증서 요청…**을 선택합니다. 이메일과 이름을 입력하고 “디스크에 저장됨”을 골라 CSR 파일(`.certSigningRequest`)을 저장합니다. 이때 개인 키가 이 Mac의 키체인에 생깁니다([CSR 만들기](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/)).
2. [Apple Developer 계정](https://developer.apple.com/account)의 Certificates에서 **+**를 누르고 **Developer ID Application**을 선택한 뒤 CSR 파일을 업로드합니다([Developer ID 인증서 만들기](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)).
3. 받은 `.cer` 파일을 더블 클릭해 키체인에 넣습니다. 키체인 접근의 **나의 인증서**에서 인증서를 펼쳐 개인 키가 연결되어 있는지 확인합니다. 보이지 않으면 인증서를 넣은 키체인에 대응하는 개인 키가 있는지 먼저 확인합니다(인증서와 개인 키가 서로 다른 키체인에 있으면 연결되지 않습니다). CSR을 다른 Mac에서 만들었다면 그 Mac에서 인증서와 개인 키를 함께 `.p12`로 내보내 가져옵니다.
4. 터미널에서 서명 ID를 확인합니다. `Developer ID Application: <이름> (<TEAMID>)` 줄이 보여야 하며, 이 문자열이 `MACPET_SIGN_ID` 값입니다.

   ```sh
   security find-identity -v -p codesigning
   ```

### 준비 3. Xcode와 notarytool

`notarytool`과 `stapler`는 Xcode 전체 설치(13 이상)에 들어 있습니다([TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)). 아래 두 명령으로 확인합니다.

```sh
xcode-select -p
xcrun notarytool --version
```

첫 줄이 Xcode 앱 안의 경로가 아니어서 `notarytool`을 찾지 못하면, 시스템 설정을 바꾸지 않고 이 터미널 세션에만 Xcode를 지정합니다. 빌드와 공증도 같은 세션에서 실행합니다.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

### 준비 4. 키체인 프로필 `MACPET-NOTARY`

공증 제출에 쓰는 자격 증명을 키체인에 한 번 저장합니다. 아래 두 방법 중 하나만 하면 됩니다. 이미 만든 프로필이 있으면 그대로 씁니다.

**방법 A. Apple Account와 앱 암호.** 이중 인증을 켠 Apple Account로 [account.apple.com](https://account.apple.com)에 로그인해 로그인 및 보안 > 앱 암호에서 앱 암호를 만듭니다([앱 암호 만들기](https://support.apple.com/en-us/102654)). Apple Account 비밀번호가 아니라 이 앱 암호를 씁니다. 암호는 명령줄에 적지 않고, 명령을 실행한 뒤 나오는 프롬프트에 입력합니다.

```sh
xcrun notarytool store-credentials MACPET-NOTARY \
  --apple-id "<Apple Account 이메일>" \
  --team-id "<TEAMID>"
```

**방법 B. App Store Connect 팀 API 키.** App Store Connect의 사용자 및 접근 권한 > 통합에서 팀 키를 만들고 `.p8` 파일을 받습니다(한 번만 받을 수 있습니다, [App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)). 본인만 읽을 수 있는 로컬 위치에 두고, 같은 화면의 Key ID와 Issuer ID를 함께 넣습니다.

```sh
xcrun notarytool store-credentials MACPET-NOTARY \
  --key "<.p8 파일 경로>" \
  --key-id "<KEY ID>" \
  --issuer "<ISSUER ID>"
```

두 키를 혼동하지 마세요. 준비 2의 개인 키는 앱에 **서명**하는 키로 키체인의 인증서에 붙어 있고, `.p8` API 키는 공증 **제출**을 인증하는 키입니다. 서로 대신 쓸 수 없습니다([공증 워크플로 맞춤 설정](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).

### 빌드와 공증

`v0.2.2` 태그를 체크아웃한 소스(`VERSION`이 `0.2.2` / `4`)에서 실행합니다. 공개한 소스 ZIP과 같은 내용이어야 하며, 공증을 위해 태그를 옮기거나 새로 만들지 않습니다. `MACPET_RELEASES_URL`은 체크아웃의 origin 설정과 무관하게 공식 주소가 들어가도록 명시합니다.

```sh
MACPET_RELEASE_SIGN=1 \
MACPET_SIGN_ID="Developer ID Application: <이름> (<TEAMID>)" \
MACPET_NOTARY_PROFILE="MACPET-NOTARY" \
MACPET_RELEASES_URL="https://github.com/sjk0503/MacPet/releases" \
scripts/release.sh
```

`release.sh` 는 Developer ID 서명(hardened runtime, 타임스탬프) → `xcrun notarytool submit --wait`(`status: Accepted` 가 아니면 중단) → `xcrun stapler staple` 과 `stapler validate` → `spctl --assess` → ZIP(`ditto`)과 SHA-256 → ZIP 을 풀어 서명·버전·아이콘 검증 후 이동 순서로 진행합니다. 결과는 `build/release/MacPet-0.2.2-macos-universal.zip` 과 `.zip.sha256` 입니다. `MACPET_NOTARY_PROFILE` 을 빼면 서명만 하고 공증은 하지 않습니다. 거절되면 출력된 id 로 `xcrun notarytool log <id> --keychain-profile MACPET-NOTARY` 를 확인합니다.

### 배포 전 재검증

올릴 ZIP 을 체크섬으로 확인하고, 임시 폴더에 풀어 앱을 다시 검증합니다.

```sh
cd build/release
shasum -a 256 -c MacPet-0.2.2-macos-universal.zip.sha256
CHECK=$(mktemp -d)
ditto -x -k MacPet-0.2.2-macos-universal.zip "$CHECK"
codesign --verify --deep --strict --verbose=2 "$CHECK/MacPet.app"
xcrun stapler validate "$CHECK/MacPet.app"
spctl --assess --type execute --verbose=2 "$CHECK/MacPet.app"
lipo -archs "$CHECK/MacPet.app/Contents/MacOS/MacPet"
```

체크섬은 `OK`, `codesign` 은 `valid on disk`, `stapler` 는 `The validate action worked!`, `spctl` 은 `accepted` 와 `source=Notarized Developer ID`, `lipo` 는 `arm64` 와 `x86_64` 가 모두 나와야 합니다. 하나라도 다르면 올리지 않습니다.

ad-hoc 산출물은 로컬 시험용입니다. 사용자에게는 위 검증을 모두 통과한 공증 산출물만 제공합니다.

## 게시

공식 저장소는 [github.com/sjk0503/MacPet](https://github.com/sjk0503/MacPet)이고, 배포 파일은 [릴리스 페이지](https://github.com/sjk0503/MacPet/releases)에만 올립니다. 워크플로는 서명이나 공증을 하지 않고 릴리스를 공개하지도 않습니다.

### 1. 소스 릴리스

1. `VERSION` 을 올린 커밋이 기본 브랜치에 있고 CI 가 통과했는지 확인합니다.
2. 그 커밋에 `v` + `VERSION` 1줄과 똑같은 태그를 붙여 push 합니다.

   ```sh
   git tag v0.2.2
   git push origin v0.2.2
   ```

3. `.github/workflows/release.yml` 이 다음 순서로 실행됩니다. 앞 단계가 실패하면 뒤 단계는 실행되지 않습니다.
   1. 태그가 `vX.Y.Z` 형식이고 `VERSION` 1줄과 일치하는지 검증합니다.
   2. `ci.yml` 전체(테스트, 네이티브·유니버설 패키징, GUI QA)를 그 태그 커밋에서 호출합니다.
   3. 그 태그 커밋으로 소스 ZIP 과 `.zip.sha256` 을 만들어 체크섬을 확인하고, 두 파일만 첨부한 초안 릴리스를 만듭니다.
4. 저장소의 **Releases** 에서 초안 `v0.2.2` 의 **Edit** 을 열어 제목, 설명, 첨부 파일 두 개를 확인한 뒤 **Publish release** 를 누릅니다. 이 단추를 누르기 전에는 외부에 보이지 않습니다.

같은 태그로 워크플로가 다시 실행돼도 안전합니다. 이미 공개된 릴리스는 건드리지 않고, 두 파일이 맞게 들어 있는 초안도 그대로 둡니다. 초안에 파일이 빠졌거나 ZIP 이 그 커밋의 소스와 다르면 실패하므로, Releases 에서 그 초안을 지운 뒤 다시 실행합니다.

### 2. 공증 앱 추가

소스 릴리스를 공개한 뒤 같은 `v0.2.2` 태그의 소스로 로컬 Mac에서 [빌드와 공증](#빌드와-공증), [배포 전 재검증](#배포-전-재검증)을 마친 최종 ZIP 과 SHA 한 쌍만 추가합니다.

1. **Releases** > 기존 `v0.2.2` 의 **Edit** 을 엽니다.
2. assets 영역에 `MacPet-0.2.2-macos-universal.zip` 과 `MacPet-0.2.2-macos-universal.zip.sha256` 을 첨부합니다.
3. 제목과 설명을 고칩니다. “실행 파일은 첨부하지 않으며” 문장을 공증된 Universal 앱 안내와 설치법(체크섬 확인, ZIP 풀기, `MacPet.app` 을 응용 프로그램 폴더로 옮기기)으로 바꿉니다.
4. **Update release** 를 누릅니다.

처음 공개한 소스 ZIP, 그 체크섬, 태그는 바꾸지 않습니다. immutable releases 가 꺼져 있으면 공개된 같은 릴리스에 파일을 추가할 수 있습니다. 켜져 있으면 공개된 릴리스의 자산을 추가·수정할 수 없으므로([GitHub 문서](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)), 공증 앱을 공개 전 초안에 첨부하거나 새 버전으로 냅니다.

## 새 버전 보기 주소와 포크

`build-app.sh` 는 메뉴 **새 버전 보기…**가 열 주소를 빌드할 때 아래 순서로 정합니다. 주소가 없으면 앱은 이 메뉴 항목을 만들지 않습니다.

| 조건 | 결과 |
|---|---|
| `MACPET_RELEASES_URL` 에 값을 지정 | 형식을 검증한 뒤 그 주소(형식이 틀리면 빌드 중단). 아래 규칙보다 우선 |
| `MACPET_RELEASES_URL` 을 빈 값으로 지정 | 메뉴 숨김 |
| 미지정, 루트에 `.git` 이 없는 소스 아카이브 | 공식 `https://github.com/sjk0503/MacPet/releases` |
| 미지정, `.git` 이 있고 origin 이 GitHub 저장소 | 그 저장소의 Releases(포크를 클론했다면 그 포크) |
| 미지정, `.git` 이 있지만 인식할 수 있는 origin 이 없음 | 메뉴 숨김 |

인식하는 origin 은 `https://github.com/OWNER/REPO`, `git@github.com:OWNER/REPO`, `ssh://git@github.com/OWNER/REPO` 입니다(끝의 `.git` 과 `/` 허용). 인증 정보가 든 주소나 GitHub 가 아닌 주소는 쓰지 않으며, origin 값은 출력하지 않습니다.

포크의 태그 push 는 그 포크에 초안을 만듭니다. 다만 포크가 배포한 소스 ZIP 도 `.git` 이 없으므로, 받은 사람이 주소를 지정하지 않고 빌드하면 공식 페이지를 가리킵니다. 포크의 Releases 를 열게 하려면 빌드 안내에 `MACPET_RELEASES_URL="https://github.com/<OWNER>/<REPO>/releases"` 를 적어 주세요.

## 업데이트(설치 교체)

업데이트는 사용자가 직접 합니다. 앱을 종료한 뒤 새 `MacPet.app` 으로 기존 위치(공증 앱은 `/Applications`)의 앱을 덮어씁니다. 저장 파일은 번들 밖에 있어 유지됩니다. 번들 ID(`local.macpetguide.prototype`)가 같고 서명 방식도 같아야 손쉬운 사용 권한이 이어집니다(ad-hoc 이면 다시 허용).

## 실제 맥 스모크 테스트

게시 전에 실제 맥에서 확인합니다. 빌드 머신의 새 OS 에서만 돌리면 최소 OS 문제를 놓치므로, **최소 지원 OS(macOS 14)** 환경이 반드시 포함되어야 합니다.

1. ZIP 체크섬을 확인하고 풀어서 `MacPet.app` 을 엽니다.
2. 펫 창과 미션 목록이 보이는지 확인합니다.
3. 손쉬운 사용 권한을 주고 미션 하나를 진행합니다.
4. 앱을 종료했다가 다시 열어 저장이 유지되는지 확인합니다.
5. 유니버설이라면 Apple Silicon 과 Intel 맥 각각에서 확인합니다.

## CI

`.github/workflows/ci.yml` 은 pull request, 모든 브랜치의 push(포크의 기본 브랜치 이름과 무관), 수동 실행, 매주 월요일(UTC)에 실행되고, `workflow_call` 도 지원해 `release.yml` 이 태그 커밋을 같은 검사로 확인할 때 호출합니다. 권한은 `contents: read` 뿐입니다. 새 push 가 오면 진행 중인 브랜치 검사는 취소하지만 태그 검사는 끝까지 실행합니다.

- `test + native package (<os>)`: `macos-15-intel`, `macos-26`, `macos-latest` 에서 `node --test Tests/Web/*.test.js`, `python3 -I scripts/tests/test_check_apple_releases.py`(오프라인 테스트), `swift test`(미션 카탈로그 검증 포함), ad-hoc 네이티브 패키징을 실행하고, macOS, 아키텍처, Xcode, Swift 버전을 요약에 남깁니다.
- GUI QA(`GUI QA scenarios (AppKit + WKWebView, scripts/qa.sh)` 단계): `test` 매트릭스 중 `macos-latest` 에서만 로컬과 똑같이 `bash scripts/qa.sh` 를 실행합니다. AppKit 창과 WKWebView 를 실제로 띄우므로 GitHub 러너에 창 세션이 있어야 합니다. 앱이 GUI 를 시작하지 못하면 `qa.sh` 의 시나리오당 제한 시간(`MACPET_QA_TIMEOUT`, 기본 150초)에 걸려 stdout/stderr 로그 끝부분과 함께 실패로 보고되며, 실패를 무시하는 설정은 없으므로, 태그 실행에서 여기가 실패하면 초안 릴리스도 만들어지지 않습니다. 지금까지 GUI 시나리오는 전부 로컬 맥에서만 실행했고, GitHub 호스팅 러너에서 실행한 결과는 아직 없습니다.
- `universal release package` 작업은 `test`가 통과하면 ad-hoc 서명된 유니버설 앱 ZIP과 소스 ZIP을 만들고 두 체크섬을 검증합니다. 이 검증용 ZIP 은 러너의 임시 폴더에만 두며 아티팩트나 릴리스로 올리지 않습니다.
- 두 패키징 단계는 `MACPET_RELEASES_URL` 을 실행 중인 저장소(포크면 그 포크)의 Releases 주소로 지정하고, 만든 앱의 `Info.plist` 에 그대로 들어갔는지와 번들의 `LICENSE.txt` 가 `LICENSE` 와 바이트 단위로 같은지 확인합니다.
- `actions/checkout` 은 v7 커밋 `3d3c42e5aac5ba805825da76410c181273ba90b1` 로 고정하고 `persist-credentials: false` 로 씁니다.

러너 목록은 [GitHub-hosted runners 문서](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)를 참고합니다. `macos-latest` 는 더 새 OS 로 바뀌므로 미래 OS 에서의 문제도 미리 알려 줍니다.

## QA

`scripts/qa.sh` 는 증분 빌드로 임시 폴더에 ad-hoc 앱을 만들고, 실행 파일을 직접 띄워 시나리오를 돌립니다. 시나리오마다 저장 파일이 따로이며, 종료 코드 0 과 `[qa] done: ... 0 failed` 줄이 모두 있어야 통과입니다. 제한 시간(`MACPET_QA_TIMEOUT`, 기본 150초)을 넘기거나 Ctrl-C 로 중단하면 스크립트가 띄운 PID 에만 신호를 보내며, 실패하면 로그를 보여 줍니다. 실행 중 펫 창이 잠깐 화면에 뜹니다.
