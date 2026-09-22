#!/usr/bin/env python3
"""Open a Sowbelly build in a real browser and check it actually starts.

    python3 caves/tools/browser_check.py [path/to/page.html]

Defaults to the standalone bundle, opened from a file:// URL - which is the thing worth
checking, because that is the one configuration a plain `godot --export` cannot do and the one
tools/bundle_single.py exists to make work. Pass any other path (or an http:// URL) to check a
normally-served build instead.

Headless Chromium with SwiftShader, so it runs on a machine with no GPU. It waits for the
engine to report progress, presses "Play on desktop", lets the cave build, and then screenshots
and reports what the console said. It is not a pass/fail gate on the gameplay - the headless
autotests do that - it is the check that the PAGE works: that the wasm loaded, the pck mounted,
no exception was thrown, and something was drawn.
"""

import os
import re
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT = os.path.join(ROOT, "build", "caves", "sowbelly-standalone.html")
SHOTS = os.path.join(ROOT, "build", "shots")

# Things the page says that mean it is working, and things that mean it is not.
GOOD = [r"\[cave\] ", r"Godot Engine v"]
BAD = [r"Uncaught", r"failed to", r"NetworkError", r"not allowed", r"SCRIPT ERROR",
       r"Failed to fetch", r"CORS", r"Aborted"]


def main(target):
    from playwright.sync_api import sync_playwright

    url = target if "://" in target else "file://" + os.path.abspath(target)
    if "://" not in target and not os.path.exists(target):
        raise SystemExit("browser_check: no such file: %s\n"
                         "Build it first: python3 caves/tools/bundle_single.py" % target)
    os.makedirs(SHOTS, exist_ok=True)
    size = None if "://" in target and not target.startswith("file:") else os.path.getsize(target)
    print("opening %s%s" % (url, "  (%.1f MB)" % (size / 1e6) if size else ""))

    # A pre-installed Chromium is often a different build number from whatever pip pulled, and
    # Playwright will not use it unless pointed at the binary. CHROME_PATH, then the usual
    # sandbox location, then Playwright's own idea of where its browser is.
    exe = os.environ.get("CHROME_PATH")
    if not exe:
        for guess in ("/opt/pw-browsers/chromium",
                      "/usr/bin/chromium", "/usr/bin/chromium-browser",
                      "/usr/bin/google-chrome"):
            if os.path.exists(guess):
                exe = guess
                break

    log = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path=exe, args=[
            "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
            "--autoplay-policy=no-user-gesture-required",
            "--allow-file-access-from-files",
        ])
        page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.on("console", lambda m: log.append("%s: %s" % (m.type, m.text)))
        page.on("pageerror", lambda e: log.append("pageerror: %s" % e))

        page.goto(url)
        # 13 MB of base64 to decode, decompress and instantiate; SwiftShader is not quick.
        deadline = time.time() + 180
        started = False
        while time.time() < deadline:
            page.wait_for_timeout(2000)
            if any(re.search(p, line) for line in log for p in GOOD):
                started = True
                break
        page.screenshot(path=os.path.join(SHOTS, "01-loaded.png"))

        # "Play on desktop" is the second button down the middle of the title screen.
        page.mouse.click(640, 400)
        page.wait_for_timeout(2000)
        for y in (360, 380, 420, 440):
            page.mouse.click(640, y)
            page.wait_for_timeout(600)
        page.wait_for_timeout(12000)
        page.screenshot(path=os.path.join(SHOTS, "02-playing.png"))

        # Walk forward a little, and open the slate.
        page.keyboard.down("w")
        page.wait_for_timeout(2500)
        page.keyboard.up("w")
        page.keyboard.press("Tab")
        page.wait_for_timeout(1500)
        page.screenshot(path=os.path.join(SHOTS, "03-moved.png"))
        browser.close()

    print("\n--- console ---")
    for line in log[-40:]:
        print("  " + line[:200])

    problems = [line for line in log if any(re.search(p, line, re.I) for p in BAD)]
    built = [line for line in log if "[cave]" in line]
    print("\n--- verdict ---")
    for line in built:
        print("  " + line[:200])
    print("  screenshots in %s" % SHOTS)
    if problems:
        print("\n  %d problem line(s):" % len(problems))
        for line in problems[:10]:
            print("    " + line[:200])
        return 1
    if not started:
        print("\n  the engine never reported starting - see the screenshots")
        return 1
    print("\n  ok - the page loads and the cave builds")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else DEFAULT))
