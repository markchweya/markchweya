# Chweya Drift — race engine.
# Pure CoffeeScript: no DOM, so it also runs headless under node for testing.

root = if typeof window isnt 'undefined' then window else global
D = root.Drift ?= {}
_u = root._

C = D.C =
  SEG: 200              # world units per road segment
  RUMBLE: 3             # segments per rumble-strip / lane-dash stripe
  ROAD_W: 2000          # half-width of the road
  LANES: [-2 / 3, 0, 2 / 3]
  CAMERA_HEIGHT: 1000
  CAMERA_DEPTH: 1 / Math.tan(50 * Math.PI / 180)
  DRAW_DIST: 300
  CAR_LEN: 820
  CAR_HALF_W: 0.18      # in road half-widths
  TOP: 12000            # units per second at 240 km/h
  NITRO_MULT: 1.25
  ACCEL: 3200
  BRAKE: 9000
  RACE_SEGS: 3000
  RUNOFF_SEGS: 500
C.PLAYER_Z = C.CAMERA_HEIGHT * C.CAMERA_DEPTH
C.FINISH_Z = C.RACE_SEGS * C.SEG
C.KMH = 240 / C.TOP
C.START_SEG = 13
C.LAMP_EVERY = 18

clamp = (v, lo, hi) -> Math.max lo, Math.min(hi, v)
lerp = (a, b, t) -> a + (b - a) * t
easeIn = (a, b, t) -> a + (b - a) * t * t
easeInOut = (a, b, t) -> a + (b - a) * (0.5 - Math.cos(t * Math.PI) / 2)

rng = (seed) ->
  a = seed | 0
  ->
    a = (a + 0x6D2B79F5) | 0
    t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    ((t ^ (t >>> 14)) >>> 0) / 4294967296

approach = (speed, target, dt, boost = 1) ->
  if speed < target
    Math.min target, speed + C.ACCEL * boost * (1 - 0.55 * speed / target) * dt
  else
    Math.max target, speed - 3500 * dt

TREES = ['island', 'island1', 'island3', 'island1']
zoneOf = (i) -> if Math.floor(i / 420) % 2 is 0 then 'city' else 'park'

D.util = {clamp, lerp, rng, zoneOf}

