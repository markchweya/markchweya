# Chweya Drift — 3D world.
# three.js renders real and CC0 models along a road mesh generated from the
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

# Real cars. Each has a full model (player and the closest rivals) and a light
# model for distant rivals; `paint` matches the body material that gets recoloured.
CARS = [
  {id: 'ferrari', name: 'Ferrari 458 Italia', file: 'real/ferrari.glb', near: 'real/ferrari_near.glb', lod: 'real/ferrari_lod.glb', paint: /^Body_Color$/, len: 4.53}
  {id: 'bmw_m4', name: 'BMW M4 CSL', file: 'real/bmw_m4.glb', lod: 'real/bmw_m4_lod.glb', paint: /Paint/, len: 4.8, yaw: Math.PI}
  {id: 'bmw_m8', name: 'BMW M8 Competition', file: 'real/bmw_m8.glb', lod: 'real/bmw_m8_lod.glb', paint: /CarPaint/, len: 4.87, yaw: Math.PI}
  {id: 'merc_e', name: 'Mercedes-Benz E-Class', file: 'real/merc_e.glb', lod: 'real/merc_e_lod.glb', paint: /^mat_body$/, len: 4.87}
  {id: 'merc_190', name: 'Mercedes-Benz 190E Evo', file: 'real/merc_190.glb', lod: 'real/merc_190_lod.glb', paint: /Car_body_color/, len: 4.43, yaw: Math.PI}
]
CARS_BY_KEY = {}
RIVAL_CARS = ['bmw_m4', 'merc_e', 'bmw_m8', 'merc_190', 'ferrari']

MODELS =
  covered: asset 'real/covered_car/covered_car_1k.gltf'
  lamp: asset 'real/street_lamp/street_lamp.glb'
  cone: asset 'cars/cone.glb'
  barrier: asset 'roads/construction-barrier.glb'
  worklight: asset 'roads/construction-light.glb'
  gantry: asset 'racing/overheadLights.glb'
# CC0 photo facades from ambientCG; tile is the real-world size of one texture repeat in metres.
FACADES =
  Facade006: {tile: 24, glass: true}
  Facade018A: {tile: 24}
  Facade019A: {tile: 26}
  Facade020A: {tile: 26}
  Facade001: {tile: 16, glass: true}
  Facade005: {tile: 14, glass: true}
STREET_FACADES = ['Facade006', 'Facade018A', 'Facade018A', 'Facade019A', 'Facade020A']
# Photoscanned Poly Haven trees baked to cross-billboard impostors (front + side view).
TREE_TYPES =
  island: {h: 9.5}
  island1: {h: 11}
  island3: {h: 8.5}
  hedge: {h: 2.6, file: 'searsia'}
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

# One textured quad per tree for the given view; the two views cross at 90 degrees.
impostorGeometry = (list, view, height, aspect) ->
  n = list.length
  pos = new Float32Array(n * 12)
  uv = new Float32Array(n * 8)
  col = new Float32Array(n * 12)
  idx = []
  for t, i in list
    hh = height * t.s
    hw = hh * aspect / 2
    a = t.rot + view * Math.PI / 2
    dx = Math.cos(a) * hw
    dz = Math.sin(a) * hw
    y0 = t.y - hh * 0.03
    y1 = y0 + hh
    p = i * 12
    pos.set [t.x - dx, y0, t.z - dz, t.x + dx, y0, t.z + dz, t.x + dx, y1, t.z + dz, t.x - dx, y1, t.z - dz], p
    uv.set [0, 0, 1, 0, 1, 1, 0, 1], i * 8
    col.set [t.shade, t.shade, t.shade, t.shade, t.shade, t.shade, t.shade, t.shade, t.shade, t.shade, t.shade, t.shade], p
    v = i * 4
    idx.push v, v + 1, v + 2, v, v + 2, v + 3
  geo = new THREE.BufferGeometry()
  geo.setAttribute 'position', new THREE.BufferAttribute(pos, 3)
  geo.setAttribute 'uv', new THREE.BufferAttribute(uv, 2)
  geo.setAttribute 'color', new THREE.BufferAttribute(col, 3)
  geo.setIndex idx
  geo.computeVertexNormals()
  geo

