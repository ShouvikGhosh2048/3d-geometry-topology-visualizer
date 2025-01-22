#!/bin/bash

# https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template/issues/22

# See https://github.com/karl-zylinski/odin-raylib-web for more examples on how
# to do a web build, including how to embed assets into it.

git clone https://github.com/emscripten-core/emsdk.git
./emsdk/emsdk install latest
./emsdk/emsdk activate latest

EMSCRIPTEN_SDK_DIR="emsdk"
OUT_DIR="build/web"

mkdir -p $OUT_DIR

export EMSDK_QUIET=1
# shellcheck disable=SC1091
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

odin-linux-amd64-nightly+2025-01-08/odin build source/main_web -target:freestanding_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -vet -strict-style -o:speed -out:$OUT_DIR/game

files="source/main_web/main_web.c $OUT_DIR/game.wasm.o odin-linux-amd64-nightly+2025-01-08/vendor/raylib/wasm/libraylib.a"
flags="-sUSE_GLFW=3 -sASSERTIONS --shell-file source/main_web/index_template.html --preload-file assets"

# shellcheck disable=SC2086
# Add `-g` to `emcc` call to enable debug symbols (works in chrome).
emcc -o $OUT_DIR/index.html $files $flags && rm $OUT_DIR/game.wasm.o

echo "Web build created in ${OUT_DIR}"