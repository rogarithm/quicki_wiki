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

prepare_req_data() {
  local query_string=""
  local request_method="GET"
  local server_software="Apache"
  local stdin_body=""
  local snapshot_pages=()
  local requires_wiki_doc_rev_dir=false

  case "$script_name" in
    wiki)
      case "$case_name" in
        welcome) query_string="WelcomeVisitors" ;;
        existing) query_string="WikiEdit" ;;
        missing) query_string="MissingPage" ;;
        mixed) query_string="MixedMarkup" ;;
      esac ;;
    edit)
      case "$case_name" in
        new) query_string="MissingPage" ;;
        existing) query_string="WelcomeVisitors" ;;
        append)
          query_string="GuestBook"
          request_method="POST"
          stdin_body="append=1"
          ;;
      esac ;;
    search)
      case "$case_name" in
        hit) query_string="search=Wiki" ;;
        none) query_string="search=NoSuchNeedle" ;;
        special) query_string="search=wiki.org%2F" ;;
      esac ;;
    changes)
      case "$case_name" in
        default) ;;
        max3) query_string="max=3" ;;
      esac ;;
    refcount)
      case "$case_name" in
        default) ;;
      esac ;;
    save)
      request_method="POST"
      requires_wiki_doc_rev_dir=true
      case "$case_name" in
        overwrite)
          query_string="SaveOverwrite"
          stdin_body="Text=Line+One&mode=edit"
          snapshot_pages=("SaveOverwrite")
          ;;
        append)
          query_string="GuestBook"
          stdin_body="Text=Appended+note&mode=append"
          snapshot_pages=("GuestBook")
          ;;
        crlf)
          query_string="SaveCrlf"
          stdin_body="Text=Line1%0D%0ALine2&mode=edit"
          snapshot_pages=("SaveCrlf")
          ;;
        backlink)
          query_string="SaveBacklink"
          stdin_body="Text=Before+%3C%3CMainTopic+After&mode=edit"
          snapshot_pages=("SaveBacklink" "MainTopic")
          ;;
      esac ;;
    *)
      echo "unknown case: $script_name:$case_name" >&2
      exit 1
      ;;
  esac

  declare -p query_string request_method server_software stdin_body snapshot_pages requires_wiki_doc_rev_dir
}

prepare_test_dir() {
  local tmpdir
  tmpdir="$(mktemp -d "$HARNESS_DIR/tmp.XXXXXX")"

  static_files=("template.html" "logo.gif" "logo_globe.gif")
  for f in ${static_files[@]}; do
    cp "$ROOT/${f}" "$tmpdir/${f}"
  done

  find "$ROOT" -maxdepth 1 -type f \( -name "*.cgi" -o -name "*.rb.cgi" \) -print0 | xargs -0 cp -t "$tmpdir/"

  cp -R "$ROOT/pages" "$tmpdir/pages"

  cp "$HARNESS_DIR"/fixtures/pages/* "$tmpdir/pages/"

  find "$tmpdir/pages" -type f | while IFS= read page; do
    touch -t 202401010101 "$page"
  done

  if [[ "$script_name" == "changes" ]]; then
    local pages=(
      WelcomeVisitors WikiEdit MixedMarkup MainTopic
      GuestBook TopicSearch SearchSymbols WikiSignature
      WikiSandbox StyleGuide LegalNotice FindPage
      WikiWord WhosWho
    )

    local day_var=14
    for p in "${pages[@]}"; do
      touch -t "202401$(printf '%02d' "$day_var")0101" "$tmpdir/pages/$p"
      ((day_var--))
    done
  fi

  printf '%s\n' "$tmpdir"
}

run_case() {
  local interpreter="$1"
  local script_path="$2"
  local cgi_resp_path="$3" # cgi 응답 텍스트를 보관
  local wiki_doc_rev_dir="$4" # 요청 처리 후 pages/ 아래 실제로 바뀐 위키 문서 파일을 보관
  local content_length
  local test_tmpdir

  mkdir -p "$(dirname "$cgi_resp_path")"
  if [[ "$requires_wiki_doc_rev_dir" == true ]]; then
    mkdir -p "$wiki_doc_rev_dir"
  fi
  content_length="${#stdin_body}"
  test_tmpdir="$(prepare_test_dir)"

  (
    cd "$test_tmpdir"
    printf '%s' "$stdin_body" | env -i \
      PATH="$PATH" \
      PERL_USE_UNSAFE_INC=1 \
      QUERY_STRING="$query_string" \
      REQUEST_METHOD="$request_method" \
      CONTENT_LENGTH="$content_length" \
      SERVER_SOFTWARE="$server_software" \
      "$interpreter" "$script_path" > "$cgi_resp_path"
  )

  if [[ "$requires_wiki_doc_rev_dir" == true ]]; then
    for page in "${snapshot_pages[@]}"; do
      if [[ -f "$test_tmpdir/pages/$page" ]]; then
        cp "$test_tmpdir/pages/$page" "$wiki_doc_rev_dir/$page"
      fi
    done
  fi

  rm -rf "$test_tmpdir"
}

# prepare_req_data 반환값을 볼 수 있게 한다
eval "$(prepare_req_data)"

perl_prefix="$HARNESS_DIR/perl/$script_name/"
perl_cgi_resp_path="$perl_prefix/$case_name.html"
perl_wiki_doc_rev_dir="$perl_prefix/$case_name.pages"
run_case perl "./$script_name.cgi" "$perl_cgi_resp_path" "$perl_wiki_doc_rev_dir"

ruby_prefix="$HARNESS_DIR/ruby/$script_name/"
ruby_cgi_resp_path="$ruby_prefix/$case_name.html"
ruby_wiki_doc_rev_dir="$ruby_prefix/$case_name.pages"
run_case ruby "./$script_name.rb.cgi" "$ruby_cgi_resp_path" "$ruby_wiki_doc_rev_dir"

# 두 구현에서 template html으로 만든 결과를 비교
git diff --no-index -- "$perl_cgi_resp_path" "$ruby_cgi_resp_path"

for page in "${snapshot_pages[@]}"; do
  # 두 구현에서 요청 처리 후 위키 문서의 상태를 비교
  git diff --no-index -- "$perl_wiki_doc_rev_dir/$page" "$ruby_wiki_doc_rev_dir/$page"
done
