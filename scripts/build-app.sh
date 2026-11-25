#!/bin/bash
# MacPet.app 조립 스크립트.
#   scripts/build-app.sh               현재 맥 아키텍처용 앱  -> $MACPET_BUILD_DIR/MacPet.app (기본 build/MacPet.app)
#   scripts/build-app.sh --universal   arm64 + x86_64 유니버설 -> $MACPET_BUILD_DIR/universal/MacPet.app
# 환경변수:
#   MACPET_BUILD_DIR       산출물 폴더 (기본 build, 상대 경로는 저장소 루트 기준)
#   MACPET_SIGN_ID         서명 ID(인증서 이름 전체 또는 SHA-1). '-' 는 ad-hoc. 없으면 .signing-id, 그것도 없으면 ad-hoc
#   MACPET_RELEASE_SIGN=1  Developer ID + hardened runtime + 보안 타임스탬프 서명. MACPET_SIGN_ID 를 명시해야 하고 .signing-id 는 쓰지 않는다
#   MACPET_RELEASES_URL    선택. https://github.com/OWNER/REPO/releases 형태만 허용, Info.plist 의 MacPetReleasesURL 로 들어간다.
#                          빈 값으로 지정하면 키를 넣지 않는다. 지정하지 않으면(unset) 다음처럼 정한다:
#                            - 루트에 .git 이 있는 체크아웃: origin 이 https://github.com/OWNER/REPO, git@github.com:OWNER/REPO,
#                              ssh://git@github.com/OWNER/REPO (끝의 .git 과 / 는 있어도 됨) 중 하나면 그 저장소의 releases 주소를 쓴다.
#                              origin 이 없거나 그 밖의 형태(GitHub 가 아님, 인증 정보 포함 등)면 키를 넣지 않는다. origin 값은 출력하지 않는다
#                            - 루트에 .git 이 없는 소스 아카이브(다른 체크아웃 안에 풀려 있어도): https://github.com/sjk0503/MacPet/releases
# 버전은 저장소 루트의 VERSION 파일이 유일한 출처다. 정확히 두 줄:
#   1줄  X.Y.Z   점으로 나눈 숫자 3개 (앞자리 0 금지, 0 자체는 허용)  -> CFBundleShortVersionString (파일 이름에도 쓰임)
#   2줄  N       1 이상의 정수 빌드 번호 (앞자리 0 금지)             -> CFBundleVersion
# 앱 아이콘은 assets/AppIcon.png (1024x1024 투명 PNG) 하나가 출처다. scripts/app-icon.sh 가 서명 전에
# Contents/Resources/MacPet.icns 로 만든다. 없거나 규격이 다르면 빌드가 실패한다.
# 앱은 임시 형제 폴더에 조립·서명·검증한 뒤 성공했을 때만 이전 산출물을 교체한다.
set -euo pipefail
export LC_ALL=C   # 정규식의 [A-Za-z0-9] 가 ASCII 만 뜻하도록
cd "$(dirname "$0")/.."
ROOT=$PWD
MIN_OS=14.0   # Package.swift 의 .macOS(.v14) 와 같아야 한다. 어긋나면 아래 minos 검사가 실패한다.

die() { echo "error: $*" >&2; exit 1; }

UNIVERSAL=0
case "$#:${1:-}" in
    0:) ;;
    1:--universal) UNIVERSAL=1 ;;
    *) die "usage: scripts/build-app.sh [--universal]" ;;
esac

# --- 입력 검증 ---
[ -f VERSION ] || die "VERSION 파일이 없다"
[ "$(wc -l < VERSION | tr -d ' ')" = 2 ] || die "VERSION 은 정확히 두 줄이어야 한다 (1줄 X.Y.Z, 2줄 빌드 번호)"
VERSION=$(sed -n 1p VERSION)
BUILD_NUMBER=$(sed -n 2p VERSION)
[[ $VERSION =~ ^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$ ]] || die "VERSION 1줄은 점으로 나눈 숫자 3개여야 한다 (예: 0.2.0)"
[[ $BUILD_NUMBER =~ ^[1-9][0-9]{0,8}$ ]] || die "VERSION 2줄은 1 이상의 정수 빌드 번호여야 한다 (예: 2)"
ICON_SRC="$ROOT/assets/AppIcon.png"
[ -f "$ICON_SRC" ] || die "assets/AppIcon.png 이 없다 (1024x1024 투명 PNG 앱 아이콘 원본)"

