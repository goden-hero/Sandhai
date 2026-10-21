#!/usr/bin/env bash
set -euo pipefail
# CLI 15.31.0 shares os.tmpdir()/firebase/storage/blobs across projects. Unique
# ports alone do not isolate Storage shutdown; give every test run its own tmpdir.
# Keep logs/artifacts available after the run. Never clear the developer project.
sandhai_repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
sandhai_test_dir="$(mktemp -d /tmp/sandhai-rules-XXXXXX)"
export TMPDIR="$sandhai_test_dir"
export NO_PROXY=127.0.0.1,localhost,::1 HTTP_PROXY= http_proxy= HTTPS_PROXY= https_proxy=
cd "$sandhai_test_dir"
printf 'Isolated emulator artifacts: %s\n' "$sandhai_test_dir"
firebase emulators:exec --config "$sandhai_repo_dir/firebase.phase3-tests.json" --only firestore,storage,auth --project sandhai-phase3-tests "node --test --test-concurrency=1 $sandhai_repo_dir/test/rules.test.js $sandhai_repo_dir/test/phase_4_1_rules.test.js"
