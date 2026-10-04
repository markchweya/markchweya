# Chweya Drift — vector HUD drawn with Raphaël: analog speedometer and minimap.

D = window.Drift
C = D.C

FONT = "'Saira Condensed', 'Arial Narrow', sans-serif"
MAX_RPM = 9000
deg = (v, max) -> 135 + 270 * v / max
rad = (v, max) -> deg(v, max) * Math.PI / 180
pt = (cx, cy, r, a) -> "#{(cx + Math.cos(a) * r).toFixed(2)},#{(cy + Math.sin(a) * r).toFixed(2)}"
arc = (cx, cy, r, a0, a1) ->
  large = if a1 - a0 > Math.PI then 1 else 0
  "M#{pt(cx, cy, r, a0)}A#{r},#{r} 0 #{large} 1 #{pt(cx, cy, r, a1)}"
txt = (p, x, y, s, size, weight = 600, color = '#ffffff') ->
  p.text(x, y, s).attr fill: color, 'font-size': size, 'font-family': FONT, 'font-weight': weight

# Tachometer with digital speed and gear, plus an N2O dial, in the style of
# modern racing-game HUDs.
class Speedo
  constructor: (el) ->
    p = @p = Raphael el, '100%', '100%'
    p.setViewBox 0, 0, 340, 250, true
    @cx = cx = 222
    @cy = cy = 122
    R = 100
    p.circle(cx, cy, 113).attr fill: '#0a0f15', 'fill-opacity': 0.38, stroke: '#ffffff', 'stroke-opacity': 0.12, 'stroke-width': 1
    p.path(arc(cx, cy, R + 6, rad(7000, MAX_RPM), rad(MAX_RPM, MAX_RPM))).attr stroke: '#ff3b30', 'stroke-width': 5, fill: 'none'
    for v in [0..MAX_RPM] by 250
      a = rad v, MAX_RPM
      major = v % 1000 is 0
      half = v % 500 is 0
      r1 = R - (if major then 15 else if half then 9 else 5)
      p.path("M#{pt(cx, cy, r1, a)}L#{pt(cx, cy, R, a)}").attr
        stroke: if v >= 7000 then '#ff3b30' else '#ffffff'
        'stroke-width': if major then 3.5 else 1.4
        'stroke-linecap': 'round'
      txt p, cx + Math.cos(a) * (R - 30), cy + Math.sin(a) * (R - 30), String(v / 1000), 19, 700 if major
    txt p, cx, cy - 34, 'RPM', 13, 700
    txt p, cx, cy - 21, '×1000', 10, 600, '#b6c0cb'
    @gearText = txt p, cx, cy + 30, 'N', 30, 800, '#38c5ef'
    @needle = p.path("M#{cx - 18},#{cy - 4}L#{cx + R - 10},#{cy}L#{cx - 18},#{cy + 4}Z").attr fill: '#ff3b30', stroke: 'none'
    p.circle(cx, cy, 10).attr fill: '#141a22', stroke: '#ff3b30', 'stroke-width': 2.5
    p.rect(cx - 44, cy + 62, 88, 40, 5).attr fill: '#9fb7cf', 'fill-opacity': 0.22, stroke: '#cfe3f5', 'stroke-opacity': 0.55, 'stroke-width': 1.5
    @speedText = txt p, cx, cy + 82, '0', 34, 700
    txt p, cx, cy + 112, 'KM/H', 12, 700, '#b6c0cb'

    @nx = nx = 58
    @ny = ny = 186
    nr = 44
    p.circle(nx, ny, nr + 8).attr fill: '#0a0f15', 'fill-opacity': 0.38, stroke: '#ffffff', 'stroke-opacity': 0.12
    p.path(arc(nx, ny, nr, rad(0, 1), rad(1, 1))).attr stroke: '#ffffff', 'stroke-opacity': 0.25, 'stroke-width': 7, fill: 'none'
    @nitroArc = p.path(arc(nx, ny, nr, rad(0, 1), rad(1, 1))).attr stroke: '#ffb02e', 'stroke-width': 7, fill: 'none'
    @nitroNeedle = p.path("M#{nx - 8},#{ny - 3}L#{nx + nr - 6},#{ny}L#{nx - 8},#{ny + 3}Z").attr fill: '#ffffff', stroke: 'none'
    p.circle(nx, ny, 6).attr fill: '#141a22', stroke: '#ffb02e', 'stroke-width': 2
    txt p, nx, ny + 30, 'N₂O', 15, 800
    @rpm = 0
    @lastSpeed = ''
    @lastGear = ''
    @lastNitro = -1

  update: (race, audio) ->
    target = if race.speed < 1 and audio.rpm < 1000 then 900 else audio.rpm
    @rpm += (target - @rpm) * 0.3
    @needle.transform "r#{deg(Math.min(@rpm, MAX_RPM), MAX_RPM)},#{@cx},#{@cy}"
    speed = String Math.round(race.speed * C.KMH)
    if speed isnt @lastSpeed
      @speedText.attr 'text', speed
      @lastSpeed = speed
    gear = if race.speed < 30 then 'N' else String(audio.gear)
    if gear isnt @lastGear
      @gearText.attr 'text', gear
      @lastGear = gear
    n = Math.round(race.nitro * 100) / 100
    if n isnt @lastNitro
      @lastNitro = n
      end = rad Math.max(0.001, n), 1
      @nitroArc.attr 'path', arc(@nx, @ny, 44, rad(0, 1), end)
      @nitroArc.attr 'stroke', if race.boosting then '#6fb2ff' else '#ffb02e'
      @nitroNeedle.transform "r#{deg(n, 1)},#{@nx},#{@ny}"
    return

