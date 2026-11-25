#!/bin/bash
# 배포용 ZIP 과 체크섬을 만든다. 게시(업로드, GitHub Release)는 하지 않는다.
#   scripts/release.sh            유니버설(arm64 + x86_64) 앱  -> MacPet-<VERSION>-macos-universal.zip
#   scripts/release.sh --native   현재 맥 아키텍처 앱           -> MacPet-<VERSION>-macos-<arch>.zip
# 산출물: $MACPET_BUILD_DIR/release/ 아래 <이름>.zip 과 <이름>.zip.sha256 (기본 build/release/). <VERSION> 은 VERSION 파일 1줄.
# 새 ZIP·체크섬은 임시 폴더에서 서명·압축 해제·체크섬 검증을 마친 뒤에만 옮기므로, 실패하면 이전 산출물이 그대로 남는다.
# ad-hoc 서명이면 ZIP 이 재현 가능(mtime 고정, 정렬, zip -X)하고, Developer ID 서명이면 ditto 로 묶는다.
# 환경변수 (build-app.sh 와 같은 것 포함, 자세한 내용은 docs/RELEASING.md):
#   MACPET_BUILD_DIR       산출물 폴더 (기본 build)
#   MACPET_SIGN_ID         지정하지 않으면 ad-hoc('-'). .signing-id 는 릴리스에서 쓰지 않는다. 지정하면 그 인증서로 서명(옵트인)
#   MACPET_RELEASE_SIGN=1  Developer ID + hardened runtime + 타임스탬프 서명 (MACPET_SIGN_ID 필요)
#   MACPET_NOTARY_PROFILE  공증용 Keychain 프로필 이름. 지정하면 notarytool 제출 → stapler → 최종 ZIP (MACPET_RELEASE_SIGN=1 필요)
#   MACPET_RELEASES_URL    선택. https://github.com/OWNER/REPO/releases
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

die() { echo "error: $*" >&2; exit 1; }

case "$#:${1:-}" in
    0:) UNIVERSAL=1 ;;
    1:--native) UNIVERSAL=0 ;;
    *) die "usage: scripts/release.sh [--native]" ;;
esac

NOTARY="${MACPET_NOTARY_PROFILE:-}"
if [ -n "$NOTARY" ] && [ "${MACPET_RELEASE_SIGN:-0}" != 1 ]; then
    die "공증(MACPET_NOTARY_PROFILE)은 MACPET_RELEASE_SIGN=1 과 Developer ID 인증서가 있어야 한다"
fi
# 명시하지 않았으면 ad-hoc. 개인 .signing-id 가 배포물에 섞이지 않게 한다.
export MACPET_SIGN_ID="${MACPET_SIGN_ID:--}"

