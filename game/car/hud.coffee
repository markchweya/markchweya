# Chweya Drift — vector HUD drawn with Raphaël: analog speedometer and minimap.

D = window.Drift
C = D.C

FONT = "'Saira Condensed', 'Arial Narrow', sans-serif"
deg = (v, max) -> 135 + 270 * v / max
rad = (v, max) -> deg(v, max) * Math.PI / 180
pt = (cx, cy, r, a) -> "#{(cx + Math.cos(a) * r).toFixed(2)},#{(cy + Math.sin(a) * r).toFixed(2)}"
arc = (cx, cy, r, a0, a1) ->
  large = if a1 - a0 > Math.PI then 1 else 0
  "M#{pt(cx, cy, r, a0)}A#{r},#{r} 0 #{large} 1 #{pt(cx, cy, r, a1)}"
txt = (p, x, y, s, size, weight = 600, color = '#ffffff') ->
  p.text(x, y, s).attr fill: color, 'font-size': size, 'font-family': FONT, 'font-weight': weight

# Racing-game cluster: RPM arc with redline, big speed and gear in the middle.
class Speedo
  constructor: (el) ->
    p = @p = Raphael el, "100%", "100%"
    p.setViewBox 0, 0, 260, 260, true
    @cx = cx = 130
    @cy = cy = 130
    @R = R = 104
    p.circle(cx, cy, 120).attr fill: "#06090d", "fill-opacity": 0.42, stroke: "#ffffff", "stroke-opacity": 0.1
    p.path(arc(cx, cy, R, rad(0, 10000), rad(10000, 10000))).attr stroke: "#ffffff", "stroke-opacity": 0.12, "stroke-width": 10, fill: "none"
    p.path(arc(cx, cy, R, rad(8000, 10000), rad(10000, 10000))).attr stroke: "#ff2d3b", "stroke-opacity": 0.35, "stroke-width": 10, fill: "none"
    for v in [0..10000] by 500
      a = rad v, 10000
      major = v % 1000 is 0
      r1 = R - (if major then 22 else 15)
      r2 = R - 9
      p.path("M#{pt(cx, cy, r1, a)}L#{pt(cx, cy, r2, a)}").attr
        stroke: if v >= 8000 then "#ff2d3b" else "#ffffff"
        "stroke-width": if major then 3 else 1.3
        "stroke-opacity": if major then 0.95 else 0.6
      txt p, cx + Math.cos(a) * (R - 36), cy + Math.sin(a) * (R - 36), String(v / 1000), 17, 600, (if v >= 8000 then "#ff4b57" else "#ffffff") if major
    @rpmArc = p.path("M0,0").attr stroke: "#ffffff", "stroke-width": 10, fill: "none", "stroke-linecap": "butt"
    @speedText = txt p, cx, cy - 6, "0", 64, 700
    txt p, cx, cy + 28, "km/h", 14, 600, "#aab4bf"
    @gearText = txt p, cx, cy + 62, "N", 40, 800
    for label, i in ["ABS", "TCS", "STM"]
      txt p, cx - 74, cy + 30 + i * 15, label, 11, 700, "#7f8a96"
    @rpm = 900
    @lastSpeed = ""
    @lastGear = ""

  update: (race, audio) ->
    target = if race.speed < 1 and audio.rpm < 1000 then 900 else audio.rpm
    @rpm += (target - @rpm) * 0.3
    end = rad Math.min(@rpm, 9990), 10000
    @rpmArc.attr path: arc(@cx, @cy, @R, rad(0, 10000), end), stroke: (if @rpm > 8000 then "#ff2d3b" else "#ffffff")
    speed = String Math.round(race.speed * C.KMH)
    if speed isnt @lastSpeed
      @speedText.attr "text", speed
      @lastSpeed = speed
    gear = if race.speed < 30 then "N" else String(audio.gear)
    if gear isnt @lastGear
      @gearText.attr "text", gear
      @lastGear = gear
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
