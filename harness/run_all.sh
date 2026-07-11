#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/harness/run_case.sh" wiki welcome
"$ROOT/harness/run_case.sh" wiki existing
"$ROOT/harness/run_case.sh" wiki missing
"$ROOT/harness/run_case.sh" wiki mixed
