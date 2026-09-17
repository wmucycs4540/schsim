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
repo_root="$(cd "$runner_dir/.." && pwd)"

program_command="${PROGRAM:-}"
program_bin="${SCHSIM_BIN:-}"
if [ -z "$program_command" ] && [ -z "$program_bin" ] && [ -x "$repo_root/schsim-x86_64-linux" ]; then
  program_bin="$repo_root/schsim-x86_64-linux"
  echo "Using bundled Linux reference executable fallback: $program_bin" >&2
fi
if [ -z "$program_command" ] && [ -z "$program_bin" ]; then
  echo "No simulator configured." >&2
  echo "Set PROGRAM (full command) or SCHSIM_BIN (executable path)." >&2
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
  if ! parsed_program="$(python3 - "$program_command" <<'PY'
import shlex
import sys

try:
    argv = shlex.split(sys.argv[1], posix=True)
except ValueError as err:
    print(err, file=sys.stderr)
    sys.exit(1)

for arg in argv:
    print(arg)
PY
)"; then
    echo "Failed to parse PROGRAM into command arguments." >&2
    exit 1
  fi
  mapfile -t program_argv <<<"$parsed_program"
  if [ "${#program_argv[@]}" -eq 0 ]; then
    echo "PROGRAM is empty after parsing." >&2
    exit 1
  fi
  "${program_argv[@]}" -v -s "$scheduler" "${extra_args[@]}" "$input_csv" "$tmp_out" >"$tmp_stdout" 2>&1 || {
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
