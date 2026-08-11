#!/usr/bin/env bash
set -eu
root="$FIXTURE_ROOT"
scenario="$(<"$root/scenario")"
vercel_base="${VERCEL_API_BASE_URL:-https://api.vercel.com}"
github_base="${GITHUB_API_URL:-https://api.github.com}"
url=""
data=""
method="GET"
output=""
write_out=""

normalize_v6_deployment() {
  jq -c '. + {uid: (.uid // .id)} | del(.id,.teamId,.accountId,.ownerId) | .url = (.url | sub("^https?://"; ""))'
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output|--write-out)
      if [[ "$1" == --output ]]; then output="${2:-}"; else write_out="${2:-}"; fi
      shift 2
      ;;
    --header|--connect-timeout|--max-time|--max-redirs|--request|--data)
      if [[ "$1" == --data ]]; then data="${2:-}"; fi
      if [[ "$1" == --request ]]; then method="${2:-}"; fi
      shift 2
      ;;
    --silent|--show-error|--fail-with-body|--location)
      shift
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *) shift ;;
  esac
done
if [[ -z "$url" ]]; then exit 1; fi
printf '%s\n' "$url" >> "$root/curl-calls"

if [[ -n "$output" && "$url" == *"/actions/artifacts/9001/zip" && ( "$scenario" == standard-terminal-artifact || "$scenario" == standard-terminal-reconciliation-artifact ) ]]; then
  cp "$root/create.zip" "$output"
  exit 0
fi

if [[ -n "$output" && "$url" == *"/actions/artifacts/9002/zip" ]]; then
  if [[ "$scenario" == standard-terminal-artifact || "$scenario" == standard-terminal-reconciliation-artifact || "$scenario" == prior-auth-terminal-success || "$scenario" == prior-auth-terminal-exact-count-one || "$scenario" == prior-auth-terminal-exact-spoofed || "$scenario" == prior-auth-terminal-owner-spoofed ]]; then
    cp "$root/terminal_exact.zip" "$output"
  else
    cp "$root/terminal_absent.zip" "$output"
  fi
  exit 0
fi

if [[ "$url" == *"/actions/runs/1001" && ( "$scenario" == standard-terminal-artifact || "$scenario" == standard-terminal-reconciliation-artifact ) ]]; then
  if [[ "$scenario" == standard-terminal-reconciliation-artifact ]]; then
    printf '%s' '{"id":1001,"path":".github/workflows/vercel-dev-deployment.yml","head_sha":"774d00dcb316a640aafb0f5e1674f9b42247e727","event":"workflow_dispatch","repository":{"full_name":"Rayer/llm-wiki-frontend"}}'
  else
    printf '%s' '{"id":1001,"path":".github/workflows/vercel-dev-deployment.yml","head_sha":"0123456789abcdef0123456789abcdef01234567","event":"workflow_dispatch","repository":{"full_name":"Rayer/llm-wiki-frontend"}}'
  fi
  exit 0
fi

if [[ "$url" == *"/actions/runs/2002" ]]; then
  if [[ "$scenario" == prior-auth-terminal-owner-spoofed ]]; then
    printf '%s' '{"id":2002,"path":".github/workflows/unrelated.yml","head_sha":"0123456789abcdef0123456789abcdef01234567","event":"workflow_dispatch","repository":{"full_name":"Rayer/llm-wiki-frontend"}}'
  else
    printf '%s' '{"id":2002,"path":".github/workflows/vercel-dev-auth-env-reconciliation.yml","head_sha":"0123456789abcdef0123456789abcdef01234567","event":"workflow_dispatch","repository":{"full_name":"Rayer/llm-wiki-frontend"}}'
  fi
  exit 0
fi

if [[ "$url" == *"/actions/runs/9001" || "$url" == *"/actions/runs/9003" ]]; then
  run_id="${url##*/}"
  printf '%s' "{\"id\":$run_id,\"path\":\".github/workflows/vercel-dev-deployment.yml\",\"head_sha\":\"0123456789abcdef0123456789abcdef01234567\",\"event\":\"workflow_dispatch\",\"repository\":{\"full_name\":\"Rayer/llm-wiki-frontend\"}}"
  exit 0
