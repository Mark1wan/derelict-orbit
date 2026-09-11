#!/usr/bin/env python3
"""Turn a simulated run into the station's own shift log - one report per day, with plates.

    python3 tools/simulate_run.py --nights 16 --seed 3 --json run.json
    python3 tools/build_run_report.py run.json docs/run_report.html

The page is written out whole rather than assembled in the browser: it is a record, and a record
should be readable the moment it opens.
"""

import html
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# which render stands in for which event, and what the plate is called
PLATE = {
    "shadow": ("apparition_cross.png", "The vulto", "Smoke, crossing the mouth of a corridor. No feet; it slides."),
    "shadow_close": ("apparition_cross.png", "The vulto", "Smoke, crossing the mouth of a corridor. No feet; it slides."),
    "watcher": ("apparition_corridor.png", "The watcher", "Stands at the far end and waits to be noticed. Comes apart when you look."),
    "ghoul": ("ghoul_lure.png", "The ghul", "Wears a crew member. Unlit. Waits for you to walk to it."),
    "thrown": ("fae_carry.png", "The Good Neighbours", "Thirteen cold lights round something loose, on their way to throwing it."),
    "chupacabra": ("chupacabra_peek.png", "The chupacabra", "Round the edge of a side passage. The wall has the rest of it."),
}
NIGHT_PLATE = ("creature_crawl.png", "The stalker", "Belly up, head first, and mirrored - which is why the walk reads as wrong.")
RITUAL_PLATE = ("ritual_doorway.png", "The ritual", "One doorway warm on a deck where nothing has been warm for hours.")

CLASS = {
    "shadow": "app", "shadow_close": "app", "watcher": "app", "ghoul": "app",
    "thrown": "fae", "chupacabra": "app",
    "bang": "noise", "whisper": "noise", "flicker": "noise", "fault": "fault",
    "drift": "shove", "blackout": "dark",
}


