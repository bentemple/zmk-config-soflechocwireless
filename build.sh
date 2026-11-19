#!/usr/bin/env bash
# build.sh builds the targets in build.yaml inside the ZMK build container (Podman).
#
#   ./build.sh            all targets
#   ./build.sh left       targets whose name contains "left"
#
# Output: firmware/<shield>-<board>.uf2
# West workspace (zmk, zephyr, modules) is cached in $ZMK_WORKSPACE, outside the repo.
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd)
ws=${ZMK_WORKSPACE:-$HOME/.cache/zmk-workspace/$(basename "$repo")}
image=${ZMK_IMAGE:-docker.io/zmkfirmware/zmk-build-arm:3.5-branch} # v0.3.x is on Zephyr 3.5
mkdir -p "$ws" "$repo/firmware"

podman run --rm --userns=keep-id -e HOME=/tmp -e FILTER="${1:-}" \
  -v "$ws:/workspace:z" \
  -v "$repo/config:/workspace/config:z" \
  -v "$repo:/repo:z" \
  -w /workspace "$image" bash -euo pipefail -c '
    [ -d .west ] || west init -l config
    sum=$(sha256sum config/west.yml)
    if [ "$sum" != "$(cat .manifest-sum 2>/dev/null)" ]; then  # west update only when the pin changes
      west update --fetch-opt=--filter=tree:0
      echo "$sum" > .manifest-sum
    fi
    west zephyr-export >/dev/null

    python3 -c "
import yaml
for t in yaml.safe_load(open(\"/repo/build.yaml\"))[\"include\"]:
    print(t[\"board\"], t.get(\"shield\", \"\").strip(), t.get(\"cmake-args\", \"\"), sep=\"|\")
" | while IFS="|" read -r board shield cmake_args; do
      name="${shield%% *}${shield:+-}$board"
      [[ "$name" == *"$FILTER"* ]] || continue
      dir="build/$board${shield:+-}${shield// /-}"  # full shield list: a shield change must not reuse a CMake cache
      echo "=== $name"
      west build -p auto -s zmk/app -d "$dir" -b "$board" -- \
        -DZMK_CONFIG=/workspace/config ${shield:+-DSHIELD="$shield"} $cmake_args </dev/null
      cp "$dir/zephyr/zmk.uf2" "/repo/firmware/$name.uf2"
    done
    ls -l /repo/firmware
  '
