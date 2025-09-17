#!/usr/bin/env bats

setup_file() {
  # shellcheck disable=SC1090
  source "$BATS_TEST_DIRNAME/test_helper.bash"
}

@test "env_init sets up directories" {
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
    env_init "$ASTRA_ROOT" "$SHAREDIR"
    [[ -d "$XDG_CONFIG_HOME/astra" ]]
    [[ -d "$XDG_CACHE_HOME/astra" ]]
  '
  [ "$status" -eq 0 ]
}