BUILD="${MACPET_BUILD_DIR:-build}"
case "$BUILD" in /*) ;; *) BUILD="$ROOT/$BUILD" ;; esac
BUILD="${BUILD%/}"
[ -n "$BUILD" ] || die "MACPET_BUILD_DIR 이 올바르지 않다"
export MACPET_BUILD_DIR="$BUILD"

# 같은 산출물 폴더를 쓰는 패키징을 직렬화한다. 아래 build-app.sh 는 9번 디스크립터로 이 잠금을 물려받고,
# 잠금은 이 스크립트가 끝날 때(공증·ZIP 이동 포함)까지 유지된다.
# shellcheck source=scripts/lock-package-output.sh disable=SC1091
. scripts/lock-package-output.sh

if [ "$UNIVERSAL" = 1 ]; then
    bash scripts/build-app.sh --universal
    APP="$BUILD/universal/MacPet.app"; TAG=universal
else
    bash scripts/build-app.sh
    APP="$BUILD/MacPet.app"; TAG=$(uname -m)
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
[[ $VERSION =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "앱의 짧은 버전이 X.Y.Z 가 아니다: $VERSION"
NAME="MacPet-$VERSION-macos-$TAG"
OUT="$BUILD/release"
mkdir -p "$OUT"

# 새 ZIP 과 체크섬은 같은 볼륨의 임시 폴더에서 만들고 검증한다. 모두 통과해야 $OUT 으로 옮기므로
# 중간에 실패해도 이전 ZIP + SHA 는 그대로 남는다.
STAGE=$(mktemp -d "$OUT/.stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

if [ -n "$NOTARY" ]; then
    # 공증은 ZIP 으로 제출하고, 티켓을 앱에 stapling 한 뒤 최종 ZIP 을 다시 만든다.
    ditto -c -k --keepParent "$APP" "$STAGE/notarize.zip"
    xcrun notarytool submit "$STAGE/notarize.zip" --keychain-profile "$NOTARY" --wait | tee "$STAGE/notary.log"
    grep -q 'status: Accepted' "$STAGE/notary.log" || die "공증이 승인되지 않았다 (위 출력의 id 로 'xcrun notarytool log' 확인)"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    rm -f "$STAGE/notarize.zip"
fi

codesign --verify --deep --strict --verbose=2 "$APP"

if [ "$MACPET_SIGN_ID" = "-" ]; then
    # ad-hoc: 같은 소스·같은 체크아웃 경로·같은 툴체인이면 ZIP 이 바이트까지 같도록 만든다.
    # 방금 복사한 임시 트리에서만 mtime 을 2000-01-01 UTC 로 고정하고(빌드 산출물은 건드리지 않음),
    # 항목은 C 로케일 순서로 정렬해 /usr/bin/zip -X (파일 메타데이터 extra 없음) 로 묶는다.
    mkdir "$STAGE/tree"
    ditto "$APP" "$STAGE/tree/MacPet.app"
    find "$STAGE/tree" -exec env TZ=UTC touch -h -t 200001010000 {} +
    (cd "$STAGE/tree" && find MacPet.app -print | LC_ALL=C sort | TZ=UTC /usr/bin/zip -X -q -y -@ "$STAGE/$NAME.zip")
else
    # Developer ID(공증 포함) 패키지는 ditto 로 묶는다.
    ditto -c -k --keepParent "$APP" "$STAGE/$NAME.zip"
fi

# 풀어서 서명이 살아 있고 버전과 아이콘이 맞는지 확인한다.
mkdir "$STAGE/unzipped"
ditto -x -k "$STAGE/$NAME.zip" "$STAGE/unzipped"
codesign --verify --deep --strict --verbose=2 "$STAGE/unzipped/MacPet.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STAGE/unzipped/MacPet.app/Contents/Info.plist")" = "$VERSION" ] ||
    die "ZIP 안의 앱 버전이 $VERSION 이 아니다"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$STAGE/unzipped/MacPet.app/Contents/Info.plist")" = "$BUILD_NUMBER" ] ||
    die "ZIP 안의 앱 빌드 번호가 $BUILD_NUMBER 가 아니다"
cmp -s "$ROOT/LICENSE" "$STAGE/unzipped/MacPet.app/Contents/Resources/LICENSE.txt" ||
    die "ZIP 안의 앱 LICENSE.txt 가 저장소 LICENSE 와 바이트 단위로 같지 않다"
# 풀린 앱의 아이콘: plist 참조, 파일 존재, 그리고 번들 밖 임시 iconset 으로 풀어 표준 10종을 확인한다 (앱은 읽기만 한다).
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$STAGE/unzipped/MacPet.app/Contents/Info.plist")" = "MacPet.icns" ] ||
    die "ZIP 안의 앱 CFBundleIconFile 이 MacPet.icns 가 아니다"
[ -s "$STAGE/unzipped/MacPet.app/Contents/Resources/MacPet.icns" ] || die "ZIP 안의 앱에 MacPet.icns 가 없거나 비어 있다"
TMPDIR="$STAGE" bash scripts/app-icon.sh verify "$STAGE/unzipped/MacPet.app/Contents/Resources/MacPet.icns"

# 체크섬 파일은 파일 이름만 담아서 폴더를 옮겨도 'shasum -a 256 -c' 가 통한다.
(cd "$STAGE" && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256" && shasum -a 256 -c "$NAME.zip.sha256")

# 모두 통과했으니 제자리로 옮긴다 (같은 볼륨이라 mv 는 rename).
mv -f "$STAGE/$NAME.zip" "$OUT/$NAME.zip"
mv -f "$STAGE/$NAME.zip.sha256" "$OUT/$NAME.zip.sha256"
echo "release: $OUT/$NAME.zip"
echo "checksum: $OUT/$NAME.zip.sha256"
