import Lake
open System Lake DSL

package SDL3

-- pin to a specific commit to avoid breakages
structure GitDep where
  repo : String
  rev : String

def sdlDep : GitDep := {
  repo := "https://github.com/libsdl-org/SDL.git"
  rev := "f3a9f66292d49322652be01ee93412d0e9b74f0b"
}
def sdlImageDep : GitDep := {
  repo := "https://github.com/libsdl-org/SDL_image.git"
  rev := "d354e3d5146117f8b2f14096800965e56f9f7bfc"
}
def sdlTtfDep : GitDep := {
  repo := "https://github.com/libsdl-org/SDL_ttf.git"
  rev := "6b6bd588e8646360b08f624fb601cc2ec75c6ada"
}
def sdlMixerDep : GitDep := {
  repo := "https://github.com/libsdl-org/SDL_mixer.git"
  rev := "5cdf029bae982df1d6c210f915fc151a616d982f"
}
-- TODO: at some point, we should figure out a better way to set the C compiler
def compiler := if Platform.isWindows then "gcc" else "cc"

input_file sdl.c where
  path := "c" / "sdl.c"
  text := true

target sdlDir pkg : FilePath := do
  return .pure (pkg.dir / "vendor" / "SDL")

target sdlImageDir pkg : FilePath := do
  return .pure (pkg.dir / "vendor" / "SDL_image")

target sdlTtfDir pkg : FilePath := do
  return .pure (pkg.dir / "vendor" / "SDL_ttf")

target sdlMixerDir pkg : FilePath := do
  return .pure (pkg.dir / "vendor" / "SDL_mixer")