# Sources/MacPetCore/ReleasesURL.swift 와 같은 규칙: OWNER/REPO 모두 ASCII 영숫자로 시작, 이후 영숫자 . _ -
re='^https://github\.com/[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*/releases/?$'
RELEASES_URL=""
if [ -n "${MACPET_RELEASES_URL+set}" ]; then
    # 명시한 값이 우선한다. 빈 값은 키를 넣지 않겠다는 뜻이다.
    RELEASES_URL=$MACPET_RELEASES_URL
    if [ -n "$RELEASES_URL" ]; then
        [[ $RELEASES_URL =~ $re ]] || die "MACPET_RELEASES_URL 은 https://github.com/OWNER/REPO/releases 형태여야 한다 (OWNER, REPO 는 영숫자로 시작)"
        RELEASES_URL="${RELEASES_URL%/}"
    fi
elif [ -e "$ROOT/.git" ]; then
    # 이 체크아웃의 origin 에서 추론한다. --git-dir 로 고정해 상위 폴더의 다른 저장소를 찾지 않게 하고,
    # origin 값(인증 정보가 들어 있을 수 있다)은 어디에도 출력하지 않는다. 알 수 없으면 키를 넣지 않는다.
    origin=$(git --git-dir="$ROOT/.git" config --local --get remote.origin.url 2>/dev/null || true)
    slug=""
    case "$origin" in
        https://github.com/*)     slug=${origin#https://github.com/} ;;
        git@github.com:*)         slug=${origin#git@github.com:} ;;
        ssh://git@github.com/*)   slug=${origin#ssh://git@github.com/} ;;
    esac
    slug=${slug%/}
    slug=${slug%.git}
    candidate="https://github.com/$slug/releases"
    if [[ $candidate =~ $re ]]; then RELEASES_URL=$candidate; fi
    unset origin slug candidate
else
    # 자체 .git 이 없는 소스 아카이브: 공식 저장소를 기본값으로 쓴다.
    RELEASES_URL="https://github.com/sjk0503/MacPet/releases"
fi

BUILD="${MACPET_BUILD_DIR:-build}"
case "$BUILD" in /*) ;; *) BUILD="$ROOT/$BUILD" ;; esac
BUILD="${BUILD%/}"
[ -n "$BUILD" ] || die "MACPET_BUILD_DIR 이 올바르지 않다"

RELEASE_SIGN="${MACPET_RELEASE_SIGN:-0}"
case "$RELEASE_SIGN" in 0|1) ;; *) die "MACPET_RELEASE_SIGN 은 1 또는 0" ;; esac

# --- 서명 ID 결정: 명시한 MACPET_SIGN_ID > .signing-id(이 맥 전용) > ad-hoc ---
SIGN_ID="${MACPET_SIGN_ID:-}"
if [ "$RELEASE_SIGN" = 1 ]; then
    { [ -n "$SIGN_ID" ] && [ "$SIGN_ID" != "-" ]; } || die "MACPET_RELEASE_SIGN=1 은 MACPET_SIGN_ID 에 Developer ID Application 인증서를 명시해야 한다"
elif [ -z "$SIGN_ID" ] && [ -f .signing-id ]; then
    # 인증서 이름에 공백이 있을 수 있으니 양 끝 공백만 지운다.
    SIGN_ID=$(head -n 1 .signing-id | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
fi
[ -n "$SIGN_ID" ] || SIGN_ID="-"

# 같은 산출물 폴더를 쓰는 다른 build-app.sh / release.sh 가 끝날 때까지 기다린다 (Swift 빌드 전부터 종료까지 유지).
# shellcheck source=scripts/lock-package-output.sh disable=SC1091
. scripts/lock-package-output.sh

minos_of() {  # $1=파일 [$2=아키텍처]
    if [ -n "${2:-}" ]; then xcrun vtool -arch "$2" -show-build "$1"; else xcrun vtool -show-build "$1"; fi |
        awk '$1 == "minos" { print $2; exit }'
}
check_minos() {
    local m; m=$(minos_of "$@")
    [ "$m" = "$MIN_OS" ] || die "$1 ${2:-} 의 최소 macOS 가 $MIN_OS 가 아니라 '${m:-없음}' 이다"
    echo "minos ok: ${2:-native} $m"
}

# --- 빌드 ---
if [ "$UNIVERSAL" = 1 ]; then
    APP="$BUILD/universal/MacPet.app"
    SLICES=()
    for arch in arm64 x86_64; do
        # 네이티브 빌드와 .build 를 공유하지 않도록 아키텍처마다 scratch 폴더를 따로 쓴다.
        sw=(swift build -c release --triple "$arch-apple-macosx$MIN_OS" --scratch-path "$ROOT/.build/universal-$arch")
        "${sw[@]}"
        SLICES+=("$("${sw[@]}" --show-bin-path)/MacPet")
    done
else
    APP="$BUILD/MacPet.app"
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/MacPet"
fi

# 같은 볼륨의 임시 형제 폴더에서 조립한다. 실패하면 이전 $APP 은 그대로 남는다.
mkdir -p "$(dirname "$APP")"
STAGE=$(mktemp -d "$(dirname "$APP")/.macpet-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
FINAL_APP=$APP
APP="$STAGE/MacPet.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
if [ "$UNIVERSAL" = 1 ]; then
    lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/MacPet"
    ARCHS=$(lipo -archs "$APP/Contents/MacOS/MacPet" | tr ' ' '\n' | sort | tr '\n' ' ')
    [ "$ARCHS" = "arm64 x86_64 " ] || die "유니버설 아키텍처가 arm64 x86_64 가 아니다: $ARCHS"
    check_minos "$APP/Contents/MacOS/MacPet" arm64
    check_minos "$APP/Contents/MacOS/MacPet" x86_64
else
    cp "$BIN" "$APP/Contents/MacOS/MacPet"
    check_minos "$APP/Contents/MacOS/MacPet"
fi

# 의도한 웹 자산만 넣는다 (.DS_Store 같은 숨김 파일, 편집기 임시 파일 제외).
(
    cd web
    find . -type f ! -path '*/.*' \( -name '*.html' -o -name '*.css' -o -name '*.js' -o -name '*.json' \
        -o -name '*.svg' -o -name '*.png' -o -name '*.jpg' -o -name '*.webp' -o -name '*.woff2' \) -print | sort
) | while IFS= read -r f; do
    mkdir -p "$APP/Contents/Resources/web/$(dirname "$f")"
    cp "web/$f" "$APP/Contents/Resources/web/$f"
