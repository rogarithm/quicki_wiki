#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="$ROOT/harness"

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <script> <case>" >&2
  exit 1
fi

script_name="$1"
case_name="$2"

query_string=""
request_method="GET"
server_software="Apache"
stdin_body=""

configure_case() {
  case "$script_name:$case_name" in
    wiki:welcome)
      query_string="WelcomeVisitors"
      ;;
    wiki:existing)
      query_string="WikiEdit"
      ;;
    wiki:missing)
      query_string="MissingPage"
      ;;
    wiki:mixed)
      query_string="MixedMarkup"
      ;;
    *)
      echo "unknown case: $script_name:$case_name" >&2
      exit 1
      ;;
  esac
}

prepare_workspace() {
  local tmpdir
  tmpdir="$(mktemp -d "$HARNESS_DIR/tmp.XXXXXX")"
  cp "$ROOT/template.html" "$tmpdir/template.html"
  cp "$ROOT/logo.gif" "$tmpdir/logo.gif"
  cp "$ROOT/logo_globe.gif" "$tmpdir/logo_globe.gif"
  cp "$ROOT/wiki.cgi" "$tmpdir/wiki.cgi"
  cp "$ROOT/wiki.rb.cgi" "$tmpdir/wiki.rb.cgi"
  cp -R "$ROOT/pages" "$tmpdir/pages"

  if [[ -d "$HARNESS_DIR/fixtures/pages" ]]; then
    cp "$HARNESS_DIR"/fixtures/pages/* "$tmpdir/pages/"
  fi

  find "$tmpdir/pages" -type f | while IFS= read -r page; do
    touch -t 202401010101 "$page"
  done

  workspace_tmpdir="$tmpdir"
}

run_case() {
  local interpreter="$1"
  local script_path="$2"
  local output_path="$3"
  local content_length

  mkdir -p "$(dirname "$output_path")"
  content_length="${#stdin_body}"

  (
    cd "$workspace_tmpdir"
    printf '%s' "$stdin_body" | env -i \
      PATH="$PATH" \
      QUERY_STRING="$query_string" \
      REQUEST_METHOD="$request_method" \
      CONTENT_LENGTH="$content_length" \
      SERVER_SOFTWARE="$server_software" \
      "$interpreter" "$script_path" > "$output_path"
  )
}

configure_case
prepare_workspace
trap 'rm -rf "$workspace_tmpdir"' EXIT

perl_output="$HARNESS_DIR/perl/$script_name/$case_name.html"
ruby_output="$HARNESS_DIR/ruby/$script_name/$case_name.html"

run_case perl ./wiki.cgi "$perl_output"
run_case ruby ./wiki.rb.cgi "$ruby_output"

git diff --no-index -- "$perl_output" "$ruby_output"
