#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/harness/run_case.sh" wiki welcome
"$ROOT/harness/run_case.sh" wiki existing
"$ROOT/harness/run_case.sh" wiki missing
"$ROOT/harness/run_case.sh" wiki mixed
"$ROOT/harness/run_case.sh" edit new
"$ROOT/harness/run_case.sh" edit existing
"$ROOT/harness/run_case.sh" edit append
"$ROOT/harness/run_case.sh" search hit
"$ROOT/harness/run_case.sh" search none
"$ROOT/harness/run_case.sh" search special
"$ROOT/harness/run_case.sh" changes default
"$ROOT/harness/run_case.sh" changes max3
