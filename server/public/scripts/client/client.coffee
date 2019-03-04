###
# Copyright (C) 2012 jareiko / http://www.jareiko.net/
###

define [
  'THREE'
  'underscore'
  'client/audio'
  'client/car'
  'cs!client/misc'
  'cs!client/scenery'
  'cs!client/terrain'
  'game/track'
  'cs!game/synchro'
  'util/pubsub'
  'cs!util/quiver'
  'util/util',
  'THREE-scene-loader'
], (
  THREE
  _
  clientAudio
  clientCar
  clientMisc
  clientScenery
  clientTerrain
  gameTrack
  synchro
  pubsub
  quiver
  util
  THREESceneLoader
) ->
  Vec2 = THREE.Vector2
  Vec3 = THREE.Vector3
  Vec4 = THREE.Vector4
  PULLTOWARD = util.PULLTOWARD
  MAP_RANGE = util.MAP_RANGE
  KEYCODE = util.KEYCODE
  deadZone = util.deadZone

  tmpVec3a = new Vec3

  class RenderCheckpointsEditor
    constructor: (scene, root) ->
      meshes = []

      do reset = ->
        for mesh in meshes
          scene.remove mesh
        checkpoints = root.track?.config?.course.checkpoints.models
        return unless checkpoints
        meshes = for cp in checkpoints
          mesh = clientMisc.checkpointMesh()
          Vec3::set.apply mesh.position, cp.pos
          scene.add mesh
          mesh

      root.on 'change:track.config.course.checkpoints.', reset
      root.on 'add:track.config.course.checkpoints.', reset
      root.on 'remove:track.config.course.checkpoints.', reset
      root.on 'reset:track.config.course.checkpoints.', reset

      @destroy = ->
        for mesh in meshes
          scene.remove mesh

    update: (camera, delta) ->

  class RenderCheckpointsDrive
    constructor: (scene, @root) ->
      @ang = 0
      @mesh = clientMisc.checkpointMesh()
      @initPos = @mesh.position.clone()
      @current = 0
      scene.add @mesh

    destroy: ->
      @mesh.parent.remove @mesh

    update: (camera, delta) ->
      targetCp = @root.track.config.course.checkpoints.at @current
      return unless targetCp?
      @mesh.rotation.z += delta * 3
      meshPos = @mesh.position
      pull = delta * 2
      pull = 1 if @current is 0
      meshPos.x = PULLTOWARD meshPos.x, targetCp.pos[0] + @initPos.x, pull
      meshPos.y = PULLTOWARD meshPos.y, targetCp.pos[1] + @initPos.y, pull
      meshPos.z = PULLTOWARD meshPos.z, targetCp.pos[2] + @initPos.z, pull

    highlightCheckpoint: (i) ->
      @current = i

  class RenderDials
    constructor: (scene, @vehic) ->
      geom = new THREE.Geometry()
      geom.vertices.push new Vec3(1, 0, 0)
      geom.vertices.push new Vec3(-0.1, 0.02, 0)
      geom.vertices.push new Vec3(-0.1, -0.02, 0)
      geom.faces.push new THREE.Face3(0, 1, 2)
      # geom.computeCentroids()
      mat = new THREE.MeshBasicMaterial
        color: 0x206020
        blending: THREE.AdditiveBlending
        transparent: 1
        depthTest: false
      @revMeter = new THREE.Mesh geom, mat
      @revMeter.position.x = -1.3
      @revMeter.position.y = -0.2
      @revMeter.scale.multiplyScalar 0.4
      scene.add @revMeter
      @speedMeter = new THREE.Mesh geom, mat
      @speedMeter.position.x = -1.3
      @speedMeter.position.y = -0.7
      @speedMeter.scale.multiplyScalar 0.4
      scene.add @speedMeter

      @$digital = $(".speedo")

    destroy: ->
      @revMeter.parent.remove @revMeter
      @speedMeter.parent.remove @speedMeter

    update: (camera, delta) ->
      vehic = @vehic
      convertKMH = 3.6
      @revMeter.rotation.z = -2.5 - 4.5 *
          ((vehic.engineAngVelSmoothed - vehic.engineIdle) /
              (vehic.engineRedline - vehic.engineIdle))
      speed = Math.abs(vehic.differentialAngVel) * vehic.avgDriveWheelRadius * convertKMH
      @speedMeter.rotation.z = -2.5 - 4.5 * speed * 0.004
      # Use actual speed for the digital indicator.
      speed = vehic.body.getLinearVel().length() * convertKMH
      @$digital.text speed.toFixed(0) + " km/h"
      return

    highlightCheckpoint: (i) ->
      @current = i
      return

  class RenderCheckpointArrows
    constructor: (@scene, @progress) ->
      mat = new THREE.MeshBasicMaterial
        color: 0x206020
        blending: THREE.AdditiveBlending
        transparent: 1
        depthTest: false
      mat2 = new THREE.MeshBasicMaterial
        color: 0x051005
        blending: THREE.AdditiveBlending
        transparent: 1
        depthTest: false
      # TODO: Use an ArrayGeometry.
      geom = new THREE.Geometry()
      geom.vertices.push new Vec3(0, 0, 0.6)
      geom.vertices.push new Vec3(0.1, 0, 0.3)
      geom.vertices.push new Vec3(-0.1, 0, 0.3)
      geom.vertices.push new Vec3(0.1, 0, -0.2)
      geom.vertices.push new Vec3(-0.1, 0, -0.2)
      geom.faces.push new THREE.Face3(0, 2, 1)
      geom.faces.push new THREE.Face3(1, 2, 3)
      geom.faces.push new THREE.Face3(2, 4, 3)
      @meshArrow = new THREE.Mesh(geom, mat)
      @meshArrow.position.set(0, 1, -2)
      @meshArrow2 = new THREE.Mesh(geom, mat2)
      @meshArrow2.position.set(0, 0, 0.8)
      scene.add @meshArrow
      @meshArrow.add @meshArrow2

    destroy: ->
      @meshArrow.parent.remove @meshArrow

    update: (camera, delta) ->
      nextCp = @progress.nextCheckpoint 0
      nextCp2 = @progress.nextCheckpoint 1
      carPos = @progress.vehicle.body.pos
      camMatrixEl = camera.matrixWorld.elements
      @meshArrow.visible = nextCp?
      if nextCp
        cpVec = new Vec2(nextCp.pos[0] - carPos.x,
                         nextCp.pos[1] - carPos.y)
        cpVecCamSpace = new Vec2(
            cpVec.x * camMatrixEl[1] + cpVec.y * camMatrixEl[9],
            cpVec.x * camMatrixEl[0] + cpVec.y * camMatrixEl[8])
        @meshArrow.rotation.y = Math.atan2(cpVecCamSpace.y, cpVecCamSpace.x)
      @meshArrow2.visible = nextCp2?
      if nextCp2
        cpVec = new Vec2(nextCp2.pos[0] - carPos.x,
                         nextCp2.pos[1] - carPos.y)
        cpVecCamSpace = new Vec2(
            cpVec.x * camMatrixEl[1] + cpVec.y * camMatrixEl[9],
            cpVec.x * camMatrixEl[0] + cpVec.y * camMatrixEl[8])
        @meshArrow2.rotation.y = Math.atan2(cpVecCamSpace.y, cpVecCamSpace.x) - @meshArrow.rotation.y

  class CamControl
    constructor: (@camera, @car) ->
      # Note that CamControl controls the camera it's given at construction,
      # not the one passed into update().
      @mode = 0

      pullTransformedQuat = (quat, quatTarget, amount) ->
        quat.x = PULLTOWARD(quat.x, -quatTarget.z, amount)
        quat.y = PULLTOWARD(quat.y,  quatTarget.w, amount)
        quat.z = PULLTOWARD(quat.z,  quatTarget.x, amount)
        quat.w = PULLTOWARD(quat.w, -quatTarget.y, amount)
        quat.normalize()

      translate = (pos, matrix, x, y, z) ->
        el = matrix.elements
        pos.x += el[0] * x + el[4] * y + el[8] * z
        pos.y += el[1] * x + el[5] * y + el[9] * z
        pos.z += el[2] * x + el[6] * y + el[10] * z

      pullCameraQuat = (cam, car, amount) ->
        pullTransformedQuat cam.quaternion, car.root.quaternion, amount
        cam.updateMatrix()

      translateCam = (cam, car, x, y, z) ->
        cam.position.copy car.root.position
        translate cam.position, cam.matrix, x, y, z
        cam.matrix.setPosition cam.position

      chaseCam =
        update: (cam, car, delta) ->
          car.bodyMesh?.visible = yes
          targetPos = car.root.position.clone()
          targetPos.add car.vehic.body.linVel.clone().multiplyScalar .17
          offset = car.config.chaseCamOffset or [ 0, 1.2, -3 ]
          matrix = car.root.matrix

          targetPos.x += matrix.elements[0] * offset[0];
          targetPos.y += matrix.elements[1] * offset[0];
          targetPos.z += matrix.elements[2] * offset[0];

          targetPos.x += matrix.elements[4] * offset[1];
          targetPos.y += matrix.elements[5] * offset[1];
          targetPos.z += matrix.elements[6] * offset[1];

          targetPos.x += matrix.elements[8] * offset[2];
          targetPos.y += matrix.elements[9] * offset[2];
          targetPos.z += matrix.elements[10] * offset[2];

          camDelta = delta * 5
          cam.position.x = PULLTOWARD cam.position.x, targetPos.x, camDelta
          cam.position.y = PULLTOWARD cam.position.y, targetPos.y, camDelta
          cam.position.z = PULLTOWARD cam.position.z, targetPos.z, camDelta

          pullTransformedQuat cam.quaternion, car.root.quaternion, 1
          lookPos = car.root.position.clone()
          translate lookPos, car.root.matrix, 0, 0.7, 0
          cam.lookAt(lookPos)
          return

      insideCam =
        update: (cam, car, delta) ->
          car.bodyMesh?.visible = yes
          pullCameraQuat cam, car, delta * 30
          translateCam cam, car, 0, 0.7, -1
          return

      insideCam2 =
        update: (cam, car, delta) ->
          car.bodyMesh?.visible = no
          pullCameraQuat cam, car, 1
          translateCam cam, car, 0, 0.7, -1
          return

      wheelCam =
        update: (cam, car, delta) ->
          car.bodyMesh?.visible = yes
          pullCameraQuat cam, car, delta * 100
          translateCam cam, car, 1, 0, -0.4
          return

      @modes = [
        chaseCam
        insideCam
        insideCam2
        wheelCam
      ]
      return

    getMode: -> @modes[@mode]

    update: (camera, delta) ->
      if @car.root?
        @getMode().update @camera, @car, delta
      return

    nextMode: ->
      @mode = (@mode + 1) % @modes.length

  class CamTerrainClipping
    constructor: (@camera, @terrain) ->
      return

    update: (camera, delta) ->
      camPos = @camera.position
      contact = @terrain.getContactRayZ camPos.x, camPos.y
      terrainHeight = contact.surfacePos.z
      camPos.z = Math.max camPos.z, terrainHeight + 0.2
      return

  class KeyboardController
    THROTTLE_RESPONSE = 8
    BRAKE_RESPONSE = 5
    HANDBRAKE_RESPONSE = 20
    TURN_RESPONSE = 5

    constructor: (@vehic, @client) ->
      @controls = util.deepClone @vehic.controller.input

    update: (delta) ->
      keyDown = @client.keyDown
      throttle = if keyDown[KEYCODE['UP']] or keyDown[KEYCODE['W']] then 1 else 0
      brake = if keyDown[KEYCODE['DOWN']] or keyDown[KEYCODE['S']] then 1 else 0
      left = if keyDown[KEYCODE['LEFT']] or keyDown[KEYCODE['A']] then 1 else 0
      right = if keyDown[KEYCODE['RIGHT']] or keyDown[KEYCODE['D']] then 1 else 0
      handbrake = if keyDown[KEYCODE['SPACE']] then 1 else 0

      controls = @controls
      controls.throttle = PULLTOWARD(controls.throttle, throttle, THROTTLE_RESPONSE * delta)
      controls.brake = PULLTOWARD(controls.brake, brake, BRAKE_RESPONSE * delta)
      controls.handbrake = PULLTOWARD(controls.handbrake, handbrake, HANDBRAKE_RESPONSE * delta)
      controls.turn = PULLTOWARD(controls.turn, left - right, TURN_RESPONSE * delta)

  class GamepadController
    constructor: (@vehic, @gamepad) ->
      @controls = util.deepClone @vehic.controller.input

    update: (delta) ->
      controls = @controls
      axes = @gamepad.axes
      buttons = @gamepad.buttons
      axes0 = deadZone axes[0], 0.05
      axes3 = deadZone axes[3], 0.05
      controls.throttle = Math.max 0, -axes3, buttons[0] or 0, buttons[5] or 0, buttons[7] or 0
      controls.brake = Math.max 0, axes3, buttons[4] or 0, buttons[6] or 0
      controls.handbrake = buttons[2] or 0
      controls.turn = -axes0 - (buttons[15] or 0) + (buttons[14] or 0)

  class WheelController
    constructor: (@vehic, @gamepad) ->
      @controls = util.deepClone @vehic.controller.input

    update: (delta) ->
      controls = @controls
      axes = @gamepad.axes
      buttons = @gamepad.buttons
      axes0 = deadZone axes[0], 0.01
      axes1 = deadZone axes[1], 0.01
      controls.throttle = Math.max 0, -axes1
      controls.brake = Math.max 0, axes1
      controls.handbrake = Math.max buttons[6] or 0, buttons[7] or 0
      controls.turn = -axes0

  getGamepads = ->
    nav = navigator
    nav.getGamepads?() or nav.gamepads or
    nav.mozGetGamepads?() or nav.mozGamepads or
    nav.webkitGetGamepads?() or nav.webkitGamepads or
    []

  gamepadType = (id) ->
    if /Racing Wheel/.test id
      WheelController
    else
      GamepadController

  class CarControl
    constructor: (@vehic, @client) ->
      @controllers = []
      @gamepadMap = {}
      @controllers.push new KeyboardController vehic, client

    update: (camera, delta) ->
      for gamepad, i in getGamepads()
        if gamepad? and i not of @gamepadMap
          @gamepadMap[i] = yes
          type = gamepadType gamepad.id
          @controllers.push new type @vehic, gamepad

      controls = @vehic.controller.input
      for key of controls
        controls[key] = 0
      for controller in @controllers
        controller.update delta
        for key of controls
          controls[key] += controller.controls[key]
      return

  class SunLight
    constructor: (scene) ->
      sunLight = @sunLight = new THREE.DirectionalLight( 0xffe0bb )
      sunLight.intensity = 1.3
      @sunLightPos = new Vec3 -6, 7, 10
      sunLight.position.copy @sunLightPos

      sunLight.castShadow = yes

      # sunLight.shadowCascade = yes
      # sunLight.shadowCascadeCount = 3
      # sunLight.shadowCascadeOffset = 10

      sunLight.shadow.camera.near = -20
      sunLight.shadow.camera.far = 60
      sunLight.shadow.camera.left = -24
      sunLight.shadow.camera.right = 24
      sunLight.shadow.camera.top = 24
      sunLight.shadow.camera.bottom = -24

      #sunLight.shadow.camera.visible = true

      # sunLight.shadowBias = -0.001
      # sunLight.shadowDarkness = 0.3

      sunLight.shadow.mapSize.width = 1024
      sunLight.shadow.mapSize.height = 1024

      scene.add sunLight
      return

    update: (camera, delta) ->
      @sunLight.target.position.copy camera.position
      @sunLight.position.copy(camera.position).add @sunLightPos
      @sunLight.updateMatrixWorld()
      @sunLight.target.updateMatrixWorld()
      return

  class Dust
    varying = """
      varying vec4 vColor;
      varying mat2 vRotation;

      """
    vertexShader = varying + """
      uniform float fScale;
      attribute vec4 aColor;
      attribute vec2 aAngSize;

      void main() {
        vColor = aColor;
        float angle = aAngSize.x;
        vec2 right = vec2(cos(angle), sin(angle));
        vRotation = mat2(right.x, right.y, -right.y, right.x);
        float size = aAngSize.y;
        //vec4 mvPosition = modelViewMatrix * vec4( position, 1.0 );
        // Vertices are already in world space.
        vec4 mvPosition = viewMatrix * vec4( position, 1.0 );
        gl_Position = projectionMatrix * mvPosition;
        gl_PointSize = fScale * size / gl_Position.w;
      }
      """
    fragmentShader = varying + """
      uniform sampler2D tMap;

      void main() {
        vec2 uv = vec2(gl_PointCoord.x - 0.5, 0.5 - gl_PointCoord.y);
        vec2 uvRotated = vRotation * uv + vec2(0.5, 0.5);
        vec4 map = texture2D(tMap, uvRotated);
        gl_FragColor = vColor * map;
      }
      """
    constructor: (scene) ->
      @length = 200
      @geom = new THREE.BufferGeometry();
      @geom.addAttribute('position', new THREE.BufferAttribute(new Float32Array(@length * 3), 3).setDynamic(true))
      @geom.addAttribute('aColor', new THREE.BufferAttribute(new Float32Array(@length * 4), 4).setDynamic(true))
      @geom.addAttribute('aAngSize', new THREE.BufferAttribute(new Float32Array(@length * 2), 2).setDynamic(true))

      @aColor = @geom.attributes.aColor
      @aAngSize = @geom.attributes.aAngSize
      @other = []
      for i in [0...@length]
        @other.push
          angVel: 0
          linVel: new Vec3

      @uniforms =
        fScale:
          value: 1000
        tMap:
          value: THREE.ImageUtils.loadTexture "/a/textures/dust.png"
      params = { @uniforms, vertexShader, fragmentShader }
      params.transparent = true
      params.depthWrite = false

      mat = new THREE.ShaderMaterial params
      @particleSystem = new THREE.Points @geom, mat
      scene.add @particleSystem
      @idx = 0

    spawnDust: (pos, vel) ->
      verts = @geom.attributes.position.array
      idx = @idx

      vertexOffset = idx * 3
      verts[vertexOffset] = pos.x
      verts[vertexOffset + 1] = pos.y
      verts[vertexOffset + 2] = pos.z

      aColorOffset = idx * 4
      @aColor.array[aColorOffset] = 0.75 + 0.2 * Math.random()
      @aColor.array[aColorOffset + 1] = 0.55 + 0.2 * Math.random()
      @aColor.array[aColorOffset + 2] = 0.35 + 0.2 * Math.random()
      @aColor.array[aColorOffset + 3] = 1;

      aAngSizeOffset = idx * 2
      @aAngSize.array[aAngSizeOffset] = Math.random() * Math.PI * 2
      @aAngSize.array[aAngSizeOffset + 1] = 0.2

      other = @other[idx]
      other.angVel = Math.random() - 0.5
      other.linVel.copy vel
      other.linVel.z += 0.5
      @idx = (idx + 1) % (verts.length / 3)

    spawnContrail: (pos, vel) ->
      verts = @geom.attributes.position.array
      idx = @idx

      vertexOffset = idx * 3
      verts[vertexOffset] = pos.x
      verts[vertexOffset + 1] = pos.y
      verts[vertexOffset + 2] = pos.z

      intensity = 1 - Math.random() * 0.05
      aColorOffset = idx * 4
      @aColor.array[aColorOffset] = intensity
      @aColor.array[aColorOffset + 1] = intensity
      @aColor.array[aColorOffset + 2] = intensity
      @aColor.array[aColorOffset + 3] = 0.3;

      aAngSizeOffset = idx * 2
      @aAngSize.array[aAngSizeOffset] = Math.random() * Math.PI * 2
      @aAngSize.array[aAngSizeOffset + 1] = 0

      other = @other[idx]
      other.angVel = 0
      other.linVel.copy vel
      # other.linVel.z += 0.5
      @idx = (idx + 1) % (verts.length / 3)

    update: (camera, delta) ->
      @uniforms.fScale.value = 1000 / camera.degreesPerPixel
      @particleSystem.position.copy camera.position
      vertices = @geom.attributes.position.array
      aColor = @aColor.array
      aAngSize = @aAngSize.array
      other = @other
      linVelScale = 1 / (1 + delta * 1)
      idx = 0
      length = @length
      while idx < length
        linVel = other[idx].linVel
        linVel.multiplyScalar linVelScale
        tmpVec3a.copy(linVel).multiplyScalar(delta)
        vertices[idx * 3] = tmpVec3a.x
        vertices[idx * 3 + 1] = tmpVec3a.y
        vertices[idx * 3 + 2] =tmpVec3a.z
        aColor[idx * 4 + 3] -= delta * 1
        aAngSize[idx * 2] += other[idx].angVel * delta
        if aColor[idx * 4 + 3] <= 0
          aAngSize[idx * 2 + 1] = 0
        else
          aAngSize[idx * 2 + 1] += delta * 0.5
        idx++

      @geom.attributes.position.updateRange.offset = 0;
      @aColor.updateRange.offset = 0;
      @aAngSize.updateRange.offset = 0;

      @geom.attributes.position.updateRange.count = -1;
      @aColor.updateRange.count = -1;
      @aAngSize.updateRange.count = -1;

      @geom.attributes.position.needsUpdate = true
      @aColor.needsUpdate = true
      @aAngSize.needsUpdate = true

  keyWeCareAbout = (event) ->
    event.keyCode <= 255
  isModifierKey = (event) ->
    event.ctrlKey or event.altKey or event.metaKey

  class TriggerClient
    constructor: (@containerEl, @root, @options = {}) ->
      # TODO: Add Detector support.
      @objects = {}
      @pubsub = new pubsub.PubSub()

      prefs = root.prefs

      @renderer = @createRenderer prefs
      @containerEl.appendChild @renderer.domElement if @renderer

      prefs.on 'change:pixeldensity', =>
        @renderer?.devicePixelRatio = prefs.pixeldensity
        @setSize @width, @height

      @sceneHUD = new THREE.Scene()
      @cameraHUD = new THREE.OrthographicCamera -1, 1, 1, -1, 1, -1

      @scene = new THREE.Scene()
      @camera = new THREE.PerspectiveCamera 75, 1, 0.1, 10000000
      @camera.idealFov = 75
      @camera.degreesPerPixel = 1
      @camera.up.set 0, 0, 1
      @camera.position.set 0, 0, 500
      @scene.add @camera  # Required so that we can attach stuff to camera.
      @camControl = null
      @scene.fog = new THREE.FogExp2 0xddeeff, 0.0002

      @scene.add new THREE.AmbientLight 0x446680
      # @scene.add new THREE.AmbientLight 0x6699C0
      @scene.add @cubeMesh()

      @add new SunLight @scene

      @add @dust = new Dust @scene

      @audio = new clientAudio.Audio()
      @audio.mute() unless prefs.audio
      @checkpointBuffer = null
      @audio.loadBuffer '/a/sounds/checkpoint.ogg', (buffer) => @checkpointBuffer = buffer
      @kachingBuffer = null
      @audio.loadBuffer '/a/sounds/kaching.ogg', (buffer) => @kachingBuffer = buffer
      @voiceBuffer = null
      @audio.loadBuffer '/a/sounds/voice.ogg', (buffer) =>
        @voiceBuffer = buffer
        # @speak 'welcome'
      @audio.setGain prefs.volume
      prefs.on 'change:audio', (prefs, audio) =>
        if audio then @audio.unmute() else @audio.mute()
      prefs.on 'change:volume', (prefs, volume) =>
        @audio.setGain volume

      @track = new gameTrack.Track @root

      sceneLoader = new THREE.SceneLoader()
      loadFunc = (url, callback) -> sceneLoader.load url, callback
      if @renderer
        @add new clientTerrain.RenderTerrain(
            @scene, @track.terrain, @renderer.context, prefs.terrainhq)
        @add new clientScenery.RenderScenery @scene, @track.scenery, loadFunc, @renderer
      @add new CamTerrainClipping(@camera, @track.terrain), 20

      @keyDown = []

    onKeyDown: (event) ->
      if keyWeCareAbout(event) and not isModifierKey(event)
        @keyDown[event.keyCode] = true
        @pubsub.publish 'keydown', event
        event.preventDefault() if @options.blockKeys and event.keyCode in [
          KEYCODE.UP
          KEYCODE.DOWN
          KEYCODE.LEFT
          KEYCODE.RIGHT
          KEYCODE.SPACE
        ]
      return

    onKeyUp: (event) ->
      if keyWeCareAbout(event)
        @keyDown[event.keyCode] = false
        #event.preventDefault()
      return

    speak: (msg) ->
      return unless @voiceBuffer
      [ offset, duration, random ] = {
        '3': [ 0, 0.621, 0.03 ]
        '2': [ 1.131, 0.531, 0.03 ]
        '1': [ 2.153, 0.690, 0.03 ]
        'go': [ 3.291, 0.351, 0.03 ]
        'checkpoint': [ 4.257, 0.702, 0.03 ]
        'complete': [ 5.575, 4.4, 0.03 ]
        # 'complete': [ 5.575, 0.975, 0.03 ]
        # 'welcome': [ 7.354, 1.378, 0 ]
      }[msg]
      rate = 1 + (Math.random() - 0.3) * random
      @audio.playRange @voiceBuffer, offset, duration, 1.5, rate

    playSound: (name) ->
      switch name
        when 'kaching'
          @audio.playSound @kachingBuffer, false, 0.3, 1 if @kachingBuffer
      return

    addGame: (game, options = {}) ->
      unless game? then throw new Error 'Added null game'
      objs = []

      priority = if options.isGhost then 2 else 1

      objs.push @add { update: (cam, delta) -> game.update delta }, priority

      onAddVehicle = (car, progress) =>
        # TODO: Use spatialized audio for ghosts.
        audio = if options.isGhost then null else @audio
        dust = if options.isGhost then null else @dust
        renderCar = new clientCar.RenderCar @scene, car, audio, dust, options.isGhost
        # progress._renderCar = renderCar
        objs.push @add renderCar
        return if options.isGhost
        objs.push @add new RenderDials(@sceneHUD, car)
        objs.push @add renderCheckpoints = new RenderCheckpointsDrive @scene, @root
        progress.on 'advance', =>
          renderCheckpoints.highlightCheckpoint progress.nextCpIndex
          @audio?.playSound @checkpointBuffer, false, 1, 1 if @checkpointBuffer?
        # TODO: Migrate isReplay out of cfg to a method argument like isGhost.
        return if car.cfg.isReplay
        objs.push @add @camControl = new CamControl @camera, renderCar
        objs.push @add new RenderCheckpointArrows @camera, progress
        objs.push @add new CarControl car, @
        return
      onAddVehicle prog.vehicle, prog for prog in game.progs
      game.on 'addvehicle', onAddVehicle

      # game.on 'deletevehicle', (progress) =>
      #   renderCar = progress._renderCar
      #   progress._renderCar = null
      #   for layer in @objects
      #     idx = layer.indexOf renderCar
      #     if idx isnt -1
      #       layer.splice idx, 1
      #   renderCar.destroy()

      game.on 'destroy', => @destroyObjects objs
      return

    destroyObjects: (objs) ->
      # Remove the objects from all update layers...
      for k, layer of @objects
        @objects[k] = _.without layer, objs...
      # ...then destroy the objects.
      for obj in objs
        obj.destroy?()
      return

    add: (obj, priority = 10) ->
      layer = @objects[priority] ?= []
      layer.push obj
      obj

    createRenderer: (prefs) ->
      try
        r = new THREE.WebGLRenderer
          alpha: false
          antialias: prefs.antialias
          premultipliedAlpha: false
          clearColor: 0xffffff
        r.devicePixelRatio = prefs.pixeldensity
        r.shadowMap.enabled = prefs.shadows
        # r.shadowMapCullFrontFaces = false
        # r.shadowMapCullFace = THREE.CullFaceBack
        r.autoClear = false
        r
      catch e
        console.error e

    updateCamera: ->
      aspect = if @height > 0 then @width / @height else 1
      @camera.aspect = aspect
      @camera.fov = @camera.idealFov / Math.max 1, aspect / 1.777
      if @renderer
        @camera.degreesPerPixel = @camera.fov / (@height * @renderer.devicePixelRatio)
      @camera.updateProjectionMatrix()
      @cameraHUD.left = -aspect
      @cameraHUD.right = aspect
      @cameraHUD.updateProjectionMatrix()

    setSize: (@width, @height) ->
      @renderer?.setSize @width, @height
      @updateCamera()

    addEditorCheckpoints: (parent) ->
      @add @renderCheckpoints = new RenderCheckpointsEditor parent, @root

    debouncedMuteAudio: _.debounce((audio) ->
      audio.setGain 0
    , 500)

    muteAudioIfStopped: ->
      if @audio?
        @audio.setGain @root.prefs.volume
        @debouncedMuteAudio @audio

    update: (delta) ->
      for priority, layer of @objects
        for object in layer
          object.update @camera, delta
      @muteAudioIfStopped()

    render: ->
      return unless @renderer
      @renderer.clear false, true
      @renderer.render @scene, @camera
      @renderer.render @sceneHUD, @cameraHUD

    cubeMesh: ->
      path = "/a/textures/miramar-z-512/miramar_"
      format = '.jpg'
      urls = (path + part + format for part in ['rt','lf','ft','bk','up','dn'])
      textureCube = THREE.ImageUtils.loadTextureCube urls
      cubeShader = THREE.ShaderLib["cube"]
      cubeShader.uniforms["tCube"].value = textureCube
      # cubeMaterial = new THREE.MeshBasicMaterial
      #   color: 0x0000FF
      #   side: THREE.BackSide
      cubeMaterial = new THREE.ShaderMaterial
        fog: yes
        side: THREE.BackSide
        uniforms: _.extend THREE.UniformsLib['fog'], cubeShader.uniforms
        vertexShader: cubeShader.vertexShader
        fragmentShader:
          THREE.ShaderChunk.fog_pars_fragment +
          """

          uniform samplerCube tCube;
          uniform float tFlip;
          varying vec3 vWorldDirection;
          vec3 worldVec;
          void main() {
            gl_FragColor = textureCube( tCube, vec3( tFlip * vWorldDirection.x, vWorldDirection.yz ) );
            worldVec = normalize(vWorldDirection);
            gl_FragColor.rgb = mix(fogColor, gl_FragColor.rgb, smoothstep(0.05, 0.15, worldVec.z));
          }

          """
      cubeMaterial.transparent = false
      cubeMesh = new THREE.Mesh(
          new THREE.CubeGeometry(5000000, 5000000, 5000000), cubeMaterial)
      cubeMesh.flipSided = false
      cubeMesh.position.set 0, 0, 2000
      cubeMesh

    viewToEye: (vec) ->
      vec.x = (vec.x / @width) * 2 - 1
      vec.y = 1 - (vec.y / @height) * 2
      vec

    viewToEyeRel: (vec) ->
      vec.x = (vec.x / @height) * 2
      vec.y = - (vec.y / @height) * 2
      vec

    viewRay: (viewX, viewY) ->
      vec = @viewToEye new Vec3 viewX, viewY, 0.9
      vec.unproject(@camera)
      vec.sub(@camera.position)
      vec.normalize()
      new THREE.Ray @camera.position, vec

    findObject: (viewX, viewY) ->
      @intersectRay @viewRay viewX, viewY

    # TODO: Does this intersection stuff belong in client?
    intersectRay: (ray) ->
      isect = []
      isect = isect.concat @track.scenery.intersectRay ray
      isect = isect.concat @intersectCheckpoints ray
      isect = isect.concat @intersectTerrain ray
      isect = isect.concat @intersectStartPosition ray
      [].concat.apply [], isect

    intersectTerrain: (ray) ->

      zeroCrossing = (fn, lower, upper, iterations = 4) ->
        fnLower = fn lower
        fnUpper = fn upper
        # Approximate the function as a line.
        gradient = (fnUpper - fnLower) / (upper - lower)
        constant = fnLower - gradient * lower
        crossing = -constant / gradient
        return crossing if iterations <= 1
        fnCrossing = fn crossing
        if fnCrossing < 0
          zeroCrossing fn, crossing, upper, iterations - 1
        else
          zeroCrossing fn, lower, crossing, iterations - 1

      terrainContact = (lambda) =>
        test = ray.direction.clone().multiplyScalar lambda
        test.add ray.origin
        {
          test
          contact: @track.terrain.getContact test
        }

      terrainFunc = (lambda) =>
        tc = terrainContact lambda
        tc.contact.surfacePos.z - tc.test.z

      lambda = 0
      step = 0.2
      count = 0
      while lambda < 50000
        nextLambda = lambda + step
        if terrainFunc(nextLambda) > 0
          lambda = zeroCrossing terrainFunc, lambda, nextLambda
          contact = terrainContact(lambda).contact
          return [
            type: 'terrain'
            distance: lambda
            object:
              pos: [
                contact.surfacePos.x
                contact.surfacePos.y
                contact.surfacePos.z
              ]
          ]
        lambda = nextLambda
        step *= 1.1
        count++
      []

    intersectStartPosition: (ray) ->
      return [] unless @root.track?.config?
      startpos = @root.track.config.course.startposition
      pos = startpos.pos
      return [] unless pos?
      hit = @intersectSphere ray, new Vec3(pos[0], pos[1], pos[2]), 4
      if hit
        hit.type = 'startpos'
        hit.object = startpos
        [hit]
      else
        []

    intersectSphere: (ray, center, radiusSq) ->
      # Destructive to center.
      center.sub ray.origin
      # We assume unit length ray direction.
      a = 1  # ray.direction.dot(ray.direction)
      along = ray.direction.dot center
      b = -2 * along
      c = center.dot(center) - radiusSq
      discrim = b * b - 4 * a * c
      return null unless discrim >= 0
      distance: along

    intersectCheckpoints: (ray) ->
      return [] unless @root.track?.config?
      radiusSq = 16
      isect = []
      for cp, idx in @root.track.config.course.checkpoints.models
        hit = @intersectSphere ray, new Vec3(cp.pos[0], cp.pos[1], cp.pos[2]), radiusSq
        if hit
          hit.type = 'checkpoint'
          hit.object = cp
          hit.idx = idx
          isect.push hit
      isect