# Registered inside a function: CoffeeScript has no shadowing, so a top-level
# loop variable would be shared with every method that uses the same name.
CARS.forEach (car) ->
  MODELS[car.id] = asset car.file
  MODELS[car.id + 'Lod'] = asset car.lod
  MODELS[car.id + 'Near'] = asset car.near if car.near
  CARS_BY_KEY[key] = car for key in [car.id, car.id + 'Lod', car.id + 'Near']
  return
nearKey = (id) -> if CARS_BY_KEY[id].near then id + 'Near' else id
# Two moods: a clear sunset, and a rainy night in the style of night street racers.
WEATHER =
  golden: {name: 'Golden hour', sky: 'kloppenheim_06_puresky', exposure: 0.82, sun: 2.3, sunColor: 0xffd9b0, hemi: 0.3, fog: [90, 470], wet: false, glow: [2.2, 0.8], peaks: 1}
  rain: {name: 'Rainy night', sky: 'kloppenheim_07_puresky', exposure: 0.72, sun: 0.12, sunColor: 0x9fb4d6, hemi: 0.2, fog: [30, 300], wet: true, glow: [5, 1], peaks: 0.22}

chevronTexture = (flip) -> canvasTex 256, 192, (g, w, h) ->
  g.fillStyle = '#111'
  g.fillRect 0, 0, w, h
  g.fillStyle = '#f5c000'
  g.fillRect 10, 10, w - 20, h - 20
  g.fillStyle = '#111'
  g.save()
  if flip
    g.translate w, 0
    g.scale -1, 1
  for x in [52, 122]
    g.beginPath()
    g.moveTo x, 34
    g.lineTo x + 44, h / 2
    g.lineTo x, h - 34
    g.lineTo x + 26, h - 34
    g.lineTo x + 70, h / 2
    g.lineTo x + 26, 34
    g.closePath()
    g.fill()
  g.restore()

trapTexture = -> canvasTex 512, 128, (g, w, h) ->
  g.fillStyle = '#10161d'
  g.fillRect 0, 0, w, h
  g.fillStyle = '#e6007e'
  g.fillRect 0, h - 10, w, 10
  g.fillStyle = '#ffffff'
  g.textAlign = 'center'
  g.textBaseline = 'middle'
  g.font = "900 64px Impact, 'Arial Black', sans-serif"
  g.fillText 'SPEED TRAP', w / 2, h / 2 - 4

# Elongated soft glow laid flat on the road: fakes light reflecting off wet asphalt.
streakTexture = -> canvasTex 64, 256, (g, w, h) ->
  img = g.createImageData w, h
  for y in [0...h]
    for x in [0...w]
      dx = (x + 0.5 - w / 2) / (w / 2)
      dy = (y + 0.5 - h / 2) / (h / 2)
      a = Math.pow Math.max(0, 1 - (dx * dx + dy * dy)), 1.6
      o = (y * w + x) * 4
      img.data[o] = img.data[o + 1] = img.data[o + 2] = 255
      img.data[o + 3] = Math.round a * 255
  g.putImageData img, 0, 0

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
  lamp: ['y', 5.4]
  barrier: ['z', 2.8]
  worklight: ['y', 2.2]
  gantry: ['x', 15]
  billboard: ['x', 10]