done
[ -f "$APP/Contents/Resources/web/index.html" ] || die "web/index.html 이 앱에 들어가지 않았다"

# 앱 아이콘: 중간 iconset 은 앱 밖($STAGE 아래 임시 폴더)에만 생기고, 검증된 icns 만 서명 전에 들어간다.
TMPDIR="$STAGE" bash scripts/app-icon.sh build "$ICON_SRC" "$APP/Contents/Resources/MacPet.icns"

URL_KEY=""
[ -z "$RELEASES_URL" ] || URL_KEY="    <key>MacPetReleasesURL</key><string>$RELEASES_URL</string>"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.macpetguide.prototype</string>
    <key>CFBundleName</key><string>MacPet</string>
    <key>CFBundleDisplayName</key><string>MacPet</string>
    <key>CFBundleExecutable</key><string>MacPet</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>MacPet.icns</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
    <key>NSHighResolutionCapable</key><true/>
$URL_KEY
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# --- 서명 ---
# 서명 전에 디버그 심볼을 지워 빌드한 기기의 경로(체크아웃·홈 디렉터리)가 배포본에 남지 않게 한다.
/usr/bin/strip -S "$APP/Contents/MacOS/MacPet"
# ad-hoc 서명은 빌드할 때마다 서명이 달라져서, 다시 빌드하면 손쉬운 사용 권한을 다시 줘야 한다.
# 고정 인증서로 서명하면 권한이 유지된다. 인증서 이름은 출력하지 않는다.
if [ "$RELEASE_SIGN" = 1 ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
    DETAILS=$(codesign -dvv "$APP" 2>&1)
    case "$DETAILS" in *"Authority=Developer ID Application"*) ;; *) die "Developer ID Application 인증서로 서명되지 않았다" ;; esac
    case "$DETAILS" in *runtime*) ;; *) die "hardened runtime 이 켜지지 않았다" ;; esac
    echo "signed for release (Developer ID, hardened runtime, timestamp)"
elif [ "$SIGN_ID" != "-" ]; then
    codesign --force --sign "$SIGN_ID" "$APP"
    echo "signed with a fixed certificate (권한이 다시 빌드해도 유지됨)"
else
    codesign --force --sign - "$APP"
    echo "signed ad-hoc (손쉬운 사용 권한은 빌드마다 다시 줘야 함)"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

# 검증을 통과한 뒤에만 이전 산출물을 교체한다.
if [ -e "$FINAL_APP" ]; then mv "$FINAL_APP" "$STAGE/previous.app"; fi
mv "$APP" "$FINAL_APP" || { [ ! -e "$STAGE/previous.app" ] || mv "$STAGE/previous.app" "$FINAL_APP"; die "앱을 제자리로 옮기지 못했다"; }
echo "built: $FINAL_APP (version $VERSION, build $BUILD_NUMBER)"
