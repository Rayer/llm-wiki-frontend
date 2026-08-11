#!/usr/bin/env bash
set -eu
root="$FIXTURE_ROOT"
url=""
output=""
write_out=""
max_filesize=""
method="GET"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output|-o) output="${2:-}"; shift 2 ;;
    --write-out|-w) write_out="${2:-}"; shift 2 ;;
    --request) method="${2:-}"; shift 2 ;;
    --header|--connect-timeout|--max-time|--max-redirs|--max-filesize|--data)
      if [[ "$1" == --max-filesize ]]; then max_filesize="${2:-}"; fi
      shift 2
      ;;
    --silent|--show-error|--fail-with-body|--location) shift ;;
    http://*|https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[[ -n "$url" ]] || exit 1
scenario="$(<"$root/scenario")"
artifact_scenario="$(<"$root/artifact-scenario")"
if [[ -n "$output" ]]; then
  printf '%s' "$max_filesize" > "$root/max-filesize"
  if [[ "$artifact_scenario" == download-too-large ]]; then
    dd if=/dev/zero of="$output" bs=65537 count=1 status=none
  else
    cp "$root/artifact.zip" "$output"
  fi
  [[ "$write_out" == '%{http_code}' ]] && printf '302'
  exit 0
fi
if [[ "$url" == *"/actions/runs/$ATTEMPT_RUN_ID/artifacts?"* ]]; then
  case "$artifact_scenario" in
    duplicate) jq '.artifacts += [.artifacts[0]] | .total_count = 2' "$root/github-artifacts.json" ;;
    wrong-run) jq '.artifacts[0].workflow_run.id = 999' "$root/github-artifacts.json" ;;
    wrong-state-key) jq '.artifacts[0].name |= sub("[0-9a-f]{64}"; "bad")' "$root/github-artifacts.json" ;;
    malformed) printf '%s' '{"artifacts":[{"name":42}],"total_count":"bad"}' ;;
    artifact-pagination-malformed) printf '%s' '{"artifacts":[],"total_count":100,"pagination":{"next":42}}' ;;
    artifact-pagination-loop)
      jq -n --argjson base "$(cat "$root/github-artifacts.json")" '
        {artifacts: ($base.artifacts + [range(0;99) | {id: (8000 + .), name: ("noise-" + tostring), expired: false, workflow_run: {id: 1}}]), total_count: 200}'
      ;;
    artifact-pagination-max)
      page="${url##*page=}"
      if [[ "$page" == 1 ]]; then
        jq -n --argjson base "$(cat "$root/github-artifacts.json")" '
          {artifacts: ($base.artifacts + [range(0;99) | {id: (8000 + .), name: ("noise-1-" + tostring), expired: false, workflow_run: {id: 1}}]), total_count: 1001}'
      else
        jq -n --arg page "$page" '
          {artifacts: [range(0;100) | {id: (9000 + .), name: ("noise-" + $page + "-" + tostring), expired: false, workflow_run: {id: 1}}], total_count: 1001}'
      fi
      ;;
    *) cat "$root/github-artifacts.json" ;;
  esac
elif [[ "$url" == *"/actions/runs/$ATTEMPT_RUN_ID" ]]; then
  case "$artifact_scenario" in
    wrong-workflow) jq '.path = ".github/workflows/other.yml"' "$root/github-run.json" ;;
    wrong-sha) jq '.head_sha = "fedcba9876543210fedcba9876543210fedcba98"' "$root/github-run.json" ;;
    *) cat "$root/github-run.json" ;;
  esac
elif [[ "$url" == *"/actions/workflows/ci.yml/runs?"* ]]; then
  cat "$root/ci.json"
elif [[ "$url" == *"/v9/projects/$VERCEL_PROJECT_ID/domains"* ]]; then
  cat "$root/domains.json"
elif [[ "$url" == *"/v9/projects/$VERCEL_PROJECT_ID"* ]]; then
  cat "$root/project.json"
elif [[ "$url" == *"/v10/projects/$VERCEL_PROJECT_ID/env?"* ]]; then
  case "$scenario" in
    absent) printf '%s' '{"envs":[]}' ;;
    mismatch) printf '%s' '{"envs":[{"key":"NEXT_PUBLIC_AUTH_URL","value":"wrong","type":"plain","target":["preview"],"gitBranch":"develop"}]}' ;;
    duplicate) printf '%s' '{"envs":[{"key":"NEXT_PUBLIC_AUTH_URL","value":"https://auth.dev.rayer.idv.tw","type":"plain","target":["preview"],"gitBranch":"develop"},{"key":"NEXT_PUBLIC_AUTH_URL","value":"https://auth.dev.rayer.idv.tw","type":"plain","target":["preview"],"gitBranch":"develop"}]}' ;;
    pagination-malformed) printf '%s' '{"envs":[],"pagination":{"next":42}}' ;;
    pagination-loop) printf '%s' '{"envs":[],"pagination":{"next":"same"}}' ;;
    pagination-max) printf '%s' '{"envs":[],"pagination":{"next":"next"}}' ;;
    *) printf '%s' '{"envs":[{"key":"NEXT_PUBLIC_AUTH_URL","value":"https://auth.dev.rayer.idv.tw","type":"plain","target":["preview"],"gitBranch":"develop"}]}' ;;
  esac
else
  exit 1
fi
if [[ "$write_out" == '%{http_code}' ]]; then printf '200'; fi
