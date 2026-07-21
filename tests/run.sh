#!/usr/bin/env bash
# tests/run.sh
#
# Run all tree-setter tests under nvim --headless.  Each `tests/test_*.lua`
# prints a final line `RESULT pass=N fail=M` and exits 0 (all pass) or non-zero.
#
# This script aggregates the per-file results, prints a single summary,
# and exits non-zero if any test failed.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TESTS_DIR="${SCRIPT_DIR}"

# Per-test timeout (in seconds).  Generous, but tight enough to catch hangs.
PER_TEST_TIMEOUT="${PER_TEST_TIMEOUT:-20}"

# Optional: restrict which tests to run.
declare -a SELECTED=()
if [[ $# -gt 0 ]]; then
    for a in "$@"; do SELECTED+=("$a"); done
fi

declare -a files
if (( ${#SELECTED[@]} > 0 )); then
    for a in "${SELECTED[@]}"; do
        # Accept bare names ("test_setter") or paths ("tests/test_setter.lua")
        local_path="$a"
        case "$local_path" in
            tests/*) ;;
            /*) ;;
            *) local_path="tests/${local_path}.lua" ;;
        esac
        files+=("$local_path")
    done
else
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$TESTS_DIR" -maxdepth 1 -type f -name 'test_*.lua' -print0 | sort -z)
fi

if (( ${#files[@]} == 0 )); then
    echo "No tests found in ${TESTS_DIR}" >&2
    exit 1
fi

cd "$REPO_ROOT"

total_pass=0
total_fail=0
declare -a failed_tests=()

for f in "${files[@]}"; do
    name="$(basename "$f" .lua)"
    if [[ ! -f "$f" ]]; then
        echo "[skip] $f does not exist" >&2
        continue
    fi
    printf '\n=== %s ===\n' "$name"
    # `vim.cmd("qa!")` at end of each test should exit cleanly.  If it hangs,
    # the timeout kills nvim and we mark the test as FAIL.
    out=$(timeout "${PER_TEST_TIMEOUT}" nvim --headless -c "luafile $f" 2>&1)
    rc=$?
    # Find the LAST line matching `^RESULT pass=N fail=M`.
    result_line="$(printf '%s\n' "$out" | grep -E '^RESULT pass=[0-9]+ fail=[0-9]+$' | tail -n 1 || true)"
    if [[ -z "$result_line" ]]; then
        echo "  [no RESULT line]  ($name likely failed to run; rc=$rc)"
        failed_tests+=("$name")
        total_fail=$((total_fail + 1))
        continue
    fi
    p="$(printf '%s' "$result_line" | sed -nE 's/^RESULT pass=([0-9]+) fail=([0-9]+)$/\1/p')"
    q="$(printf '%s' "$result_line" | sed -nE 's/^RESULT pass=([0-9]+) fail=([0-9]+)$/\2/p')"
    total_pass=$((total_pass + p))
    total_fail=$((total_fail + q))
    if [[ "$q" -ne 0 ]]; then
        failed_tests+=("$name")
    fi
    echo "  -> $result_line  (rc=$rc)"
done

echo
echo "================================================================"
echo "ALL TESTS  pass=${total_pass}  fail=${total_fail}"
if (( total_fail > 0 )); then
    echo "FAILED:"
    for n in "${failed_tests[@]}"; do
        echo "  - $n"
    done
    exit 1
fi
echo "OK"
exit 0
