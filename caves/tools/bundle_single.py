#!/usr/bin/env python3
"""Fold the web export into ONE HTML file that opens from a file:// URL.

    godot --headless --path caves --export-release "Web (WebXR, Quest 3)" build/caves/index.html
    python3 caves/tools/bundle_single.py [out.html]

A Godot web export is five files, and the engine fetches its .wasm and .pck by URL at startup.
Open index.html off the disk and those fetches fail, because a file:// page is not allowed to
read its siblings - which is why the normal advice is "serve it over HTTP". That is fine for a
deploy and useless for handing someone a build to try.

So everything is inlined and the loader is pointed at the page's own memory instead:

  - The .wasm (38 MB) and .pck are GZIPPED and then base64'd, and decompressed in the browser
    with DecompressionStream before anything else runs. Base64 alone would make a 50 MB file;
    gzipped first it is about 13 MB, which is the difference between something you can send
    and something you cannot.
  - Each one becomes a Blob URL. The .wasm blob is given type application/wasm, because the
    engine uses WebAssembly.instantiateStreaming and that refuses a response without it.
  - fetch() and XMLHttpRequest.open() are then wrapped to rewrite any request ending in one
    of those names to its Blob URL. The wrappers are installed only after the blobs exist,
    so they can be entirely synchronous and there is no ordering to get wrong.
  - The engine bootstrap is moved behind that await, so nothing can ask for a file early.
  - index.js and both audio worklets are inlined too; the worklets are what make sound work
    at all from file://.

The result needs no server, no extension and no flags. WebXR still needs HTTPS, so the single
file is for desktop and phone testing - a headset wants the CI artifact on a real host.
"""

import base64
import gzip
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build", "caves")

# Inlined and served from memory. Gzipped ones are decompressed in the page.
PACKED = {"index.wasm": "application/wasm", "index.pck": "application/octet-stream"}
WORKLETS = ["index.audio.worklet.js", "index.audio.position.worklet.js"]


def b64(data):
    return base64.b64encode(data).decode("ascii")


def read(name):
    with open(os.path.join(BUILD, name), "rb") as f:
        return f.read()


LOADER = """
<script id="sowbelly-inline">
// Everything the engine will ask for, inlined. The two big ones are gzipped; the worklets are
// small enough not to bother. See caves/tools/bundle_single.py for why this exists.
const SOWBELLY_GZ = %(packed)s;
const SOWBELLY_RAW = %(worklets)s;

// Godot's page and the engine both reach for a service worker, to offer an offline install. A
// file:// origin cannot have one, and the rejection surfaces as a page error that looks exactly
// like something being broken. Removing the API outright is worse - the engine then trips over
// getRegistration on undefined - so it gets a stub that says "no registration" politely.
if (location.protocol === 'file:') {
	try {
		Object.defineProperty(navigator, 'serviceWorker', {
			configurable: true,
			get: function () {
				return {
					controller: null,
					ready: new Promise(function () { /* never */ }),
					getRegistration: function () { return Promise.resolve(undefined); },
					getRegistrations: function () { return Promise.resolve([]); },
					register: function () { return Promise.reject(new Error('not available from a file:// page')); },
					addEventListener: function () {},
					removeEventListener: function () {},
				};
			},
		});
	} catch (e) { /* locked down; the console line is cosmetic either way */ }
}

window.SOWBELLY_READY = (async function () {
	const nativeFetch = window.fetch.bind(window);

	async function bytes(b64) {
		// A data: URL through fetch is the fastest native path to an ArrayBuffer, and it
		// keeps a 12 MB base64 literal out of any hand-written decode loop.
		const res = await nativeFetch('data:application/octet-stream;base64,' + b64);
		return res;
	}

	async function inflate(b64, type) {
		const res = await bytes(b64);
		const stream = res.body.pipeThrough(new DecompressionStream('gzip'));
		const buf = await new Response(stream).arrayBuffer();
		return URL.createObjectURL(new Blob([buf], { type: type }));
	}

	async function plain(b64, type) {
		const res = await bytes(b64);
		const buf = await res.arrayBuffer();
		return URL.createObjectURL(new Blob([buf], { type: type }));
	}

	const map = {};
	for (const name in SOWBELLY_GZ) {
		map[name] = await inflate(SOWBELLY_GZ[name][0], SOWBELLY_GZ[name][1]);
	}
	for (const name in SOWBELLY_RAW) {
		map[name] = await plain(SOWBELLY_RAW[name], 'text/javascript');
	}

	// Installed only now, so it can be synchronous: by this point every blob exists.
	function remap(url) {
		try {
			const s = String(url);
			for (const name in map) {
				if (s.endsWith(name)) {
					return map[name];
				}
			}
		} catch (e) { /* a Request object, or something else we should not touch */ }
		return url;
	}

	window.fetch = function (input, init) {
		if (typeof input === 'string' || input instanceof URL) {
			return nativeFetch(remap(input), init);
		}
		return nativeFetch(input, init);
	};

	const open = XMLHttpRequest.prototype.open;
	XMLHttpRequest.prototype.open = function (method, url) {
		const rest = Array.prototype.slice.call(arguments, 2);
		return open.apply(this, [method, remap(url)].concat(rest));
	};

	return map;
})();
</script>
"""


