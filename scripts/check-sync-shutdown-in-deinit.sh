#!/usr/bin/env bash

set -euo pipefail

search_paths=("$@")
if [[ ${#search_paths[@]} -eq 0 ]]; then
    search_paths=(Sources Tests)
fi

existing_paths=()
for path in "${search_paths[@]}"; do
    [[ -e "$path" ]] && existing_paths+=("$path")
done

if [[ ${#existing_paths[@]} -eq 0 ]]; then
    printf 'No existing Swift source paths were supplied.\n' >&2
    exit 2
fi

readonly blocking_pattern='deinit\s*\{(?:(?!\n\s*\}).)*(?:syncShutdownGracefully|DispatchSemaphore|dispatch_semaphore_wait|\.wait\s*\(|\.join\s*\()'
if rg \
    --glob '*.swift' \
    --line-number \
    --multiline \
    --multiline-dotall \
    --pcre2 \
    "$blocking_pattern" \
    "${existing_paths[@]}"; then
    printf 'Blocking shutdown or waiting from deinit is not permitted.\n' >&2
    exit 1
fi

printf 'No blocking Swift deinit shutdown pattern was found.\n'
