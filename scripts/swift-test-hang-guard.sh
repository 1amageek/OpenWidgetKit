#!/usr/bin/env bash

set -euo pipefail

repeats=3
timeout_seconds=30
build_timeout_seconds=120

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repeats)
            repeats="$2"
            shift 2
            ;;
        --timeout)
            timeout_seconds="$2"
            shift 2
            ;;
        --build-timeout)
            build_timeout_seconds="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

for value in "$repeats" "$timeout_seconds" "$build_timeout_seconds"; do
    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 || value > 120 )); then
        printf 'Repeat and timeout values must be integers from 1 through 120.\n' >&2
        exit 2
    fi
done

if [[ $# -eq 0 ]]; then
    printf 'A test command is required after --.\n' >&2
    exit 2
fi

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(pwd -P)"
readonly artifact_root="${SWIFT_TEST_ARTIFACT_ROOT:-$repository_root/.test-artifacts/hang-guard}"
readonly lock_directory="$artifact_root/lock"
readonly run_directory="$artifact_root/$(date -u '+%Y%m%dT%H%M%SZ')-$$"

mkdir -p "$artifact_root"
if ! mkdir "$lock_directory" 2>/dev/null; then
    printf 'Another hang-guard run owns %s.\n' "$lock_directory" >&2
    exit 3
fi
trap 'rmdir "$lock_directory" 2>/dev/null || true' EXIT
mkdir -p "$run_directory"

matching_processes() {
    ps -axo pid=,command= | awk -v root="$repository_root" '
        index($0, root) > 0 && ($0 ~ /swiftpm-testing-helper/ || $0 ~ /\.xctest/) { print }
    '
}

write_diagnostics() {
    local destination="$1"
    {
        printf 'Repository processes:\n'
        matching_processes
        printf '\nSwift processes:\n'
        ps -axo pid=,ppid=,state=,etime=,command= | rg 'swift|xcodebuild|xctest' || true
        printf '\nSwiftPM lock:\n'
        if [[ -e "$repository_root/.build/.lock" ]]; then
            ls -l "$repository_root/.build/.lock"
        else
            printf 'none\n'
        fi
    } > "$destination"
}

if [[ -n "$(matching_processes)" ]]; then
    write_diagnostics "$run_directory/preexisting.diag.txt"
    printf 'A stale repository test process exists before the guarded run.\n' >&2
    exit 1
fi

for (( run = 1; run <= repeats; run += 1 )); do
    limit="$timeout_seconds"
    if (( run == 1 )); then
        limit="$build_timeout_seconds"
    fi
    log_path="$run_directory/run-$run.log"
    set +e
    "$script_directory/swift-test-timeout.sh" "$limit" -- "$@" \
        > "$log_path" 2>&1
    result=$?
    set -e
    if (( result != 0 )); then
        write_diagnostics "$run_directory/run-$run.diag.txt"
        printf 'Guarded test run %d failed with exit code %d. See %s.\n' \
            "$run" "$result" "$run_directory" >&2
        exit "$result"
    fi
    sleep 1
    if [[ -n "$(matching_processes)" ]]; then
        write_diagnostics "$run_directory/run-$run.diag.txt"
        printf 'Guarded test run %d left a stale repository test process.\n' \
            "$run" >&2
        exit 1
    fi
done

printf 'OK: %d guarded runs completed without timeout or stale helper.\n' "$repeats"
