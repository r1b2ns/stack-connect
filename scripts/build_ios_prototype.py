#!/usr/bin/env python3
"""Builds docs/prototype/ios/index.html from the per-section manifest.json files.

Each section folder under docs/prototype/ios/ holds PNG captures of the iOS app
(fake data mode) and a manifest.json:
    [{"file", "title", "module", "flow", "notes", "status", "failure"}]

Usage: python3 scripts/build_ios_prototype.py
"""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "docs" / "prototype" / "ios"

SECTIONS = [
    ("asc-apps", "App Store Connect — apps"),
    ("asc-team-settings", "App Store Connect — team, Settings & accounts"),
    ("firebase-play", "Firebase & Google Play"),
]


def load(section):
    path = ROOT / section / "manifest.json"
    if not path.exists():
        return []
    entries = json.loads(path.read_text())
    return [e for e in entries if (ROOT / section / e.get("file", "")).exists()]


def card(section, entry):
    esc = lambda key: html.escape(str(entry.get(key) or ""))
    failed = entry.get("status") == "failure"
    search = " ".join(str(entry.get(k) or "") for k in ("title", "module", "flow", "notes", "failure")).lower()
    failure = f'<p class="failure">{esc("failure")}</p>' if failed else ""
    module = f'<span class="module">{esc("module")}</span>' if entry.get("module") else ""
    src = f"{section}/{html.escape(entry['file'])}"
    return f"""
    <figure class="card{' is-failure' if failed else ''}" data-search="{html.escape(search)}" data-failure="{str(failed).lower()}">
      <a href="{src}" target="_blank" rel="noopener"><img src="{src}" alt="{esc('title')}" loading="lazy"></a>
      <figcaption>
        <h3>{esc('title')}</h3>
        <p class="flow">{esc('flow')}</p>
        {module}
        <p class="notes">{esc('notes')}</p>
        {failure}
        <p class="file">{html.escape(entry['file'])}</p>
      </figcaption>
    </figure>"""


def main():
    blocks, total, failures, nav = [], 0, 0, []
    for section, title in SECTIONS:
        entries = load(section)
        if not entries:
            continue
        total += len(entries)
        failures += sum(e.get("status") == "failure" for e in entries)
        nav.append(f'<a href="#{section}">{html.escape(title)} <span>{len(entries)}</span></a>')
        cards = "".join(card(section, e) for e in entries)
        blocks.append(f'<section id="{section}"><h2>{html.escape(title)} <span>{len(entries)}</span></h2><div class="grid">{cards}</div></section>')

    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>StackConnect iOS Prototype</title>
<style>
:root {{ --bg:#f5f5f7; --card:#fff; --text:#1d1d1f; --muted:#6e6e73; --line:#d2d2d7; --accent:#0071e3; --bad:#d70015; --badbg:#fff0f1; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#000; --card:#1c1c1e; --text:#f5f5f7; --muted:#98989d; --line:#38383a; --accent:#0a84ff; --bad:#ff453a; --badbg:#2c1214; }} }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--text); font:15px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }}
header {{ position:sticky; top:0; z-index:2; background:color-mix(in srgb, var(--bg) 88%, transparent); backdrop-filter:blur(16px); border-bottom:1px solid var(--line); padding:14px 16px; }}
header .row {{ max-width:1400px; margin:0 auto; display:flex; flex-wrap:wrap; gap:10px 18px; align-items:center; }}
h1 {{ font-size:20px; margin:0; }}
.stats {{ color:var(--muted); }}
nav {{ display:flex; flex-wrap:wrap; gap:8px; }}
nav a {{ color:var(--accent); text-decoration:none; font-size:14px; }}
nav a span, h2 span {{ color:var(--muted); font-weight:400; }}
input[type=search] {{ flex:1 1 220px; min-width:0; padding:8px 12px; border-radius:10px; border:1px solid var(--line); background:var(--card); color:var(--text); font:inherit; }}
label {{ color:var(--muted); font-size:14px; white-space:nowrap; }}
main {{ max-width:1400px; margin:0 auto; padding:8px 16px 48px; }}
h2 {{ font-size:18px; margin:28px 0 12px; scroll-margin-top:110px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(220px, 1fr)); gap:16px; }}
.card {{ margin:0; background:var(--card); border:1px solid var(--line); border-radius:14px; overflow:hidden; display:flex; flex-direction:column; }}
.card.is-failure {{ border-color:var(--bad); }}
.card img {{ display:block; width:100%; height:auto; background:var(--line); }}
figcaption {{ padding:10px 12px 12px; }}
h3 {{ font-size:15px; margin:0 0 2px; }}
.flow, .file {{ color:var(--muted); font-size:12px; margin:0 0 6px; overflow-wrap:anywhere; }}
.module {{ display:inline-block; font:12px ui-monospace, SFMono-Regular, Menlo, monospace; background:var(--bg); border:1px solid var(--line); border-radius:6px; padding:1px 6px; margin-bottom:6px; }}
.notes {{ font-size:13px; margin:0 0 6px; }}
.failure {{ font-size:13px; color:var(--bad); background:var(--badbg); border-radius:8px; padding:6px 8px; margin:0 0 6px; }}
.hidden {{ display:none !important; }}
</style>
</head>
<body>
<header><div class="row">
  <h1>StackConnect iOS Prototype</h1>
  <span class="stats">{total} screens · {failures} failures · iPhone 17 Pro Max · fake data mode</span>
  <nav>{''.join(nav)}</nav>
  <input type="search" id="q" placeholder="Filter by screen, module, flow…">
  <label><input type="checkbox" id="onlyFail"> Failures only</label>
</div></header>
<main>{''.join(blocks)}</main>
<script>
const q = document.getElementById('q'), f = document.getElementById('onlyFail');
function apply() {{
  const t = q.value.trim().toLowerCase();
  document.querySelectorAll('.card').forEach(c => {{
    const ok = (!t || c.dataset.search.includes(t)) && (!f.checked || c.dataset.failure === 'true');
    c.classList.toggle('hidden', !ok);
  }});
  document.querySelectorAll('section').forEach(s => s.classList.toggle('hidden', !s.querySelector('.card:not(.hidden)')));
}}
q.addEventListener('input', apply); f.addEventListener('change', apply);
</script>
</body>
</html>
"""
    (ROOT / "index.html").write_text(page)
    print(f"Wrote {ROOT / 'index.html'} ({total} screens, {failures} failures)")


if __name__ == "__main__":
    main()
