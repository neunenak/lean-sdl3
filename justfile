_default:
    @just --list


[doc: "Build the general test app"]
[group: "build"]
build-test-app:
    @just _build test-app
    @just _perform_nix_patch test-app

[doc: "Build the general test app"]
[group: "run"]
run-test-app: build-test-app
    .lake/build/bin/test-app

[doc: "Build the webcam demo"]
[group: "build"]
build-webcam-demo:
    @just _build webcam-app
    @just _perform_nix_patch webcam-app

[doc: "Run the webcam demo"]
[group: "run"]
run-webcam-demo: build-webcam-demo
    .lake/build/bin/webcam-app


_build binary-name:
    lake build {{binary-name}}

_perform_nix_patch binary-name:
    patchelf --set-interpreter /usr/lib/ld-linux-x86-64.so.2 .lake/build/bin/{{binary-name}}
    patchelf --set-rpath '$ORIGIN:/usr/lib' .lake/build/bin/{{binary-name}}
