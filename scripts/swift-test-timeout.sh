#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
    printf 'Usage: %s <seconds> [--] <command> [arguments...]\n' "$0" >&2
    exit 2
fi

readonly timeout_seconds="$1"
shift

if [[ "$1" == "--" ]]; then
    shift
fi

if [[ ! "$timeout_seconds" =~ ^[0-9]+$ ]] \
    || (( timeout_seconds < 1 || timeout_seconds > 120 )); then
    printf 'Timeout must be an integer from 1 through 120 seconds.\n' >&2
    exit 2
fi

if [[ $# -eq 0 ]]; then
    printf 'A command is required.\n' >&2
    exit 2
fi

exec perl -e 'alarm shift; exec @ARGV' "$timeout_seconds" "$@"
