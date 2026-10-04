# Chweya Drift — 3D world.
# three.js renders CC0 Kenney models along a road mesh generated from the
# race engine's track, lit by a Poly Haven HDR sky.

D = window.Drift
C = D.C
rng = D.util.rng
zoneOf = D.util.zoneOf

SEG_M = 1.1          # metres per road segment
HALF = 5.4           # metres per road half-width
VERT = 0.0025        # metres per unit of track elevation
ROAD_EDGE = 6.2
CURB = 6.45
WALK = 10
GRASS = 120
CHUNK = 40
UNITS = C.SEG / SEG_M  # engine units per metre

asset = (p) -> 'assets/models/' + p
MODELS =
  ferrari: asset 'real/ferrari.glb'
  ferrariLod: asset 'real/ferrari_lod.glb'
  covered: asset 'real/covered_car/covered_car_1k.gltf'
  cone: asset 'cars/cone.glb'
  lamp: asset 'roads/light-curved.glb'
  barrier: asset 'roads/construction-barrier.glb'
  worklight: asset 'roads/construction-light.glb'
  sign: asset 'roads/sign-highway.glb'
  oak: asset 'nature/tree_oak.glb'
  tree: asset 'nature/tree_default.glb'
  detailed: asset 'nature/tree_detailed.glb'
  pine: asset 'nature/tree_pineTallA_detailed.glb'
  palm: asset 'nature/tree_palmTall.glb'
  palm2: asset 'nature/tree_palmDetailedTall.glb'
  bush: asset 'nature/plant_bushLarge.glb'
  gantry: asset 'racing/overheadLights.glb'
  billboard: asset 'racing/billboard.glb'
# CC0 photo facades from ambientCG; tile is the real-world size of one texture repeat in metres.
FACADES =
  Facade006: {tile: 24, glass: true}
  Facade018A: {tile: 24}
  Facade019A: {tile: 26}
  Facade020A: {tile: 26}
  Facade001: {tile: 16, glass: true}
  Facade005: {tile: 14, glass: true}
STREET_FACADES = ['Facade006', 'Facade018A', 'Facade018A', 'Facade019A', 'Facade020A']
TOWER_FACADES = ['Facade001', 'Facade005', 'Facade019A', 'Facade020A', 'Facade006']

buildingParts = (w, h, d, tile, uOff) ->
  hw = w / 2
  hd = d / 2
  make = -> {pos: [], nrm: [], uv: [], idx: []}
  walls = make()
  roof = make()
  quad = (g, a, b, c, e, n, uw, vh, u0) ->
    i = g.pos.length / 3
    g.pos.push a..., b..., c..., e...
    g.nrm.push n..., n..., n..., n...
    g.uv.push u0, 0, u0 + uw, 0, u0 + uw, vh, u0, vh
    g.idx.push i, i + 1, i + 2, i, i + 2, i + 3
    return
  quad walls, [-hw, 0, hd], [hw, 0, hd], [hw, h, hd], [-hw, h, hd], [0, 0, 1], w / tile, h / tile, uOff
  quad walls, [hw, 0, hd], [hw, 0, -hd], [hw, h, -hd], [hw, h, hd], [1, 0, 0], d / tile, h / tile, uOff
  quad walls, [hw, 0, -hd], [-hw, 0, -hd], [-hw, h, -hd], [hw, h, -hd], [0, 0, -1], w / tile, h / tile, uOff
  quad walls, [-hw, 0, -hd], [-hw, 0, hd], [-hw, h, hd], [-hw, h, -hd], [-1, 0, 0], d / tile, h / tile, uOff
  quad roof, [-hw, h, hd], [hw, h, hd], [hw, h, -hd], [-hw, h, -hd], [0, 1, 0], w / 6, d / 6, 0
  toGeo = (g) ->
    geo = new THREE.BufferGeometry()
    geo.setAttribute 'position', new THREE.Float32BufferAttribute(g.pos, 3)
    geo.setAttribute 'normal', new THREE.Float32BufferAttribute(g.nrm, 3)
    geo.setAttribute 'uv', new THREE.Float32BufferAttribute(g.uv, 2)
    geo.setIndex g.idx
    geo
  {walls: toGeo(walls), roof: toGeo(roof)}

