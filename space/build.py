#!/usr/bin/env python3
"""Render the space-themed profile panels from live GitHub data.

Every number on the profile comes from GitHub's GraphQL API at build time, so nothing is
hand-typed or invented. The script writes self-contained animated SVGs (CSS + SMIL, no
scripts, no external fonts or images) that GitHub renders inside the README.

Usage:
    GITHUB_TOKEN=... python3 space/build.py --login markchweya --out assets/space
    python3 space/build.py --fixture space/fixture.json --out /tmp/space   # offline preview

Standard library only, so the workflow needs no dependency install.
"""
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import math
import os
import random
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

API = "https://api.github.com/graphql"
HERE = Path(__file__).resolve().parent

# Lunar / Solar palette, shared with the Repo Constellation hero.
BG = "#0d1117"
INK = "#1a1c22"
LIGHT = "#e9e6df"
SILVER = "#c9ccd3"
SLATE = "#7d8597"
AMBER = "#ffb347"
EMBER = "#d9480f"

SANS = "'Space Grotesk','Segoe UI',Helvetica,Arial,sans-serif"
MONO = "'JetBrains Mono',ui-monospace,SFMono-Regular,Menlo,Consolas,monospace"
W = 1000  # every panel shares one width so the README reads as one continuous sky

# --------------------------------------------------------------------------- data


@dataclass
class Repo:
    name: str
    stars: int
    language: str | None
    color: str | None


@dataclass
class Profile:
    login: str
    name: str
    since_year: int
    total_all_time: int
    last_year: int
    days: list[tuple[dt.date, int]]           # contribution calendar, oldest first
    repos: list[Repo] = field(default_factory=list)
    languages: list[tuple[str, str, int]] = field(default_factory=list)  # name, color, bytes