fi

if [[ "$url" == *"/v10/projects/$VERCEL_PROJECT_ID/env?gitBranch=develop&teamId=$VERCEL_TEAM_ID"* ]]; then
  if [[ "$url" == *"limit=100"* ]]; then
    case "$scenario" in
      auth-env-page-2-exact)
        if [[ "$url" == *"until=auth-cursor-2"* ]]; then
          printf '%s' "$(jq -c '{envs: .envs}' "$root/auth-env.json")"
        else
          printf '%s' '{"envs":[{"key":"OTHER_KEY","value":"ignored","type":"plain","target":["preview"],"gitBranch":"develop"}],"pagination":{"next":"auth-cursor-2"}}'
        fi
        ;;
      auth-env-page-2-duplicate)
        if [[ "$url" == *"until=auth-cursor-2"* ]]; then
          cat "$root/auth-env.json"
        else
          printf '%s' "$(jq -c '. + {pagination: {next: "auth-cursor-2"}}' "$root/auth-env.json")"
        fi
        ;;
      auth-env-pagination-malformed)
        printf '%s' '{"envs":[],"pagination":{"next":{"not":"a cursor"}}}'
        ;;
      auth-env-pagination-cursor-loop)
        printf '%s' '{"envs":[],"pagination":{"next":"auth-cursor-loop"}}'
        ;;
      auth-env-pagination-max-pages)
        printf '%s' '{"envs":[],"pagination":{"next":"auth-cursor-max"}}'
        ;;
      *)
        cat "$root/auth-env.json"
        ;;
    esac
    exit 0
  fi
  case "$scenario" in
    auth-env-wrong-value)
      jq '.envs[0].value = "https://auth-wrong.example"' "$root/auth-env.json"
      ;;
    auth-env-wrong-type)
      jq '.envs[0].type = "secret"' "$root/auth-env.json"
      ;;
    auth-env-wrong-target)
      jq '.envs[0].target = ["production"]' "$root/auth-env.json"
      ;;
    auth-env-wrong-branch)
      jq '.envs[0].gitBranch = "main"' "$root/auth-env.json"
      ;;
    auth-env-duplicate)
      cat "$root/auth-env.json"
      ;;
    auth-env-ambiguous)
      cat "$root/auth-env.json"
      ;;
    *)
      cat "$root/auth-env.json"
      ;;
  esac