# Roadside ads for the technologies the rivals are named after.
ADS = [
  {kicker: 'ADOBE', title: 'FLASH PLAYER', line: 'Required to view this content', a: '#7a0d12', b: '#e53935'}
  {kicker: 'BEST VIEWED IN', title: 'INTERNET EXPLORER 6', line: 'at 800 \u00d7 600 resolution', a: '#0b2a63', b: '#1e88e5'}
  {kicker: 'IS YOUR BUSINESS', title: 'Y2K READY?', line: 'Certified compliant \u00b7 1999', a: '#0f3d1f', b: '#43a047'}
  {kicker: 'POWERED BY', title: 'JAVA APPLETS', line: 'Loading\u2026 please wait', a: '#5a2a00', b: '#fb8c00'}
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
  canvasTex 1024, 410, (g, w, h) ->
    grad = g.createLinearGradient 0, 0, w, h
    grad.addColorStop 0, ad.a
    grad.addColorStop 1, ad.b
    g.fillStyle = grad
    g.fillRect 0, 0, w, h
    g.fillStyle = 'rgba(255,255,255,0.08)'
    g.beginPath()
    g.arc w * 0.86, h * 0.2, h * 0.75, 0, Math.PI * 2
    g.fill()
    g.fillStyle = 'rgba(255,255,255,0.85)'
    g.font = "600 34px 'Segoe UI', Arial, sans-serif"
    g.fillText ad.kicker, 60, 100
    g.fillStyle = '#ffffff'
    g.font = "900 96px Impact, 'Arial Black', sans-serif"
    g.fillText ad.title, 56, 210, w - 110
    g.fillStyle = 'rgba(255,255,255,0.9)'
    g.font = "400 38px 'Segoe UI', Arial, sans-serif"
    g.fillText ad.line, 60, 290, w - 120
    g.fillStyle = 'rgba(0,0,0,0.25)'
    g.fillRect 0, h - 48, w, 48
    g.fillStyle = 'rgba(255,255,255,0.7)'
    g.font = "600 24px 'Segoe UI', Arial, sans-serif"
    g.fillText 'THE GRAVEYARD SPRINT  \u00b7  OFFICIAL SPONSOR', 60, h - 16

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
    @weatherId = 'golden'
    @skies = {}
    @envs = {}
    @heading = 0
    @mirrorOn = true
    @carId = 'ferrari'
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
    @treeTex = {}
    for id, spec of TREE_TYPES
      file = spec.file or id
      @treeTex[id] = (texLoader.load("assets/tex/trees/#{file}_#{v}.png", ((t) -> t.encoding = THREE.sRGBEncoding)) for v in ['a', 'b'])
    @facadeTex = {}
    for id, spec of FACADES
      dir = "assets/tex/facades/#{id}"
      @facadeTex[id] =
        map: @texture texLoader, "#{dir}_Color.jpg", true
        normalMap: @texture texLoader, "#{dir}_NormalGL.jpg", false
        roughnessMap: @texture texLoader, "#{dir}_Roughness.jpg", false
        metalnessMap: if spec.glass then @texture(texLoader, "#{dir}_Metalness.jpg", false) else null
    sky = WEATHER[@weatherId].sky
    new THREE.RGBELoader(manager).setDataType(THREE.FloatType).load "assets/tex/#{sky}_2k.hdr", (t) => @skies[sky] = t
    return

  texture: (loader, url, color) ->
    t = loader.load url
    t.wrapS = t.wrapT = THREE.RepeatWrapping
    t.encoding = THREE.sRGBEncoding if color
    t.anisotropy = Math.min 8, @renderer.capabilities.getMaxAnisotropy()
    t

  prep: (key, scene) ->
    spec = CARS_BY_KEY[key]
    isCar = spec? or key is 'covered'
    paint = null
    if spec
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
      o.castShadow = not spec
      o.receiveShadow = not spec
      o.material = paint if paint and spec.paint.test(o.material.name)
      return
    box = new THREE.Box3().setFromObject scene
    size = box.getSize new THREE.Vector3()
    center = box.getCenter new THREE.Vector3()
    # Soft contact shadow under every real car (ferrari_ao.png is a generic blurred footprint).
    if spec and not /Lod$/.test(key)
      ao = new THREE.Mesh new THREE.PlaneGeometry(size.x * 1.2, size.z * 1.15), new THREE.MeshBasicMaterial
        map: @aoTex
        blending: THREE.MultiplyBlending
        toneMapped: false
        transparent: true
        depthWrite: false
      ao.rotation.x = -Math.PI / 2
      ao.position.set center.x, box.min.y + 0.02, center.z
      ao.renderOrder = 2
      scene.add ao
    s = if spec then spec.len / Math.max(size.z, size.x)
    else if isCar then 4.6 / Math.max(size.z, size.x)
    else if SIZE[key] then SIZE[key][1] / size[SIZE[key][0]]
    else 1
    holder = new THREE.Group()
    scene.position.set -center.x, -box.min.y, -center.z
    holder.add scene
    holder.scale.setScalar s
    holder.rotation.y = spec.yaw or 0 if spec
    wrap = new THREE.Group()
    wrap.add holder
    wrap.userData.size = size.clone().multiplyScalar s
    wrap.userData.tip = new THREE.Vector3 0, size.y * s * 0.86, 0 if key is 'lamp'
    wrap

  setup: ->
    @scene.fog = new THREE.Fog 0x000000, 90, 470
    @hemi = new THREE.HemisphereLight 0xfff0de, 0x3d3529, 0.3
    @scene.add @hemi
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
    @mat.trees = {}
    for id of TREE_TYPES
      @mat.trees[id] = for t in @treeTex[id]
        t.anisotropy = 4
        m = new THREE.MeshBasicMaterial map: t, alphaTest: 0.45, side: THREE.DoubleSide, vertexColors: true, alphaToCoverage: true
        m.userData.depth = new THREE.MeshDepthMaterial depthPacking: THREE.RGBADepthPacking, map: t, alphaTest: 0.45
        m
    @ads = for ad in ADS
      t = adTexture ad
      t.anisotropy = 8
      new THREE.MeshStandardMaterial map: t, emissive: 0xffffff, emissiveMap: t, emissiveIntensity: 0.35, roughness: 0.45
    @mat.steel = new THREE.MeshStandardMaterial color: 0x80868c, metalness: 0.75, roughness: 0.38
    @mat.frame = new THREE.MeshStandardMaterial color: 0x1d2126, metalness: 0.4, roughness: 0.6
    @geo =
      post: new THREE.CylinderGeometry 0.16, 0.2, 6.4, 12
      panel: new THREE.BoxGeometry 9, 3.6, 0.28
      lamp: new THREE.BoxGeometry 0.5, 0.12, 0.7
      chevronPost: new THREE.CylinderGeometry 0.05, 0.05, 1.5, 8
      chevron: new THREE.PlaneGeometry 1.1, 0.82
      trapPost: new THREE.CylinderGeometry 0.2, 0.24, 7, 12
      trapBeam: new THREE.BoxGeometry 15.4, 0.5, 0.5
      trapSign: new THREE.PlaneGeometry 4.2, 1.05
      trapCam: new THREE.BoxGeometry 0.5, 0.35, 0.7
      streak: new THREE.PlaneGeometry 1.6, 10
      tailStreak: new THREE.PlaneGeometry 1.3, 3
    @mat.rail = new THREE.MeshStandardMaterial color: 0xb9bfc5, metalness: 0.85, roughness: 0.32, side: THREE.DoubleSide
    @mat.chevrons = [new THREE.MeshStandardMaterial(map: chevronTexture(false), roughness: 0.5, side: THREE.DoubleSide), new THREE.MeshStandardMaterial(map: chevronTexture(true), roughness: 0.5, side: THREE.DoubleSide)]
    @mat.trap = new THREE.MeshStandardMaterial map: trapTexture(), emissive: 0xffffff, emissiveMap: trapTexture(), emissiveIntensity: 0.4, side: THREE.DoubleSide
    streak = streakTexture()
    @mat.lampStreak = new THREE.MeshBasicMaterial map: streak, color: 0xffb46b, transparent: true, opacity: 0.55, blending: THREE.AdditiveBlending, depthWrite: false
    @mat.tailStreak = new THREE.MeshBasicMaterial map: streak, color: 0xff2a1f, transparent: true, opacity: 0.32, blending: THREE.AdditiveBlending, depthWrite: false
    @mirrorCam = new THREE.PerspectiveCamera 46, 3.6, 0.5, 700
    @buildMountains()
    @buildRain()
    @applyWeather()
    return

  # ---------- weather ----------
  setWeather: (id, done) ->
    return unless WEATHER[id]
    @weatherId = id
    sky = WEATHER[id].sky
    if not @ready or @skies[sky]
      @applyWeather() if @ready
      done?()
      return
    new THREE.RGBELoader().setDataType(THREE.FloatType).load "assets/tex/#{sky}_2k.hdr", (t) =>
      @skies[sky] = t
      @applyWeather()
      done?()
    return

  applyWeather: ->
    w = WEATHER[@weatherId]
    hdr = @skies[w.sky]
    return unless hdr
    unless @envs[w.sky]
      hdr.mapping = THREE.EquirectangularReflectionMapping
      pmrem = new THREE.PMREMGenerator @renderer
      @envs[w.sky] = {env: pmrem.fromEquirectangular(hdr).texture, info: analyseSky(hdr)}
      pmrem.dispose()
    e = @envs[w.sky]
    @scene.background = hdr
    @scene.environment = e.env
    @sunDir = e.info.sun
    @scene.fog.color.copy e.info.horizon
    @scene.fog.near = w.fog[0]
    @scene.fog.far = w.fog[1]
    @renderer.toneMappingExposure = w.exposure
    @sun.intensity = w.sun
    @sun.color.setHex w.sunColor
    @sun.castShadow = not w.wet
    @hemi.intensity = w.hemi
    @mat.road.roughness = if w.wet then 0.22 else 1
    @mat.road.envMapIntensity = if w.wet then 1.7 else 1
    @mat.road.color.setScalar(if w.wet then 0.62 else 1)
    @mat.walk.roughness = if w.wet then 0.45 else 1
    @mat.walk.color.setScalar(if w.wet then 0.7 else 1)
    @rain.visible = w.wet
    @mountains.material.color.setScalar w.peaks
    @refreshWeatherFx()
    return

  refreshWeatherFx: ->
    w = WEATHER[@weatherId]
    for g in (@lampGlows or [])
      g.scale.set w.glow[0], w.glow[0], 1
      g.material.opacity = w.glow[1]
    fx.visible = w.wet for fx in (@wetFx or [])
    return

  buildRain: ->
    n = 1500
    @drops = for i in [0...n]
      {x: (Math.random() - 0.5) * 50, y: Math.random() * 24, z: -45 + Math.random() * 60}
    geo = new THREE.BufferGeometry()
    geo.setAttribute 'position', new THREE.BufferAttribute(new Float32Array(n * 6), 3)
    @rain = new THREE.LineSegments geo, new THREE.LineBasicMaterial(color: 0xaab9cc, transparent: true, opacity: 0.35)
    @rain.frustumCulled = false
    @rain.visible = false
    @scene.add @rain
    return

  updateRain: (dt, speedMs) ->
    return unless @rain.visible
    pos = @rain.geometry.attributes.position.array
    slant = Math.min 2.5, speedMs * 0.03
    for d, i in @drops
      d.y -= 19 * dt
      d.z += speedMs * dt
      d.y += 24 if d.y < 0
      d.z -= 60 if d.z > 15
      o = i * 6
      pos[o] = d.x
      pos[o + 1] = d.y
      pos[o + 2] = d.z
      pos[o + 3] = d.x
      pos[o + 4] = d.y - 0.85
      pos[o + 5] = d.z + slant * 0.4
    @rain.geometry.attributes.position.needsUpdate = true
    @rain.position.copy @camera.position
    @rain.position.y -= 6
    @rain.rotation.y = -@heading
    return

  # A ring of snow-capped mountains that always sits on the horizon.
  buildMountains: ->
    n = 240
    radius = 1250
    r = rng 4242
    ph = (r() * Math.PI * 2 for i in [0...6])
    pos = []
    col = []
    idx = []
    base = new THREE.Color 0x56677e
    high = new THREE.Color 0x8796aa
    snow = new THREE.Color 0xe9eef3
    for i in [0..n]
      a = i / n * Math.PI * 2
      ridge = 0.5 + 0.5 * Math.sin(a * 3 + ph[0])
      peaks = Math.abs(Math.sin(a * 7 + ph[1])) * 0.6 + Math.abs(Math.sin(a * 17 + ph[2])) * 0.3 + Math.abs(Math.sin(a * 41 + ph[3])) * 0.1
      h = 60 + 300 * ridge * peaks + 40 * Math.sin(a * 5 + ph[4])
      x = Math.cos(a) * radius
      z = Math.sin(a) * radius
      pos.push x, -60, z, x, h, z
      top = high.clone()
      top.lerp snow, Math.min(1, Math.max(0, (h - 210) / 80))
      col.push base.r, base.g, base.b, top.r, top.g, top.b
      if i < n
        k = i * 2
        idx.push k, k + 1, k + 2, k + 1, k + 3, k + 2
    geo = new THREE.BufferGeometry()
    geo.setAttribute 'position', new THREE.Float32BufferAttribute(pos, 3)
    geo.setAttribute 'color', new THREE.Float32BufferAttribute(col, 3)
    geo.setIndex idx
    @mountains = new THREE.Mesh geo, new THREE.MeshBasicMaterial(vertexColors: true, fog: false, side: THREE.DoubleSide, depthWrite: false)
    @mountains.renderOrder = -1
    @mountains.frustumCulled = false
    @scene.add @mountains
    return

  # Live rear-view mirror: a second camera rendered into the mirror frame's rectangle.
  renderMirror: ->
    el = document.getElementById 'mirror'
    return unless @mirrorOn and el and @player and el.closest('.hud.on')
    rect = el.getBoundingClientRect()
    return if rect.width < 20
    p = @player.position
    fx = Math.sin @heading
    fz = -Math.cos @heading
    cam = @mirrorCam
    cam.position.set p.x + fx * 0.2, p.y + 1.85, p.z + fz * 0.2
    cam.lookAt p.x - fx * 40, p.y + 1.3, p.z - fz * 40
    cam.aspect = rect.width / rect.height
    cam.updateProjectionMatrix()
    r = @renderer
    W = r.domElement.clientWidth
    H = r.domElement.clientHeight
    x = rect.left
    y = H - rect.bottom
    r.shadowMap.autoUpdate = false
    r.setScissorTest true
    r.setScissor x, y, rect.width, rect.height
    r.setViewport x, y, rect.width, rect.height
    r.render @scene, cam
    r.setScissorTest false
    r.setViewport 0, 0, W, H
    r.shadowMap.autoUpdate = true
    return

  resize: ->
    w = window.innerWidth
    h = window.innerHeight
    @renderer.setSize w, h, false
    @camera.aspect = w / h
    @camera.updateProjectionMatrix()
    return

  # Drops render resolution, then shadows, when the frame rate stays under 40 FPS.
  adapt: (dt) ->
    @frameAvg = (@frameAvg ? dt) * 0.95 + dt * 0.05
    @adaptTimer = (@adaptTimer or 0) + dt
    return if @adaptTimer < 4 or @quality is 0
    @adaptTimer = 0
    return unless @frameAvg > 1 / 40
    @quality = (@quality ? 2) - 1
    if @quality is 1
      @renderer.setPixelRatio 1
      @mirrorOn = false
      @resize()
    else
      @renderer.shadowMap.enabled = false
      @scene.traverse (o) ->
        o.material.needsUpdate = true if o.material?.isMaterial
        return
    return

  setPaint: (id) ->
    @paintId = id
    @spawnPlayer() if @root
    return

  setCar: (id) ->
    @carId = id if CARS_BY_KEY[id]
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
    @lampGlows = []
    @wetFx = []
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
    @placeChevrons track
    @placeTraps race
    for s in [-1, 1]
      @ribbon s * 10.15, s * 10.15, 0.42, 0.82, @mat.rail, 1, 1, (k) -> zoneOf(k) isnt 'city'
    @refreshWeatherFx()
    @spawnPlayer()
    return

  placeScenery: (track) ->
    trees = {}
    pos = new THREE.Vector3()
    for seg in track.segments
      z = seg.p1.world.z
      for sp in seg.sprites
        lat = sp.offset * HALF
        side = if lat < 0 then -1 else 1
        switch sp.kind
          when 'lamp'
            obj = @put 'lamp', z, lat, ((h) -> -h)
            if obj
              obj.position.y += 0.16
              light = @glow 0xffc27a, 2.2, 0.8
              light.position.copy @models.lamp.userData.tip
              obj.add light
              @lampGlows.push light
              streak = new THREE.Mesh @geo.streak, @mat.lampStreak
              streak.rotation.x = -Math.PI / 2
              streak.position.set side * -2.6, -0.14, 0
              obj.add streak
              @wetFx.push streak
          when 'start', 'finish'
            @put 'gantry', z, 0, ((h) -> -h), @root
          when 'board'
            board = @billboard sp.variant
            h = @at z, lat, board.position
            board.rotation.y = -h + side * 0.35
            @chunk(z).add board
          when 'tree', 'hedge'
            type = if sp.kind is 'hedge' then 'hedge' else sp.variant
            @at z, lat, pos
            d = Math.abs lat
            pos.y += if d <= WALK then 0.16 else 0.12 - Math.min(1, (d - WALK) / (GRASS - WALK)) * 1.72
            c = Math.max 0, Math.floor(z / C.SEG / CHUNK)
            ((trees[c] ?= {})[type] ?= []).push
              x: pos.x
              y: pos.y
              z: pos.z
              s: sp.scale or 1
              rot: Math.random() * Math.PI
              shade: 0.8 + Math.random() * 0.22
    for c, groups of trees
      for type, list of groups
        for view in [0, 1]
          tex = @treeTex[type][view]
          geo = impostorGeometry list, view, TREE_TYPES[type].h, tex.image.width / tex.image.height
          @disposables.push geo
          mat = @mat.trees[type][view]
          mesh = new THREE.Mesh geo, mat
          mesh.castShadow = true
          mesh.customDepthMaterial = mat.userData.depth
          @chunk(c * CHUNK * C.SEG).add mesh
    return

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
          park = zoneOf(i) isnt 'city'
          if park and row is 0
            z += toUnits 25
            continue
          pool = if row is 0 then STREET_FACADES else TOWER_FACADES
          f = pool[Math.floor(r() * pool.length)]
          width = if row is 0 then 14 + r() * 16 else 22 + r() * 14
          depth = if row is 0 then 14 + r() * 8 else 20 + r() * 12
          height = if row is 0 then 12 + Math.floor(r() * 9) * 3.3 else 55 + r() * 90
          setback = if row is 0 then WALK + 1.5 + depth / 2 + r() * 2 else WALK + (if park then 95 else 42) + depth / 2 + r() * 40
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

  # Two steel posts and a lit panel with the ad printed across the whole face.
  billboard: (variant) ->
    g = new THREE.Group()
    for x in [-2.8, 2.8]
      post = new THREE.Mesh @geo.post, @mat.steel
      post.position.set x, 3.2, 0
      post.castShadow = true
      g.add post
    ad = @ads[variant % @ads.length]
    panel = new THREE.Mesh @geo.panel, [@mat.frame, @mat.frame, @mat.frame, @mat.frame, ad, @mat.frame]
    panel.position.y = 7.6
    panel.castShadow = true
    g.add panel
    for x in [-3, 0, 3]
      lamp = new THREE.Mesh @geo.lamp, @mat.frame
      lamp.position.set x, 9.5, 0.45
      g.add lamp
    g

  vehicle: (key, opts = {}) ->
    src = @models[key]
    obj = src.clone()
    size = src.userData.size
    mats = []
    obj.traverse (o) ->
      return unless o.isMesh
      if opts.paint and o.material.userData.paint
        o.material = o.material.clone()
        o.material.color.set(opts.paint).convertSRGBToLinear()
      if opts.fade
        o.material = o.material.clone()
        o.material.transparent = true
        o.castShadow = false
        mats.push o.material
      return
    tails = []
    for side in [-1, 1] when not opts.dark
      t = @glow 0xff2a1f, 0.7, 0.9
      t.position.set side * size.x * 0.32, size.y * 0.5, size.z / 2 + 0.05
      obj.add t
      tails.push t
    obj.userData.tails = tails
    if tails.length and @wetFx
      tail = new THREE.Mesh @geo.tailStreak, @mat.tailStreak
      tail.rotation.x = -Math.PI / 2
      tail.position.set 0, 0.03, size.z / 2 + 1.3
      tail.visible = WEATHER[@weatherId].wet
      obj.add tail
      @wetFx.push tail
    obj.userData.mats = mats
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

  # Yellow chevron boards on the outside of every sharp bend.
  placeChevrons: (track) ->
    pos = new THREE.Vector3()
    for seg in track.segments when Math.abs(seg.curve) >= 3 and seg.index % 18 is 0 and seg.index > C.START_SEG + 30
      side = if seg.curve > 0 then -1 else 1
      z = seg.p1.world.z
      h = @at z, side * 7.1, pos
      g = new THREE.Group()
      g.position.copy pos
      g.position.y += 0.16
      g.rotation.y = -h
      post = new THREE.Mesh @geo.chevronPost, @mat.steel
      post.position.y = 0.75
      board = new THREE.Mesh @geo.chevron, @mat.chevrons[if seg.curve > 0 then 0 else 1]
      board.position.y = 1.35
      board.position.z = 0.06
      g.add post, board
      @chunk(z).add g
    return

  placeTraps: (race) ->
    for trap in race.traps
      g = new THREE.Group()
      h = @at trap.z, 0, g.position
      g.rotation.y = -h
      for x in [-7.5, 7.5]
        post = new THREE.Mesh @geo.trapPost, @mat.steel
        post.position.set x, 3.5, 0
        post.castShadow = true
        g.add post
      beam = new THREE.Mesh @geo.trapBeam, @mat.frame
      beam.position.y = 6.6
      sign = new THREE.Mesh @geo.trapSign, @mat.trap
      sign.position.set 0, 5.7, 0.3
      g.add beam, sign
      for x in [-3.6, 0, 3.6]
        cam = new THREE.Mesh @geo.trapCam, @mat.frame
        cam.position.set x, 6.15, 0.35
        g.add cam
        flash = @glow 0xff3048, 0.9, 0.9
        flash.position.set x, 6.15, 0.75
        g.add flash
      @root.add g
    return

  placeRivals: (race) ->
    @rivals = for rv in race.rivals
      paint = RIVAL_PAINTS[rv.index % RIVAL_PAINTS.length]
      holder = new THREE.Group()
      car = RIVAL_CARS[rv.index % RIVAL_CARS.length]
      near = @vehicle nearKey(car), paint: paint
      far = @vehicle car + 'Lod', paint: paint
      label = new THREE.Sprite new THREE.SpriteMaterial(map: labelTexture(rv.name), transparent: true, depthWrite: false)
      label.scale.set 3.6, 0.9, 1
      label.position.y = 2.5
      holder.add near, far, label
      holder.userData = {near: near, far: far, label: label, mats: near.userData.mats.concat(far.userData.mats), faded: false}
      @root.add holder
      holder
    return

  spawnPlayer: ->
    @player?.parent?.remove @player
    paint = _.findWhere(PAINTS, id: @paintId) or PAINTS[0]
    @player = @vehicle @carId, paint: paint.hex
    size = @models[@carId].userData.size
    @wheels = []
    @player.traverse (o) => @wheels.push o if /^(wheel_(fl|fr|rl|rr)|Wheel(FL|FR|RL|RR))$/.test(o.name)
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
    @heading = h
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

    # Full-detail models for the two closest rivals, light ones for the rest.
    gaps = ((rv.z - pz) / UNITS for rv in race.rivals)
    closest = (i for g, i in gaps when g > -5 and g < 25).sort((a, b) -> Math.abs(gaps[a]) - Math.abs(gaps[b]))[0...2]
    for rv, i in race.rivals
      obj = @rivals[i]
      u = obj.userData
      gap = gaps[i]
      obj.visible = gap > -5 and gap < 260
      continue unless obj.visible
      u.label.visible = gap > 14
      u.near.visible = i in closest
      u.far.visible = not u.near.visible
      obj.rotation.y = -@at(rv.z + C.CAR_LEN / 2, rv.x * HALF, obj.position)

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
    @mountains.position.set @camera.position.x, @camera.position.y - 28, @camera.position.z
    @updateRain dt, race.speed / UNITS
    @renderer.render @scene, @camera
    @renderMirror()
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
D.CARS = CARS.map (car) -> {id: car.id, name: car.name}
