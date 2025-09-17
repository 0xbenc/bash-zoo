#!/usr/bin/env bats

setup_file() {
  # shellcheck disable=SC1090
  source "$BATS_TEST_DIRNAME/test_helper.bash"
}

@test "preview_show handles missing file" {
  run bash -c '
    set -Eeuo pipefail
    TMPDIR=$(mktemp -d)
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export XDG_DATA_HOME="$TMPDIR/data"
    export XDG_STATE_HOME="$TMPDIR/state"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    ASTRA_ROOT="$ASTRA_REPO_ROOT/astra"
    SHAREDIR="$ASTRA_ROOT/share"
    LIBDIR="$ASTRA_ROOT/lib"
    source "$LIBDIR/core/env.sh"
    source "$LIBDIR/core/log.sh"
    source "$LIBDIR/core/config.sh"
    source "$LIBDIR/core/preview.sh"
    env_init "$ASTRA_ROOT" "$SHAREDIR"
    config_init ""
    preview_show "$TMPDIR/does-not-exist" >/dev/null
  '
  [ "$status" -eq 0 ]
}
