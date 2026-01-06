# Lean SDL3 Bindings

This is my (Greg Shuflin's) fork of Srayan Jana's [Lean
SDL3](https://github.com/ValorZard/lean-sdl3) bindings. I've added a few
additional SDL3 bindings, particularly ones necessary to make the webcam work.
Note that this is an incomplete, work-in-progress project.

## Sample Projects

In this repo, run `just run` to build and run the original sdl3 demo, which
displays some basic graphics and plays an mp3. Run `just webcam` to build and
run the webcam demo, which accesses a webcam (if one exists) and mirrors its
video on the screen.

If you want to see an example project that uses these bindings, check this out:

https://github.com/ValorZard/lean-sdl-test

## How to use:

If you want to use SDL3 bindings in your own Lean4 project, add this library as
a dependency in your `lakefile.lean` (Not `.toml`)

In your default target in your project, make sure you do something like this

```lean
@[default_target]
lean_exe «lean-sdl-test» where
  root := `Main
  -- this is necessary because on Linux, binaries don't automatically get picked up by the executable unless you set the rpath
  -- also, moreLinkArgs doesn't get inherited by the parent project
  moreLinkArgs := if !System.Platform.isWindows then #["-Wl,--allow-shlib-undefined", "-Wl,-rpath=$ORIGIN"] else #[]
```


## Acknowledgements
MASSIVE thanks to Oliver Dressler (@oOo0oOo) and Mac Malone (@tydeu) for all the help they gave!

## License & Attribution

MIT
