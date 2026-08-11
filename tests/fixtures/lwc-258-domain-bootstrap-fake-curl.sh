#!/usr/bin/env bash
set -eu
root="$FIXTURE_ROOT"
url=""
method="GET"
data=""
output=""
write_out=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --request) method="${2:-}"; shift 2 ;;
    --data) data="${2:-}"; shift 2 ;;
    --output|-o) output="${2:-}"; shift 2 ;;
    --write-out|-w) write_out="${2:-}"; shift 2 ;;
    --header|--connect-timeout|--max-time|--max-redirs) shift 2 ;;
    --silent|--show-error|--fail-with-body|--location) shift ;;
    http://*|https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
scenario="$(<"$root/scenario")"
if [[ "$url" == */v9/projects/* && "$url" != */domains* ]]; then
  response='{"id":"prj_test123","name":"llm-wiki-frontend-dev","accountId":"team_test123","link":{"repoId":"repo_test"}}'
elif [[ "$url" == *"/v9/projects/$VERCEL_PROJECT_ID/domains"* ]]; then
  if [[ "$method" == POST ]]; then
    printf '%s\n' POST >> "$root/mutation-log"
    [[ "$scenario" == ambiguous-write ]] && exit 7
    response='{"name":"wiki.dev.rayer.idv.tw","configuredBy":"manual"}'
  elif [[ "$scenario" == wrong-domain ]]; then
    response='{"domains":[{"name":"other.dev.rayer.idv.tw"}]}'
  elif [[ -f "$root/created" ]]; then
    response='{"domains":[{"name":"wiki.dev.rayer.idv.tw","configuredBy":"manual"}]}'
  else
    response="$(cat "$root/domains.json")"
  fi
else
  exit 1
fi
if [[ -n "$output" ]]; then printf '%s' "$response" > "$output"; else printf '%s' "$response"; fi
if [[ "$write_out" == '%{http_code}' ]]; then printf '200'; fi
if [[ "$method" == POST ]]; then touch "$root/created"; fi
