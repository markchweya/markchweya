#!/usr/bin/env python3
"""Community jigsaw for the profile README.

Visitors place pieces by opening pre-filled issues; the puzzle workflow
runs `python3 game/puzzle.py place "<issue title>" "<username>"`, which
updates game/state.json, regenerates assets/puzzle-board.svg, and
rewrites the section between the PUZZLE markers in README.md.
"""
import html
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / "game" / "state.json"
BOARD = ROOT / "assets" / "puzzle-board.svg"
README = ROOT / "README.md"
MSG = ROOT / "game" / "last_move.txt"

COLS, ROWS, CELL, PAD, R = 6, 3, 150, 20, 18
TOTAL = COLS * ROWS
REPO = "markchweya/markchweya"
FONT = "'Segoe UI', 'Helvetica Neue', Arial, sans-serif"


def load_state():
    return json.loads(STATE.read_text(encoding="utf-8"))


def save_state(state):
    STATE.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def cover_path(r, c):
    """Jigsaw cover for cell (r, c): tabs/sockets alternate by parity so
    neighbouring covers interlock; board-border edges stay flat."""
    x, y = PAD + c * CELL, PAD + r * CELL
    X, Y = x + CELL, y + CELL
    mx, my = x + CELL // 2, y + CELL // 2
    p = [f"M {x} {y}"]
    # top edge, left -> right
    if r == 0:
        p.append(f"L {X} {y}")
    else:
        socket = ((r - 1) + c) % 2 == 0  # piece above tabs down into me
        sweep = 1 if socket else 0
        p.append(f"L {mx - R} {y} A {R} {R} 0 0 {sweep} {mx + R} {y} L {X} {y}")
    # right edge, top -> bottom
    if c == COLS - 1:
        p.append(f"L {X} {Y}")
    else:
        tab = (r + c) % 2 == 0  # my tab bulges right
        sweep = 1 if tab else 0
        p.append(f"L {X} {my - R} A {R} {R} 0 0 {sweep} {X} {my + R} L {X} {Y}")
    # bottom edge, right -> left
    if r == ROWS - 1:
        p.append(f"L {x} {Y}")
    else:
        tab = (r + c) % 2 == 0  # my tab bulges down
        sweep = 0 if tab else 1
        p.append(f"L {mx + R} {Y} A {R} {R} 0 0 {sweep} {mx - R} {Y} L {x} {Y}")
    # left edge, bottom -> top
    if c == 0:
        p.append("Z")
    else:
        socket = (r + (c - 1)) % 2 == 0  # left neighbour tabs into me
        sweep = 0 if socket else 1
        p.append(f"L {x} {my + R} A {R} {R} 0 0 {sweep} {x} {my - R} Z")
    return " ".join(p)


def board_svg(placed):
    W, H = COLS * CELL + 2 * PAD, ROWS * CELL + 2 * PAD
    parts = [
        f'<svg width="{W}" height="{H}" viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg">',
        '<defs><linearGradient id="art" x1="0%" y1="0%" x2="100%" y2="100%">'
        '<stop offset="0%" stop-color="#38bdf8"/><stop offset="100%" stop-color="#a78bfa"/>'
        "</linearGradient></defs>",
        f'<rect width="{W}" height="{H}" rx="18" fill="#0d1117"/>',
        f'<rect x="{PAD}" y="{PAD}" width="{COLS * CELL}" height="{ROWS * CELL}" fill="url(#art)"/>',
        '<circle cx="130" cy="100" r="40" fill="#ffffff" fill-opacity="0.14"/>',
        '<circle cx="800" cy="380" r="55" fill="#ffffff" fill-opacity="0.12"/>',
        '<circle cx="720" cy="80" r="22" fill="#ffffff" fill-opacity="0.16"/>',
        f'<g font-family="{FONT}" text-anchor="middle" fill="#ffffff">'
        f'<text x="{W // 2}" y="205" font-size="118" font-weight="800">MARK</text>'
        f'<text x="{W // 2}" y="365" font-size="118" font-weight="800" fill-opacity="0.92">CHWEYA</text>'
        "</g>",
    ]
    for i in range(1, TOTAL + 1):
        if str(i) in placed:
            continue
        r, c = divmod(i - 1, COLS)
        parts.append(
            f'<path d="{cover_path(r, c)}" fill="#161b22" stroke="#30363d" stroke-width="1.5"/>'
        )
        parts.append(
            f'<text x="{PAD + c * CELL + CELL // 2}" y="{PAD + r * CELL + CELL // 2 + 11}" '
            f'font-family="{FONT}" text-anchor="middle" font-size="30" font-weight="700" '
            f'fill="#475569">{i:02d}</text>'
        )
    parts.append("</svg>")
    return "\n".join(parts)


