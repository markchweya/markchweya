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
      # Billboards stand in the open park sections; on city blocks they would sit inside the buildings.
      if not city and i % 90 is 45
        seg.sprites.push {kind: 'board', variant: Math.floor(r() * 4), offset: (if r() < 0.5 then -2.5 else 2.5)}
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
      @rows.push {z: z, open: open, blocked: blocked}
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
LOOKAHEAD = 11000   # just under the minimum gap between hazard rows
PACE = [1.03, 1.01, 0.99, 0.97, 0.95, 0.93, 0.91, 0.89, 0.87, 0.85, 0.82]

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
      shiftCool: 0
      finishTime: null
    }

  playerZ: -> @position + C.PLAYER_Z
  progress: -> clamp @playerZ() / C.FINISH_Z, 0, 1

  steer: (dir) ->
    return unless @phase is 'race'
    next = clamp @lane + dir, 0, 2
    return if next is @lane
    @prevLane = @lane
    @lane = next

  # Demo driver: take the guaranteed open lane, but pass slower traffic through any other unblocked lane.
  autoLane: ->
    pz = @playerZ()
    want = @nextOpenLane()
    return want if @laneClear(want, pz, 'player')
    row = @rowAhead pz
    blocked = if row then row.blocked else []
    for l in [want - 1, want + 1, @lane] when 0 <= l <= 2 and l not in blocked and @laneClear(l, pz, 'player')
      return l
    want

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
      @lane = @autoLane()
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
    @moveRivals dt
    @collideRivals dt if racing
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

  # The hazard row a car at z still has to get past, if it is close enough to react to.
  rowAhead: (z) ->
    for row in @track.rows when row.z + C.CAR_LEN > z
      return (if row.z - z < LOOKAHEAD then row else null)
    null

  # True when no other car is alongside or just ahead in that lane.
  laneClear: (lane, z, self) ->
    cx = C.LANES[lane]
    for o in @rivals when o isnt self
      dz = o.z - z
      return false if Math.abs(o.x - cx) < 0.45 and dz > -C.CAR_LEN * 1.6 and dz < C.CAR_LEN * 3
    return true if self is 'player'
    dz = @playerZ() - z
    not (Math.abs(@x - cx) < 0.45 and dz > -C.CAR_LEN * 1.6 and dz < C.CAR_LEN * 3)

  # Rival driving: dodge hazard rows, follow slower traffic, overtake when a lane is clear.
  moveRival: (r, dt) ->
    target = @rivalTarget r, @time
    row = @rowAhead r.z
    blocked = if row then row.blocked else []
    if r.lane in blocked
      options = (l for l in [0..2] when l not in blocked).sort((a, b) -> Math.abs(a - r.lane) - Math.abs(b - r.lane))
      r.lane = (l for l in options when @laneClear(l, r.z, r))[0] ? options[0]
      r.shiftCool = 1
    aheadSpeed = null
    for o in @rivals when o isnt r and Math.abs(o.x - r.x) < 0.45 and o.z > r.z and o.z - r.z < C.CAR_LEN * 3
      aheadSpeed = Math.min(aheadSpeed ? Infinity, o.speed)
    pz = @playerZ()
    if Math.abs(@x - r.x) < 0.45 and pz > r.z and pz - r.z < C.CAR_LEN * 3
      aheadSpeed = Math.min(aheadSpeed ? Infinity, @speed)
    if aheadSpeed? and aheadSpeed < target - 200
      if r.shiftCool <= 0
        for l in [r.lane - 1, r.lane + 1] when 0 <= l <= 2 and l not in blocked and @laneClear(l, r.z, r)
          r.lane = l
          r.shiftCool = 1.5
          break
      target = Math.min target, aheadSpeed if Math.abs(C.LANES[r.lane] - r.x) < 0.45
    r.shiftCool -= dt
    r.speed = approach r.speed, target, dt
    r.z += r.speed * dt
    r.x += (C.LANES[r.lane] - r.x) * Math.min(1, dt * 4)
    r.finishTime = @time if not r.finishTime? and r.z >= C.FINISH_Z
    return

  moveRivals: (dt) ->
    @moveRival(r, dt) for r in @rivals
    # Never let two rivals occupy the same space: working front to back, the one behind drops back.
    order = @rivals.slice().sort (a, b) -> b.z - a.z
    for pass in [0, 1]
      for a, i in order
        for b in order[0...i] when b.z - a.z < C.CAR_LEN and Math.abs(a.x - b.x) < C.CAR_HALF_W * 2
          a.z = b.z - C.CAR_LEN
          a.speed = Math.min a.speed, b.speed
    return

  # Contact with rivals: rear-ending one slows you to its pace, cutting into an
  # occupied lane bounces you back, and a rival that hits you from behind drops back.
  collideRivals: (dt) ->
    @bounceCool = Math.max 0, (@bounceCool or 0) - dt
    pz = @playerZ()
    for r in @rivals
      dz = r.z - pz
      continue unless Math.abs(dz) < C.CAR_LEN and Math.abs(r.x - @x) < C.CAR_HALF_W * 2
      changing = Math.abs(C.LANES[@lane] - @x) > 0.08
      if changing and @prevLane? and Math.abs(C.LANES[@lane] - r.x) < 0.3
        continue if @bounceCool > 0
        @lane = @prevLane
        @speed *= 0.9
        @bounceCool = 0.4
        @bump 0.25
      else if dz > 0
        closing = @speed - r.speed
        @speed = Math.min @speed, r.speed * 0.97
        @position = r.z - C.CAR_LEN - C.PLAYER_Z
        @bump(if closing > 3000 then 0.45 else 0.2) if closing > 1200
      else
        r.speed = Math.min r.speed, @speed * 0.95
        r.z = pz - C.CAR_LEN
    return

  bump: (strength) ->
    @shake = Math.max @shake, strength
    @onBump?(strength)
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
