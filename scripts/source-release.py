#!/usr/bin/env python3
"""공개 소스 배포용 ZIP 과 체크섬을 만든다. Git 을 쓰지 않고, 서명·게시도 하지 않는다.

    scripts/source-release.py [--output-dir DIR]

산출물: DIR/MacPet-<VERSION>-source.zip 과 같은 이름의 .zip.sha256
        (DIR 기본값은 ${MACPET_BUILD_DIR:-build}/release, <VERSION> 은 VERSION 파일 1줄).
VERSION 은 scripts/build-app.sh 와 같은 규칙으로 검사한다: 줄바꿈(LF)으로 끝나는 ASCII 두 줄,
1줄 X.Y.Z, 2줄 빌드 번호. 어긋나면 아무것도 쓰지 않고 실패한다.
ZIP 안의 최상위 폴더는 MacPet-<VERSION>-source/ 이다.

담는 파일은 아래 허용 목록(FILES)에 적힌 것뿐이다. 폴더를 훑어 담지 않으므로 .signing-id,
.claude, .agents, .git, build, 캐시 같은 것은 처음부터 들어갈 수 없다. 공개 파일을 새로 만들면
FILES 에 한 줄을 더해야 하고, 빠뜨리면 실행할 때 경고가 나온다.

같은 내용이면 어느 기계에서든 ZIP 이 바이트까지 같다: 이름순 정렬, 2000-01-01 고정 시각,
0644/0755 고정 권한, 무압축(zlib 버전에 따라 달라지지 않게). 필수 파일이 하나라도 없거나
고른 파일의 경로에 심볼릭 링크가 끼어 있으면 아무것도 쓰지 않고 실패한다.
"""
import argparse
import fcntl
import hashlib
import io
import os
import re
import stat
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def group(base, names):
    return [f"{base}/{name}" for name in names.split()]


FILES = [
    ".gitignore", "CHANGELOG.md", "DESIGN.md", "LICENSE", "Package.swift", "README.md", "VERSION",
    "assets/AppIcon.png",
    *group(".github/workflows", "apple-releases.yml ci.yml release.yml"),
    *group("Sources/MacPet", """
        AccessibilityAccess.swift AppDelegate.swift ElementFinder.swift MissionWatcher.swift
        PanelMover.swift PetPanelController.swift PointerOverlay.swift QARunner.swift
        SaveStore.swift ShortcutWatcher.swift main.swift"""),
    *group("Sources/MacPetCore", """
        Mission.swift MissionCatalog.swift PointGeometry.swift ReleasesURL.swift
        ResumableWalk.swift Shortcut.swift TriggerLogic.swift WatchPlan.swift
        WebSurfacePolicy.swift"""),
    *group("Tests/MacPetCoreTests", """
        MissionCatalogTests.swift PointGeometryTests.swift ResumableWalkTests.swift
        ShortcutTests.swift TriggerLogicTests.swift WatchPlanTests.swift"""),
    "Tests/Web/generations.test.js",
    *group("docs", "COMPATIBILITY.md RELEASING.md pet-collection.png pet-missions.png"),
    *group("qa", """
        advanced.json advanced.save.json design-navigation.json design-navigation.save.json
        early-permission.json first-run.json graduation.json graduation.save.json
        legacy-progress.json legacy-progress.save.json panel-visibility.json
        permission-recovery.json permission-recovery.save.json"""),
    *group("scripts", """
        app-icon.sh apple-macos-releases.baseline.txt build-app.sh check-apple-releases.py
        lock-package-output.sh qa.sh release.sh source-release.py"""),
    "scripts/tests/test_check_apple_releases.py",
    *group("scripts/tests/fixtures", """
        baseline-ok.xml baseline.txt empty.xml entity.xml new-builds.xml no-macos.xml
        truncated.xml weird-title.xml"""),
    *group("web", "app.js collection.js engine.js generations.js index.html missions.json style.css"),
]
# 루트 LICENSE 는 필수(FILES)다. 고지 파일은 있을 때만 담는다.
OPTIONAL = ["NOTICE", "NOTICE.md", "NOTICE.txt"]

# scripts/build-app.sh 의 VERSION 검사와 같은 계약을 파일 전체 바이트에 적용한다: 정확히 두 줄이고 둘 다 LF 로 끝난다.
# 숫자는 0 이거나 앞자리 0 없는 1~9자리, 빌드 번호는 1 이상. 공백, CR, 프리릴리스 접미사, 빈 줄, 셋째 줄은 모두 거부한다.
_NUM = rb"(?:0|[1-9][0-9]{0,8})"
VERSION_FILE = re.compile(rb"(" + _NUM + rb"\." + _NUM + rb"\." + _NUM + rb")\n[1-9][0-9]{0,8}\n")
NOISE = {".DS_Store", "__pycache__"}


class Fail(Exception):
    pass


def read(rel):
    """허용 목록의 파일을 읽는다. 없으면 None. 경로 어디든 심볼릭 링크가 있으면 실패한다."""
    path = ROOT
    for part in rel.split("/"):
        path = os.path.join(path, part)
        try:
            mode = os.lstat(path).st_mode
        except FileNotFoundError:
            return None
        if stat.S_ISLNK(mode):
            raise Fail(f"심볼릭 링크는 담지 않는다: {os.path.relpath(path, ROOT)} ({rel})")
    if not stat.S_ISREG(mode):
        raise Fail(f"일반 파일이 아니다: {rel}")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as f:
        return f.read()


