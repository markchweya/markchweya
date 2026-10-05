# Chweya Drift — engine audio.
# Six recorded CC0 engine loops (OpenGameArt) are crossfaded and pitch-shifted
# by RPM, which comes from a simple 6-speed gearbox model driven by road speed.

D = window.Drift
C = D.C

GEARS = [0, 62, 102, 142, 182, 222, 300]   # km/h at the top of each gear
IDLE = 900
REDLINE = 7800
LOOPS = ['loop_0', 'loop_1_0', 'loop_2_0', 'loop_3_0', 'loop_4_0', 'loop_5_0']
LOOP_RPM = [900, 2500, 3800, 5100, 6400, 7700]

fetchBuffer = (ctx, url) ->
  new Promise (resolve, reject) ->
    xhr = new XMLHttpRequest()
    xhr.open 'GET', url
    xhr.responseType = 'arraybuffer'
    xhr.onload = -> ctx.decodeAudioData xhr.response, resolve, reject
    xhr.onerror = reject
    xhr.send()

gearbox = (kmh) ->
  g = 1
  g += 1 while g < GEARS.length - 1 and kmh > GEARS[g]
  lo = GEARS[g - 1]
  hi = GEARS[g]
  t = Math.max 0, Math.min(1, (kmh - lo) / (hi - lo))
  rpm = if g is 1 then IDLE + t * (REDLINE - IDLE) else 3600 + t * (REDLINE - 3600)
  {gear: g, rpm: rpm}

class EngineAudio
  constructor: ->
    @ctx = null
    @muted = false
    @rpm = IDLE
    @gear = 1

  # Browsers only allow audio after a user gesture, so this runs on the first click/key.
  start: ->
    return if @ctx
    AC = window.AudioContext or window.webkitAudioContext
    return unless AC
    @ctx = c = new AC()
    @master = c.createGain()
    @master.gain.value = if @muted then 0 else 0.55
    @master.connect c.destination

    @filter = c.createBiquadFilter()
    @filter.type = 'lowpass'
    @filter.frequency.value = 700
    @filter.Q.value = 3
    @engineGain = c.createGain()
    @engineGain.gain.value = 0
    @filter.connect @engineGain
    @engineGain.connect @master

    @loops = []
    LOOPS.forEach (name, i) =>
      fetchBuffer(c, "assets/audio/#{name}.wav").then (buf) =>
        src = c.createBufferSource()
        src.buffer = buf
        src.loop = true
        g = c.createGain()
        g.gain.value = 0
        src.connect g
        g.connect @filter
        src.start()
        @loops[i] = {src: src, gain: g, rpm: LOOP_RPM[i]}
    fetchBuffer(c, 'assets/audio/engine_start.wav').then (buf) =>
      @startBuf = buf
      @ignition() if @wantIgnition

    @noiseBuf = c.createBuffer 1, c.sampleRate * 2, c.sampleRate
    data = @noiseBuf.getChannelData 0
    data[i] = Math.random() * 2 - 1 for i in [0...data.length]
    noise = c.createBufferSource()
    noise.buffer = @noiseBuf
    noise.loop = true
    @windFilter = c.createBiquadFilter()
    @windFilter.type = 'bandpass'
    @windFilter.frequency.value = 900
    @windFilter.Q.value = 0.6
    @windGain = c.createGain()
    @windGain.gain.value = 0
    noise.connect @windFilter
    @windFilter.connect @windGain
    @windGain.connect @master
    noise.start()
    return

  setMuted: (m) ->
    @muted = m
    @master?.gain.setTargetAtTime (if m then 0 else 0.55), @ctx.currentTime, 0.05
    return

  update: (race, active) ->
    kmh = race.speed * C.KMH
    box = gearbox kmh
    @gear = box.gear
    @rpm = box.rpm
    return unless @ctx
    now = @ctx.currentTime
    j = 0
    j += 1 while j < LOOP_RPM.length - 2 and @rpm > LOOP_RPM[j + 1]
    t = Math.max 0, Math.min(1, (@rpm - LOOP_RPM[j]) / (LOOP_RPM[j + 1] - LOOP_RPM[j]))
    for l, i in @loops when l
      w = if i is j then Math.cos(t * Math.PI / 2) else if i is j + 1 then Math.sin(t * Math.PI / 2) else 0
      l.gain.gain.setTargetAtTime w, now, 0.05
      l.src.playbackRate.setTargetAtTime Math.max(0.6, Math.min(1.6, @rpm / l.rpm)), now, 0.05
    load = if race.throttle then 1 else 0.35
    load = 1.4 if race.boosting
    @filter.frequency.setTargetAtTime 900 + @rpm * 0.5 + load * 2500, now, 0.06
    vol = if active then 0.32 + load * 0.3 else 0.12
    @engineGain.gain.setTargetAtTime vol, now, 0.08
    f = race.speed / C.TOP
    wind = (if active then f * f * 0.09 else 0) + (if race.boosting then 0.12 else 0)
    @windGain.gain.setTargetAtTime wind, now, 0.1
    @windFilter.frequency.setTargetAtTime (if race.boosting then 2400 else 700 + f * 900), now, 0.1
    return

  burst: (dur, freq, gain) ->
    return unless @ctx
    c = @ctx
    src = c.createBufferSource()
    src.buffer = @noiseBuf
    flt = c.createBiquadFilter()
    flt.type = 'lowpass'
    flt.frequency.value = freq
    g = c.createGain()
    g.gain.setValueAtTime gain, c.currentTime
    g.gain.exponentialRampToValueAtTime 0.001, c.currentTime + dur
    src.connect flt
    flt.connect g
    g.connect @master
    src.start()
    src.stop c.currentTime + dur
    return

  ignition: ->
    return unless @ctx
    unless @startBuf
      @wantIgnition = true
      return
    @wantIgnition = false
    src = @ctx.createBufferSource()
    src.buffer = @startBuf
    g = @ctx.createGain()
    g.gain.value = 0.8
    src.connect g
    g.connect @master
    src.start()
    return

  thud: (strength) ->
    @burst 0.25, 500, Math.min(0.7, strength * 1.4)
    return

  crash: ->
    @burst 0.6, 900, 0.9
    @burst 0.25, 4000, 0.4
    return

  beep: (high) ->
    return unless @ctx
    c = @ctx
    o = c.createOscillator()
    o.type = 'square'
    o.frequency.value = if high then 1320 else 660
    g = c.createGain()
    g.gain.setValueAtTime 0.12, c.currentTime
    g.gain.exponentialRampToValueAtTime 0.001, c.currentTime + (if high then 0.6 else 0.25)
    o.connect g
    g.connect @master
    o.start()
    o.stop c.currentTime + 0.6
    return

D.EngineAudio = EngineAudio
D.gearbox = gearbox
