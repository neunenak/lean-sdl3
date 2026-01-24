import Lake
open System Lake DSL

package SDL3

-- pin to a specific commit to avoid breakages
structure GitDep where
  repo : String
  rev : String
  name : String

/-- The directory where this cloned repo should live --/
def GitDep.dir (dep : GitDep) (pkg : Package) : FilePath :=
  pkg.dir / "vendor" / dep.name

/-- Invoke git to clone this dependency to a vendored directory --/
def GitDep.clone (dep : GitDep) (pkg : Package) : FetchM Unit := do
  let dstDir := dep.dir pkg
  if (<- dstDir.pathExists) then
    logInfo s!"Directory {dstDir} already exists, skipping clone"
  else
    logInfo s!"Cloning {dep.repo} into {dstDir}"
    proc {
      cmd := "git"
      args := #["clone", "--revision", dep.rev,
              "--single-branch", "--depth", "1", "--recursive", dep.repo, dstDir.toString
              ]
    }

def sdlDep : GitDep := {
  repo := "https://github.com/libsdl-org/SDL.git"
  rev := "f3a9f66292d49322652be01ee93412d0e9b74f0b"
  name := "SDL"
}
def sdlImageDep : GitDep := {
  repo := "https://github.com/libsdl-org/SDL_image.git"
  rev := "d354e3d5146117f8b2f14096800965e56f9f7bfc"
  name := "SDL_image"
}
def sdlTtfDep : GitDep := {
  repo := "https://github.com/libsdl-org/SDL_ttf.git"
  rev := "6b6bd588e8646360b08f624fb601cc2ec75c6ada"
  name := "SDL_ttf"
}
def sdlMixerDep : GitDep := {
  repo := "https://github.com/libsdl-org/SDL_mixer.git"
  rev := "5cdf029bae982df1d6c210f915fc151a616d982f"
  name := "SDL_mixer"
}
-- TODO: at some point, we should figure out a better way to set the C compiler
def compiler := if Platform.isWindows then "gcc" else "cc"

input_file sdlSrc where
  path := "c" / "sdl.c"
  text := true

target sdlObj pkg : FilePath := do
  let srcJob ← sdlSrc.fetch
  let oFile := pkg.buildDir / "c" / "sdl.o"

  let leanInclude := <- getLeanIncludeDir

  let includeDirs : List FilePath := [sdlDep, sdlImageDep, sdlTtfDep, sdlMixerDep].map
    (fun dep => dep.dir pkg / "include/")

  let flags: List String := ["-fPIC"] ++
    includeDirs.map (fun dir => s!"-I{dir}") ++
    ["-D_REENTRANT", s!"-I{leanInclude}"]

  let flags: Array String := flags.toArray

  buildO oFile srcJob #[] flags compiler

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

target libSDL3 pkg : Dynlib := do
  return .pure {
    name := "SDL3"
    path := sdlDep.dir pkg / "build" / nameToSharedLib "SDL3"
  }

target libSDL3Image pkg : Dynlib := do
  return .pure {
    name := "SDL3_image"
    path := sdlImageDep.dir pkg / "build" / nameToSharedLib "SDL3_image"
  }

target libSDL3Ttf pkg : Dynlib := do
  return .pure {
    name := "SDL3_ttf"
    path := sdlTtfDep.dir pkg / "build" / nameToSharedLib "SDL3_ttf"
  }

target libSDL3Mixer pkg : Dynlib := do
  return .pure {
    name := "SDL3_mixer"
    path := sdlMixerDep.dir pkg / "build" / nameToSharedLib "SDL3_mixer"
  }

target libleansdl pkg : FilePath := do
  let deps := [sdlDep, sdlImageDep, sdlTtfDep, sdlMixerDep]

  -- clone the git repositories we need so we can build them later
  for dep in deps do
    dep.clone pkg

  -- build all the libraries we need
  let sdlRepoBuildDir := (sdlDep.dir pkg / "build").toString
  let sdlDirFlag := s!"-DSDL3_DIR={sdlRepoBuildDir}"

  buildCMakeProject (sdlDep.dir pkg) #[]
  buildCMakeProject (sdlImageDep.dir pkg) #[sdlDirFlag]
  buildCMakeProject (sdlTtfDep.dir pkg) #[sdlDirFlag, "-DSDLTTF_VENDORED=true"]
  buildCMakeProject (sdlMixerDep.dir pkg) #[sdlDirFlag, "-DSDLMIXER_VENDORED=true"]

  logInfo "All libraries built successfully"

  -- copy binaries
  let binaryDstDir := ((<- getRootPackage).binDir)
  IO.FS.createDirAll binaryDstDir

  -- manually copy the DLLs we need to .lake/build/bin/ in the root directory for the game to work
  for dep in deps do
    let sourceDir := dep.dir pkg
    logInfo s!"Copying binaries from {sourceDir} to {binaryDstDir}"

    let buildDir := sourceDir / "build"
    for entry in (← buildDir.readDir) do
      if entry.path.extension != none then
        copyFile entry.path (binaryDstDir / entry.path.fileName.get!)

  let sdlO ← sdlObj.fetch
  let name := nameToStaticLib "leansdl"
  buildStaticLib (pkg.staticLibDir / name) #[sdlO]

def libList : TargetArray Dynlib := #[libSDL3, libSDL3Image, libSDL3Ttf, libSDL3Mixer]

-- make sure to copy these link args into whatever project is using this library in order for it to work
-- This is because without "-rpath=$ORIGIN", the Linux executable will not load dynlibs next to the executable (i.e., the SDL ones you've copied there).
def moreLinkArgs: Array String := if Platform.isWindows
  then
    #[]
  else
    #["-Wl,--allow-shlib-undefined", "-Wl,-rpath=$ORIGIN"]

@[default_target]
lean_lib SDL where
  moreLinkObjs := #[libleansdl]
  moreLinkLibs := libList
  moreLinkArgs := moreLinkArgs

lean_exe «test-app» where
  root := `TestApp
  moreLinkObjs := #[libleansdl]
  moreLinkLibs := libList
  moreLinkArgs := moreLinkArgs

lean_exe «webcam-app» where
    root := `WebcamApp
    moreLinkObjs := #[libleansdl]
    moreLinkLibs := libList
    moreLinkArgs := moreLinkArgs