def GitDep.clone (dep : GitDep) (dstDir : FilePath) : FetchM Unit := do
  let doesExist ← dstDir.pathExists
  if !doesExist then
    logInfo s!"Cloning {dep.repo} into {dstDir}"
    let clone ← IO.Process.output { cmd := "git", args := #["clone", "--revision", dep.rev, "--single-branch", "--depth", "1", "--recursive", dep.repo, dstDir.toString] }
    if clone.exitCode != 0 then
      logError s!"Error cloning {dep.repo}: {clone.stderr}"
    else
      logInfo s!"{dep.repo} cloned successfully"
      logInfo clone.stdout
  else
    logInfo s!"Directory {dstDir} already exists, skipping clone"

def copyBinaries (sourceDir : FilePath) : FetchM (Unit) := do
  -- manually copy the DLLs we need to .lake/build/bin/ in the root directory for the game to work
  let dstDir := ((<- getRootPackage).binDir)
  IO.FS.createDirAll dstDir
  logInfo s!"Copying binaries from {sourceDir} to {dstDir}"
  let binariesDir : FilePath := sourceDir / "build"
  for entry in (← binariesDir.readDir) do
    if entry.path.extension != none then
      copyFile entry.path (dstDir / entry.path.fileName.get!)
  pure ()

target sdl.o pkg : FilePath := do
  let srcJob ← sdl.c.fetch
  let oFile := pkg.buildDir / "c" / "sdl.o"

  let leanInclude := (<- getLeanIncludeDir).toString

  let sdlRepoDir : FilePath ← (← sdlDir.fetch).await
  let sdlImageDir : FilePath ← (← sdlImageDir.fetch).await
  let sdlTtfDir : FilePath ← (← sdlTtfDir.fetch).await
  let sdlMixerDir : FilePath ← (← sdlMixerDir.fetch).await

  let sdlInclude := sdlRepoDir / "include/"
  let sdlImageInclude := sdlImageDir / "include/"
  let sdlTtfInclude := sdlTtfDir / "include/"
  let sdlMixerInclude := sdlMixerDir / "include/"

  buildO oFile srcJob #[] #["-fPIC", s!"-I{sdlInclude}", s!"-I{sdlImageInclude}", s!"-I{sdlTtfInclude}", s!"-I{sdlMixerInclude}", "-D_REENTRANT", s!"-I{leanInclude}"] compiler

def buildCMakeProject (repoDir : FilePath) (args : Array String): FetchM (Unit) := do
  logInfo s!"Building {repoDir} with CMake with args {args}"

  let buildDir := repoDir / "build"
  let buildDirExists ← buildDir.pathExists

  if !buildDirExists then
    let configureBuild ← IO.Process.output {
      cmd := "cmake",
      args := #[
        "-S", repoDir.toString,
        "-B", buildDir.toString,
        "-DBUILD_SHARED_LIBS=ON",
        "-DCMAKE_BUILD_TYPE=Release",
        s!"-DCMAKE_C_COMPILER={compiler}",] ++ args
    }

    if configureBuild.exitCode != 0 then
      logError s!"Error configuring build: {configureBuild.stderr}"
    logInfo "Build configured successfully"
  else
    logInfo "Build directory already exists, skipping configuration step"

  let buildProject ← IO.Process.output { cmd := "cmake", args := #["--build", buildDir.toString, "--config", "Release"] }
  if buildProject.exitCode != 0 then
    logError s!"Error building project: {buildProject.exitCode}"
    logError s!"Project build stderr: {buildProject.stderr}"

  logInfo s!"{repoDir} built successfully"

target libSDL3 : Dynlib := Job.async do
  let sdlRepoDir : FilePath ← (← sdlDir.fetch).await
  return {
    name := "SDL3"
    path := sdlRepoDir / "build" / nameToSharedLib "SDL3"
  }

target libSDL3Image : Dynlib := Job.async do
  let sdlImageRepoDir : FilePath ← (← sdlImageDir.fetch).await
  return {
    name := "SDL3_image"
    path := sdlImageRepoDir / "build" / nameToSharedLib "SDL3_image"
  }

target libSDL3Ttf : Dynlib := Job.async do
  let sdlTtfRepoDir : FilePath ← (← sdlTtfDir.fetch).await
  return {
    name := "SDL3_ttf"
    path := sdlTtfRepoDir / "build" / nameToSharedLib "SDL3_ttf"
  }

target libSDL3Mixer : Dynlib := Job.async do
  let sdlMixerRepoDir : FilePath ← (← sdlMixerDir.fetch).await
  return {
    name := "SDL3_mixer"
    path := sdlMixerRepoDir / "build" / nameToSharedLib "SDL3_mixer"
  }

target libleansdl pkg : FilePath := do
  -- clone the git repositories we need so we can build them later
  let sdlRepoDir ← (← sdlDir.fetch).await
  let sdlImageRepoDir ← (← sdlImageDir.fetch).await
  let sdlTtfRepoDir ← (← sdlTtfDir.fetch).await
  let sdlMixerRepoDir ← (← sdlMixerDir.fetch).await

  sdlDep.clone sdlRepoDir
  sdlImageDep.clone sdlImageRepoDir
  sdlTtfDep.clone sdlTtfRepoDir
  sdlMixerDep.clone sdlMixerRepoDir

  -- build all the libraries we need
  buildCMakeProject sdlRepoDir #[]
  let sdlRepoBuildDir := sdlRepoDir / "build"
  buildCMakeProject sdlImageRepoDir #["-DSDL3_DIR=" ++ sdlRepoBuildDir.toString]
  buildCMakeProject sdlTtfRepoDir #["-DSDL3_DIR=" ++ sdlRepoBuildDir.toString,  s!"-DSDLTTF_VENDORED=true"]
  buildCMakeProject sdlMixerRepoDir #["-DSDL3_DIR=" ++ sdlRepoBuildDir.toString,  s!"-DSDLMIXER_VENDORED=true"]

  logInfo "All libraries built successfully"

  copyBinaries sdlRepoDir
  copyBinaries sdlImageRepoDir
  copyBinaries sdlTtfRepoDir
  copyBinaries sdlMixerRepoDir

  let sdlO ← sdl.o.fetch
  let name := nameToStaticLib "leansdl"
  buildStaticLib (pkg.staticLibDir / name) #[sdlO]

def libList : TargetArray Dynlib := #[libSDL3, libSDL3Image, libSDL3Ttf, libSDL3Mixer]

@[default_target]
lean_lib SDL where
  moreLinkObjs := #[libleansdl]
  moreLinkLibs := libList
  -- make sure to copy these link args into whatever project is using this library in order for it to work
  -- This is because without "-rpath=$ORIGIN", the Linux executable will not load dynlibs next to the executable (i.e., the SDL ones you've copied there).
  moreLinkArgs := if !Platform.isWindows then #["-Wl,--allow-shlib-undefined", "-Wl,-rpath=$ORIGIN"] else #[]

lean_exe «test-app» where
  root := `TestApp
  moreLinkObjs := #[libleansdl]
  moreLinkLibs := libList
  moreLinkArgs := if !Platform.isWindows then #["-Wl,--allow-shlib-undefined", "-Wl,-rpath=$ORIGIN"] else #[]

lean_exe «webcam-app» where
    root := `WebcamApp
    moreLinkObjs := #[libleansdl]
    moreLinkLibs := libList
    moreLinkArgs := if !Platform.isWindows then #["-Wl,--allow-shlib-undefined", "-Wl,-rpath=$ORIGIN"] else #[]

