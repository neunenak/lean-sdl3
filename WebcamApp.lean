import SDL

def SCREEN_WIDTH : Int32 := 1280
def SCREEN_HEIGHT : Int32 := 720

def isEscapeKeyDown : IO Bool := SDL.getKeyState SDL.SDL_SCANCODE_ESCAPE

structure WebcamState where
  window : SDL.SDLWindow
  renderer : SDL.SDLRenderer
  camera : SDL.SDLCamera
  texture : Option SDL.SDLTexture
  running : Bool

partial def webcamLoop (stateRef: IO.Ref WebcamState): IO Unit := do
    let state ← stateRef.get

    -- Check for quit event
    let eventType ← SDL.pollEvent
    if eventType == SDL.SDL_QUIT || (← isEscapeKeyDown) then
      stateRef.modify fun s => { s with running := false }
      return

    -- Try to acquire a camera frame (may return none if no frame ready)
    let maybeFrame ← SDL.acquireCameraFrame state.camera

    match maybeFrame with
    | none =>
      -- No frame available yet, just continue
      pure ()
    | some cameraFrame =>
      let w := cameraFrame.w.toUInt32
      let h := cameraFrame.h.toUInt32

      match state.texture with
      | none =>
        -- First frame: create the texture
        let cameraTexture ← SDL.createTexture state.renderer cameraFrame.format SDL.SDL_TEXTUREACCESS_STREAMING w h
        stateRef.modify fun s => { s with texture := some cameraTexture }
      | some tx =>
        -- Subsequent frames: update the texture directly from the camera frame
        let _ ← SDL.updateTextureFromSurface tx cameraFrame

      SDL.releaseCameraFrame state.camera cameraFrame

    -- Clear the renderer
    let _ ← SDL.setRenderDrawColorFloat state.renderer 0.4 0.6 1.0 SDL.SDL_ALPHA_OPAQUE_FLOAT
    let _ ← SDL.renderClear state.renderer

    -- Render the texture if we have one
    let state ← stateRef.get
    match state.texture with
    | none => pure ()
    | some tx =>
      let _ ← SDL.renderTextureFullscreen state.renderer tx
      pure ()

    -- Present the frame
    SDL.renderPresent state.renderer

    -- Continue the loop if still running
    let state ← stateRef.get
    if state.running then
      webcamLoop stateRef

partial def run : IO Unit := do
  unless (← SDL.init (SDL.SDL_INIT_VIDEO ||| SDL.SDL_INIT_CAMERA)) == 1 do
    IO.println "Failed to initialize SDL"
    return

  let (window, renderer) ← try
    SDL.createWindowAndRenderer "WebcamTest" SCREEN_WIDTH SCREEN_HEIGHT SDL.SDL_WINDOW_SHOWN
  catch sdlError =>
    IO.println sdlError
    SDL.quit
    return

  let cameraCount ← SDL.getCameras
  IO.println s!"Camera count: {cameraCount}"

  if cameraCount.isEmpty then
    IO.println "No cameras found!"
    SDL.quit
    return

  let idx := cameraCount[0]!
  let camera ← SDL.openCamera idx

  let spec ← SDL.getCameraFormat camera

  let msg :=
    let width := spec.width
    let height := spec.height
    let n := spec.framerateNumerator
    let d := spec.framerateDenominator
    s!"Framerate: {n}/{d} FPS width: {width}, height: {height}"
  IO.println msg

  let initialState : WebcamState := {
    window := window
    renderer := renderer
    camera := camera
    texture := none
    running := true
  }

  let stateRef ← IO.mkRef initialState
  IO.println "Starting webcam loop..."
  webcamLoop stateRef
  SDL.quit

def main : IO Unit :=
  run
