#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <scheduler> <input_csv> <expected_csv> [scheduler args...]" >&2
  exit 2
fi

scheduler="$1"
input_csv="$2"
expected_csv="$3"
shift 3
extra_args=("$@")

runner_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

program_command="${PROGRAM:-}"
program_bin="${SCHSIM_BIN:-}"
if [ -z "$program_command" ] && [ -z "$program_bin" ]; then
  echo "No simulator configured." >&2
  echo "Set PROGRAM (command string) or SCHSIM_BIN (executable path)." >&2
  exit 1
fi

tmp_out="$(mktemp)"
tmp_stdout="$(mktemp)"
tmp_diff="$(mktemp)"
cleanup() {
  rm -f "$tmp_out" "$tmp_stdout" "$tmp_diff"
}
trap cleanup EXIT

if [ -n "$program_command" ]; then
  sh -c "$program_command \"\$@\"" sh -v -s "$scheduler" "${extra_args[@]}" "$input_csv" "$tmp_out" >"$tmp_stdout" 2>&1 || {
    echo "Fail: Program did not exit zero"
    cat "$tmp_stdout"
    exit 1
  }
else
  if [ ! -x "$program_bin" ]; then
    echo "Simulator is not executable: $program_bin" >&2
    exit 1
  fi
  "$program_bin" -v -s "$scheduler" "${extra_args[@]}" "$input_csv" "$tmp_out" >"$tmp_stdout" 2>&1 || {
    echo "Fail: Program did not exit zero"
    cat "$tmp_stdout"
    exit 1
  }
fi

if ! diff "$tmp_out" "$expected_csv" >"$tmp_diff"; then
  echo "Fail: Output is not correct"
  cat "$tmp_diff"
  exit 1
fi

echo "Pass: Output is correct"