def collect():
    """{상대 경로: 내용}. 필수 파일이 빠졌으면 전부 모아 한 번에 알린다."""
    found, missing = {}, []
    for rel in FILES:
        data = read(rel)
        if data is None:
            missing.append(rel)
        else:
            found[rel] = data
    for rel in OPTIONAL:
        data = read(rel)
        if data is not None:
            found[rel] = data
    if missing:
        raise Fail("필수 파일이 없다: " + ", ".join(missing))
    return found


def unlisted():
    """허용 목록의 폴더 안에 있지만 목록에 없는 파일. 담지는 않고 경고만 한다."""
    extra = []
    for top in sorted({rel.split("/")[0] for rel in FILES if "/" in rel}):
        for folder, dirs, names in os.walk(os.path.join(ROOT, top)):
            dirs[:] = sorted(d for d in dirs if d not in NOISE)
            for name in sorted(names):
                rel = os.path.relpath(os.path.join(folder, name), ROOT).replace(os.sep, "/")
                if name not in NOISE and rel not in FILES:
                    extra.append(rel)
    return extra


def is_executable(rel, data):
    return re.fullmatch(r"scripts/[^/]+\.(sh|py)", rel) is not None and data.startswith(b"#!")


def build_zip(top, files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as z:
        for rel in sorted(files):
            info = zipfile.ZipInfo(f"{top}/{rel}", date_time=(2000, 1, 1, 0, 0, 0))
            info.create_system = 3  # Unix: external_attr 의 권한 비트가 풀 때 적용된다
            mode = 0o755 if is_executable(rel, files[rel]) else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            z.writestr(info, files[rel])
    return buf.getvalue()


def write_all(out_dir, outputs):
    """임시 파일에 모두 쓴 뒤에만 제자리로 옮긴다. 쓰는 중에 실패하면 이전 산출물이 그대로 남는다.

    파일 하나하나의 교체는 원자적이지만 ZIP 과 체크섬은 rename 두 번이라 한 묶음으로 원자적이지 않다.
    두 rename 사이에 프로세스가 죽으면 새 ZIP 과 이전 체크섬이 남는다. 이때 'shasum -a 256 -c' 가
    실패하므로 드러나고, 다시 실행하면 고쳐진다.

    같은 폴더에 쓰는 다른 source-release.py 와 교체가 섞이지 않도록 산출물 폴더의 디스크립터에 flock 을
    건다. 잠금은 열린 폴더에 걸리므로 잠금 파일을 남기지 않고, 프로세스가 끝나면(비정상 종료 포함)
    커널이 푼다.
    """
    os.makedirs(out_dir, exist_ok=True)
    lock = os.open(out_dir, os.O_RDONLY | os.O_DIRECTORY)
    staged = []
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for name, data in outputs:
            fd, tmp = tempfile.mkstemp(prefix=f".{name}.", dir=out_dir)
            staged.append((tmp, os.path.join(out_dir, name)))
            with os.fdopen(fd, "wb") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            os.chmod(tmp, 0o644)
        for tmp, final in staged:
            os.replace(tmp, final)
    finally:
        for tmp, _ in staged:
            if os.path.lexists(tmp):
                os.unlink(tmp)
        os.close(lock)  # 닫으면 잠금도 풀린다


def main():
    parser = argparse.ArgumentParser(description="MacPet 소스 배포 ZIP 과 체크섬을 만든다.")
    parser.add_argument("--output-dir", help="산출물 폴더 (기본 ${MACPET_BUILD_DIR:-build}/release)")
    args = parser.parse_args()
    out_dir = args.output_dir or os.path.join(os.environ.get("MACPET_BUILD_DIR") or "build", "release")
    out_dir = os.path.join(ROOT, out_dir) if args.output_dir is None else os.path.abspath(out_dir)

    try:
        if len(set(FILES)) != len(FILES):
            raise Fail("허용 목록에 중복이 있다")
        files = collect()
        match = VERSION_FILE.fullmatch(files["VERSION"])
        if not match:
            raise Fail("VERSION 은 줄바꿈으로 끝나는 정확히 두 줄이어야 한다: 1줄 X.Y.Z (예: 0.2.0), "
                       "2줄 1 이상의 정수 빌드 번호 (예: 2). 앞자리 0, 공백, CRLF, 프리릴리스 접미사는 안 된다")
        version = match.group(1).decode("ascii")
        name = f"MacPet-{version}-source"
        data = build_zip(name, files)
        digest = hashlib.sha256(data).hexdigest()
        # 체크섬 파일은 파일 이름만 담아서 폴더를 옮겨도 'shasum -a 256 -c' 가 통한다.
        write_all(out_dir, [(f"{name}.zip", data), (f"{name}.zip.sha256", f"{digest}  {name}.zip\n".encode())])
    except (Fail, OSError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    for rel in unlisted():
        print(f"warning: 허용 목록에 없어 담지 않았다: {rel}", file=sys.stderr)
    print(f"source release: {os.path.join(out_dir, name)}.zip ({len(files)} files)")
    print(f"checksum: {os.path.join(out_dir, name)}.zip.sha256")
    return 0


if __name__ == "__main__":
    sys.exit(main())