elif [[ "$url" == *"/v10/projects/$VERCEL_PROJECT_ID/env?teamId=$VERCEL_TEAM_ID"* ]]; then
  [[ "$method" == POST ]] || exit 1
  printf '%s\n' "$data" >> "$root/env-post-log"
  printf 'env create\n' >> "$root/mutation-log"
  if [[ "$scenario" == auth-env-create-failed ]]; then exit 8; fi
  if [[ "$scenario" == auth-env-create-uncertain ]]; then
    jq --argjson created "$(jq -c 'if type == "array" then .[0] else . end' <<< "$data")" '.envs = [$created]' "$root/auth-env.json" > "$root/auth-env.json.tmp"
    mv "$root/auth-env.json.tmp" "$root/auth-env.json"
    exit 8
  fi
  if ! jq -e 'type == "object" and .key == "NEXT_PUBLIC_AUTH_URL" and .value == "https://auth-dev.rayer.idv.tw" and .type == "sensitive" and .target == ["preview"] and .gitBranch == "develop"' <<< "$data" >/dev/null; then
    response='{"error":{"code":"BAD_REQUEST"}}'
    if [[ -n "$output" ]]; then printf '%s' "$response" > "$output"; [[ "$write_out" == '%{http_code}' ]] && printf '400'; else printf '%s' "$response"; fi
    exit 0
  fi
  if [[ "$scenario" == auth-env-http-400 || "$scenario" == auth-env-http-403 ]]; then
    if [[ "$scenario" == auth-env-http-400 ]]; then response='{"error":{"code":"ENV_CONFLICT","message":"arbitrary provider text must not be recorded"}}'; else response='{"error":{"code":"forbidden message","message":"arbitrary provider text must not be recorded"}}'; fi
    if [[ -n "$output" ]]; then printf '%s' "$response" > "$output"; [[ "$write_out" == '%{http_code}' ]] && { [[ "$scenario" == auth-env-http-400 ]] && printf '400' || printf '403'; }; else printf '%s' "$response"; fi
    exit 0
  fi
  if [[ "$scenario" == auth-env-sensitive-policy || "$scenario" == auth-env-type-invalid || "$scenario" == auth-env-schema-invalid || "$scenario" == auth-env-conflict || "$scenario" == auth-env-malicious-message ]]; then
    case "$scenario" in
      auth-env-sensitive-policy) message='Sensitive Environment Variable Policy requires sensitive values' ;;
      auth-env-type-invalid) message='invalid type for environment variable' ;;
      auth-env-schema-invalid) message='request schema is invalid' ;;
      auth-env-conflict) message='environment variable already exists' ;;
      *) message='reflected https://evil.example/token/abc?target=production must not leak' ;;
    esac
    response="$(jq -cn --arg message "$message" '{error:{code:"BAD_REQUEST",message:$message}}')"
    if [[ -n "$output" ]]; then printf '%s' "$response" > "$output"; [[ "$write_out" == '%{http_code}' ]] && printf '400'; else printf '%s' "$response"; fi
    exit 0
  fi
  jq --argjson created "$data" '.envs = [$created]' "$root/auth-env.json" > "$root/auth-env.json.tmp"
  mv "$root/auth-env.json.tmp" "$root/auth-env.json"
  if [[ -n "$output" ]]; then printf '%s' "$data" > "$output"; [[ "$write_out" == '%{http_code}' ]] && printf '200'; else printf '%s' "$data"; fi
elif [[ "$url" == *"/actions/workflows/ci.yml/runs?"* ]]; then
  if [[ "$scenario" == ci-failure ]]; then
    jq '.workflow_runs[0].conclusion = "failure"' "$root/ci.json"
  elif [[ "$scenario" == ci-wrong-sha ]]; then
    jq '.workflow_runs[0].head_sha = "fedcba9876543210fedcba9876543210fedcba98"' "$root/ci.json"
  else
    cat "$root/ci.json"
  fi
elif [[ "$url" == *"/actions/artifacts?"* ]]; then
  cat "$root/github-artifacts.json"
elif [[ "$url" == *"/repos/$GITHUB_REPOSITORY"* ]]; then
  printf '%s' '{"id":12345}'
elif [[ "$url" == *"/v6/domains/wiki.dev.rayer.idv.tw/config"* ]]; then
  printf '%s' '{"misconfigured":false,"configuredBy":"CNAME","acceptedChallenges":["dns-01"],"recommendedCNAME":[{"rank":1,"value":"cname.vercel-dns.com"},{"rank":2,"value":"cname.vercel-dns-legacy.com"}],"recommendedIPv4":[{"rank":1,"value":["76.76.21.21","76.76.21.22"]},{"rank":2,"value":["192.0.2.1"]}]}'
elif [[ "$url" == *"/v9/projects/$VERCEL_PROJECT_ID/domains"* ]]; then
  if [[ "$scenario" == domain-mismatch ]]; then
    printf '%s' '{"domains":[{"name":"llm-wiki-frontend.vercel.app"}]}'
  else
    cat "$root/domains.json"
  fi