class Track
  constructor: (seed) ->
    @rnd = rng seed
    @segments = []
    @hazards = []
    @rows = []
    @build()
    @decorate()
    @placeHazards()
    @buildMap()

  lastY: ->
    if @segments.length then @segments[@segments.length - 1].p2.world.y else 0

  addSegment: (curve, y) ->
    n = @segments.length
    @segments.push
      index: n
      p1: {world: {y: @lastY(), z: n * C.SEG}, camera: {}, screen: {}}
      p2: {world: {y: y, z: (n + 1) * C.SEG}, camera: {}, screen: {}}
      curve: curve
      sprites: []
      items: []
      dark: Math.floor(n / C.RUMBLE) % 2 is 1
      checker: false
      clip: 0
    return

  addRoad: (enter, hold, leave, curve, hill) ->
    startY = @lastY()
    endY = startY + hill * C.SEG
    total = enter + hold + leave
    for n in [0...enter]
      @addSegment easeIn(0, curve, n / enter), easeInOut(startY, endY, n / total)
    for n in [0...hold]
      @addSegment curve, easeInOut(startY, endY, (enter + n) / total)
    for n in [0...leave]
      @addSegment easeInOut(curve, 0, n / leave), easeInOut(startY, endY, (enter + hold + n) / total)
    return

  build: ->
    r = @rnd
    @addRoad 0, 90, 0, 0, 0
    total = C.RACE_SEGS + C.RUNOFF_SEGS
    while @segments.length < total
      len = 20 + Math.floor(r() * 40)
      curve = (if r() < 0.5 then -1 else 1) * [0, 2, 3, 4, 6][Math.floor(r() * 5)]
      hill = (r() - 0.5) * 60
      @addRoad len, len + Math.floor(r() * 40), len, curve, hill
    @segments.length = total
    for i in [C.START_SEG, C.START_SEG + 1, C.RACE_SEGS, C.RACE_SEGS + 1]
      @segments[i].checker = true
    return

  decorate: ->
    r = @rnd
    tree = -> TREES[Math.floor(r() * TREES.length)]
    for seg in @segments
      i = seg.index
      city = zoneOf(i) is 'city'
      if i % C.LAMP_EVERY is 0
        seg.sprites.push {kind: 'lamp', offset: -1.3}
        seg.sprites.push {kind: 'lamp', offset: 1.3}
      for side in [-1, 1]
        if city
          seg.sprites.push {kind: 'tree', variant: tree(), offset: side * 1.68, scale: 0.85 + r() * 0.25} if i % 14 is (if side < 0 then 7 else 0)
        else
          seg.sprites.push {kind: 'tree', variant: tree(), offset: side * (2.1 + r() * 2.6), scale: 0.8 + r() * 0.5} if r() < 0.3
          seg.sprites.push {kind: 'tree', variant: tree(), offset: side * (5 + r() * 12), scale: 0.9 + r() * 0.6} if r() < 0.32
          seg.sprites.push {kind: 'hedge', offset: side * (1.95 + r() * 0.6), scale: 0.8 + r() * 0.4} if r() < 0.07
      if i % 150 is 75
        seg.sprites.push {kind: 'board', variant: Math.floor(r() * 4), offset: (if r() < 0.5 then -2.4 else 2.4)}
    @segments[C.START_SEG].sprites.push {kind: 'start', offset: 0}
    @segments[C.RACE_SEGS].sprites.push {kind: 'finish', offset: 0}
    return

  # Hazards come in rows. Every row leaves at least one lane open, and the
  # open lane only ever moves to a neighbouring lane, so a path always exists.
  placeHazards: ->
    r = @rnd
    z = 130 * C.SEG
    open = 1
    endZ = (C.RACE_SEGS - 30) * C.SEG
    while z < endZ
      p = z / C.FINISH_Z
      open = clamp open + Math.floor(r() * 3) - 1, 0, 2
      others = (l for l in [0..2] when l isnt open)
      blocked = if r() < 0.25 + 0.45 * p then others else [others[Math.floor(r() * 2)]]
      for lane in blocked
        roll = r()
        kind = if roll < 0.55 then 'car' else if roll < 0.75 then 'barrier' else 'cones'
        item =
          kind: kind
          lane: lane
          x: C.LANES[lane]
          z: z
          len: if kind is 'car' then C.CAR_LEN else 500
          halfW: if kind is 'car' then C.CAR_HALF_W else 0.2
          color: Math.floor(r() * 6)
          hit: false
        @segments[Math.floor(z / C.SEG)].items.push item
        @hazards.push item
      @rows.push {z: z, open: open}
      z += lerp(16000, 11000, p) + r() * 2000
    return

  buildMap: ->
    h = 0
    x = 0
    y = 0
    @map = []
    for seg in @segments
      h += seg.curve * 0.0012
      x += Math.sin h
      y -= Math.cos h
      @map.push {x: x, y: y, h: h}
    return

RIVALS = ['Flash', 'Silverlight', 'Java Applet', 'ActiveX', 'VBScript', 'IE6',
          'Google Wave', 'Prototype.js', 'MooTools', 'YUI', 'Bower']
PACE = [1.075, 1.055, 1.035, 1.015, 0.995, 0.975, 0.955, 0.93, 0.905, 0.88, 0.85]