class MiniMap
  constructor: (el) ->
    @p = Raphael el, '100%', '100%'
    @p.setViewBox 0, 0, 180, 180, true
    @c = 90
    @scale = 0.42

  load: (race) ->
    @race = race
    p = @p
    p.clear()
    map = race.track.map
    s = @scale
    d = ((if i is 0 then 'M' else 'L') + (q.x * s).toFixed(1) + ',' + (q.y * s).toFixed(1) for q, i in map by 3).join ''
    p.rect(0, 0, 180, 180).attr fill: '#0f1720', 'fill-opacity': 0.5, stroke: 'none'
    @layer = p.set()
    @layer.push p.path(d).attr(stroke: '#e8edf2', 'stroke-opacity': 0.3, 'stroke-width': 11, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', fill: 'none')
    @layer.push p.path(d).attr(stroke: '#38c5ef', 'stroke-width': 4, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', fill: 'none')
    fin = map[Math.min(map.length - 1, C.RACE_SEGS)]
    @layer.push p.circle(fin.x * s, fin.y * s, 5).attr(fill: '#ffffff', stroke: '#111111', 'stroke-width': 2)
    @dots = (p.circle(0, 0, 3.6).attr(fill: '#ffcc33', stroke: '#1a1a1a', 'stroke-width': 1) for r in race.rivals)
    @arrow = p.path('M90,79L98,99L90,94L82,99Z').attr fill: '#ffffff', stroke: '#0b0f14', 'stroke-width': 1.5
    p.text(90, 13, 'N').attr fill: '#ffffff', 'font-size': 12, 'font-family': FONT, 'font-weight': 700
    return

  update: (race) ->
    return unless @race is race
    map = race.track.map
    last = map.length - 1
    at = (z) -> map[Math.max(0, Math.min(last, Math.floor(z / C.SEG)))]
    cur = at race.playerZ()
    s = @scale
    tx = @c - cur.x * s
    ty = @c - cur.y * s
    @layer.transform "t#{tx},#{ty}"
    @arrow.transform "r#{cur.h * 180 / Math.PI},#{@c},#{@c}"
    for r, k in race.rivals
      m = at r.z
      @dots[k].attr cx: m.x * s + tx, cy: m.y * s + ty
    return

D.Speedo = Speedo
D.MiniMap = MiniMap
