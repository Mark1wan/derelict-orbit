"""Load build/web in headless Chromium, click 'Play on desktop', force night, screenshot.
Usage: python3 tools/browser_check.py"""
import asyncio, http.server, threading, functools, os

ROOT = os.path.join(os.path.dirname(__file__), "..", "build", "web")
PORT = 8765
OUT = os.path.join(os.path.dirname(__file__), "..", "build", "shots")
os.makedirs(OUT, exist_ok=True)

def serve():
    h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=ROOT)
    h.log_message = lambda *a, **k: None
    http.server.ThreadingHTTPServer.allow_reuse_address = True
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), h).serve_forever()

async def main():
    from playwright.async_api import async_playwright
    threading.Thread(target=serve, daemon=True).start()
    async with async_playwright() as p:
        b = await p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
                                          "--autoplay-policy=no-user-gesture-required"])
        pg = await b.new_page(viewport={"width": 1280, "height": 720})
        pg.set_default_timeout(120000)
        logs = []
        pg.on("console", lambda m: logs.append(f"[{m.type}] {m.text}"))
        pg.on("pageerror", lambda e: logs.append(f"[pageerror] {e}"))
        await pg.goto(f"http://127.0.0.1:{PORT}/index.html")
        await pg.wait_for_timeout(15000)
        w, h = 1280, 720
        await pg.mouse.click(w / 2, h / 2 + 52)          # "Play on desktop"
        await pg.wait_for_timeout(4000)
        await pg.screenshot(path=os.path.join(OUT, "02_day_start.png"))
        await pg.mouse.click(w / 2, h / 2)                # capture mouse
        await pg.keyboard.press("Control+Shift+N")        # end shift -> sleep -> night
        await pg.wait_for_timeout(16000)
        await pg.screenshot(path=os.path.join(OUT, "03_night.png"))
        await pg.keyboard.down("w")
        await pg.wait_for_timeout(2000)
        await pg.keyboard.up("w")
        await pg.wait_for_timeout(1000)
        await pg.screenshot(path=os.path.join(OUT, "04_night_move.png"))
        await b.close()
        print("\n".join(l for l in logs if "error" in l.lower() or "USER" in l)[-3000:])
        print("screenshots in", OUT)

asyncio.run(main())
