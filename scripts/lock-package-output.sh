# shellcheck shell=bash
# build-app.sh 와 release.sh 가 source 한다. 절대 경로로 검증된 $BUILD 와 die 가 필요하다.
# 같은 산출물 폴더를 쓰는 패키징을 직렬화한다: $BUILD/.macpet-package.lock 을 9번 디스크립터로 열고
# 커널 flock 을 건다. 잠금은 열린 파일에 걸리므로 경로 표기가 달라도(심볼릭 링크 등) 같은 폴더면 같은 잠금이고,
# 이 셸이 끝나면(비정상 종료 포함) 커널이 푼다. 잠금 파일은 지우지 않는다. 파일이 있다는 것만으로는 잠금이 아니다.
mkdir -p "$BUILD" || die "산출물 폴더를 만들지 못했다: $BUILD"
lockpath="$BUILD/.macpet-package.lock"
# macOS 에서는 [[ /dev/fd/9 -ef 경로 ]] 가 같은 파일이어도 거짓이라, fstat 과 stat 을 python3 로 비교한다.
if [[ -e /dev/fd/9 && -f "$lockpath" ]] &&
    python3 -I -c 'import os, sys; sys.exit(not os.path.samestat(os.fstat(9), os.stat(sys.argv[1])))' "$lockpath" 2>/dev/null; then
    : # release.sh 가 잡은 잠금을 물려받은 build-app.sh. 같은 열린 파일이므로 다시 잡지 않는다.
else
    exec 9>>"$lockpath" || die "잠금 파일을 열지 못했다: $lockpath"
    # macOS 14 에는 lockf(1) 이 없어서, 물려준 9번 디스크립터에 python3 로 flock 을 건다.
    python3 -I -c '
import fcntl, sys
try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.stderr.write("같은 산출물 폴더의 다른 패키징이 끝나기를 기다린다...\n")
    fcntl.flock(9, fcntl.LOCK_EX)
' || die "패키징 잠금을 얻지 못했다: $lockpath"
fi
unset lockpath