def main(out_path):
    missing = [n for n in list(PACKED) + WORKLETS + ["index.html", "index.js"]
               if not os.path.exists(os.path.join(BUILD, n))]
    if missing:
        raise SystemExit("bundle_single: no export in %s (missing %s).\n"
                         "Run the export first - see the docstring." % (BUILD, ", ".join(missing)))

    html = read("index.html").decode("utf-8")
    engine_js = read("index.js").decode("utf-8")

    packed = {}
    total_raw = 0
    for name, mime in PACKED.items():
        raw = read(name)
        total_raw += len(raw)
        packed[name] = [b64(gzip.compress(raw, 9)), mime]
    worklets = {n: b64(read(n)) for n in WORKLETS}

    def js_obj(d):
        return "{\n" + ",\n".join('\t"%s": %s' % (k, _js(v)) for k, v in d.items()) + "\n}"

    def _js(v):
        if isinstance(v, list):
            return "[" + ",".join('"%s"' % x for x in v) + "]"
        return '"%s"' % v

    loader = LOADER % {"packed": js_obj(packed), "worklets": js_obj(worklets)}

    # Drop the external engine script and inline it in the same place. Callable replacements
    # throughout: the engine's own JS is full of backslashes that re would read as escapes.
    html, n = re.subn(r'<script src="index\.js"></script>',
                      lambda m: "<script>\n%s\n</script>" % engine_js, html)
    if n != 1:
        raise SystemExit("bundle_single: could not find the index.js script tag to inline")

    # The loader has to run before anything else on the page.
    html = html.replace("<head>", "<head>\n" + loader, 1)

    # And the bootstrap has to wait for it, or the engine asks for index.wasm before the blob
    # for index.wasm exists.
    html, n = re.subn(r"(\n\t*)\(function \(\) \{(\s*\n\t*const statusOverlay)",
                      lambda m: "%swindow.SOWBELLY_READY.then(function () {%s" % (m.group(1), m.group(2)),
                      html, count=1)
    if n != 1:
        raise SystemExit("bundle_single: could not find the bootstrap IIFE to defer")
    html, n = re.subn(r"\n(\t*)\}\(\)\);\s*\n(\s*</script>)",
                      lambda m: "\n%s});\n%s" % (m.group(1), m.group(2)), html, count=1)
    if n != 1:
        raise SystemExit("bundle_single: could not find the end of the bootstrap IIFE")

    # Icons are the only other siblings referenced, and they are decoration.
    for icon in ("index.icon.png", "index.apple-touch-icon.png", "index.png"):
        path = os.path.join(BUILD, icon)
        if os.path.exists(path):
            html = html.replace(icon, "data:image/png;base64," + b64(read(icon)))

    html = html.replace("<title>Sowbelly</title>",
                        "<title>Sowbelly - standalone</title>", 1)

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)

    size = os.path.getsize(out_path)
    print("%s" % out_path)
    print("  %.1f MB  (from %.1f MB of wasm + pck, gzipped then base64)"
          % (size / 1e6, total_raw / 1e6))
    print("  open it straight off the disk - no server, no flags")
    print("  WebXR needs HTTPS, so a headset still wants the CI artifact on a real host")
    return 0


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else os.path.join(BUILD, "sowbelly-standalone.html")
    sys.exit(main(target))
