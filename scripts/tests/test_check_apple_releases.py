import importlib.util
import io
import contextlib
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("car", HERE.parent / "check-apple-releases.py")
car = importlib.util.module_from_spec(spec)
spec.loader.exec_module(car)
FX = HERE / "fixtures"
BASE = HERE.parent / "apple-macos-releases.baseline.txt"  # 실제 기준선: 형식 검사에만 쓴다
FIXED_BASE = FX / "baseline.txt"  # 픽스처용 고정 기준선: 실제 기준선에 새 빌드가 추가돼도 테스트가 흔들리지 않는다


def run(name):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = car.main(["--input", str(FX / name), "--baseline", str(FIXED_BASE)])
    return code, out.getvalue(), err.getvalue()


class CheckAppleReleases(unittest.TestCase):
    def test_known_builds_pass(self):
        self.assertEqual(run("baseline-ok.xml")[0], car.EXIT_OK)

    def test_new_builds_listed(self):
        code, out, _ = run("new-builds.xml")
        self.assertEqual(code, car.EXIT_UNSEEN)
        self.assertIn("macOS 27.3 RC (26C5100)", out)
        self.assertIn("macOS 27.4 beta 1 (26D5001a)", out)
        self.assertNotIn("26C5047e\n", out.split("기준선에 없는")[1].split("다음 순서")[0])

    def test_malformed_inputs_exit_2(self):
        for name in ("empty.xml", "truncated.xml", "no-macos.xml", "entity.xml"):
            with self.subTest(name):
                self.assertEqual(run(name)[0], car.EXIT_MALFORMED)

    def test_weird_title_not_echoed(self):
        code, out, err = run("weird-title.xml")
        self.assertEqual(code, car.EXIT_MALFORMED)
        self.assertNotIn("pwned", out + err)

    def test_baseline_has_only_valid_titles(self):
        for t in car.load_baseline(BASE):
            self.assertRegex(t, car.MACOS_TITLE)

    def test_fetch_rejects_non_https(self):
        with self.assertRaises(car.FetchError):
            car.fetch("http://example.com/x")


if __name__ == "__main__":
    unittest.main()