def clock(t, day_length):
    frac = max(0.0, min(1.0, t / day_length))
    minutes = int(8 * 60 + frac * 12 * 60)
    return "%02d:%02d" % (minutes // 60 % 24, minutes % 60)


def event_line(e, labels):
    kind = e["kind"]
    if kind == "fault":
        text = "A lamp stutters. The deck's own - nothing behind it."
    else:
        text = labels.get(kind, kind)
        text = text[0].upper() + text[1:] + "."
    extra = []
    if kind == "thrown":
        extra.append("you see the lights" if e.get("seen") else "nothing visible - a crate crosses the corridor on its own")
    if kind == "chupacabra":
        extra.append("bolts across the opening" if e.get("bolted") else "withdraws round the corner")
    if e.get("flicker") and kind != "fault":
        extra.append("the nearest lamp goes" + (" a beat later" if e.get("delayed") else ""))
    return text, extra


def build(run, out_path):
    days = run["days"]
    dl = run["day_length"]
    labels = run["labels"]
    tally = run["tally"]
    total_app = sum(v for k, v in tally.items() if k in run["apparitions"])
    faults = tally.get("fault", 0)
    false_breath = tally.get("fault_under", 0)
    true_breath = round(total_app * 0.30 * 0.75)
    pct = round(100.0 * true_breath / max(1, true_breath + false_breath))

    parts = []
    A = parts.append

    for d in days:
        day, I, night = d["day"], d["I"], d["night"]
        # the clock ruler: every event placed where it actually happened in the shift
        ticks = []
        for e in d["events"]:
            x = 100.0 * min(1.0, max(0.0, e["t"] / dl))
            cls = CLASS.get(e["kind"], "noise")
            mark = '<span class="breath"></span>' if e.get("under") else ""
            ticks.append('<i class="tick %s" style="left:%.2f%%" title="%s %s">%s</i>'
                         % (cls, x, clock(e["t"], dl), html.escape(e["kind"]), mark))
        rows = []
        for e in d["events"]:
            text, extra = event_line(e, labels)
            cls = CLASS.get(e["kind"], "noise")
            tail = ""
            if extra:
                tail = '<span class="note">' + " &middot; ".join(html.escape(x) for x in extra) + "</span>"
            breath = '<span class="heard">breath under the buzz</span>' if e.get("under") else ""
            rows.append(
                '<li class="ev %s"><span class="at">%s</span>'
                '<span class="what">%s%s%s</span></li>'
                % (cls, clock(e["t"], dl), html.escape(text), tail, breath))

        seen_kinds = []
        for e in d["events"]:
            if e["kind"] in PLATE and e["kind"] not in seen_kinds:
                seen_kinds.append(e["kind"])
        plates = []
        used = set()
        for k in seen_kinds:
            src, name, cap = PLATE[k]
            if src in used:
                continue
            used.add(src)
            plates.append('<figure class="plate"><img src="plates/%s" alt="%s" loading="lazy">'
                          '<figcaption><b>%s</b>%s</figcaption></figure>' % (src, html.escape(name), html.escape(name), html.escape(cap)))
        if night["ritual"]:
            src, name, cap = RITUAL_PLATE
            plates.append('<figure class="plate ritual"><img src="plates/%s" alt="%s" loading="lazy">'
                          '<figcaption><b>%s</b>%s</figcaption></figure>' % (src, html.escape(name), html.escape(name), html.escape(cap)))
        src, name, cap = NIGHT_PLATE
        plates.append('<figure class="plate"><img src="plates/%s" alt="%s" loading="lazy">'
                      '<figcaption><b>%s</b>%s</figcaption></figure>' % (src, html.escape(name), html.escape(name), html.escape(cap)))

        night_bits = ["%.2f m/s" % night["speed"]]
        night_bits.append("eyes lit" if night["eyes"] else "eyes dark - you hear it first")
        if night["lit"]:
            night_bits.append("pushes through the torch")
        if night["teleport"]:
            night_bits.append("closes distance while you look away")
        tasks = d["done"]
        task_cls = "ok" if tasks == run["tasks"] else ("part" if tasks else "none")

        A('<section class="day">')
        A('  <header class="sheet-head">')
        A('    <h2>Day <span class="num">%02d</span></h2>' % day)
        A('    <dl class="stats">')
        A('      <div><dt>Intensity</dt><dd>%d</dd></div>' % I)
        A('      <div><dt>Tasks</dt><dd class="%s">%d / %d</dd></div>' % (task_cls, tasks, run["tasks"]))
        A('      <div><dt>Events</dt><dd>%d</dd></div>' % len(d["events"]))
        A('      <div><dt>Dark</dt><dd>%d s</dd></div>' % round(night["length"]))
        A('    </dl>')
        A('  </header>')
        A('  <div class="ruler" role="img" aria-label="Shift timeline, 08:00 to 20:00">')
        A('    <div class="track">%s</div>' % "".join(ticks))
        A('    <div class="hours"><span>08:00</span><span>11:00</span><span>14:00</span><span>17:00</span><span>20:00</span></div>')
        A('  </div>')
        A('  <ol class="events">%s</ol>' % "".join(rows))
        A('  <div class="night">')
        A('    <h3>Night %02d</h3>' % day)
        A('    <p class="nightline">Main power out. <b>%d seconds in the dark.</b> Stalker: %s.</p>'
          % (round(night["length"]), ", ".join(night_bits)))
        if night["ritual"]:
            A('    <p class="warm">One doorway is warm: somebody is sitting in a circle of candles.</p>')
        A('    <p class="beats">%d disturbances in the dark &mdash; %d bangs, %d whispers.</p>'
          % (len(night["beats"]),
             sum(1 for b in night["beats"] if b[1] == "bang"),
             sum(1 for b in night["beats"] if b[1] == "whisper")))
        A('  </div>')
        A('  <div class="plates">%s</div>' % "".join(plates))
        A('</section>')

    body = "\n".join(parts)
    counts = sorted(((k, v) for k, v in tally.items() if k in run["apparitions"]), key=lambda kv: -kv[1])
    tally_rows = "".join('<tr><td>%s</td><td class="n">%d</td></tr>' % (html.escape(labels.get(k, k)), v)
                         for k, v in counts)

    page = TEMPLATE.format(
        nights=run["nights"], seed=run["seed"], body=body, total_app=total_app,
        faults=faults, true_breath=true_breath, false_breath=false_breath, pct=pct,
        tally_rows=tally_rows,
        days=len(days),
        total_events=sum(len(d["events"]) for d in days),
        dark=round(sum(d["night"]["length"] for d in days)),
        top_speed="%.2f" % max(d["night"]["speed"] for d in days),
    )
    with open(out_path, "w") as f:
        f.write(page)
    return out_path


TEMPLATE = """<title>Kestrel-9 Shift Log</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@500;600;700&family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500&display=swap">
<style>
  :root {{
    --ink: #08090b;
    --sheet: #101216;
    --sheet-2: #0c0e11;
    --rule: #1e2228;
    --rule-soft: #171a1f;
    --text: #c6cad1;
    --dim: #767d88;
    --faint: #4a515b;
    --amber: #e2a33f;
    --ember: #d2532a;
    --fae: #a3b552;
    --cold: #5d7fa8;
    --bad: #b4472e;
    --mono: "IBM Plex Mono", ui-monospace, "SF Mono", Menlo, monospace;
    --sans: "IBM Plex Sans", system-ui, -apple-system, sans-serif;
    --disp: "Barlow Condensed", "Arial Narrow", system-ui, sans-serif;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0;
    background: var(--ink);
    color: var(--text);
    font-family: var(--sans);
    font-size: 15px;
    line-height: 1.55;
    padding-block: 0 64px;
  }}
  .wrap {{ max-width: 940px; margin: 0 auto; padding-inline: 20px; }}

  /* ---------- masthead ---------- */
  .masthead {{ border-bottom: 2px solid var(--rule); padding-block: 44px 20px; margin-bottom: 34px; }}
  .eyebrow {{
    font-family: var(--mono); font-size: 11px; letter-spacing: .22em; text-transform: uppercase;
    color: var(--amber); margin: 0 0 10px;
  }}
  h1 {{
    font-family: var(--disp); font-weight: 700; font-size: clamp(38px, 8vw, 68px);
    line-height: .95; letter-spacing: .01em; margin: 0; text-wrap: balance; color: #e9ecf1;
    text-transform: uppercase;
  }}
  .standfirst {{ max-width: 60ch; color: var(--dim); margin: 14px 0 0; }}
  .standfirst b {{ color: var(--text); font-weight: 500; }}
  .runbar {{
    display: flex; flex-wrap: wrap; gap: 10px 26px; margin-top: 22px;
    font-family: var(--mono); font-size: 12px; color: var(--faint);
  }}
  .runbar b {{ color: var(--text); font-weight: 500; }}

  /* ---------- day sheet ---------- */
  .day {{
    background: var(--sheet); border: 1px solid var(--rule); border-top: 2px solid var(--amber);
    padding: 22px 22px 24px; margin-bottom: 22px;
  }}
  .sheet-head {{ display: flex; flex-wrap: wrap; align-items: baseline; gap: 12px 28px; }}
  .sheet-head h2 {{
    font-family: var(--disp); text-transform: uppercase; letter-spacing: .06em;
    font-size: 26px; font-weight: 600; margin: 0; color: #e9ecf1;
  }}
  .sheet-head .num {{ color: var(--amber); }}
  .stats {{ display: flex; flex-wrap: wrap; gap: 6px 26px; margin: 0 0 0 auto; }}
  .stats div {{ display: flex; gap: 8px; align-items: baseline; }}
  dt {{ font-family: var(--mono); font-size: 10px; letter-spacing: .16em; text-transform: uppercase; color: var(--faint); }}
  dd {{ margin: 0; font-family: var(--mono); font-size: 14px; font-variant-numeric: tabular-nums; color: var(--text); }}
  dd.ok {{ color: var(--fae); }}
  dd.part {{ color: var(--amber); }}
  dd.none {{ color: var(--bad); }}

  /* ---------- the clock ruler ---------- */
  .ruler {{ margin: 18px 0 20px; }}
  .track {{
    position: relative; height: 26px; border: 1px solid var(--rule-soft);
    background: linear-gradient(90deg, var(--sheet-2), #14181d 50%, var(--sheet-2));
  }}
  .tick {{ position: absolute; top: 3px; width: 2px; height: 20px; margin-left: -1px; background: var(--dim); }}
  .tick.app {{ background: var(--ember); box-shadow: 0 0 7px rgba(210,83,42,.55); }}
  .tick.fae {{ background: var(--fae); box-shadow: 0 0 7px rgba(163,181,82,.5); }}
  .tick.shove {{ background: var(--amber); }}
  .tick.dark {{ background: #2b3039; width: 4px; }}
  .tick.fault {{ background: var(--faint); height: 9px; top: 14px; }}
  .tick.noise {{ background: var(--dim); height: 9px; top: 3px; }}
  .breath {{
    position: absolute; left: 50%; top: -7px; width: 6px; height: 6px; margin-left: -3px;
    border-radius: 50%; background: #e8e0d2;
  }}
  .hours {{
    display: flex; justify-content: space-between; font-family: var(--mono); font-size: 10px;
    color: var(--faint); letter-spacing: .1em; margin-top: 5px;
  }}

  /* ---------- events ---------- */
  .events {{ list-style: none; margin: 0; padding: 0; border-top: 1px solid var(--rule-soft); }}
  .ev {{
    display: flex; gap: 14px; align-items: baseline; padding: 5px 0 5px 10px;
    border-bottom: 1px solid var(--rule-soft); border-left: 2px solid transparent;
  }}
  .ev .at {{ font-family: var(--mono); font-size: 12px; color: var(--faint); font-variant-numeric: tabular-nums; }}
  .ev .what {{ flex: 1; }}
  .ev.app {{ border-left-color: var(--ember); }}
  .ev.fae {{ border-left-color: var(--fae); }}
  .ev.shove {{ border-left-color: var(--amber); }}
  .ev.dark {{ border-left-color: #39404b; }}
  .ev.fault .what, .ev.noise .what {{ color: var(--dim); }}
  .note {{ display: block; font-family: var(--mono); font-size: 11.5px; color: var(--faint); }}
  .heard {{
    display: inline-block; margin-top: 3px; font-family: var(--mono); font-size: 10px;
    letter-spacing: .14em; text-transform: uppercase; color: #e8e0d2;
    border: 1px solid #3a3730; padding: 1px 7px;
  }}

  /* ---------- night ---------- */
  .night {{
    margin-top: 18px; padding: 16px 18px; background: #090c10;
    border: 1px solid #172029; border-left: 3px solid var(--cold);
  }}
  .night h3 {{
    font-family: var(--disp); text-transform: uppercase; letter-spacing: .1em; font-size: 17px;
    font-weight: 600; margin: 0 0 6px; color: #9fb4cb;
  }}
  .nightline {{ margin: 0; }}
  .nightline b {{ color: #cdd7e2; font-weight: 500; }}
  .beats {{ margin: 6px 0 0; font-family: var(--mono); font-size: 12px; color: var(--faint); }}
  .warm {{
    margin: 8px 0 0; padding: 8px 12px; border-left: 2px solid var(--amber);
    background: rgba(226,163,63,.07); color: #f0d5a5;
  }}

  /* ---------- plates ---------- */
  .plates {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 14px; margin-top: 18px; }}
  .plate {{ margin: 0; background: var(--sheet-2); border: 1px solid var(--rule-soft); }}
  .plate img {{ display: block; width: 100%; max-width: 100%; height: 150px; object-fit: cover; object-position: center; filter: contrast(1.06); }}
  .plate figcaption {{ padding: 8px 10px 10px; font-size: 12.5px; color: var(--dim); line-height: 1.4; }}
  .plate figcaption b {{
    display: block; font-family: var(--mono); font-size: 10.5px; letter-spacing: .14em;
    text-transform: uppercase; color: var(--text); font-weight: 500; margin-bottom: 3px;
  }}
  .plate.ritual {{ border-color: #3a2e17; }}

  /* ---------- close ---------- */
  .close {{ border-top: 2px solid var(--rule); margin-top: 40px; padding-top: 26px; }}
  .close h2 {{ font-family: var(--disp); text-transform: uppercase; letter-spacing: .07em; font-size: 30px; margin: 0 0 14px; color: #e9ecf1; }}
  .cols {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 26px; }}
  table {{ border-collapse: collapse; width: 100%; font-size: 14px; }}
  td {{ padding: 5px 0; border-bottom: 1px solid var(--rule-soft); }}
  td.n {{ text-align: right; font-family: var(--mono); font-variant-numeric: tabular-nums; color: var(--amber); }}
  .verdict {{ font-size: 16px; }}
  .verdict b {{ color: #e8e0d2; }}
  .legend {{ display: flex; flex-wrap: wrap; gap: 8px 18px; font-family: var(--mono); font-size: 11px; color: var(--faint); margin-top: 14px; }}
  .legend span {{ display: flex; align-items: center; gap: 6px; }}
  .key {{ width: 10px; height: 10px; }}
  .key.app {{ background: var(--ember); }} .key.fae {{ background: var(--fae); }}
  .key.fault {{ background: var(--faint); }} .key.breath {{ background: #e8e0d2; border-radius: 50%; }}
  footer {{ margin-top: 30px; font-family: var(--mono); font-size: 11.5px; color: var(--faint); line-height: 1.7; }}
  @media (max-width: 560px) {{
    .stats {{ margin-left: 0; }}
    .plate img {{ height: 124px; }}
  }}
</style>
<div class="wrap">
  <header class="masthead">
    <p class="eyebrow">Orbital Station Kestrel-9 &middot; Maintenance Deck &middot; Shift Record</p>
    <h1>{nights} Nights</h1>
    <p class="standfirst">A simulated run of <b>Derelict Orbit</b>, played out from the game's own event tables. Every time, count and behaviour below is what <code>tools/simulate_run.py</code> read out of the GDScript &mdash; the schedule, not the geometry.</p>
    <div class="runbar">
      <span>SEED <b>{seed}</b></span>
      <span>DAYS <b>{days}</b></span>
      <span>LOGGED EVENTS <b>{total_events}</b></span>
      <span>APPARITIONS <b>{total_app}</b></span>
      <span>TIME IN THE DARK <b>{dark} s</b></span>
      <span>FASTEST STALKER <b>{top_speed} m/s</b></span>
    </div>
    <div class="legend">
      <span><i class="key app"></i> apparition</span>
      <span><i class="key fae"></i> Good Neighbours</span>
      <span><i class="key fault"></i> a lamp the deck broke on its own</span>
      <span><i class="key breath"></i> breath under the buzz</span>
    </div>
  </header>

{body}

  <section class="close">
    <h2>What sixteen nights came to</h2>
    <div class="cols">
      <div>
        <table>
          <tbody>{tally_rows}</tbody>
        </table>
      </div>
      <div>
        <p class="verdict">The deck's own failing lamps stuttered <b>{faults}</b> times with nothing behind them &mdash; far more often than anything haunted did. That is deliberate: it is what makes every other flicker deniable.</p>
        <p class="verdict">The breath under the buzz was heard <b>{true_breath}</b> times with something there and <b>{false_breath}</b> times without. Hearing it means something is there <b>{pct}%</b> of the time: worth listening for, never safe to trust.</p>
      </div>
    </div>
    <footer>
      Plates are software renders from the game's own rigs and apparition data, not concept art.<br>
      Regenerate: <code>python3 tools/simulate_run.py --nights {nights} --seed {seed} --json run.json</code> then <code>python3 tools/build_run_report.py run.json docs/run_report.html</code>
    </footer>
  </section>
</div>
"""


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "run.json")
    dest = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "docs", "run_report.html")
    print(build(json.load(open(src)), dest))
