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
    --header)
      if [[ "${2:-}" == 'Content-Type: application/json' ]]; then content_type='application/json'; fi
      shift 2 ;;
    --connect-timeout|--max-time|--max-redirs) shift 2 ;;
    --silent|--show-error|--fail-with-body|--location) shift ;;
    http://*|https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s|%s|%s|%s\n' "$method" "$url" "${content_type:-}" "$data" >> "$root/request-log"
scenario="$(<"$root/scenario")"
if [[ "$url" == *"/actions/workflows/ci.yml/runs?"* ]]; then
  if [[ "$scenario" == ci-failure ]]; then
    response='{"workflow_runs":[{"path":".github/workflows/ci.yml","head_branch":"develop","head_sha":"0123456789abcdef0123456789abcdef01234567","event":"push","status":"completed","conclusion":"failure","id":123,"html_url":"https://github.test/runs/123"}]}'
  else
    response='{"workflow_runs":[{"path":".github/workflows/ci.yml","head_branch":"develop","head_sha":"0123456789abcdef0123456789abcdef01234567","event":"push","status":"completed","conclusion":"success","id":123,"html_url":"https://github.test/runs/123"}]}'
  fi
elif [[ "$url" == *"/actions/artifacts?"* ]]; then
  response='{"artifacts":[],"total_count":0}'
elif [[ "$url" == */v9/projects/* && "$url" != */domains* ]]; then
  response='{"id":"prj_test123","name":"llm-wiki-frontend-dev","accountId":"team_test123","link":{"repoId":"repo_test"}}'
  [[ "$scenario" == project-mismatch ]] && response='{"id":"prj_other","name":"llm-wiki-frontend-dev","accountId":"team_test123"}'
elif [[ "$url" == *"/v6/domains/wiki.dev.rayer.idv.tw/config"* ]]; then
  [[ "$scenario" == config-read-failure ]] && exit 7
  response="$(cat "$root/config.json")"
elif [[ "$url" == *"/v10/projects/$VERCEL_PROJECT_ID/domains"* ]]; then
  [[ "$method" == POST ]] || exit 1
  printf '%s\n' POST >> "$root/mutation-log"
  [[ "$scenario" == ambiguous-write ]] && exit 7
  response='{"name":"wiki.dev.rayer.idv.tw","configuredBy":"manual"}'
  touch "$root/created"
elif [[ "$url" == *"/v9/projects/$VERCEL_PROJECT_ID/domains"* ]]; then
  if [[ "$method" == POST ]]; then
    exit 1
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