def issue_url(n):
    return (
        f"https://github.com/{REPO}/issues/new"
        f"?title=puzzle%7Cplace%7C{n}"
        f"&body=Just%20press%20%22Create%22%20and%20the%20bot%20will%20place%20piece%20{n}%20for%20you%20%F0%9F%A7%A9"
    )


def readme_section(state):
    placed = state["placed"]
    links = []
    for i in range(1, TOTAL + 1):
        if str(i) in placed:
            links.append(f"<code>~{i:02d}~</code>")
        else:
            links.append(f'<a href="{issue_url(i)}"><code>{i:02d}</code></a>')
    n = len(placed)
    solved = state["solved_count"]
    status = f"\U0001f9e9 {n}/{TOTAL} placed &nbsp;·&nbsp; {solved} puzzle{'s' if solved != 1 else ''} completed"
    if state.get("last_player"):
        lp = html.escape(state["last_player"])
        status += f' &nbsp;·&nbsp; last piece by <a href="https://github.com/{lp}">@{lp}</a>'
    hall = ""
    if state["finishers"]:
        recent = " · ".join(
            f'<a href="https://github.com/{html.escape(u)}">@{html.escape(u)}</a>'
            for u in state["finishers"][-5:]
        )
        hall = f"\n<br />\n<sub>\U0001f3c6 <b>Hall of Fame:</b> {recent}</sub>"
    return f"""<!-- PUZZLE:START -->
<div align="center">

<img src="https://raw.githubusercontent.com/{REPO}/main/assets/puzzle-board.svg" width="72%" alt="Community jigsaw board" />

<br /><br />

<b>Pick a piece to place it:</b>

<br /><br />

{' '.join(links)}

<br /><br />

<sub>{status}</sub>{hall}

</div>
<!-- PUZZLE:END -->"""


def render(state):
    BOARD.write_text(board_svg(state["placed"]) + "\n", encoding="utf-8")
    text = README.read_text(encoding="utf-8")
    start = text.index("<!-- PUZZLE:START -->")
    end = text.index("<!-- PUZZLE:END -->") + len("<!-- PUZZLE:END -->")
    README.write_text(text[:start] + readme_section(state) + text[end:], encoding="utf-8")


def place(title, player):
    state = load_state()
    parts = title.strip().split("|")
    if len(parts) != 3 or parts[0] != "puzzle" or parts[1] != "place" or not parts[2].isdigit():
        MSG.write_text(
            "\U0001f914 I couldn't read that move — use the numbered piece links in the README to play!",
            encoding="utf-8",
        )
        return
    n = int(parts[2])
    if not 1 <= n <= TOTAL:
        MSG.write_text(
            f"\U0001f914 Piece {n} doesn't exist — pick 1 to {TOTAL} from the README.",
            encoding="utf-8",
        )
        return
    if str(n) in state["placed"]:
        MSG.write_text(
            f"\U0001f605 Piece {n:02d} was already placed — grab another one from the README!",
            encoding="utf-8",
        )
        return
    state["placed"][str(n)] = player
    state["last_player"] = player
    if len(state["placed"]) == TOTAL:
        state["solved_count"] += 1
        if player not in state["finishers"]:
            state["finishers"].append(player)
        state["placed"] = {}
        state["last_player"] = None
        MSG.write_text(
            f"\U0001f389 @{player} placed the FINAL piece and completed puzzle "
            f"#{state['solved_count']}! You're in the Hall of Fame \U0001f3c6 "
            "A fresh puzzle has been laid out — tell a friend.",
            encoding="utf-8",
        )
    else:
        MSG.write_text(
            f"\U0001f9e9 @{player} placed piece {n:02d} — "
            f"{len(state['placed'])}/{TOTAL} done. The board updates in a minute or two. Thanks for playing!",
            encoding="utf-8",
        )
    save_state(state)
    render(state)


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "render":
        render(load_state())
    elif len(sys.argv) >= 4 and sys.argv[1] == "place":
        place(sys.argv[2], sys.argv[3])
    else:
        print("usage: puzzle.py render | puzzle.py place <title> <player>", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