elif [[ "$url" == *"/teams/$VERCEL_TEAM_ID"* ]]; then
  case "$scenario" in
    team-policy-off) printf '%s' '{"id":"team_dev123","sensitiveEnvironmentVariablePolicy":"off"}' ;;
    team-policy-missing) printf '%s' '{"id":"team_dev123"}' ;;
    team-policy-null) printf '%s' '{"id":"team_dev123","sensitiveEnvironmentVariablePolicy":null}' ;;
    team-policy-unexpected-string) printf '%s' '{"id":"team_dev123","sensitiveEnvironmentVariablePolicy":"unexpected"}' ;;
    team-policy-non-string) printf '%s' '{"id":"team_dev123","sensitiveEnvironmentVariablePolicy":true}' ;;
    team-policy-number) printf '%s' '{"id":"team_dev123","sensitiveEnvironmentVariablePolicy":42}' ;;
    team-policy-object) printf '%s' '{"id":"team_dev123","sensitiveEnvironmentVariablePolicy":{}}' ;;
    team-policy-array) printf '%s' '{"id":"team_dev123","sensitiveEnvironmentVariablePolicy":[]}' ;;
    team-policy-malformed) printf '%s' '{"id":42,"sensitiveEnvironmentVariablePolicy":"on"}' ;;
    team-policy-mismatch) printf '%s' '{"id":"team_other123","sensitiveEnvironmentVariablePolicy":"on"}' ;;
    team-policy-fetch-failure) exit 7 ;;
    *) printf '%s' '{"id":"team_dev123","sensitiveEnvironmentVariablePolicy":"on"}' ;;
  esac
elif [[ "$url" == *"/v9/projects/$VERCEL_PROJECT_ID"* ]]; then
  if [[ "$scenario" == project-mismatch ]]; then
    jq '.name = "llm-wiki-frontend"' "$root/project.json"
  elif [[ "$scenario" == team-mismatch ]]; then
    jq '.accountId = "team_main123"' "$root/project.json"
  else
    cat "$root/project.json"
  fi
elif [[ "$url" == *"/v13/deployments/dpl_"* && "$url" != *"/v13/deployments?"* ]]; then
  if [[ "$scenario" == create-read-failure ]]; then exit 7; fi
  response="$(jq -c --arg team "$VERCEL_TEAM_ID" '.ownerId = $team | del(.teamId) | .url = (.url | sub("^https?://"; ""))' "$root/deployment.json")"
  if [[ "$scenario" == create-poll-timeout ]]; then
    response="$(jq '.readyState = "BUILDING"' <<< "$response")"
  elif [[ "$scenario" == create-source-mismatch ]]; then
    response="$(jq '.meta.githubCommitRef = "release"' <<< "$response")"
  elif [[ "$scenario" == existing-source-mismatch ]]; then
    response="$(jq '.meta.githubCommitRef = "release"' <<< "$response")"
  elif [[ "$scenario" == marker-mismatch ]]; then
    response="$(jq '.meta.lwcAuthEnvProvenance = "lwc-auth-env-v1:wrong"' <<< "$response")"
  elif [[ "$scenario" == post-read-mismatch && -f "$root/mutated" ]]; then
    response="$(jq '.projectId = "prj_other"' <<< "$response")"
  fi
  printf '%s' "$response"
elif [[ "$url" == *"/v6/deployments?"* ]]; then
  case "$scenario" in
    deployment-missing|create-failure|create-uncertain|create-poll-timeout|create-source-mismatch|create-read-failure)
      printf '%s' '{"deployments":[]}'
      ;;
    historical-deployment)
      normalize_v6_deployment <<< "$(jq '.meta.githubCommitSha = "fedcba9876543210fedcba9876543210fedcba98"' "$root/deployment.json")" | jq '{deployments: [.] }'
      ;;
    page-2-exact)
      if [[ "$url" == *"until=cursor-2"* ]]; then
        normalize_v6_deployment <<< "$(cat "$root/deployment.json")" | jq '{deployments: [.] }'
      else
        normalize_v6_deployment <<< "$(jq '.meta.githubCommitSha = "fedcba9876543210fedcba9876543210fedcba98"' "$root/deployment.json")" | jq '{deployments: [.], pagination: {next: "cursor-2"}}'
      fi
      ;;
    *)
      normalize_v6_deployment <<< "$(cat "$root/deployment.json")" | jq '{deployments: [.] }'
      ;;
  esac
