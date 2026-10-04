# Chweya Drift — app shell: Backbone state, jQuery input, Underscore templates,
# AngularJS screens, and the frame loop that drives the engine, world and HUD.

D = window.Drift
C = D.C

D.TECHS = [
  {name: 'CoffeeScript', years: '2009 – made redundant by ES2015', role: 'Every line of game logic, compiled in your browser as the page loads.'}
  {name: 'AngularJS 1.x', years: '2010 – end of life Dec 2021', role: 'Menus, garage, HUD panels and the results screen.'}
  {name: 'Backbone.js', years: '2010 – the MVC darling of 2012', role: 'Race state model and the event bus between engine and UI.'}
  {name: 'Raphaël', years: '2008 – built so IE6 could draw vectors', role: 'The tachometer, N₂O gauge and minimap.'}
  {name: 'Underscore.js', years: '2009 – replaced by native JS', role: 'Templates (this list), throttling, shuffled grids.'}
  {name: 'jQuery 1.x', years: '2006 – final 1.x release 2016', role: 'Keyboard and touch input.'}
  {name: 'LESS', years: '2009 – lost the war to Sass', role: 'Every style on this page, compiled client-side.'}
]

store =
  get: (k, fallback) ->
    try
      v = localStorage.getItem k
      if v? then JSON.parse(v) else fallback
    catch e
      fallback
  set: (k, v) ->
    try
      localStorage.setItem k, JSON.stringify(v)
    catch e
      null
    return

fmt = (t) ->
  return '--:--.--' unless t?
  m = Math.floor t / 60
  s = t - m * 60
  "#{m}:#{if s < 10 then '0' else ''}#{s.toFixed(2)}"

RaceState = Backbone.Model.extend
  defaults:
    phase: 'loading'
    loaded: 0
    banner: ''
    progress: 0
    rank: 12
    field: 12
    time: 0
    nitro: 1
    crashes: 0
    car: 'rosso'
    best: null
    muted: false

state = new RaceState()
bus = _.extend {}, Backbone.Events
keys = {boost: false, brake: false}
audio = new D.EngineAudio()
world = new D.World document.getElementById('scene')

class Game
  constructor: ->
    car = store.get 'drift.paint', 'rosso'
    car = 'rosso' unless _.findWhere(D.PAINTS, id: car)
    muted = store.get 'drift.muted', false
    audio.muted = muted
    state.set car: car, best: store.get('drift.best', null), muted: muted
    world.setPaint car
    @race = new D.Race autopilot: true
    @resultsIn = 0
    @resumeTo = 'race'
    @lastBeep = null

  attach: (@speedo, @minimap) ->
    @minimap.load @race
    return

  loaded: ->
    world.build @race
    state.set phase: 'menu'
    return

  setCar: (id) ->
    store.set 'drift.paint', id
    state.set 'car', id
    world.setPaint id
    return

  toggleMute: ->
    m = not state.get('muted')
    state.set 'muted', m
    store.set 'drift.muted', m
    audio.setMuted m
    return

  newRace: (opts) ->
    @race = new D.Race opts
    world.build @race
    @minimap?.load @race
    return

  start: ->
    return unless world.ready
    audio.start()
    audio.ignition()
    @newRace {}
    @race.onFinish = => @finished()
    @race.onCrash = -> audio.crash()
    @resultsIn = 0
    @lastBeep = null
    keys.boost = keys.brake = false
    state.set phase: 'countdown'
    return

  quit: ->
    @newRace autopilot: true
    @resultsIn = 0
    state.set phase: 'menu', banner: ''
    return

  pause: ->
    ph = state.get 'phase'
    return unless ph in ['countdown', 'race']
    @resumeTo = ph
    state.set phase: 'paused'
    return

  resume: ->
    return unless state.get('phase') is 'paused'
    state.set phase: @resumeTo
    return

  steer: (dir) ->
    @race.steer dir unless @race.autopilot or state.get('phase') is 'paused'
    return

  finished: ->
    r = @race
    best = state.get 'best'
    rank = r.rank()
    newBest = not best? or r.finishTime < best.time
    if newBest
      best = {time: r.finishTime, rank: rank}
      store.set 'drift.best', best
      state.set 'best', best
    standings = r.standings()
    leader = standings[0].time
    rows = for row, i in standings
      pos: i + 1
      name: row.name
      time: fmt(row.time)
      gap: if i is 0 then '' else '+' + (row.time - leader).toFixed(2)
      me: row.me
    bus.trigger 'results',
      rank: rank
      time: fmt(r.finishTime)
      crashes: r.crashes
      newBest: newBest
      rows: rows
    @resultsIn = 2.6
    return

  frame: (dt) ->
    return unless world.ready and state.get('phase') isnt 'loading'
    r = @race
    paused = state.get('phase') is 'paused'
    unless paused
      unless r.autopilot
        r.input.boost = keys.boost
        r.input.brake = keys.brake
      r.update dt
    if r.autopilot and r.phase is 'finished'
      @quit()
      return
    if @resultsIn > 0
      @resultsIn -= dt
      state.set 'phase', 'results' if @resultsIn <= 0
    @countdownBeeps r
    audio.update @race, not paused and not @race.autopilot
    @sync() unless paused
    return

  countdownBeeps: (r) ->
    return if r.autopilot
    if r.phase is 'countdown'
      n = Math.ceil r.countdown
      if n isnt @lastBeep and n <= 3
        audio.beep false
        @lastBeep = n
    else if r.phase is 'race' and @lastBeep isnt 0
      audio.beep true
      @lastBeep = 0
    return

  sync: ->
    r = @race
    ph = state.get 'phase'
    ph = 'race' if ph is 'countdown' and r.phase is 'race'
    ph = 'finished' if ph is 'race' and r.phase is 'finished'
    banner = ''
    unless r.autopilot
      if r.phase is 'countdown'
        banner = String Math.max(1, Math.ceil(r.countdown))
      else if r.phase is 'race' and r.time < 1.1
        banner = 'GO!'
      else if ph is 'finished'
        banner = 'FINISH'
    state.set
      phase: ph
      banner: banner
      progress: Math.floor(r.progress() * 100)
      rank: r.rank()
      time: r.time
      nitro: r.nitro
      crashes: r.crashes
    return