def graphql(token: str, query: str, variables: dict) -> dict:
    """POST one GraphQL query; raise with GitHub's own message on any error."""
    body = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(API, data=body, headers={
        "Authorization": f"bearer {token}",
        "Content-Type": "application/json",
        "User-Agent": "space-profile-builder",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as err:
        raise SystemExit(f"GitHub API returned HTTP {err.code}: {err.read()[:300]!r}") from err
    if payload.get("errors"):
        raise SystemExit(f"GitHub API error: {payload['errors'][0].get('message')}")
    return payload["data"]


Q_USER = """
query($login:String!){ user(login:$login){
  name createdAt
  contributionsCollection{ contributionCalendar{ totalContributions
    weeks{ contributionDays{ date contributionCount } } } }
  repositories(first:100, ownerAffiliations:OWNER, isFork:false, privacy:PUBLIC,
               orderBy:{field:STARGAZERS, direction:DESC}){
    nodes{ name stargazerCount primaryLanguage{ name color }
           languages(first:10, orderBy:{field:SIZE, direction:DESC}){ edges{ size node{ name color } } } } }
}}"""

Q_YEAR = """
query($login:String!,$from:DateTime!,$to:DateTime!){ user(login:$login){
  contributionsCollection(from:$from,to:$to){ contributionCalendar{ totalContributions } } }}"""


def fetch(login: str, token: str) -> Profile:
    """Pull the calendar, all-time total (year by year) and public repos for one user."""
    u = graphql(token, Q_USER, {"login": login})["user"]
    if u is None:
        raise SystemExit(f"no GitHub user named {login!r}")
    cal = u["contributionsCollection"]["contributionCalendar"]
    days = [(dt.date.fromisoformat(d["date"]), d["contributionCount"])
            for w in cal["weeks"] for d in w["contributionDays"]]
    since = int(u["createdAt"][:4])
    total = 0
    for year in range(since, dt.date.today().year + 1):
        y = graphql(token, Q_YEAR, {"login": login, "from": f"{year}-01-01T00:00:00Z",
                                    "to": f"{year}-12-31T23:59:59Z"})
        total += y["user"]["contributionsCollection"]["contributionCalendar"]["totalContributions"]
    repos, langs = [], {}
    for n in u["repositories"]["nodes"]:
        pl = n["primaryLanguage"] or {}
        repos.append(Repo(n["name"], n["stargazerCount"], pl.get("name"), pl.get("color")))
        for e in n["languages"]["edges"]:
            name, color = e["node"]["name"], e["node"]["color"] or SLATE
            prev = langs.get(name, (color, 0))
            langs[name] = (color, prev[1] + e["size"])
    languages = sorted(((k, c, s) for k, (c, s) in langs.items()), key=lambda x: -x[2])
    return Profile(login, u["name"] or login, since, total, cal["totalContributions"], days, repos, languages)


def load_fixture(path: Path) -> Profile:
    """Offline preview data; never committed as output (see README in this folder)."""
    d = json.loads(path.read_text())
    days = [(dt.date.fromisoformat(k), v) for k, v in d["days"]]
    return Profile(d["login"], d["name"], d["since_year"], d["total_all_time"], d["last_year"], days,
                   [Repo(**r) for r in d["repos"]], [tuple(x) for x in d["languages"]])


def streaks(days: list[tuple[dt.date, int]], today: dt.date | None = None) -> tuple[int, int]:
    """(current, longest) runs of days with at least one contribution.

    The current streak survives an empty *today* (the day is not over yet), matching how
    GitHub streak counters usually read.
    """
    if not days:
        return 0, 0
    longest = run = 0
    for _, n in days:
        run = run + 1 if n > 0 else 0
        longest = max(longest, run)
    today = today or days[-1][0]
    seq = [n for d, n in days if d <= today]
    if seq and seq[-1] == 0:
        seq = seq[:-1]
    current = 0
    for n in reversed(seq):
        if n == 0:
            break
        current += 1
    return current, longest


# --------------------------------------------------------------------------- svg helpers

def esc(s: str) -> str:
    return html.escape(str(s), quote=True)


def fmt(n: int) -> str:
    return f"{n:,}"


def shell(h: int, body: str, title: str) -> str:
    """Wrap panel content: GitHub-dark sky, soft edge fade so panels melt into the page."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {h}" width="{W}" height="{h}" role="img" aria-label="{esc(title)}">
<title>{esc(title)}</title>
<defs>
  <radialGradient id="fade" cx="50%" cy="50%" r="68%">
    <stop offset="80%" stop-color="{BG}" stop-opacity="0"/><stop offset="100%" stop-color="{BG}" stop-opacity="1"/>
  </radialGradient>
  <radialGradient id="glowA" cx="50%" cy="50%" r="50%">
    <stop offset="0%" stop-color="{AMBER}" stop-opacity=".55"/><stop offset="100%" stop-color="{EMBER}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="glowS" cx="50%" cy="50%" r="50%">
    <stop offset="0%" stop-color="{SILVER}" stop-opacity=".35"/><stop offset="100%" stop-color="{SLATE}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="planetS" cx="35%" cy="32%" r="75%">
    <stop offset="0%" stop-color="{LIGHT}"/><stop offset="55%" stop-color="{SLATE}"/><stop offset="100%" stop-color="{INK}"/>
  </radialGradient>
  <radialGradient id="planetA" cx="35%" cy="32%" r="75%">
    <stop offset="0%" stop-color="#ffe2b0"/><stop offset="50%" stop-color="{AMBER}"/><stop offset="100%" stop-color="{EMBER}"/>
  </radialGradient>
</defs>
<style>
  .t{{animation:tw 4s ease-in-out infinite}}
  @keyframes tw{{0%,100%{{opacity:.25}}50%{{opacity:1}}}}
  .drift{{animation:dr 60s linear infinite}}
  @keyframes dr{{from{{transform:translateX(0)}}to{{transform:translateX(-40px)}}}}
  .lbl{{font-family:{SANS};fill:{LIGHT}}}
  .mono{{font-family:{MONO};fill:{SILVER};letter-spacing:.14em}}
  @media (prefers-reduced-motion: reduce){{.t,.drift,.draw{{animation:none}}}}
</style>
<rect width="{W}" height="{h}" fill="{BG}"/>
{stars(h)}
{body}
<rect width="{W}" height="{h}" fill="url(#fade)"/>
</svg>
"""


def stars(h: int, seed: int | None = None, n: int | None = None) -> str:
    """A sparse, twinkling star field; seeded by height so each panel differs but is stable."""
    rnd = random.Random(seed if seed is not None else h * 7919)
    count = n if n is not None else int(W * h / 5200)
    out = ['<g class="drift">']
    for _ in range(count):
        x, y = rnd.uniform(0, W + 40), rnd.uniform(0, h)
        r = rnd.choice((0.6, 0.8, 0.8, 1.0, 1.3))
        delay = rnd.uniform(0, 4)
        out.append(f'<circle class="t" style="animation-delay:{delay:.2f}s" cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{LIGHT}"/>')
    out.append("</g>")
    return "\n".join(out)


def orbit(cx: float, cy: float, rx: float, ry: float, dur: float, color: str, r: float = 3.2,
          begin: float = 0.0, opacity: float = .55) -> str:
    """A tilted orbit ellipse with a moon travelling along it (SMIL animateMotion)."""
    path = f"M {cx - rx} {cy} a {rx} {ry} 0 1 0 {2 * rx} 0 a {rx} {ry} 0 1 0 {-2 * rx} 0"
    return (f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="none" stroke="{SLATE}" '
            f'stroke-opacity="{opacity}" stroke-width="1"/>'
            f'<circle r="{r}" fill="{color}"><animateMotion dur="{dur}s" begin="{-begin}s" '
            f'repeatCount="indefinite" path="{path}"/></circle>')


# --------------------------------------------------------------------------- panels

def telemetry(p: Profile) -> str:
    """Three worlds: contributions last year, current streak (ringed), longest streak."""
    cur, best = streaks(p.days)
    h = 380
    cy = 190
    parts = [f'<text x="{W / 2}" y="44" text-anchor="middle" class="mono" font-size="13">MISSION TELEMETRY</text>']
    worlds = [
        (200, "planetS", "glowS", fmt(p.last_year), "CONTRIBUTIONS", "in the last year", 58),
        (500, "planetA", "glowA", f"{cur}", "DAY STREAK", f"current · longest {best}", 72),
        (800, "planetS", "glowS", fmt(p.total_all_time), "ALL-TIME", f"contributions since {p.since_year}", 58),
    ]
    for i, (x, grad, glow, value, label, sub, r) in enumerate(worlds):
        parts.append(f'<circle cx="{x}" cy="{cy}" r="{r * 2.2}" fill="url(#{glow})"/>')
        parts.append(orbit(x, cy, r * 1.75, r * 0.52, 9 + 4 * i, AMBER if i == 1 else SILVER, begin=i * 2))
        parts.append(f'<circle cx="{x}" cy="{cy}" r="{r}" fill="url(#{grad})"/>')
        if i == 1 and best:
            frac = min(cur / best, 1.0)
            circ = 2 * math.pi * (r + 12)
            parts.append(f'<circle cx="{x}" cy="{cy}" r="{r + 12}" fill="none" stroke="{SLATE}" stroke-opacity=".35" stroke-width="3"/>')
            parts.append(f'<circle cx="{x}" cy="{cy}" r="{r + 12}" fill="none" stroke="{AMBER}" stroke-width="3" '
                         f'stroke-linecap="round" stroke-dasharray="{circ * frac:.1f} {circ:.1f}" '
                         f'transform="rotate(-90 {x} {cy})"/>')
        ink = INK if i == 1 else BG
        parts.append(f'<text x="{x}" y="{cy + 12}" text-anchor="middle" class="lbl" font-size="{34 if len(value) < 6 else 28}" '
                     f'font-weight="700" fill="{ink}" style="fill:{ink}">{esc(value)}</text>')
        parts.append(f'<text x="{x}" y="{cy + r + 58}" text-anchor="middle" class="mono" font-size="13">{esc(label)}</text>')
        parts.append(f'<text x="{x}" y="{cy + r + 80}" text-anchor="middle" class="lbl" font-size="14" '
                     f'fill-opacity=".7">{esc(sub)}</text>')
    return shell(h, "\n".join(parts), f"Contribution telemetry for {p.name}")


# Alien-head activity scale: dim moss for quiet days up to a pale glowing green for the busiest.
ALIEN = ("#3d5a4c", "#5f9c7c", "#9be0b4", "#d4ffe3")
ALIEN_GLOW = "#7dffb0"
ALIEN_SCALE = (.48, .60, .71, .82)   # head size per level, in units of the 20-unit glyph


def alien_defs() -> str:
    """One original alien-head glyph (wide cranium, narrow chin, two dark almond eyes), reused per day."""
    return f"""<defs>
  <symbol id="alien" viewBox="-10 -10 20 20" overflow="visible">
    <path d="M0 -9.2 C6.4 -9.2 9.4 -5.4 9.4 -1.2 C9.4 4.2 3.6 9.2 0 9.2 C-3.6 9.2 -9.4 4.2 -9.4 -1.2 C-9.4 -5.4 -6.4 -9.2 0 -9.2Z"/>
    <ellipse cx="-3.9" cy="0.4" rx="3.3" ry="1.8" transform="rotate(28 -3.9 0.4)" fill="{BG}"/>
    <ellipse cx="3.9" cy="0.4" rx="3.3" ry="1.8" transform="rotate(-28 3.9 0.4)" fill="{BG}"/>
    <circle cx="-4.6" cy="-0.2" r=".7" fill="{LIGHT}" fill-opacity=".8"/>
    <circle cx="3.2" cy="-0.2" r=".7" fill="{LIGHT}" fill-opacity=".8"/>
  </symbol>
  <radialGradient id="ahalo" cx="50%" cy="50%" r="50%">
    <stop offset="0%" stop-color="{ALIEN_GLOW}" stop-opacity=".45"/><stop offset="100%" stop-color="{ALIEN_GLOW}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="beam" cx="50%" cy="50%" r="50%">
    <stop offset="0%" stop-color="{ALIEN_GLOW}" stop-opacity=".11"/>
    <stop offset="100%" stop-color="{ALIEN_GLOW}" stop-opacity="0"/>
  </radialGradient>
</defs>
<style>
  .bob{{animation:bob 3.2s ease-in-out infinite}}
  @keyframes bob{{0%,100%{{transform:translateY(0)}}50%{{transform:translateY(-1.6px)}}}}
  .pulse{{animation:pl 3.6s ease-in-out infinite}}
  @keyframes pl{{0%,100%{{opacity:.75}}50%{{opacity:1}}}}
  .sweep{{animation:sw 9s linear infinite}}
  @keyframes sw{{from{{transform:translateX(-140px)}}to{{transform:translateX({W + 140}px)}}}}
  @media (prefers-reduced-motion: reduce){{.bob,.pulse,.sweep{{animation:none}}}}
</style>"""


def alien(x: float, y: float, level: int, delay: float, tip: str = "") -> str:
    """An alien head centred on (x, y); level 1..4 sets its size and brightness."""
    size = 20 * ALIEN_SCALE[level - 1]
    head = (f'<use href="#alien" x="{x - size / 2:.1f}" y="{y - size / 2:.1f}" width="{size:.1f}" '
            f'height="{size:.1f}" fill="{ALIEN[level - 1]}"/>')
    title = f"<title>{esc(tip)}</title>" if tip else ""
    if level < 3:
        return f"<g>{title}{head}</g>"
    halo = (f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{size * .95:.1f}" fill="url(#ahalo)"/>' if level == 4 else "")
    return (f'<g class="{"bob" if level == 4 else "pulse"}" style="animation-delay:{delay:.2f}s">'
            f"{title}{halo}{head}</g>")


def activity_level(n: int, peak: int) -> int:
    """GitHub-style quartile level (0 = nothing) of a day's count against the scaled peak."""
    if n <= 0:
        return 0
    k = min(n, peak) / peak
    return 1 if k <= .25 else 2 if k <= .5 else 3 if k <= .75 else 4


def galaxy(p: Profile) -> str:
    """The last 53 weeks as a fleet of alien heads: bigger and brighter where more happened."""
    h = 330
    days = p.days[-371:]
    if not days:
        return shell(h, "", "No contributions yet")
    first = days[0][0]
    # Scale by the 95th percentile of active days, so one huge day (a bulk import or a
    # migration) does not shrink every other head to the smallest size.
    active = sorted(n for _, n in days if n > 0)
    peak = active[int(.95 * (len(active) - 1))] if active else 1
    x0, step_x, y0, step_y = 84, 16.9, 98, 19
    grid_bottom = y0 + 6 * step_y
    parts = [alien_defs(),
             f'<text x="{W / 2}" y="44" text-anchor="middle" class="mono" font-size="13">52 WEEKS IN ORBIT</text>',
             # a faint tractor-beam scan crossing the fleet
             f'<rect class="sweep" x="0" y="{y0 - 40}" width="140" height="{6 * step_y + 80}" fill="url(#beam)"/>']
    for i, name in ((1, "MON"), (3, "WED"), (5, "FRI")):
        parts.append(f'<text x="{x0 - 22}" y="{y0 + i * step_y + 4}" text-anchor="end" class="mono" '
                     f'font-size="10" fill-opacity=".55">{name}</text>')
    rnd = random.Random(53)
    for d, n in days:
        wk = ((d - first).days + (first.weekday() + 1) % 7) // 7
        dow = (d.weekday() + 1) % 7                 # GitHub rows start on Sunday
        x, y = x0 + wk * step_x, y0 + dow * step_y
        level = activity_level(n, peak)
        if level == 0:
            parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="1.2" fill="{SLATE}" fill-opacity=".28"/>')
        else:
            word = "contribution" if n == 1 else "contributions"
            parts.append(alien(x, y, level, rnd.uniform(0, 3.6), f"{d.strftime('%b %d, %Y')}: {n} {word}"))
    month = None
    for d, _ in days:
        if d.day <= 7 and d.weekday() == 6 and d.month != month:
            month = d.month
            wk = ((d - first).days + (first.weekday() + 1) % 7) // 7
            parts.append(f'<text x="{x0 + wk * step_x:.1f}" y="{grid_bottom + 30}" class="mono" font-size="11" '
                         f'fill-opacity=".8">{d.strftime("%b").upper()}</text>')
    # legend: less -> more, right-aligned under the grid
    lx = x0 + 52 * step_x - 4 * 20 - 40
    ly = grid_bottom + 62
    parts.append(f'<text x="{lx - 12}" y="{ly + 4}" text-anchor="end" class="mono" font-size="10" fill-opacity=".6">LESS</text>')
    for lv in range(1, 5):
        parts.append(alien(lx + (lv - 1) * 20 + 6, ly, lv, lv * .4))
    parts.append(f'<text x="{lx + 4 * 20 + 2}" y="{ly + 4}" class="mono" font-size="10" fill-opacity=".6">MORE</text>')
    busiest = max(days, key=lambda t: t[1])
    parts.append(f'<text x="{x0 - 10}" y="{ly + 5}" class="lbl" font-size="14" fill-opacity=".75">'
                 f'{fmt(p.last_year)} contributions in the last year · busiest day '
                 f'{busiest[0].strftime("%b %d")} with {fmt(busiest[1])}</text>')
    return shell(h, "\n".join(parts), f"{fmt(p.last_year)} contributions in the last year")


def constellations(stack: dict[str, list[str]]) -> str:
    """Each tech group becomes a constellation; lines draw themselves in, stars twinkle."""
    h = 430
    parts = [f'<text x="{W / 2}" y="44" text-anchor="middle" class="mono" font-size="13">TECH CONSTELLATIONS</text>',
             "<style>.draw{stroke-dasharray:600;stroke-dashoffset:600;animation:dw 6s ease-out infinite alternate}"
             "@keyframes dw{to{stroke-dashoffset:0}}</style>"]
    groups = list(stack.items())
    cols = len(groups)
    rnd = random.Random(11)
    for gi, (group, items) in enumerate(groups):
        cx = W * (gi + 0.5) / cols
        pts = []
        for k, _ in enumerate(items):
            a = -math.pi / 2 + k * (2 * math.pi / max(len(items), 1)) + rnd.uniform(-.35, .35)
            rr = 92 + rnd.uniform(-10, 14)
            pts.append((cx + rr * math.cos(a) * .82, 205 + rr * math.sin(a) * 1.18))
        d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in pts + pts[:1])
        parts.append(f'<path d="{d}" fill="none" stroke="{SLATE}" stroke-width="1" stroke-opacity=".3"/>')
        parts.append(f'<path class="draw" style="animation-delay:{gi * .8:.1f}s" d="{d}" fill="none" '
                     f'stroke="{SILVER}" stroke-width="1.2" stroke-opacity=".75"/>')
        for k, ((x, y), item) in enumerate(zip(pts, items)):
            star = AMBER if k == 0 else SILVER
            parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="9" fill="{star}" fill-opacity=".12"/>')
            parts.append(f'<circle class="t" style="animation-delay:{rnd.uniform(0, 4):.2f}s" cx="{x:.1f}" cy="{y:.1f}" r="3.4" fill="{star}"/>')
            above = y < 215
            parts.append(f'<text x="{x:.1f}" y="{y + (-12 if above else 22):.1f}" text-anchor="middle" class="lbl" '
                         f'font-size="13">{esc(item)}</text>')
        parts.append(f'<text x="{cx:.1f}" y="385" text-anchor="middle" class="mono" font-size="12">{esc(group.upper())}</text>')
    return shell(h, "\n".join(parts), "Tech stack: " + "; ".join(f"{g}: {', '.join(i)}" for g, i in groups))


def fleet(p: Profile, featured: list[str]) -> str:
    """Featured repositories as worlds sized by stars, tinted by their main language."""
    by_name = {r.name.lower(): r for r in p.repos}
    chosen = [by_name[n.lower()] for n in featured if n.lower() in by_name]
    for r in p.repos:                      # top up with the most-starred public repos
        if len(chosen) >= 6:
            break
        if r not in chosen:
            chosen.append(r)
    chosen = chosen[:6]
    h = 400
    parts = [f'<text x="{W / 2}" y="44" text-anchor="middle" class="mono" font-size="13">THE FLEET</text>']
    peak = max((r.stars for r in chosen), default=0) or 1
    for i, r in enumerate(chosen):
        col, row = i % 3, i // 3
        x, y = 200 + col * 300, 140 + row * 150
        rad = 16 + 14 * math.sqrt(r.stars / peak)
        tint = r.color or SLATE
        parts.append(orbit(x - 70, y, rad + 18, (rad + 18) * .32, 7 + i * 1.3, tint, r=2.4, begin=i, opacity=.4))
        parts.append(f'<circle cx="{x - 70}" cy="{y}" r="{rad:.1f}" fill="url(#planetS)"/>')
        parts.append(f'<circle cx="{x - 70}" cy="{y}" r="{rad:.1f}" fill="{tint}" fill-opacity=".45"/>')
        parts.append(f'<text x="{x - 30}" y="{y - 4}" class="lbl" font-size="17" font-weight="700">{esc(r.name)}</text>')
        meta = " · ".join(x for x in (f"★ {r.stars}" if r.stars else "", r.language or "") if x)
        parts.append(f'<text x="{x - 30}" y="{y + 18}" class="mono" font-size="12">{esc(meta)}</text>')
    return shell(h, "\n".join(parts), "Featured repositories: " + ", ".join(r.name for r in chosen))


def belt(p: Profile) -> str:
    """Language mix as an asteroid belt arc around a small sun."""
    h = 300
    langs = p.languages[:7]
    total = sum(s for _, _, s in langs) or 1
    cx, cy, rx, ry = W / 2, 150, 300, 78
    parts = [f'<text x="{W / 2}" y="44" text-anchor="middle" class="mono" font-size="13">LANGUAGE BELT</text>',
             f'<circle cx="{cx}" cy="{cy}" r="70" fill="url(#glowA)"/><circle cx="{cx}" cy="{cy}" r="22" fill="url(#planetA)"/>']
    a = -math.pi
    rnd = random.Random(5)
    legend_x = W / 2 - 56 * len(langs)
    for name, color, size in langs:
        share = size / total
        span = 2 * math.pi * share
        for _ in range(max(6, int(320 * share))):
            t = a + rnd.uniform(0, span)
            jitter = rnd.uniform(-10, 10)
            x, y = cx + (rx + jitter) * math.cos(t), cy + (ry + jitter * .3) * math.sin(t)
            parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{rnd.uniform(1.2, 3.0):.1f}" fill="{color}" fill-opacity=".9"/>')
        a += span
    parts.insert(2, f'<g><animateTransform attributeName="transform" type="rotate" from="0 {cx} {cy}" '
                    f'to="360 {cx} {cy}" dur="240s" repeatCount="indefinite"/>')
    parts.append("</g>")
    for name, color, size in langs:
        pct = 100 * size / total
        parts.append(f'<circle cx="{legend_x}" cy="{h - 44}" r="4" fill="{color}"/>'
                     f'<text x="{legend_x + 9}" y="{h - 40}" class="lbl" font-size="12">{esc(name)} {pct:.0f}%</text>')
        legend_x += 112
    return shell(h, "\n".join(parts), "Languages by code size: " + ", ".join(
        f"{n} {100 * s / total:.0f}%" for n, _, s in langs))


# --------------------------------------------------------------------------- main

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--login", default=os.environ.get("PROFILE_LOGIN", "markchweya"))
    ap.add_argument("--out", type=Path, default=Path("assets/space"))
    ap.add_argument("--fixture", type=Path, help="render from a JSON fixture instead of the API")
    args = ap.parse_args(argv)

    if args.fixture:
        profile = load_fixture(args.fixture)
    else:
        token = os.environ.get("GITHUB_TOKEN")
        if not token:
            print("GITHUB_TOKEN is not set", file=sys.stderr)
            return 2
        profile = fetch(args.login, token)

    config = json.loads((HERE / "config.json").read_text())
    args.out.mkdir(parents=True, exist_ok=True)
    panels = {
        "telemetry.svg": telemetry(profile),
        "galaxy.svg": galaxy(profile),
        "belt.svg": belt(profile),
        "constellations.svg": constellations(config["stack"]),
        "fleet.svg": fleet(profile, config["featured"]),
    }
    for name, svg in panels.items():
        (args.out / name).write_text(svg, encoding="utf-8")
    cur, best = streaks(profile.days)
    print(f"wrote {len(panels)} panels to {args.out}: {profile.last_year} last year, "
          f"{profile.total_all_time} all-time, streak {cur}/{best}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