elif [[ "$url" == *"/v13/deployments?"* ]]; then
  if [[ "$scenario" == create-failure ]]; then exit 8; fi
  if [[ "$scenario" == create-uncertain ]]; then
    printf '%s\n' "$data" >> "$root/deployment-post-log"
    exit 8
  fi
  printf '%s\n' "$data" >> "$root/deployment-post-log"
  jq --arg marker "$(jq -r '.meta.lwcAuthEnvProvenance // empty' <<< "$data")" '.meta.lwcAuthEnvProvenance = $marker' "$root/deployment.json" > "$root/deployment.json.tmp"
  mv "$root/deployment.json.tmp" "$root/deployment.json"
  if [[ -n "$output" ]]; then printf '%s' '{"id":"dpl_devready"}' > "$output"; [[ "$write_out" == '%{http_code}' ]] && printf '200'; else printf '%s' '{"id":"dpl_devready"}'; fi
elif [[ "$url" == *"/v4/aliases/$STABLE_DOMAIN"* ]]; then
  if [[ "$scenario" == authority-conflict ]]; then
    printf '%s' '{"alias":"wiki.dev.rayer.idv.tw","projectId":"prj_main123","deploymentId":"dpl_mainready"}'
  elif [[ "$scenario" == alias-absent ]]; then
    printf '{"alias":"%s","projectId":"%s","deploymentId":""}' "$STABLE_DOMAIN" "$VERCEL_PROJECT_ID"
  elif [[ "$scenario" == alias-divergent ]]; then
    printf '%s' '{"alias":"different.example","projectId":"prj_dev123","deploymentId":"dpl_devold"}'
  elif [[ "$scenario" == alias-project-mismatch ]]; then
    printf '{"alias":"%s","projectId":"prj_main123","deploymentId":"dpl_mainready"}' "$STABLE_DOMAIN"
  elif [[ "$scenario" == rollback-freeze-failure ]]; then
    exit 7
  elif [[ "$scenario" == post-read-mismatch && -f "$root/mutated" ]]; then
    printf '{"alias":"%s","projectId":"%s","deploymentId":"dpl_other"}' "$STABLE_DOMAIN" "$VERCEL_PROJECT_ID"
  else
    deployment_id="$(jq -r --arg domain "$STABLE_DOMAIN" '.[$domain]' "$root/aliases.json")"
    printf '{"alias":"%s","projectId":"%s","deploymentId":"%s"}' "$STABLE_DOMAIN" "$VERCEL_PROJECT_ID" "$deployment_id"
  fi
elif [[ "$url" == *"/v4/aliases?"* ]]; then
  if [[ "$url" == *"domain="* ]]; then
    printf '%s' '{"aliases":[]}'
  elif [[ "$scenario" == authority-conflict ]]; then
    printf '{"aliases":[{"alias":"%s","projectId":"%s","deploymentId":"dpl_devold"}]}' "$STABLE_DOMAIN" "$VERCEL_PROJECT_ID"
  elif [[ "$scenario" == alias-absent ]]; then
    printf '{"aliases":[{"alias":"%s","projectId":"%s","deploymentId":""}]}' "$STABLE_DOMAIN" "$VERCEL_PROJECT_ID"
  elif [[ "$scenario" == alias-divergent ]]; then
    printf '%s' '{"aliases":[{"alias":"different.example","projectId":"prj_dev123","deploymentId":"dpl_devold"}]}'
  elif [[ "$scenario" == alias-project-mismatch ]]; then
    printf '{"aliases":[{"alias":"%s","projectId":"prj_main123","deploymentId":"dpl_mainready"}]}' "$STABLE_DOMAIN"
  elif [[ "$scenario" == post-read-mismatch && -f "$root/mutated" ]]; then
    printf '{"aliases":[{"alias":"%s","projectId":"%s","deploymentId":"dpl_other"}]}' "$STABLE_DOMAIN" "$VERCEL_PROJECT_ID"
  else
    deployment_id="$(jq -r --arg domain "$STABLE_DOMAIN" '.[$domain]' "$root/aliases.json")"
    printf '{"aliases":[{"alias":"%s","projectId":"%s","deploymentId":"%s"}]}' "$STABLE_DOMAIN" "$VERCEL_PROJECT_ID" "$deployment_id"
  fi
else
  exit 1
fi