game = new Game()

# ---------- input (jQuery 1.x) ----------
CODES =
  left: [37, 65]
  right: [39, 68]
  boost: [38, 87, 32, 16]
  brake: [40, 83]

$(document).on 'keydown', (e) ->
  k = e.which
  ph = state.get 'phase'
  if k is 77
    game.toggleMute()
    return
  if ph in ['menu', 'results']
    if k in [13, 32]
      game.start()
      e.preventDefault()
    return
  if k in [27, 80]
    if ph is 'paused' then game.resume() else game.pause()
    e.preventDefault()
    return
  repeat = e.originalEvent?.repeat
  if k in CODES.left
    game.steer(-1) unless repeat
    e.preventDefault()
  else if k in CODES.right
    game.steer(1) unless repeat
    e.preventDefault()
  else if k in CODES.boost
    keys.boost = true
    e.preventDefault()
  else if k in CODES.brake
    keys.brake = true
    e.preventDefault()
  return

$(document).on 'keyup', (e) ->
  keys.boost = false if e.which in CODES.boost
  keys.brake = false if e.which in CODES.brake
  return

$('#touch').on 'pointerdown', (e) ->
  game.steer(if e.originalEvent.clientX < window.innerWidth / 2 then -1 else 1)
  return

$('#nitro').on 'pointerdown', (e) ->
  keys.boost = true
  e.preventDefault()
  return

$('#nitro').on 'pointerup pointerleave pointercancel', ->
  keys.boost = false
  return

$(window).on 'blur', -> game.pause()
$(window).on 'resize', -> world.resize()

# ---------- credits (Underscore template) ----------
graveTpl = _.template $('#grave-tpl').html()
$('#graveyard').html graveTpl(techs: D.TECHS)

# ---------- screens (AngularJS 1.x) ----------
angular.module('drift', []).controller 'HudCtrl', ['$scope', ($scope) ->
  vm = this
  vm.cars = D.PAINTS
  vm.s = state.toJSON()
  vm.r = {}
  vm.fmt = fmt
  pull = -> vm.s = state.toJSON()
  state.on 'change', _.throttle((-> $scope.$applyAsync pull), 90)
  state.on 'change:phase change:banner change:car change:muted', -> $scope.$applyAsync pull
  bus.on 'results', (res) -> $scope.$applyAsync -> vm.r = res
  vm.inRace = -> vm.s.phase in ['countdown', 'race', 'finished', 'paused']
  vm.kmLeft = -> ((100 - vm.s.progress) * C.FINISH_Z / C.SEG * 1.1 / 100000).toFixed(1)
  vm.carName = -> (_.findWhere(D.PAINTS, id: vm.s.car) or {}).name
  vm.start = -> game.start()
  vm.pause = -> game.pause()
  vm.resume = -> game.resume()
  vm.quit = -> game.quit()
  vm.pick = (c) -> game.setCar c.id
  vm.mute = -> game.toggleMute()
  return
]
angular.bootstrap document.getElementById('ui'), ['drift']

# ---------- boot ----------
game.attach new D.Speedo(document.getElementById('speedo')), new D.MiniMap(document.getElementById('minimap'))
world.load ((f) -> state.set 'loaded', Math.round(f * 100)), (-> game.loaded())

last = null
tick = (now) ->
  last ?= now
  dt = Math.min 0.05, (now - last) / 1000
  last = now
  game.frame dt
  if world.ready and state.get('phase') isnt 'loading'
    world.update game.race, dt
    world.adapt dt
    game.speedo.update game.race, audio
    game.minimap.update game.race
  requestAnimationFrame tick
requestAnimationFrame tick

D.game = game
D.state = state
D.world = world
D.audio = audio