CAR_KEYS = ['ferrari', 'ferrariLod', 'covered']
PAINTS = [
  {id: 'rosso', name: 'Rosso Corsa', hex: '#a3000f'}
  {id: 'giallo', name: 'Giallo Modena', hex: '#f2b600'}
  {id: 'nero', name: 'Nero Daytona', hex: '#0d0d0f'}
  {id: 'bianco', name: 'Bianco Avus', hex: '#e9e9e6'}
  {id: 'blu', name: 'Blu Pozzi', hex: '#14306e'}
  {id: 'verde', name: 'Verde British', hex: '#0d3b2a'}
  {id: 'argento', name: 'Grigio Silverstone', hex: '#8d949b'}
]
RIVAL_PAINTS = ['#f2b600', '#0d0d0f', '#e9e9e6', '#14306e', '#0d3b2a', '#8d949b', '#ff5a00', '#5b2a86', '#00a3b4', '#c0c0c0', '#7a0019']
DRACO_PATH = 'https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/libs/draco/gltf/'
SIZE =
  cone: ['y', 0.8]
  lamp: ['y', 8.5]
  barrier: ['z', 2.8]
  worklight: ['y', 2.2]
  sign: ['y', 6]
  oak: ['y', 11]
  tree: ['y', 10]
  detailed: ['y', 12]
  pine: ['y', 15]
  palm: ['y', 13]
  palm2: ['y', 12]
  bush: ['y', 1.6]
  gantry: ['x', 15]
  billboard: ['x', 10]
CAR_MODEL_YAW = {ferrari: 0, ferrariLod: 0, covered: 0}
ADS = [
  ['GET FLASH PLAYER', 'Required to view this content', '#b71c1c', '#ff5252']
  ['BEST VIEWED IN IE6', 'at 800 × 600', '#0d47a1', '#42a5f5']
  ['Y2K READY', 'Certified since 1999', '#1b5e20', '#66bb6a']
  ['JAVA APPLET', 'Loading… please wait', '#e65100', '#ffa726']
]

canvasTex = (w, h, paint) ->
  c = document.createElement 'canvas'
  c.width = w
  c.height = h
  paint c.getContext('2d'), w, h
  t = new THREE.CanvasTexture c
  t.encoding = THREE.sRGBEncoding
  t

glowTexture = -> canvasTex 128, 128, (g) ->
  grad = g.createRadialGradient 64, 64, 0, 64, 64, 64
  grad.addColorStop 0, 'rgba(255,255,255,1)'
  grad.addColorStop 0.18, 'rgba(255,255,255,0.75)'
  grad.addColorStop 0.45, 'rgba(255,255,255,0.18)'
  grad.addColorStop 1, 'rgba(255,255,255,0)'
  g.fillStyle = grad
  g.fillRect 0, 0, 128, 128

adTexture = (ad) ->
  t = canvasTex 512, 256, (g, w, h) ->
    grad = g.createLinearGradient 0, 0, 0, h
    grad.addColorStop 0, ad[3]
    grad.addColorStop 1, ad[2]
    g.fillStyle = grad
    g.fillRect 0, 0, w, h
    g.fillStyle = '#ffffff'
    g.textAlign = 'center'
    g.textBaseline = 'middle'
    g.font = "900 64px Impact, 'Arial Black', sans-serif"
    g.fillText ad[0], w / 2, h * 0.42, w * 0.92
    g.font = '600 30px Arial, sans-serif'
    g.fillText ad[1], w / 2, h * 0.72, w * 0.9
  t.flipY = false
  t

checkerTexture = -> canvasTex 512, 64, (g, w, h) ->
  for x in [0...16]
    for y in [0...2]
      g.fillStyle = if (x + y) % 2 then '#111111' else '#f2f2f2'
      g.fillRect x * 32, y * 32, 32, 32

labelTexture = (text) -> canvasTex 256, 64, (g, w, h) ->
  g.font = "700 34px 'Saira Condensed', 'Arial Narrow', sans-serif"
  g.textAlign = 'center'
  g.textBaseline = 'middle'
  tw = Math.min w - 8, g.measureText(text).width + 30
  g.fillStyle = 'rgba(10,16,24,0.62)'
  g.fillRect (w - tw) / 2, 8, tw, 48
  g.fillStyle = '#ffffff'
  g.fillText text, w / 2, 33