class Race
  constructor: (opts = {}) ->
    @seed = opts.seed ? Math.floor(Math.random() * 1e9)
    @autopilot = !!opts.autopilot
    @track = new Track @seed
    @position = 0
    @lane = 1
    @x = C.LANES[1]
    @speed = 0
    @nitro = 1
    @boosting = false
    @braking = false
    @time = 0
    @crashes = 0
    @shake = 0
    @flash = 0
    @countdown = if @autopilot then 0 else 3
    @phase = if @autopilot then 'race' else 'countdown'
    @finishTime = null
    @input = {boost: false, brake: false}
    pace = _u.shuffle PACE
    @rivals = (@makeRival(name, i, pace[i]) for name, i in RIVALS)

  makeRival: (name, i, pace) ->
    lane = [0, 2, 1][i % 3]
    {
      name: name
      index: i
      pace: pace
      lane: lane
      x: C.LANES[lane]
      z: C.PLAYER_Z + (i + 1) * 900
      speed: 0
      wobble: Math.random() * 6
      shiftIn: 3 + Math.random() * 6
      finishTime: null
    }

  playerZ: -> @position + C.PLAYER_Z
  progress: -> clamp @playerZ() / C.FINISH_Z, 0, 1

  steer: (dir) ->
    return unless @phase is 'race'
    @lane = clamp @lane + dir, 0, 2

  nextOpenLane: ->
    pz = @playerZ()
    for row in @track.rows when row.z + C.CAR_LEN > pz
      return row.open
    @lane

  update: (dt) ->
    if @phase is 'countdown'
      @countdown -= dt
      @phase = 'race' if @countdown <= 0
      return
    return unless @phase in ['race', 'finished']
    racing = @phase is 'race'
    @time += dt if racing
    if @autopilot
      @lane = @nextOpenLane()
      @input.boost = @nitro > 0.6 or (@boosting and @nitro > 0.05)
    @boosting = racing and @input.boost and @nitro > 0.01
    @braking = racing and @input.brake and not @autopilot
    if @boosting
      @nitro = Math.max 0, @nitro - 0.3 * dt
    else
      @nitro = Math.min 1, @nitro + 0.06 * dt
    target = if racing then C.TOP * (if @boosting then C.NITRO_MULT else 1) else C.TOP * 0.3
    if @braking
      @speed = Math.max 0, @speed - C.BRAKE * dt
    else
      @speed = approach @speed, target, dt, (if @boosting then 1.7 else 1)
    @throttle = racing and not @braking and @speed < target - 1
    @x += (C.LANES[@lane] - @x) * Math.min(1, dt * 10)
    @position += @speed * dt
    @shake = Math.max 0, @shake - dt
    @flash = Math.max 0, @flash - dt
    @collide() if racing
    @moveRival(r, dt) for r in @rivals
    @finish() if racing and @playerZ() >= C.FINISH_Z
    return

  collide: ->
    pz = @playerZ()
    segs = @track.segments
    first = Math.max 0, Math.floor((pz - C.CAR_LEN) / C.SEG)
    last = Math.min segs.length - 1, Math.floor((pz + C.CAR_LEN) / C.SEG)
    for i in [first..last]
      for item in segs[i].items when not item.hit
        if pz < item.z + item.len and item.z < pz + C.CAR_LEN and Math.abs(item.x - @x) < item.halfW + C.CAR_HALF_W
          @crash item
    return

  crash: (item) ->
    item.hit = true
    item.hitAt = @time
    item.hitDir = if item.x >= @x then 1 else -1
    @speed *= 0.3
    @crashes += 1
    @shake = 0.6
    @flash = 0.35
    @onCrash?(item)
    return

  rivalTarget: (r, t) -> C.TOP * r.pace * (1 + 0.03 * Math.sin(t * 0.6 + r.wobble))

  moveRival: (r, dt) ->
    r.speed = approach r.speed, @rivalTarget(r, @time), dt
    r.z += r.speed * dt
    r.shiftIn -= dt
    if r.shiftIn <= 0
      r.lane = clamp r.lane + (if Math.random() < 0.5 then -1 else 1), 0, 2
      r.shiftIn = 4 + Math.random() * 6
    r.x += (C.LANES[r.lane] - r.x) * Math.min(1, dt * 2)
    r.finishTime = @time if not r.finishTime? and r.z >= C.FINISH_Z
    return

  # Rivals still on track when the player finishes get their times projected.
  finish: ->
    @finishTime = @time
    @phase = 'finished'
    step = 1 / 30
    for r in @rivals when not r.finishTime?
      z = r.z
      speed = r.speed
      t = @time
      while z < C.FINISH_Z and t < @time + 600
        speed = approach speed, @rivalTarget(r, t), step
        z += speed * step
        t += step
      r.finishTime = t
    @onFinish?()
    return

  standings: ->
    rows = ({name: r.name, z: r.z, time: r.finishTime, me: false, index: r.index} for r in @rivals)
    rows.push {name: 'YOU', z: @playerZ(), time: @finishTime, me: true, index: -1}
    rows.sort (a, b) ->
      if a.time? and b.time? then a.time - b.time
      else if a.time? then -1
      else if b.time? then 1
      else b.z - a.z
    rows

  rank: ->
    for row, i in @standings() when row.me
      return i + 1
    12

D.Track = Track
D.Race = Race
D.RIVALS = RIVALS
