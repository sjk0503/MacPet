#!/bin/bash
# MacPet 앱 아이콘(.icns) 생성·검증 도우미. macOS 기본 도구(/usr/bin/sips, /usr/bin/iconutil)만 쓴다.
#   scripts/app-icon.sh build  <원본.png> <출력.icns>   1024x1024 투명 PNG -> 표준 10종 iconset -> icns (검증을 통과해야 출력)
#   scripts/app-icon.sh verify <파일.icns>              icns 를 임시 iconset 으로 풀어 표준 10종과 픽셀 크기를 확인
# 원본과 검증 대상은 읽기만 한다. 중간 iconset 은 $TMPDIR(기본 /tmp) 아래 임시 폴더에만 만들고 끝나면 지운다.
set -euo pipefail
export LC_ALL=C

die() { echo "error: $*" >&2; exit 1; }

# 표준 iconset 구성원 "파일이름:픽셀" (16, 32, 128, 256, 512 포인트의 @1x 와 @2x)
MEMBERS="icon_16x16.png:16 icon_16x16@2x.png:32 icon_32x32.png:32 icon_32x32@2x.png:64
icon_128x128.png:128 icon_128x128@2x.png:256 icon_256x256.png:256 icon_256x256@2x.png:512
icon_512x512.png:512 icon_512x512@2x.png:1024"

info() {  # $1=이미지 -> "형식:가로x세로:알파" (읽지 못하면 빈 칸)
    /usr/bin/sips -g format -g pixelWidth -g pixelHeight -g hasAlpha "$1" 2>/dev/null |
        awk '$1 == "format:" { f = $2 } $1 == "pixelWidth:" { w = $2 } $1 == "pixelHeight:" { h = $2 }
             $1 == "hasAlpha:" { a = $2 } END { print f ":" w "x" h ":" a }' || true
}

verify() {  # $1=icns
    local m f px
    [ -s "$1" ] || die "아이콘 파일이 없거나 비어 있다: $1"
    /usr/bin/iconutil -c iconset "$1" -o "$WORK/verify.iconset" || die "icns 를 iconset 으로 풀 수 없다: $1"
    for m in $MEMBERS; do
        f="$WORK/verify.iconset/${m%%:*}"; px=${m##*:}
        [ -s "$f" ] || die "icns 에 ${m%%:*} 이 없다: $1"
        case "$(info "$f")" in
            "png:${px}x${px}:"*) ;;
            *) die "icns 의 ${m%%:*} 이 ${px}x${px} PNG 가 아니다: $1" ;;
        esac
    done
}

case "$#:${1:-}" in
    3:build|2:verify) ;;
    *) die "usage: scripts/app-icon.sh build <source.png> <output.icns> | verify <file.icns>" ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/macpet-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

if [ "$1" = verify ]; then
    verify "$2"
    echo "icon ok: $2"
    exit 0
fi

SRC=$2
OUT=$3
[ -f "$SRC" ] || die "앱 아이콘 원본이 없다: $SRC (1024x1024 투명 PNG 가 필요하다)"
[ "$(head -c 8 "$SRC" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a ] || die "앱 아이콘 원본이 PNG 가 아니다: $SRC"
I=$(info "$SRC")
case "$I" in png:[0-9]*) ;; *) die "앱 아이콘 원본을 PNG 로 읽을 수 없다 (손상됨): $SRC" ;; esac
case "$I" in png:1024x1024:*) ;; *) die "앱 아이콘 원본은 1024x1024 여야 한다 (지금 $(echo "$I" | cut -d: -f2)): $SRC" ;; esac
case "$I" in *:yes) ;; *) die "앱 아이콘 원본에 알파 채널이 없다: $SRC" ;; esac

mkdir "$WORK/MacPet.iconset"
for m in $MEMBERS; do
    f="$WORK/MacPet.iconset/${m%%:*}"; px=${m##*:}
    if [ "$px" = 1024 ]; then
        cp "$SRC" "$f"   # 가장 큰 항목은 원본 그대로
    else
        /usr/bin/sips -s format png -z "$px" "$px" "$SRC" --out "$f" >/dev/null
    fi
done
/usr/bin/iconutil -c icns "$WORK/MacPet.iconset" -o "$WORK/MacPet.icns"
verify "$WORK/MacPet.icns"
cp "$WORK/MacPet.icns" "$OUT"
echo "icon built: $OUT"