# Brightest pixel gives the sun direction; the horizon band gives the fog colour.
analyseSky = (tex) ->
  img = tex.image
  d = img.data
  w = img.width
  h = img.height
  best = -1
  bi = 0
  for i in [0...w * h] by 3
    l = d[i * 4] + d[i * 4 + 1] + d[i * 4 + 2]
    if l > best
      best = l
      bi = i
  u = (bi % w + 0.5) / w
  v = 1 - (Math.floor(bi / w) + 0.5) / h
  theta = (u - 0.5) * 2 * Math.PI
  el = Math.max 0.18, (v - 0.5) * Math.PI
  sun = new THREE.Vector3(Math.cos(el) * Math.cos(theta), Math.sin(el), Math.cos(el) * Math.sin(theta)).normalize()
  row = Math.floor((1 - 0.515) * h)
  sum = [0, 0, 0]
  for x in [0...w]
    o = (row * w + x) * 4
    sum[c] += Math.min(3, d[o + c]) for c in [0..2]
  horizon = new THREE.Color sum[0] / w, sum[1] / w, sum[2] / w
  {sun, horizon}

class World
  constructor: (canvas) ->
    @renderer = new THREE.WebGLRenderer canvas: canvas, antialias: true, powerPreference: 'high-performance'
    @renderer.setPixelRatio Math.min(window.devicePixelRatio or 1, 1.25)
    @renderer.outputEncoding = THREE.sRGBEncoding
    @renderer.toneMapping = THREE.ACESFilmicToneMapping
    @renderer.toneMappingExposure = 0.82
    @renderer.shadowMap.enabled = true
    @renderer.shadowMap.type = THREE.PCFSoftShadowMap
    @scene = new THREE.Scene()
    @camera = new THREE.PerspectiveCamera 62, 1, 0.1, 1600
    @fov = 62
    @models = {}
    @tex = {}
    @tmp = new THREE.Vector3()
    @camPos = new THREE.Vector3()
    @look = new THREE.Vector3()
    @glowTex = glowTexture()
    @paintId = 'rosso'
    @ready = false
    @resize()

  # ---------- loading ----------
  load: (onProgress, onDone) ->
    manager = new THREE.LoadingManager()
    manager.onProgress = (url, loaded, total) -> onProgress?(loaded / total)
    manager.onError = (url) -> console.error 'Chweya Drift: failed to load', url
    manager.onLoad = =>
      @setup()
      @ready = true
      onDone?()
    gltf = new THREE.GLTFLoader manager
    draco = new THREE.DRACOLoader()
    draco.setDecoderPath DRACO_PATH
    gltf.setDRACOLoader draco
    @aoTex = new THREE.TextureLoader(manager).load 'assets/models/real/ferrari_ao.png'
    for key, url of MODELS
      do (key) => gltf.load url, (g) => @models[key] = @prep(key, g.scene)
    texLoader = new THREE.TextureLoader manager
    for name in ['asphalt_02', 'aerial_grass_rock', 'concrete_pavement']
      @tex[name] =
        map: @texture texLoader, "assets/tex/#{name}_diff_1k.jpg", true
        normalMap: @texture texLoader, "assets/tex/#{name}_nor_gl_1k.jpg", false
        roughnessMap: @texture texLoader, "assets/tex/#{name}_rough_1k.jpg", false
    @facadeTex = {}
    for id, spec of FACADES
      dir = "assets/tex/facades/#{id}"
      @facadeTex[id] =
        map: @texture texLoader, "#{dir}_Color.jpg", true
        normalMap: @texture texLoader, "#{dir}_NormalGL.jpg", false
        roughnessMap: @texture texLoader, "#{dir}_Roughness.jpg", false
        metalnessMap: if spec.glass then @texture(texLoader, "#{dir}_Metalness.jpg", false) else null
    new THREE.RGBELoader(manager).setDataType(THREE.FloatType).load 'assets/tex/kloppenheim_06_puresky_2k.hdr', (t) => @hdr = t
    return

  texture: (loader, url, color) ->
    t = loader.load url
    t.wrapS = t.wrapT = THREE.RepeatWrapping
    t.encoding = THREE.sRGBEncoding if color
    t.anisotropy = Math.min 8, @renderer.capabilities.getMaxAnisotropy()
    t

  prep: (key, scene) ->
    isCar = key in CAR_KEYS
    paint = null
    if key in ['ferrari', 'ferrariLod']
      paint = new THREE.MeshPhysicalMaterial
        color: 0x8c0007
        metalness: 0.3
        roughness: 0.28
        clearcoat: 1
        clearcoatRoughness: 0.04
      paint.color.convertSRGBToLinear()
      paint.userData.paint = true
    scene.traverse (o) ->
      return unless o.isMesh
      ferrari = key in ['ferrari', 'ferrariLod']
      o.castShadow = not ferrari
      o.receiveShadow = not ferrari
      o.material = paint if paint and o.material.name is 'Body_Color'
      return
    if key in ['oak', 'tree', 'detailed', 'pine', 'palm', 'palm2', 'bush']
      scene.traverse (o) ->
        return unless o.isMesh
        o.material = o.material.clone()
        n = o.material.name
        dark = /dark/i.test n
        if /leaf|grass/i.test n
          o.material.color.set(if dark then '#24391c' else '#355224').convertSRGBToLinear()
        else if /bark|wood/i.test n
          o.material.color.set(if dark then '#33271d' else '#4d3b2b').convertSRGBToLinear()
        o.material.roughness = 0.92
        return
    box = new THREE.Box3().setFromObject scene
    if key is 'ferrari'
      ao = new THREE.Mesh new THREE.PlaneGeometry(0.655 * 4, 1.3 * 4), new THREE.MeshBasicMaterial
        map: @aoTex
        blending: THREE.MultiplyBlending
        toneMapped: false
        transparent: true
        depthWrite: false
      ao.rotation.x = -Math.PI / 2
      ao.position.y = 0.02
      ao.renderOrder = 2
      scene.add ao
    size = box.getSize new THREE.Vector3()
    s = if isCar then 4.6 / Math.max(size.z, size.x)
    else if SIZE[key] then SIZE[key][1] / size[SIZE[key][0]]
    else 1
    holder = new THREE.Group()
    if key is 'lamp'
      scene.position.set 0, -box.min.y, 0
    else
      center = box.getCenter new THREE.Vector3()
      scene.position.set -center.x, -box.min.y, -center.z
    holder.add scene
    holder.scale.setScalar s
    holder.rotation.y = CAR_MODEL_YAW[key] if isCar
    wrap = new THREE.Group()
    wrap.add holder
    wrap.userData.size = size.clone().multiplyScalar s
    if key is 'lamp'
      arm = if box.max.z + box.min.z >= 0 then 1 else -1
      wrap.userData.arm = arm
      wrap.userData.tip = new THREE.Vector3 0, box.max.y * s - 0.25, (if arm > 0 then box.max.z else box.min.z) * s * 0.92
    wrap

  setup: ->
    pmrem = new THREE.PMREMGenerator @renderer
    @hdr.mapping = THREE.EquirectangularReflectionMapping
    @scene.background = @hdr
    @scene.environment = pmrem.fromEquirectangular(@hdr).texture
    pmrem.dispose()
    sky = analyseSky @hdr
    @sunDir = sky.sun
    @scene.fog = new THREE.Fog sky.horizon, 90, 470
    @scene.add new THREE.HemisphereLight(0xfff0de, 0x3d3529, 0.3)
    @sun = new THREE.DirectionalLight 0xffd9b0, 2.3
    @sun.castShadow = true
    @sun.shadow.mapSize.set 2048, 2048
    cam = @sun.shadow.camera
    cam.left = -45
    cam.right = 45
    cam.top = 45
    cam.bottom = -45
    cam.near = 1
    cam.far = 300
    @sun.shadow.bias = -0.0004
    @sun.shadow.normalBias = 0.03
    @scene.add @sun, @sun.target
    pbr = (set, extra = {}) ->
      new THREE.MeshStandardMaterial _.extend({map: set.map, normalMap: set.normalMap, roughnessMap: set.roughnessMap, side: THREE.DoubleSide}, extra)
    @mat =
      road: pbr @tex.asphalt_02, {normalScale: new THREE.Vector2(0.8, 0.8)}
      walk: pbr @tex.concrete_pavement
      grass: pbr @tex.aerial_grass_rock
      paint: new THREE.MeshStandardMaterial color: 0xf0efe9, roughness: 0.55, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -4
      curb: new THREE.MeshStandardMaterial color: 0xc9c5bd, roughness: 0.85, side: THREE.DoubleSide
      checker: new THREE.MeshStandardMaterial map: checkerTexture(), roughness: 0.6, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -6
    @mat.facades = {}
    for id, spec of FACADES
      t = @facadeTex[id]
      @mat.facades[id] = new THREE.MeshStandardMaterial
        map: t.map
        normalMap: t.normalMap
        roughnessMap: t.roughnessMap
        metalnessMap: t.metalnessMap
        metalness: if spec.glass then 1 else 0
        envMapIntensity: if spec.glass then 1.3 else 0.8
    @mat.roof = new THREE.MeshStandardMaterial color: 0x55585c, roughness: 0.9
    @ads = (adTexture(ad) for ad in ADS)
    return

  resize: ->
    w = window.innerWidth
    h = window.innerHeight
    @renderer.setSize w, h, false
    @camera.aspect = w / h
    @camera.updateProjectionMatrix()
    return

  setPaint: (id) ->
    @paintId = id
    @spawnPlayer() if @root
    return

  # ---------- path helpers ----------
  at: (z, lateral, out) ->
    f = z / C.SEG
    k = Math.max 0, Math.min(@n - 1, Math.floor(f))
    t = Math.max 0, Math.min(1, f - k)
    a = @pts[k]
    b = @pts[k + 1]
    h0 = @head[k]
    h = h0 + (@head[Math.min(@n - 1, k + 1)] - h0) * t
    out.set a.x + (b.x - a.x) * t + Math.cos(h) * lateral, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t + Math.sin(h) * lateral
    h

  ribbon: (inner, outer, y0, y1, mat, uS, vS, keep) ->
    n = @n
    pos = new Float32Array((n + 1) * 6)
    uv = new Float32Array((n + 1) * 4)
    idx = []
    for k in [0..n]
      p = @pts[k]
      h = @head[Math.min(k, n - 1)]
      cx = Math.cos h
      sz = Math.sin h
      o = k * 6
      pos[o] = p.x + cx * inner
      pos[o + 1] = p.y + y0
      pos[o + 2] = p.z + sz * inner
      pos[o + 3] = p.x + cx * outer
      pos[o + 4] = p.y + y1
      pos[o + 5] = p.z + sz * outer
      v = k * SEG_M / vS
      q = k * 4
      uv[q] = inner / uS
      uv[q + 1] = v
      uv[q + 2] = outer / uS
      uv[q + 3] = v
      if k < n and (not keep or keep(k))
        a = k * 2
        idx.push a, a + 2, a + 1, a + 1, a + 2, a + 3
    geo = new THREE.BufferGeometry()
    geo.setAttribute 'position', new THREE.BufferAttribute(pos, 3)
    geo.setAttribute 'uv', new THREE.BufferAttribute(uv, 2)
    geo.setIndex idx
    geo.computeVertexNormals()
    @disposables.push geo
    mesh = new THREE.Mesh geo, mat
    mesh.receiveShadow = true
    @root.add mesh
    mesh

  chunk: (z) ->
    c = Math.max 0, Math.floor(z / C.SEG / CHUNK)
    unless @chunks[c]
      @chunks[c] = new THREE.Group()
      @root.add @chunks[c]
    @chunks[c]

  put: (key, z, lateral, yaw, parent) ->
    src = @models[key]
    return null unless src
    obj = src.clone()
    h = @at z, lateral, obj.position
    obj.rotation.y = yaw(h)
    (parent or @chunk(z)).add obj
    obj

  glow: (color, size, opacity = 1) ->
    s = new THREE.Sprite new THREE.SpriteMaterial
      map: @glowTex
      color: color
      transparent: true
      opacity: opacity
      blending: THREE.AdditiveBlending
      depthWrite: false
    s.scale.set size, size, 1
    s

  # ---------- per-race build ----------
  build: (race) ->
    if @root
      @scene.remove @root
      g.dispose() for g in @disposables
    @root = new THREE.Group()
    @scene.add @root
    @disposables = []
    @chunks = []
    @camH = null
    @race = race
    track = race.track
    segs = track.segments
    @n = n = segs.length
    @pts = [new THREE.Vector3(0, segs[0].p1.world.y * VERT, 0)]
    @head = []
    minY = Infinity
    for k in [0...n]
      m = track.map[k]
      p = new THREE.Vector3 m.x * SEG_M, segs[k].p2.world.y * VERT, m.y * SEG_M
      minY = Math.min minY, p.y
      @pts.push p
      @head.push m.h

    @ribbon -ROAD_EDGE, ROAD_EDGE, 0, 0, @mat.road, 7, 7
    for s in [-1, 1]
      @ribbon s * 5.05, s * 5.2, 0.012, 0.012, @mat.paint, 1, 1
      @ribbon s * 1.73, s * 1.87, 0.012, 0.012, @mat.paint, 1, 1, (k) -> Math.floor(k / 3) % 2 is 0
      @ribbon s * ROAD_EDGE, s * ROAD_EDGE, 0, 0.16, @mat.curb, 1, 1
      @ribbon s * ROAD_EDGE, s * CURB, 0.16, 0.16, @mat.curb, 1, 1
      @ribbon s * CURB, s * WALK, 0.16, 0.16, @mat.walk, 3, 3
      @ribbon s * WALK, s * GRASS, 0.12, -1.6, @mat.grass, 9, 9

    ground = new THREE.PlaneGeometry 9000, 9000
    uv = ground.attributes.uv
    uv.setXY i, uv.getX(i) * 900, uv.getY(i) * 900 for i in [0...uv.count]
    @disposables.push ground
    plane = new THREE.Mesh ground, @mat.grass
    plane.rotation.x = -Math.PI / 2
    mid = @pts[Math.floor(n / 2)]
    plane.position.set mid.x, minY - 1.7, mid.z
    plane.receiveShadow = true
    @root.add plane

    for idx in [C.START_SEG, C.RACE_SEGS]
      strip = new THREE.Mesh new THREE.PlaneGeometry(ROAD_EDGE * 2, 1.4), @mat.checker
      @disposables.push strip.geometry
      holder = new THREE.Group()
      h = @at (idx + 0.5) * C.SEG, 0, holder.position
      holder.position.y += 0.014
      holder.rotation.y = -h
      strip.rotation.x = -Math.PI / 2
      strip.receiveShadow = true
      holder.add strip
      @root.add holder

    @placeScenery track
    @placeCity race.seed
    @placeHazards track
    @placeRivals race
    @spawnPlayer()
    return

  placeScenery: (track) ->
    face = (side) -> if side < 0 then ((h) -> Math.PI / 2 - h) else ((h) -> -Math.PI / 2 - h)
    for seg in track.segments
      z = seg.p1.world.z
      for sp in seg.sprites
        lat = sp.offset * HALF
        side = if lat < 0 then -1 else 1
        switch sp.kind
          when 'lamp'
            src = @models.lamp
            yaw = face side
            obj = @put 'lamp', z, lat, (if src.userData.arm > 0 then yaw else (h) -> yaw(h) + Math.PI)
            if obj
              light = @glow 0xffb56b, 3.2, 0.9
              light.position.copy src.userData.tip
              obj.add light
          when 'start', 'finish'
            @put 'gantry', z, 0, ((h) -> -h), @root
          when 'board'
            obj = @put 'billboard', z, lat, ((h) -> -h + side * 0.35)
            if obj
              ad = @ads[sp.variant % @ads.length]
              obj.traverse (o) ->
                if o.isMesh and o.material.name is 'tankco'
                  o.material = o.material.clone()
                  o.material.map = ad
                  o.material.emissive = new THREE.Color 0x222222
                  o.material.emissiveMap = ad
                return
          when 'sign'
            @put 'sign', z, lat, ((h) -> -h + Math.PI / 2)
          else
            spin = Math.random() * Math.PI * 2
            @put sp.kind, z, lat, ((h) -> spin)
    return

  # Buildings are laid out as continuous street walls so they never overlap.
  # Buildings are generated boxes wearing CC0 photo facades, laid out as
  # continuous street walls, then merged per chunk and facade to keep draw calls low.
  placeCity: (seed) ->
    r = rng seed + 17
    toUnits = (m) -> m * UNITS
    batches = {}
    add = (z, geo, key) =>
      c = Math.max 0, Math.floor(z / C.SEG / CHUNK)
      ((batches[c] ?= {})[key] ?= []).push geo
    m = new THREE.Matrix4()
    pos = new THREE.Vector3()
    for side in [-1, 1]
      for row in [0, 1]
        z = toUnits(30)
        limit = (C.RACE_SEGS + C.RUNOFF_SEGS - 40) * C.SEG
        while z < limit
          i = Math.floor z / C.SEG
          if zoneOf(i) isnt 'city'
            z += toUnits 25
            continue
          pool = if row is 0 then STREET_FACADES else TOWER_FACADES
          f = pool[Math.floor(r() * pool.length)]
          width = if row is 0 then 14 + r() * 16 else 22 + r() * 14
          depth = if row is 0 then 14 + r() * 8 else 20 + r() * 12
          height = if row is 0 then 12 + Math.floor(r() * 9) * 3.3 else 55 + r() * 90
          setback = if row is 0 then WALK + 1.5 + depth / 2 + r() * 2 else WALK + 42 + depth / 2 + r() * 40
          zc = z + toUnits(width / 2)
          h = @at zc, side * setback, pos
          yaw = if side < 0 then Math.PI / 2 - h else -Math.PI / 2 - h
          m.makeRotationY(yaw).setPosition pos.x, pos.y - 0.5, pos.z
          parts = buildingParts width, height, depth, FACADES[f].tile, r() * 4
          parts.walls.applyMatrix4 m
          parts.roof.applyMatrix4 m
          add zc, parts.walls, f
          add zc, parts.roof, 'roof'
          z += toUnits(width + (if row is 0 then 1 + r() * 3 else 14 + r() * 30))
    for c, groups of batches
      for key, geos of groups
        merged = THREE.BufferGeometryUtils.mergeBufferGeometries geos
        g.dispose() for g in geos
        @disposables.push merged
        mesh = new THREE.Mesh merged, (if key is 'roof' then @mat.roof else @mat.facades[key])
        mesh.castShadow = true
        mesh.receiveShadow = true
        @chunk(c * CHUNK * C.SEG).add mesh
    return

  vehicle: (key, opts = {}) ->
    src = @models[key]
    obj = src.clone()
    size = src.userData.size
    obj.traverse (o) ->
      return unless o.isMesh
      if opts.paint and o.material.userData.paint
        o.material = o.material.clone()
        o.material.color.set(opts.paint).convertSRGBToLinear()
      if opts.ghost
        o.material = o.material.clone()
        o.material.transparent = true
        o.material.opacity = 0.42
        o.material.depthWrite = false
        o.castShadow = false
      return
    tails = []
    for side in [-1, 1] when not opts.dark
      t = @glow 0xff2a1f, 0.7, (if opts.ghost then 0.5 else 0.9)
      t.position.set side * size.x * 0.32, size.y * 0.5, size.z / 2 + 0.05
      obj.add t
      tails.push t
    obj.userData.tails = tails
    obj

  placeHazards: (track) ->
    @hazards = []
    for item in track.hazards
      zc = item.z + item.len / 2
      lat = item.x * HALF
      switch item.kind
        when 'car'
          obj = @vehicle 'covered', dark: true
          @at zc, lat, obj.position
          obj.rotation.y = -@at(zc, lat, @tmp)
          size = @models.covered.userData.size
          obj.userData.blink = for side in [-1, 1]
            b = @glow 0xffa21f, 1.1, 0.95
            b.position.set side * size.x * 0.42, 0.55, size.z / 2 + 0.15
            obj.add b
            b
        when 'cones'
          obj = new THREE.Group()
          for dx in [-1.3, 0, 1.3]
            c = @models.cone.clone()
            c.position.x = dx
            obj.add c
          obj.rotation.y = -@at(zc, lat, obj.position)
        else
          obj = new THREE.Group()
          bar = @models.barrier.clone()
          bar.rotation.y = Math.PI / 2
          obj.add bar
          lamp = @models.worklight.clone()
          lamp.position.y = 0.6
          lamp.scale.setScalar 0.5
          obj.add lamp
          beacon = @glow 0xffb300, 1.6, 1
          beacon.position.y = 1.85
          obj.add beacon
          obj.userData.blink = [beacon]
          obj.rotation.y = -@at(zc, lat, obj.position)
      obj.userData.base = obj.position.clone()
      obj.userData.yaw = obj.rotation.y
      @root.add obj
      @hazards.push {item: item, obj: obj}
    return

  placeRivals: (race) ->
    @rivals = for rv in race.rivals
      obj = @vehicle 'ferrariLod', ghost: true, paint: RIVAL_PAINTS[rv.index % RIVAL_PAINTS.length]
      label = new THREE.Sprite new THREE.SpriteMaterial(map: labelTexture(rv.name), transparent: true, depthWrite: false)
      label.scale.set 3.6, 0.9, 1
      label.position.y = obj.userData.size?.y + 1.3 or 2.6
      obj.add label
      obj.userData.label = label
      @root.add obj
      obj
    return

  spawnPlayer: ->
    @player?.parent?.remove @player
    paint = _.findWhere(PAINTS, id: @paintId) or PAINTS[0]
    @player = @vehicle 'ferrari', paint: paint.hex
    size = @models.ferrari.userData.size
    @wheels = []
    @player.traverse (o) => @wheels.push o if /^wheel_(fl|fr|rl|rr)$/.test(o.name)
    @flames = for side in [-1, 1]
      f = @glow 0x6fa8ff, 0.9, 1
      f.position.set side * 0.35, 0.35, size.z / 2 + 0.25
      f.visible = false
      @player.add f
      f
    @root.add @player
    return

  # ---------- per-frame ----------
  update: (race, dt) ->
    return unless @ready and @root and race is @race
    pz = race.playerZ()
    seg = pz / C.SEG
    first = Math.floor((seg - 40) / CHUNK)
    last = Math.floor((seg + 420) / CHUNK)
    for g, c in @chunks when g
      g.visible = c >= first and c <= last

    zc = pz + C.CAR_LEN / 2
    h = @at zc, race.x * HALF, @player.position
    steer = C.LANES[race.lane] - race.x
    clock = performance.now() / 1000
    @player.position.y += Math.sin(clock * 31) * 0.012 * (race.speed / C.TOP)
    @player.rotation.set 0, -h - steer * 0.3, 0
    @player.rotateZ -steer * 0.05
    spin = race.speed / UNITS / 0.36 * dt
    w.rotation.x -= spin for w in @wheels
    brake = if race.braking then 1.6 else 1
    t.scale.set 0.7 * brake, 0.7 * brake, 1 for t in @player.userData.tails
    for f in @flames
      f.visible = race.boosting
      s = 0.7 + Math.random() * 0.7
      f.scale.set s, s, 1

    for rv, i in race.rivals
      obj = @rivals[i]
      gap = (rv.z - pz) / UNITS
      obj.visible = gap > -5 and gap < 260
      obj.userData.label.visible = gap > 14
      obj.rotation.y = -@at(rv.z + C.CAR_LEN / 2, rv.x * HALF, obj.position) if obj.visible

    blinkOn = Math.floor(clock * 2.4) % 2 is 0
    for hz in @hazards
      item = hz.item
      obj = hz.obj
      b.visible = blinkOn and not item.hit for b in (obj.userData.blink or [])
      if item.hit
        age = race.time - item.hitAt
        base = obj.userData.base
        yaw = obj.userData.yaw
        side = item.hitDir * Math.min(age, 1.2) * 7
        obj.position.set base.x + Math.cos(-yaw) * side, base.y + Math.max(0, 5 * age - 9 * age * age), base.z + Math.sin(-yaw) * side
        obj.rotation.y = yaw + item.hitDir * Math.min(age, 1.2) * 2.2

    @updateCamera race, dt
    @sun.position.copy(@player.position).addScaledVector @sunDir, 150
    @sun.target.position.copy @player.position
    @renderer.render @scene, @camera
    return

  updateCamera: (race, dt) ->
    k = 1 - Math.exp(-dt * 5)
    @camLat ?= race.x * HALF
    @camLat += (race.x * HALF * 0.9 - @camLat) * k
    zc = race.playerZ() + C.CAR_LEN / 2
    @at zc - 7.6 * UNITS, @camLat, @camPos
    @camH ?= @camPos.y
    @camH += (@camPos.y - @camH) * (1 - Math.exp(-dt * 4))
    @camera.position.set @camPos.x, @camH + 2.6, @camPos.z
    @at zc + 9 * UNITS, race.x * HALF * 0.95, @look
    @look.y += 1.05
    if race.shake > 0
      j = race.shake * 0.5
      @camera.position.x += (Math.random() - 0.5) * j
      @camera.position.y += (Math.random() - 0.5) * j
    @camera.lookAt @look
    fov = 60 + (race.speed / C.TOP) * 9 + (if race.boosting then 7 else 0)
    if Math.abs(fov - @fov) > 0.05
      @fov += (fov - @fov) * k
      @camera.fov = @fov
      @camera.updateProjectionMatrix()
    return

D.World = World
D.PAINTS = PAINTS
