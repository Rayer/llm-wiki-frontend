#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-}"
if [[ "${VERCEL_DEV_DEPLOYMENT_LIBRARY:-}" != 1 && "$MODE" != "validate" && "$MODE" != "preflight" && "$MODE" != "prepare" && "$MODE" != "configure" && "$MODE" != "promote" ]]; then
  printf 'usage: %s {validate|preflight|prepare|configure|promote}\n' "$0" >&2
  exit 2
fi

readonly EXPECTED_REPOSITORY="Rayer/llm-wiki-frontend"
readonly EXPECTED_PROJECT_NAME="llm-wiki-frontend-dev"
readonly EXPECTED_SCOPE="rayer-tung-s-projects"
readonly STABLE_DOMAIN="llm-wiki-frontend-dev.vercel.app"
readonly EXPECTED_REF="develop"
readonly API_BASE_URL="${VERCEL_API_BASE_URL:-https://api.vercel.com}"
readonly GITHUB_BASE_URL="${GITHUB_API_URL:-https://api.github.com}"
readonly EVIDENCE_DIR="${EVIDENCE_DIR:-artifacts/vercel-dev-deployment}"
readonly EVIDENCE_PATH="$EVIDENCE_DIR/vercel-dev-deployment.json"
readonly VALIDATION_PATH="$EVIDENCE_DIR/validation.json"
readonly ROLLBACK_PATH="$EVIDENCE_DIR/rollback-contract.json"
readonly CONTEXT_PATH="${DEV_DEPLOYMENT_CONTEXT_PATH:-$EVIDENCE_DIR/vercel-dev-deployment-context.json}"
readonly POLL_ATTEMPTS="${VERCEL_POLL_ATTEMPTS:-30}"
readonly POLL_INTERVAL="${VERCEL_POLL_INTERVAL_SECONDS:-2}"
readonly ALIAS_TIMEOUT="${VERCEL_ALIAS_TIMEOUT_SECONDS:-15}"
readonly DEPLOYMENT_PAGE_LIMIT=100
readonly DEPLOYMENT_MAX_PAGES=10
readonly AUTH_ENV_PAGE_LIMIT=100
readonly AUTH_ENV_MAX_PAGES=10
readonly AUTH_ENV_PROVENANCE_SCHEMA_VERSION=1
readonly AUTH_ENV_KEY="NEXT_PUBLIC_AUTH_URL"
readonly AUTH_ENV_VALUE="https://auth-dev.rayer.idv.tw"
readonly AUTH_ENV_TYPE="plain"
readonly AUTH_ENV_TARGET="preview"
readonly AUTH_ENV_GIT_BRANCH="develop"
readonly AUTH_ENV_VALUE_SHA256="$(printf '%s' "$AUTH_ENV_VALUE" | sha256sum | awk '{print $1}')"
readonly DEPLOYMENT_AUTH_ENV_MARKER="lwc-auth-env-v${AUTH_ENV_PROVENANCE_SCHEMA_VERSION}:$AUTH_ENV_VALUE_SHA256"
readonly AUTH_ENV_STATE_PATH="$EVIDENCE_DIR/auth-env-state.json"

COMMIT_SHA="${COMMIT_SHA:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
VERCEL_TOKEN="${VERCEL_TOKEN:-}"
VERCEL_PROJECT_ID="${VERCEL_PROJECT_ID:-}"
VERCEL_TEAM_ID="${VERCEL_TEAM_ID:-}"
VERCEL_SCOPE="${VERCEL_SCOPE:-}"
GITHUB_RUN_ID="${GITHUB_RUN_ID:-}"
ORIGINATING_WORKFLOW_RUN_ID="${ORIGINATING_WORKFLOW_RUN_ID:-}"
TICKET_REF="${TICKET_REF:-}"
DEPLOYMENT_ID="${DEPLOYMENT_ID:-}"
DEPLOYMENT_DECISION="deployment_needed"
DEPLOYMENT_CREATED=0
PROJECT_REPOSITORY_ID=""
CI_RUN_ID=""
CI_RUN_URL=""
CURRENT_HEAD_SHA="${CURRENT_HEAD_SHA:-}"
CURRENT_REMOTE_DEVELOP_SHA="${CURRENT_REMOTE_DEVELOP_SHA:-}"
DEPLOYMENT_URL=""
OBSERVED_DEPLOYMENT_ID=""
OBSERVED_DEPLOYMENT_URL=""
OBSERVED_SOURCE=""
OBSERVED_REPOSITORY=""
OBSERVED_REF=""
OBSERVED_SHA=""
OBSERVED_READY_STATE=""
OBSERVED_TARGET=""
OBSERVED_PROJECT_ID=""
OBSERVED_TEAM_ID=""
OBSERVED_PROVENANCE_MARKER=""
FROZEN_ALIAS_DEPLOYMENT_ID=""
OBSERVED_ALIAS_DEPLOYMENT_ID=""
OBSERVED_ALIAS_PROJECT_ID=""
ROLLBACK_ARTIFACT_ID="${ROLLBACK_ARTIFACT_ID:-}"
ROLLBACK_ARTIFACT_URL="${ROLLBACK_ARTIFACT_URL:-}"
ROLLBACK_ARTIFACT_DIGEST="${ROLLBACK_ARTIFACT_DIGEST:-}"
ROLLBACK_CONTRACT_SHA256=""
MUTATION_COUNT=0
AUTH_ENV_PREFLIGHT_STATE=""
AUTH_ENV_CONFIGURED_STATE="not_run"
AUTH_ENV_READBACK_STATE="not_run"
AUTH_ENV_MUTATION_COUNT=0
AUTH_ENV_CURRENT_STATE=""
AUTH_ENV_REASON_CODE="AUTH_ENV_CONFLICT"
AUTH_ENV_STATE=""
AUTH_ENV_STATE_KEY=""
AUTH_ENV_RUN_ID="${ORIGINATING_WORKFLOW_RUN_ID:-$GITHUB_RUN_ID}"
AUTH_ENV_DURABLE_STATE="none"
STATUS="FAILED"
REASON_CODE="UNEXPECTED_FAILURE"
REASON="unexpected failure"
NEXT_ACTION="Inspect normalized evidence and reconcile provider state before retrying."
PROVIDER_CHECKS='[]'
EVIDENCE_WRITTEN=0

string_or_null() {
  if [[ -n "${1:-}" ]]; then printf '%s' "$1"; else printf 'null'; fi
}

write_evidence() {
  [[ "$EVIDENCE_WRITTEN" -eq 1 ]] && return
  EVIDENCE_WRITTEN=1
  mkdir -p "$EVIDENCE_DIR"
  jq -n \
    --arg ticketRef "$TICKET_REF" \
    --arg commitSha "$COMMIT_SHA" \
    --arg expectedRef "refs/heads/$EXPECTED_REF" \
    --arg currentHead "$CURRENT_HEAD_SHA" \
    --arg currentRemote "$CURRENT_REMOTE_DEVELOP_SHA" \
    --arg ciRunId "$CI_RUN_ID" \
    --arg ciRunUrl "$CI_RUN_URL" \
    --arg deploymentId "$DEPLOYMENT_ID" \
    --arg deploymentUrl "$DEPLOYMENT_URL" \
    --arg observedDeploymentId "$OBSERVED_DEPLOYMENT_ID" \
    --arg observedDeploymentUrl "$OBSERVED_DEPLOYMENT_URL" \
    --arg observedSource "$OBSERVED_SOURCE" \
    --arg observedRepository "$OBSERVED_REPOSITORY" \
    --arg observedRef "$OBSERVED_REF" \
    --arg observedSha "$OBSERVED_SHA" \
    --arg observedReadyState "$OBSERVED_READY_STATE" \
    --arg observedTarget "$OBSERVED_TARGET" \
    --arg observedProjectId "$OBSERVED_PROJECT_ID" \
    --arg observedTeamId "$OBSERVED_TEAM_ID" \
    --arg observedProvenanceMarker "$OBSERVED_PROVENANCE_MARKER" \
    --arg stableDomain "$STABLE_DOMAIN" \
    --arg targetProjectId "$VERCEL_PROJECT_ID" \
    --arg targetTeamId "$VERCEL_TEAM_ID" \
    --arg frozenAliasDeploymentId "$FROZEN_ALIAS_DEPLOYMENT_ID" \
    --arg observedAliasDeploymentId "$OBSERVED_ALIAS_DEPLOYMENT_ID" \
    --arg observedAliasProjectId "$OBSERVED_ALIAS_PROJECT_ID" \
    --arg rollbackArtifactId "$ROLLBACK_ARTIFACT_ID" \
    --arg rollbackArtifactUrl "$ROLLBACK_ARTIFACT_URL" \
    --arg rollbackArtifactDigest "$ROLLBACK_ARTIFACT_DIGEST" \
    --arg rollbackContractSha256 "$ROLLBACK_CONTRACT_SHA256" \
    --arg authEnvPreflightState "$AUTH_ENV_PREFLIGHT_STATE" \
    --arg authEnvConfiguredState "$AUTH_ENV_CONFIGURED_STATE" \
    --arg authEnvReadbackState "$AUTH_ENV_READBACK_STATE" \
    --arg authEnvMutationCount "$AUTH_ENV_MUTATION_COUNT" \
    --arg authEnvValueSha "$AUTH_ENV_VALUE_SHA256" \
    --arg status "$STATUS" \
    --arg reasonCode "$REASON_CODE" \
    --arg reason "$REASON" \
    --arg nextAction "$NEXT_ACTION" \
    --argjson providerChecks "$PROVIDER_CHECKS" \
    --arg mutationCount "$MUTATION_COUNT" \
    'def num_or_null: if test("^[0-9]+$") then tonumber else null end;
     def str_or_null: if . == "" then null else . end;
     {
       schema_version: 1,
       ticket_ref: $ticketRef | str_or_null,
       environment: "development",
       action: "deploy_and_promote",
       source: {
         commit_sha: $commitSha | str_or_null,
         ref: $expectedRef,
         checked_out_sha: $currentHead | str_or_null,
         current_remote_develop_sha: $currentRemote | str_or_null,
         canonical_ci: {
           workflow: "ci.yml",
           head_branch: "develop",
           head_sha: $commitSha | str_or_null,
           conclusion: (if $ciRunId == "" then null else "success" end),
           run_id: ($ciRunId | num_or_null),
           run_url: ($ciRunUrl | str_or_null)
         }
       },
       target: {
         project_name: "llm-wiki-frontend-dev",
         project_id: ($targetProjectId | str_or_null),
         team_id: ($targetTeamId | str_or_null),
         stable_domain: $stableDomain
       },
       auth_env: {
         key: "NEXT_PUBLIC_AUTH_URL",
         target: ["preview"],
         git_branch: "develop",
         expected_value_sha256: $authEnvValueSha,
         preflight_state: ($authEnvPreflightState | str_or_null),
         configured_state: ($authEnvConfiguredState | str_or_null),
         readback_state: ($authEnvReadbackState | str_or_null),
         mutation_count: ($authEnvMutationCount | num_or_null)
       },
       deployment: {
         id: ($deploymentId | str_or_null),
         url: ($deploymentUrl | str_or_null),
         source: ($observedSource | str_or_null),
         repository: ($observedRepository | str_or_null),
         ref: ($observedRef | str_or_null),
         commit_sha: ($observedSha | str_or_null),
         ready_state: ($observedReadyState | str_or_null),
         target: ($observedTarget | str_or_null),
         project_id: ($observedProjectId | str_or_null),
         team_id: ($observedTeamId | str_or_null),
         auth_env_provenance_marker: ($observedProvenanceMarker | str_or_null)
       },
       rollback: {
         alias: $stableDomain,
         deployment_id: ($frozenAliasDeploymentId | str_or_null),
         artifact: "rollback-contract.json",
         artifact_id: ($rollbackArtifactId | num_or_null),
         artifact_url: ($rollbackArtifactUrl | str_or_null),
         artifact_digest: ($rollbackArtifactDigest | str_or_null),
         contract_sha256: ($rollbackContractSha256 | str_or_null)
       },
       observed_alias: {
         alias: $stableDomain,
         project_id: ($observedAliasProjectId | str_or_null),
         deployment_id: ($observedAliasDeploymentId | str_or_null)
       },
       provider_verification: {
         checks: $providerChecks,
         mutation_count: ($mutationCount | num_or_null)
       },
       status: $status,
       reason_code: $reasonCode,
       reason: $reason,
       next_action: $nextAction
     }' > "$EVIDENCE_PATH.tmp"
  mv "$EVIDENCE_PATH.tmp" "$EVIDENCE_PATH"
}

if [[ "${VERCEL_DEV_DEPLOYMENT_LIBRARY:-}" != 1 ]]; then
  trap 'exit_code=$?; write_evidence; exit "$exit_code"' EXIT
fi

fail() {
  STATUS="$1"
  REASON_CODE="$2"
  REASON="$3"
  NEXT_ACTION="$4"
  printf '%s: %s\n' "$REASON_CODE" "$REASON" >&2
  exit 1
}

preflight_fail() { fail "PREFLIGHT_FAILED" "$1" "$2" "Correct the validated input or read-only provider state; no DEV alias mutation was attempted."; }
partial_fail() { fail "PARTIAL_MUTATION" "$1" "$2" "Reconcile the exact DEV alias, deployment, and project env read-back before any retry or rollback; do not blindly replay the mutation."; }

validate_inputs() {
  if [[ ! "$COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
    preflight_fail INPUT_SHA_INVALID "commit_sha must be exactly 40 lowercase hexadecimal characters"
  fi
  if [[ -z "$GITHUB_REPOSITORY" || "$GITHUB_REPOSITORY" != "$EXPECTED_REPOSITORY" ]]; then
    preflight_fail REPOSITORY_NOT_ALLOWLISTED "GITHUB_REPOSITORY must equal the exact repository identity"
  fi
  if [[ -n "$TICKET_REF" && ! "$TICKET_REF" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    preflight_fail TICKET_REF_INVALID "ticket_ref contains unsupported characters"
  fi
  if [[ -n "${GITHUB_ACTIONS:-}" && "${GITHUB_ACTIONS:-}" == true && "${LWC253_TEST_MODE:-}" == 1 ]]; then
    preflight_fail TEST_MODE_FORBIDDEN "LWC253_TEST_MODE is forbidden in GitHub Actions"
  fi
  if [[ "${GITHUB_ACTIONS:-}" == true && ( "$API_BASE_URL" != "https://api.vercel.com" || "$GITHUB_BASE_URL" != "https://api.github.com" ) ]]; then
    preflight_fail API_ORIGIN_NOT_ALLOWLISTED "GitHub Actions requires canonical provider API origins"
  fi
  if [[ "${GITHUB_ACTIONS:-}" != true && "${LWC253_TEST_MODE:-}" != 1 && ( "$API_BASE_URL" != "https://api.vercel.com" || "$GITHUB_BASE_URL" != "https://api.github.com" ) ]]; then
    preflight_fail API_ORIGIN_NOT_ALLOWLISTED "API origin overrides require LWC253_TEST_MODE=1 outside GitHub Actions"
  fi
  if [[ "$MODE" != validate ]]; then
    if [[ -z "$VERCEL_TOKEN" || -z "$VERCEL_PROJECT_ID" || -z "$VERCEL_TEAM_ID" || -z "$VERCEL_SCOPE" ]]; then
      preflight_fail CONFIG_MISSING "required DEV Vercel configuration is missing"
    fi
    if [[ ! "$VERCEL_PROJECT_ID" =~ ^prj_[A-Za-z0-9]+$ || ! "$VERCEL_TEAM_ID" =~ ^team_[A-Za-z0-9]+$ ]]; then
      preflight_fail CONFIG_ID_INVALID "DEV project or team configuration is not a bounded Vercel ID"
    fi
    if [[ "$VERCEL_SCOPE" != "$EXPECTED_SCOPE" ]]; then
      preflight_fail TEAM_NOT_ALLOWLISTED "DEV Vercel scope is not the allowlisted team scope"
    fi
    if [[ ! "$POLL_ATTEMPTS" =~ ^[1-9][0-9]*$ || "$POLL_ATTEMPTS" -gt 60 || ! "$POLL_INTERVAL" =~ ^[0-9]+$ || "$POLL_INTERVAL" -gt 60 ]]; then
      preflight_fail POLL_BOUNDS_INVALID "deployment polling bounds are invalid"
    fi
    if [[ ! "$ALIAS_TIMEOUT" =~ ^[1-9][0-9]*$ || "$ALIAS_TIMEOUT" -gt 300 ]]; then
      preflight_fail ALIAS_TIMEOUT_INVALID "DEV alias mutation timeout is not bounded"
    fi
    for command in curl jq sha256sum timeout vercel; do
      command -v "$command" >/dev/null 2>&1 || preflight_fail TOOL_MISSING "required command is unavailable: $command"
    done
    AUTH_ENV_STATE_KEY="$(printf '%s' "$(jq -cn --arg repository "$GITHUB_REPOSITORY" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg scope "$VERCEL_SCOPE" --arg key "$AUTH_ENV_KEY" --arg target "$AUTH_ENV_TARGET" --arg valueSha "$AUTH_ENV_VALUE_SHA256" '{repository: $repository, project_id: $project, team_id: $team, scope: $scope, key: $key, target: [$target], value_sha256: $valueSha}')" | sha256sum | awk '{print $1}')"
  else
    for command in curl jq; do
      command -v "$command" >/dev/null 2>&1 || preflight_fail TOOL_MISSING "required command is unavailable: $command"
    done
  fi
}

read_durable_auth_env_state() {
  local page=1 response page_count artifact_count total_count prefix
  local -i max_pages=10
  prefix="vercel-dev-auth-state-${AUTH_ENV_STATE_KEY}-"
  AUTH_ENV_DURABLE_STATE="none"
  while (( page <= max_pages )); do
    response="$(github_query "/repos/$GITHUB_REPOSITORY/actions/artifacts?per_page=100&page=$page")" || return 1
    jq -e 'type == "object" and (.artifacts | type == "array") and (.total_count | type == "number" and floor == . and . >= 0)' <<< "$response" >/dev/null || return 1
    jq -e --arg prefix "$prefix" '
      [.artifacts[] | select(.name | startswith($prefix)) |
        (.expired == true) or
        (.expired == false and (.workflow_run.id | type == "number" and floor == .) and
          (.name | test("^" + $prefix + "[0-9]+-(create_attempted|create_uncertain|terminal_exact|already_exact)$")))] |
      all(.[]; . == true)
    ' <<< "$response" >/dev/null || return 1
    page_count="$(jq '.artifacts | length' <<< "$response")"
    artifact_count="$(jq --arg prefix "$prefix" '[.artifacts[] | select((.name | startswith($prefix)) and .expired == false)] | length' <<< "$response")"
    if [[ "$artifact_count" != 0 ]]; then
      if jq -e --arg prefix "$prefix" --arg runId "$AUTH_ENV_RUN_ID" '
        any(.artifacts[]; ((.name | startswith($prefix)) and .expired == false and (.workflow_run.id | tostring) != $runId and (.name | test("-(create_attempted|create_uncertain)$"))))
      ' <<< "$response" >/dev/null; then
        AUTH_ENV_DURABLE_STATE="uncertain"
      elif jq -e --arg prefix "$prefix" '
        any(.artifacts[]; ((.name | startswith($prefix)) and .expired == false and (.name | test("-terminal_exact$"))))
      ' <<< "$response" >/dev/null && [[ "$AUTH_ENV_DURABLE_STATE" != uncertain ]]; then
        AUTH_ENV_DURABLE_STATE="terminal_exact"
      fi
    fi
    total_count="$(jq -r '.total_count' <<< "$response")"
    if (( page_count < AUTH_ENV_PAGE_LIMIT || page * AUTH_ENV_PAGE_LIMIT >= total_count )); then
      return 0
    fi
    page=$((page + 1))
  done
  return 1
}

write_github_output() {
  local state_suffix="$AUTH_ENV_STATE"
  [[ "$AUTH_ENV_CONFIGURED_STATE" == already_exact ]] && state_suffix="already_exact"
  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  printf 'state_key=%s\nstate_suffix=%s\n' "$AUTH_ENV_STATE_KEY" "$state_suffix" >> "$GITHUB_OUTPUT"
}

github_query() {
  curl --fail-with-body --silent --show-error --location \
    --connect-timeout 10 --max-time 30 \
    --header "Authorization: Bearer $GITHUB_TOKEN" \
    --header 'Accept: application/vnd.github+json' \
    "$GITHUB_BASE_URL$1" 2>/dev/null
}

api_query() {
  curl --fail-with-body --silent --show-error --location \
    --connect-timeout 10 --max-time 30 \
    --header "Authorization: Bearer $VERCEL_TOKEN" \
    --header 'Accept: application/json' \
    "$API_BASE_URL$1" 2>/dev/null
}

api_post() {
  curl --fail-with-body --silent --show-error --location \
    --connect-timeout 10 --max-time 30 --request POST \
    --header "Authorization: Bearer $VERCEL_TOKEN" \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --data "$2" "$API_BASE_URL$1" 2>/dev/null
}

read_auth_env() {
  local cursor="" query response page='[]' inventory='{"envs":[]}' next pages=0 encoded
  while (( pages < AUTH_ENV_MAX_PAGES )); do
    query="/v10/projects/$VERCEL_PROJECT_ID/env?gitBranch=$AUTH_ENV_GIT_BRANCH&teamId=$VERCEL_TEAM_ID&limit=$AUTH_ENV_PAGE_LIMIT"
    if [[ -n "$cursor" ]]; then
      encoded="$(printf '%s' "$cursor" | jq -Rr @uri)"
      query+="&until=$encoded"
    fi
    response="$(api_query "$query")" || return 1
    jq -e 'type == "object" and (.envs | type == "array") and ((has("pagination") | not) or (.pagination | type == "object")) and ((.pagination.next == null) or (.pagination.next | type == "string"))' <<< "$response" >/dev/null || return 1
    page="$(jq -c '.envs' <<< "$response")" || return 1
    inventory="$(jq -cn --argjson current "$(jq -c '.envs' <<< "$inventory")" --argjson page "$page" '{envs: ($current + $page)}')"
    next="$(jq -r '.pagination.next // empty' <<< "$response")"
    [[ -n "$next" ]] || { printf '%s' "$inventory"; return 0; }
    [[ "$next" != "$cursor" ]] || return 1
    cursor="$next"
    pages=$((pages + 1))
  done
  return 1
}

classify_auth_env() {
  local response="$1" records count exact_count
  records="$(jq -c 'if type == "object" and (.envs | type == "array") then .envs else empty end' <<< "$response" 2>/dev/null)" || return 1
  [[ -n "$records" ]] || return 1
  count="$(jq --arg key "$AUTH_ENV_KEY" '[.[] | select(.key == $key)] | length' <<< "$records")"
  if [[ "$count" == 0 ]]; then
    AUTH_ENV_CURRENT_STATE="absent"
    return 0
  fi
  exact_count="$(jq --arg key "$AUTH_ENV_KEY" --arg value "$AUTH_ENV_VALUE" --arg type "$AUTH_ENV_TYPE" --arg target "$AUTH_ENV_TARGET" --arg branch "$AUTH_ENV_GIT_BRANCH" '[.[] | select(.key == $key and .value == $value and .type == $type and .gitBranch == $branch and (.target | type == "array" and length == 1 and .[0] == $target))] | length' <<< "$records")"
  if [[ "$count" -gt 1 ]]; then
    if [[ "$exact_count" == "$count" ]]; then
      AUTH_ENV_REASON_CODE="AUTH_ENV_DUPLICATE"
    elif jq -e --arg key "$AUTH_ENV_KEY" '[.[] | select(.key == $key) | (.target // []) | if type == "array" then any(.[]; . == "preview") else false end] | any' <<< "$records" >/dev/null; then
      AUTH_ENV_REASON_CODE="AUTH_ENV_AMBIGUOUS"
    else
      AUTH_ENV_REASON_CODE="AUTH_ENV_METADATA_MISMATCH"
    fi
    return 1
  fi
  if [[ "$exact_count" == 1 ]]; then
    AUTH_ENV_CURRENT_STATE="exact"
    return 0
  fi
  if jq -e --arg key "$AUTH_ENV_KEY" --arg value "$AUTH_ENV_VALUE" '[.[] | select(.key == $key and .value != $value)] | length == 1' <<< "$records" >/dev/null; then
    AUTH_ENV_REASON_CODE="AUTH_ENV_VALUE_MISMATCH"
  else
    AUTH_ENV_REASON_CODE="AUTH_ENV_METADATA_MISMATCH"
  fi
  return 1
}

read_and_classify_auth_env() {
  local response
  response="$(read_auth_env)" || return 2
  classify_auth_env "$response" || return 1
}

write_auth_env_state() {
  jq -n \
    --arg state "$AUTH_ENV_STATE" \
    --arg repository "$GITHUB_REPOSITORY" \
    --arg project "$VERCEL_PROJECT_ID" \
    --arg team "$VERCEL_TEAM_ID" \
    --arg scope "$VERCEL_SCOPE" \
    --arg preflight "$AUTH_ENV_PREFLIGHT_STATE" \
    --arg configured "$AUTH_ENV_CONFIGURED_STATE" \
    --arg readback "$AUTH_ENV_READBACK_STATE" \
    --arg mutationCount "$AUTH_ENV_MUTATION_COUNT" \
    --arg valueSha "$AUTH_ENV_VALUE_SHA256" \
    --arg runId "$AUTH_ENV_RUN_ID" \
    --argjson providerChecks "$PROVIDER_CHECKS" \
    '{schema_version: 2, kind: "vercel-dev-auth-env-state", state: $state, repository: $repository, project_id: $project, team_id: $team, scope: $scope, key: "NEXT_PUBLIC_AUTH_URL", target: ["preview"], git_branch: "develop", expected_value_sha256: $valueSha, workflow_run_id: $runId, provider_checks: $providerChecks, preflight_state: ($preflight | if . == "" then null else . end), configured_state: ($configured | if . == "" then null else . end), readback_state: ($readback | if . == "" then null else . end), mutation_count: ($mutationCount | tonumber)}' > "$AUTH_ENV_STATE_PATH.tmp"
  mv "$AUTH_ENV_STATE_PATH.tmp" "$AUTH_ENV_STATE_PATH"
}

load_auth_env_state() {
  [[ -f "$AUTH_ENV_STATE_PATH" ]] || preflight_fail AUTH_ENV_STATE_MISSING "validated DEV Auth env state is missing"
  jq -e --arg repository "$GITHUB_REPOSITORY" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg scope "$VERCEL_SCOPE" --arg valueSha "$AUTH_ENV_VALUE_SHA256" --arg runId "$AUTH_ENV_RUN_ID" '
    .schema_version == 2 and .kind == "vercel-dev-auth-env-state" and (.state == "preflight" or .state == "create_attempted" or .state == "create_uncertain" or .state == "terminal_exact") and
    .repository == $repository and .project_id == $project and .team_id == $team and .scope == $scope and .key == "NEXT_PUBLIC_AUTH_URL" and .target == ["preview"] and .git_branch == "develop" and .expected_value_sha256 == $valueSha and .workflow_run_id == $runId and
    (.provider_checks | type == "array") and (.preflight_state == "absent" or .preflight_state == "exact") and (.configured_state | type == "string") and (.readback_state | type == "string") and (.mutation_count | type == "number" and . >= 0 and floor == .)' "$AUTH_ENV_STATE_PATH" >/dev/null ||
    preflight_fail AUTH_ENV_STATE_INVALID "validated DEV Auth env state was malformed"
  AUTH_ENV_STATE="$(jq -r '.state' "$AUTH_ENV_STATE_PATH")"
  AUTH_ENV_PREFLIGHT_STATE="$(jq -r '.preflight_state' "$AUTH_ENV_STATE_PATH")"
  AUTH_ENV_CONFIGURED_STATE="$(jq -r '.configured_state' "$AUTH_ENV_STATE_PATH")"
  AUTH_ENV_READBACK_STATE="$(jq -r '.readback_state' "$AUTH_ENV_STATE_PATH")"
  AUTH_ENV_MUTATION_COUNT="$(jq -r '.mutation_count' "$AUTH_ENV_STATE_PATH")"
  local state_provider_checks
  state_provider_checks="$(jq -c '.provider_checks' "$AUTH_ENV_STATE_PATH")"
  PROVIDER_CHECKS="$(jq -cn --argjson current "$PROVIDER_CHECKS" --argjson extra "$state_provider_checks" '$current + $extra | unique')"
  MUTATION_COUNT="$AUTH_ENV_MUTATION_COUNT"
}

validate_durable_auth_env_state() {
  read_durable_auth_env_state || preflight_fail AUTH_ENV_DURABLE_READ_FAILED "durable DEV Auth env state could not be read from GitHub Actions artifacts"
  if [[ "$AUTH_ENV_DURABLE_STATE" == uncertain ]]; then
    preflight_fail AUTH_ENV_RECONCILIATION_REQUIRED "a prior DEV Auth env creation has no terminal exact read-back artifact"
  fi
  if [[ "$AUTH_ENV_DURABLE_STATE" == terminal_exact ]]; then
    PROVIDER_CHECKS="$(jq -c '. + ["auth_env_terminal_artifact_available"]' <<< "$PROVIDER_CHECKS")"
  fi
}

validate_auth_env_preflight() {
  if read_and_classify_auth_env; then
    :
  else
    local read_status=$?
    [[ "$read_status" == 2 ]] && preflight_fail AUTH_ENV_READ_FAILED "DEV Auth env metadata read failed"
    preflight_fail "$AUTH_ENV_REASON_CODE" "DEV Auth env metadata was not the exact bounded contract"
  fi
  AUTH_ENV_PREFLIGHT_STATE="$AUTH_ENV_CURRENT_STATE"
  AUTH_ENV_STATE="preflight"
  AUTH_ENV_CONFIGURED_STATE="not_run"
  AUTH_ENV_READBACK_STATE="not_run"
  AUTH_ENV_MUTATION_COUNT=0
  PROVIDER_CHECKS="$(jq -c '. + ["auth_env_preflight_exact"]' <<< "$PROVIDER_CHECKS")"
}

validate_exact_sha() {
  validate_inputs
  if [[ "${LWC253_TEST_MODE:-}" == 1 ]]; then
    CURRENT_HEAD_SHA="${CURRENT_HEAD_SHA:-$COMMIT_SHA}"
    CURRENT_REMOTE_DEVELOP_SHA="${CURRENT_REMOTE_DEVELOP_SHA:-$COMMIT_SHA}"
  else
    CURRENT_HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || preflight_fail CHECKED_OUT_SHA_UNAVAILABLE "checked-out HEAD could not be read"
    CURRENT_REMOTE_DEVELOP_SHA="$(git ls-remote origin refs/heads/develop 2>/dev/null | awk 'NR == 1 { print $1 }')"
  fi
  [[ "$COMMIT_SHA" == "$CURRENT_HEAD_SHA" ]] || preflight_fail CHECKED_OUT_SHA_MISMATCH "requested SHA did not match checked-out HEAD"
  [[ "$COMMIT_SHA" == "$CURRENT_REMOTE_DEVELOP_SHA" ]] || preflight_fail REMOTE_DEVELOP_SHA_MISMATCH "requested SHA did not match current origin/develop HEAD"
  [[ -n "$GITHUB_TOKEN" ]] || preflight_fail GITHUB_TOKEN_MISSING "GITHUB_TOKEN is required for canonical CI read-back"
  local runs ci_run
  runs="$(github_query "/repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$COMMIT_SHA&branch=develop&event=push&per_page=100")" || preflight_fail CI_READ_FAILED "canonical CI read failed"
  ci_run="$(jq -c --arg sha "$COMMIT_SHA" '
    first(.workflow_runs[]? | select(
      .path == ".github/workflows/ci.yml" and
      .head_branch == "develop" and
      .head_sha == $sha and
      .event == "push" and
      .status == "completed" and
      .conclusion == "success" and
      (.id | type) == "number" and
      (.html_url | type) == "string"
    )) // empty' <<< "$runs")"
  [[ -n "$ci_run" ]] || preflight_fail CI_NOT_GREEN "exact develop CI success was not found for commit_sha"
  CI_RUN_ID="$(jq -r '.id' <<< "$ci_run")"
  CI_RUN_URL="$(jq -r '.html_url' <<< "$ci_run")"
  mkdir -p "$EVIDENCE_DIR"
  jq -n --arg sha "$COMMIT_SHA" --arg head "$CURRENT_HEAD_SHA" --arg remote "$CURRENT_REMOTE_DEVELOP_SHA" --arg runId "$CI_RUN_ID" --arg runUrl "$CI_RUN_URL" \
    '{schema_version: 1, status: "VALIDATED", commit_sha: $sha, checked_out_sha: $head, current_remote_develop_sha: $remote, ci_run_id: ($runId | tonumber), ci_run_url: $runUrl}' > "$VALIDATION_PATH.tmp"
  mv "$VALIDATION_PATH.tmp" "$VALIDATION_PATH"
}

validate_project() {
  local project="$1"
  jq -e --arg id "$VERCEL_PROJECT_ID" --arg name "$EXPECTED_PROJECT_NAME" --arg team "$VERCEL_TEAM_ID" '
    type == "object" and .id == $id and .name == $name and ((.accountId // .teamId) == $team)' <<< "$project" >/dev/null ||
    preflight_fail PROJECT_METADATA_MISMATCH "provider project metadata did not identify the allowlisted DEV project and team"
  PROJECT_REPOSITORY_ID="$(jq -r '.link.repoId // empty' <<< "$project")"
  PROVIDER_CHECKS="$(jq -c '. + ["project_metadata_exact"]' <<< "$PROVIDER_CHECKS")"
}

validate_domains() {
  local domains="$1"
  jq -e --arg domain "$STABLE_DOMAIN" '
    type == "object" and (.domains | type == "array" and length == 1 and .[0].name == $domain)' <<< "$domains" >/dev/null ||
    preflight_fail DOMAIN_NOT_ALLOWLISTED "provider domain metadata did not identify the single allowlisted DEV domain"
  PROVIDER_CHECKS="$(jq -c '. + ["project_domain_exact"]' <<< "$PROVIDER_CHECKS")"
}

read_alias() {
  local encoded
  encoded="$(printf '%s' "$STABLE_DOMAIN" | jq -Rr @uri)"
  api_query "/v4/aliases/$encoded?teamId=$VERCEL_TEAM_ID"
}

read_alias_inventory() {
  local cursor="" query response inventory='{"aliases":[]}' next pages=0 encoded
  while (( pages < 10 )); do
    query="/v4/aliases?projectId=$VERCEL_PROJECT_ID&teamId=$VERCEL_TEAM_ID&limit=100"
    if [[ -n "$cursor" ]]; then
      encoded="$(printf '%s' "$cursor" | jq -Rr @uri)"
      query+="&until=$encoded"
    fi
    response="$(api_query "$query")" || return 1
    inventory="$(jq -cn --argjson current "$(jq -c '.aliases // .' <<< "$inventory")" --argjson page "$(jq -c '.aliases // .' <<< "$response")" '{aliases: ($current + $page)}')"
    next="$(jq -r '.pagination.next // empty' <<< "$response")"
    [[ -n "$next" ]] || { printf '%s' "$inventory"; return 0; }
    cursor="$next"
    pages=$((pages + 1))
  done
  return 1
}

read_authority() {
  local alias_response="$1" inventory="$2"
  OBSERVED_ALIAS_DEPLOYMENT_ID="$(jq -r '.deploymentId // empty' <<< "$alias_response")"
  OBSERVED_ALIAS_PROJECT_ID="$(jq -r '.projectId // empty' <<< "$alias_response")"
  jq -e --arg domain "$STABLE_DOMAIN" --arg project "$VERCEL_PROJECT_ID" '
    type == "object" and .alias == $domain and .projectId == $project and ((.deploymentId | type) == "string") and (.deploymentId | test("^dpl_[A-Za-z0-9]+$"))' <<< "$alias_response" >/dev/null ||
    preflight_fail ALIAS_AUTHORITY_CONFLICT "single-alias authority was absent or identified a different project"
  jq -e --arg domain "$STABLE_DOMAIN" --arg project "$VERCEL_PROJECT_ID" --arg deployment "$(jq -r '.deploymentId' <<< "$alias_response")" '
    ((.aliases // .) | map(select(.alias == $domain and .projectId == $project and .deploymentId == $deployment)) | length == 1)' <<< "$inventory" >/dev/null ||
    preflight_fail ALIAS_AUTHORITY_CONFLICT "project-scoped alias inventory disagreed with the exact single-alias authority"
  PROVIDER_CHECKS="$(jq -c '. + ["single_alias_exact","project_alias_inventory_exact"]' <<< "$PROVIDER_CHECKS")"
}

normalize_deployment() {
  local response="$1"
  OBSERVED_DEPLOYMENT_ID="$(jq -r '.id // empty' <<< "$response" 2>/dev/null || true)"
  OBSERVED_DEPLOYMENT_URL="$(jq -r '.url // empty' <<< "$response" 2>/dev/null || true)"
  OBSERVED_SOURCE="$(jq -r '(.gitSource.type // (if .meta.githubDeployment == "1" then "github" else empty end))' <<< "$response" 2>/dev/null || true)"
  OBSERVED_REPOSITORY="$(jq -r 'if (.meta.githubOrg and .meta.githubRepo) then (.meta.githubOrg + "/" + .meta.githubRepo) elif (.gitSource.org and .gitSource.repo) then (.gitSource.org + "/" + .gitSource.repo) else empty end' <<< "$response" 2>/dev/null || true)"
  OBSERVED_REF="$(jq -r '(.gitSource.ref // .meta.githubCommitRef // empty) | if . == "develop" then "refs/heads/develop" else . end' <<< "$response" 2>/dev/null || true)"
  OBSERVED_SHA="$(jq -r '(.gitSource.sha // .meta.githubCommitSha // empty)' <<< "$response" 2>/dev/null || true)"
  OBSERVED_READY_STATE="$(jq -r '.readyState // empty' <<< "$response" 2>/dev/null || true)"
  OBSERVED_TARGET="$(jq -r '(.target // "preview") | tostring' <<< "$response" 2>/dev/null || true)"
  OBSERVED_PROJECT_ID="$(jq -r '.projectId // empty' <<< "$response" 2>/dev/null || true)"
  OBSERVED_TEAM_ID="$(jq -r '(.teamId // .accountId // .ownerId // empty)' <<< "$response" 2>/dev/null || true)"
  OBSERVED_PROVENANCE_MARKER="$(jq -r '.meta.lwcAuthEnvProvenance // empty' <<< "$response" 2>/dev/null || true)"
  DEPLOYMENT_URL="$OBSERVED_DEPLOYMENT_URL"
}

deployment_matches() {
  local response="$1"
  jq -e --arg id "$DEPLOYMENT_ID" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg sha "$COMMIT_SHA" --arg repo "$EXPECTED_REPOSITORY" --arg marker "$DEPLOYMENT_AUTH_ENV_MARKER" '
    type == "object" and .id == $id and .projectId == $project and ((.teamId // .accountId // .ownerId) == $team) and
    .readyState == "READY" and ((.target == null) or .target == "preview") and
    (.gitSource.type // (if .meta.githubDeployment == "1" then "github" else null end)) == "github" and
    ((.gitSource.ref // .meta.githubCommitRef) == "develop" or (.gitSource.ref // .meta.githubCommitRef) == "refs/heads/develop") and
    (.gitSource.sha // .meta.githubCommitSha) == $sha and
    (if (.meta.githubOrg and .meta.githubRepo) then (.meta.githubOrg + "/" + .meta.githubRepo) else (.gitSource.org + "/" + .gitSource.repo) end) == $repo and
    .meta.lwcAuthEnvProvenance == $marker and
    (.url | type == "string" and test("^[A-Za-z0-9._-]+\\.[A-Za-z0-9._-]+$"))' <<< "$response" >/dev/null
}

inspect_deployment() {
  api_query "/v13/deployments/$DEPLOYMENT_ID?teamId=$VERCEL_TEAM_ID"
}

read_deployment_inventory() {
  local cursor="" query response page inventory='{"deployments":[]}' next pages=0 encoded
  while (( pages < DEPLOYMENT_MAX_PAGES )); do
    query="/v6/deployments?projectId=$VERCEL_PROJECT_ID&teamId=$VERCEL_TEAM_ID&limit=$DEPLOYMENT_PAGE_LIMIT"
    if [[ -n "$cursor" ]]; then
      encoded="$(printf '%s' "$cursor" | jq -Rr @uri)"
      query+="&until=$encoded"
    fi
    response="$(api_query "$query")" || return 1
    page="$(jq -c '.deployments // .' <<< "$response")" || return 1
    jq -e 'type == "array"' <<< "$page" >/dev/null || return 1
    jq -e 'all(.[]; type == "object" and (((.id | type == "string") and ((.uid | type) != "string")) or ((.uid | type == "string") and ((.id | type) != "string"))))' <<< "$page" >/dev/null || return 1
    page="$(jq -c 'map(. + {id: (.id // .uid)} | del(.uid))' <<< "$page")"
    inventory="$(jq -cn --argjson current "$(jq -c '.deployments // .' <<< "$inventory")" --argjson page "$page" '{deployments: ($current + $page)}')"
    next="$(jq -r '.pagination.next // empty' <<< "$response")"
    [[ -n "$next" ]] || { printf '%s' "$inventory"; return 0; }
    cursor="$next"
    pages=$((pages + 1))
  done
  return 1
}

find_exact_deployment() {
  local inventory="$1"
  jq -c --arg sha "$COMMIT_SHA" --arg repo "$EXPECTED_REPOSITORY" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg marker "$DEPLOYMENT_AUTH_ENV_MARKER" '
    first((.deployments // .)[]? | select(
      (.id | type == "string" and test("^dpl_[A-Za-z0-9]+$")) and
      (.projectId // "") == $project and
      ((.teamId // "") == "" or .teamId == $team) and
      ((.accountId // "") == "" or .accountId == $team) and
      ((.ownerId // "") == "" or .ownerId == $team) and
      .readyState == "READY" and (.target == null or .target == "preview") and
      (.gitSource.type // (if .meta.githubDeployment == "1" then "github" else null end)) == "github" and
      ((.gitSource.ref // .meta.githubCommitRef // "") == "develop" or (.gitSource.ref // .meta.githubCommitRef // "") == "refs/heads/develop") and
      (.gitSource.sha // .meta.githubCommitSha // "") == $sha and
      (if (.meta.githubOrg and .meta.githubRepo) then (.meta.githubOrg + "/" + .meta.githubRepo) else ((.gitSource.org // "") + "/" + (.gitSource.repo // "")) end) == $repo and
      .meta.lwcAuthEnvProvenance == $marker and
      (.url | type == "string" and test("^[A-Za-z0-9._-]+\\.[A-Za-z0-9._-]+$"))
    )) // empty' <<< "$inventory"
}

reconcile_deployment_inventory() {
  local inventory candidate
  inventory="$(read_deployment_inventory 2>/dev/null)" || return 1
  candidate="$(find_exact_deployment "$inventory")"
  if [[ -n "$candidate" ]]; then
    OBSERVED_DEPLOYMENT_ID="$(jq -r '.id' <<< "$candidate")"
    OBSERVED_DEPLOYMENT_URL="$(jq -r '.url // empty' <<< "$candidate")"
    PROVIDER_CHECKS="$(jq -c '. + ["deployment_inventory_reconciled"]' <<< "$PROVIDER_CHECKS")"
  fi
  return 0
}

deployment_partial_fail() {
  local reason_code="$1" reason="$2"
  reconcile_deployment_inventory || true
  partial_fail "$reason_code" "$reason"
}

create_deployment() {
  local repo_id payload created
  repo_id="$PROJECT_REPOSITORY_ID"
  if [[ -z "$repo_id" ]]; then
    repo_id="$(jq -r '.id // empty' <<< "$(github_query "/repos/$GITHUB_REPOSITORY")" 2>/dev/null || true)"
  fi
  [[ "$repo_id" =~ ^[0-9]+$ ]] || preflight_fail DEPLOYMENT_CREATE_FAILED "exact GitHub repository provenance could not be resolved before DEV deployment creation"
  payload="$(jq -cn --arg project "$VERCEL_PROJECT_ID" --arg repoId "$repo_id" --arg sha "$COMMIT_SHA" --arg marker "$DEPLOYMENT_AUTH_ENV_MARKER" \
    '{name: "llm-wiki-frontend-dev", project: $project, gitSource: {type: "github", repoId: ($repoId | tonumber), ref: "develop", sha: $sha}, meta: {lwcAuthEnvProvenance: $marker}}')"
  MUTATION_COUNT=$((MUTATION_COUNT + 1))
  PROVIDER_CHECKS="$(jq -c '. + ["deployment_create_attempted"]' <<< "$PROVIDER_CHECKS")"
  if ! created="$(api_post "/v13/deployments?teamId=$VERCEL_TEAM_ID&forceNew=1" "$payload")"; then
    deployment_partial_fail DEPLOYMENT_CREATE_UNCERTAIN "provider deployment-create POST failed or became uncertain"
  fi
  DEPLOYMENT_CREATED=1
  DEPLOYMENT_ID="$(jq -r '.id // empty' <<< "$created" 2>/dev/null || true)"
  [[ "$DEPLOYMENT_ID" =~ ^dpl_[A-Za-z0-9]+$ ]] || deployment_partial_fail DEPLOYMENT_CREATE_UNCERTAIN "provider deployment-create response did not return an immutable DEV deployment ID"
  PROVIDER_CHECKS="$(jq -c '. + ["deployment_created"]' <<< "$PROVIDER_CHECKS")"
}

resolve_deployment() {
  local inventory candidate
  if [[ "$DEPLOYMENT_DECISION" == existing ]]; then
    [[ "$DEPLOYMENT_ID" =~ ^dpl_[A-Za-z0-9]+$ ]] || preflight_fail DEPLOYMENT_CONTEXT_INVALID "existing DEV deployment identity was not immutable"
    return 0
  fi
  inventory="$(read_deployment_inventory 2>/dev/null)" || preflight_fail DEPLOYMENT_LIST_FAILED "DEV deployment inventory read failed during promote reconciliation"
  candidate="$(find_exact_deployment "$inventory")"
  if [[ -n "$candidate" ]]; then
    DEPLOYMENT_ID="$(jq -r '.id' <<< "$candidate")"
    DEPLOYMENT_DECISION="existing"
    PROVIDER_CHECKS="$(jq -c '. + ["deployment_reused_after_handoff"]' <<< "$PROVIDER_CHECKS")"
  else
    create_deployment
  fi
}

poll_deployment() {
  [[ "$DEPLOYMENT_ID" =~ ^dpl_[A-Za-z0-9]+$ ]] || {
    if (( DEPLOYMENT_CREATED )); then
      deployment_partial_fail DEPLOYMENT_CREATE_UNCERTAIN "provider deployment identity was not immutable"
    fi
    preflight_fail DEPLOYMENT_INSPECT_FAILED "provider deployment identity was not immutable"
  }
  local attempts=0
  while (( attempts < POLL_ATTEMPTS )); do
    if ! response="$(inspect_deployment 2>/dev/null)"; then
      if (( DEPLOYMENT_CREATED )); then
        deployment_partial_fail DEPLOYMENT_INSPECT_FAILED "DEV deployment inspection failed after creation"
      fi
      preflight_fail DEPLOYMENT_INSPECT_FAILED "DEV deployment inspection failed"
    fi
    normalize_deployment "$response"
    if deployment_matches "$response"; then
      PROVIDER_CHECKS="$(jq -c '. + ["deployment_exact_ready"]' <<< "$PROVIDER_CHECKS")"
      return 0
    fi
    state="$(jq -r '.readyState // empty' <<< "$response" 2>/dev/null || true)"
    if [[ "$state" == ERROR || "$state" == CANCELED || "$state" == FAILED ]]; then
      if (( DEPLOYMENT_CREATED )); then
        deployment_partial_fail DEPLOYMENT_NOT_READY "DEV deployment reached a terminal non-READY state after creation"
      fi
      preflight_fail DEPLOYMENT_NOT_READY "DEV deployment reached a terminal non-READY state"
    fi
    if [[ "$state" == READY ]]; then
      if (( DEPLOYMENT_CREATED )); then
        deployment_partial_fail DEPLOYMENT_SOURCE_MISMATCH "DEV deployment read-back had mismatched source metadata after creation"
      fi
      preflight_fail DEPLOYMENT_SOURCE_MISMATCH "DEV deployment read-back had mismatched source metadata"
    fi
    if [[ "$state" != BUILDING && "$state" != QUEUED && "$state" != INITIALIZING && "$state" != READY ]]; then
      if (( DEPLOYMENT_CREATED )); then
        deployment_partial_fail DEPLOYMENT_SOURCE_MISMATCH "DEV deployment read-back had unknown or mismatched source metadata after creation"
      fi
      preflight_fail DEPLOYMENT_SOURCE_MISMATCH "DEV deployment read-back had unknown or mismatched source metadata"
    fi
    attempts=$((attempts + 1))
    sleep "$POLL_INTERVAL"
  done
  if (( DEPLOYMENT_CREATED )); then
    deployment_partial_fail DEPLOYMENT_POLL_TIMEOUT "DEV deployment did not converge to exact READY state after creation"
  fi
  preflight_fail DEPLOYMENT_POLL_TIMEOUT "DEV deployment did not converge to exact READY state within the bounded poll window"
}

write_rollback_contract() {
  local contract
  contract="$(jq -n --arg sha "$COMMIT_SHA" --arg repo "$EXPECTED_REPOSITORY" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg domain "$STABLE_DOMAIN" --arg target "$DEPLOYMENT_ID" --arg targetUrl "$DEPLOYMENT_URL" --arg decision "$DEPLOYMENT_DECISION" --arg prior "$FROZEN_ALIAS_DEPLOYMENT_ID" --arg authState "$AUTH_ENV_PREFLIGHT_STATE" --arg authSha "$AUTH_ENV_VALUE_SHA256" \
    '{schema_version: 2, kind: "vercel-dev-rollback-contract", source: {repository: $repo, commit_sha: $sha, ref: "refs/heads/develop"}, target: {decision: $decision, deployment_id: ($target | if . == "" then null else . end), url: ($targetUrl | if . == "" then null else . end)}, rollback: {alias: $domain, stable_domain: $domain, deployment_id: $prior, project_id: $project, team_id: $team, auth_env: {preflight_state: $authState, key: "NEXT_PUBLIC_AUTH_URL", target: ["preview"], git_branch: "develop", expected_value_sha256: $authSha}}}')"
  printf '%s' "$contract" > "$ROLLBACK_PATH.tmp"
  mv "$ROLLBACK_PATH.tmp" "$ROLLBACK_PATH"
  ROLLBACK_CONTRACT_SHA256="$(sha256sum "$ROLLBACK_PATH" | awk '{print $1}')"
}

write_context() {
  jq -n --arg sha "$COMMIT_SHA" --arg repo "$EXPECTED_REPOSITORY" --arg ref "refs/heads/$EXPECTED_REF" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg domain "$STABLE_DOMAIN" --arg target "$DEPLOYMENT_ID" --arg decision "$DEPLOYMENT_DECISION" --arg prior "$FROZEN_ALIAS_DEPLOYMENT_ID" --arg mutationCount "$MUTATION_COUNT" --arg authState "$AUTH_ENV_PREFLIGHT_STATE" --arg authSha "$AUTH_ENV_VALUE_SHA256" --argjson providerChecks "$PROVIDER_CHECKS" \
    '{schema_version: 2, phase: "preflight-complete", source: {repository: $repo, commit_sha: $sha, ref: $ref}, target: {decision: $decision, deployment_id: ($target | if . == "" then null else . end)}, frozen_authority: {alias: $domain, stable_domain: $domain, deployment_id: $prior, project_id: $project, team_id: $team}, auth_env: {preflight_state: $authState, key: "NEXT_PUBLIC_AUTH_URL", target: ["preview"], git_branch: "develop", expected_value_sha256: $authSha}, mutation_count: ($mutationCount | tonumber), provider_checks: $providerChecks}' > "$CONTEXT_PATH.tmp"
  mv "$CONTEXT_PATH.tmp" "$CONTEXT_PATH"
}

run_preflight() {
  validate_exact_sha
  validate_durable_auth_env_state
  local project domains alias_response inventory deployment_inventory candidate
  project="$(api_query "/v9/projects/$VERCEL_PROJECT_ID?teamId=$VERCEL_TEAM_ID")" || preflight_fail PROJECT_READ_FAILED "DEV project metadata read failed"
  validate_project "$project"
  domains="$(api_query "/v9/projects/$VERCEL_PROJECT_ID/domains?teamId=$VERCEL_TEAM_ID")" || preflight_fail DOMAIN_READ_FAILED "DEV project domain metadata read failed"
  validate_domains "$domains"
  validate_auth_env_preflight
  alias_response="$(read_alias)" || preflight_fail ALIAS_READ_FAILED "DEV stable alias read failed"
  inventory="$(read_alias_inventory)" || preflight_fail ALIAS_INVENTORY_READ_FAILED "DEV project-scoped alias inventory read failed"
  read_authority "$alias_response" "$inventory"
  FROZEN_ALIAS_DEPLOYMENT_ID="$OBSERVED_ALIAS_DEPLOYMENT_ID"
  deployment_inventory="$(read_deployment_inventory)" || preflight_fail DEPLOYMENT_LIST_FAILED "DEV deployment inventory read failed"
  candidate="$(find_exact_deployment "$deployment_inventory")"
  if [[ -n "$candidate" ]]; then
    DEPLOYMENT_DECISION="existing"
    DEPLOYMENT_ID="$(jq -r '.id' <<< "$candidate")"
    PROVIDER_CHECKS="$(jq -c '. + ["deployment_inventory_exact","deployment_candidate_existing"]' <<< "$PROVIDER_CHECKS")"
  else
    DEPLOYMENT_DECISION="deployment_needed"
    DEPLOYMENT_ID=""
    PROVIDER_CHECKS="$(jq -c '. + ["deployment_inventory_exact","deployment_needed"]' <<< "$PROVIDER_CHECKS")"
  fi
  write_rollback_contract
  write_auth_env_state
  write_context
  STATUS="PREFLIGHT_READY"
  REASON_CODE="PREFLIGHT_READY"
  REASON="exact SHA, canonical CI, allowlisted DEV project/team/domain, frozen alias authority, and read-only deployment decision were validated"
  NEXT_ACTION="Upload rollback-contract.json before running promote."
  printf '%s\n' "$STATUS"
}

run_prepare() {
  validate_inputs
  validate_artifact_handoff
  load_context
  load_auth_env_state
  validate_durable_auth_env_state
  if [[ "$AUTH_ENV_CONFIGURED_STATE" == create_uncertain || "$AUTH_ENV_STATE" == create_uncertain ]]; then
    preflight_fail AUTH_ENV_RECONCILIATION_REQUIRED "prior DEV Auth env creation was uncertain and requires provider reconciliation before retry"
  fi
  if read_and_classify_auth_env; then
    :
  else
    local read_status=$?
    [[ "$read_status" == 2 ]] && preflight_fail AUTH_ENV_READ_FAILED "DEV Auth env metadata read failed before mutation guard"
    preflight_fail "$AUTH_ENV_REASON_CODE" "DEV Auth env metadata was not the exact bounded contract before mutation guard"
  fi
  if [[ "$AUTH_ENV_CURRENT_STATE" == exact ]]; then
    AUTH_ENV_STATE="terminal_exact"
    AUTH_ENV_CONFIGURED_STATE="already_exact"
    AUTH_ENV_READBACK_STATE="exact"
    AUTH_ENV_MUTATION_COUNT=0
    PROVIDER_CHECKS="$(jq -c '. + ["auth_env_already_exact"]' <<< "$PROVIDER_CHECKS")"
  elif [[ "$AUTH_ENV_CURRENT_STATE" == absent ]]; then
    [[ "$AUTH_ENV_DURABLE_STATE" != terminal_exact ]] || preflight_fail AUTH_ENV_RECONCILIATION_REQUIRED "terminal DEV Auth env success state exists but provider read-back is now absent"
    [[ "$AUTH_ENV_PREFLIGHT_STATE" != exact ]] || preflight_fail AUTH_ENV_DRIFT "DEV Auth env changed after exact preflight; refusing to create or overwrite provider state"
    AUTH_ENV_STATE="create_attempted"
    AUTH_ENV_CONFIGURED_STATE="create_attempted"
    AUTH_ENV_READBACK_STATE="not_available"
    AUTH_ENV_MUTATION_COUNT=1
    MUTATION_COUNT=1
    PROVIDER_CHECKS="$(jq -c '. + ["auth_env_create_attempted"]' <<< "$PROVIDER_CHECKS")"
  else
    preflight_fail "$AUTH_ENV_REASON_CODE" "DEV Auth env metadata was not the exact bounded contract before mutation guard"
  fi
  write_auth_env_state
  write_github_output
  STATUS="PREFLIGHT_READY"
  REASON_CODE="PREFLIGHT_READY"
  REASON="durable DEV Auth env mutation guard was materialized before any provider POST"
  NEXT_ACTION="Upload auth-env-state.json before running configure."
  printf '%s\n' "$STATUS"
}

load_context() {
  [[ -f "$CONTEXT_PATH" && -f "$ROLLBACK_PATH" ]] || preflight_fail ROLLBACK_ARTIFACT_MISSING "validated DEV rollback context is missing"
  jq -e --arg sha "$COMMIT_SHA" --arg repo "$EXPECTED_REPOSITORY" --arg ref "refs/heads/$EXPECTED_REF" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg domain "$STABLE_DOMAIN" --arg authSha "$AUTH_ENV_VALUE_SHA256" '
    .schema_version == 2 and .phase == "preflight-complete" and
    .source.repository == $repo and .source.commit_sha == $sha and .source.ref == $ref and
    (.target.decision == "existing" or .target.decision == "deployment_needed") and
    (.target.deployment_id == null or (.target.deployment_id | type == "string" and test("^dpl_[A-Za-z0-9]+$"))) and
    .frozen_authority.alias == $domain and .frozen_authority.stable_domain == $domain and
    .frozen_authority.project_id == $project and .frozen_authority.team_id == $team and
    (.frozen_authority.deployment_id | type == "string" and test("^dpl_[A-Za-z0-9]+$")) and
    (.auth_env.preflight_state == "absent" or .auth_env.preflight_state == "exact") and
    .auth_env.key == "NEXT_PUBLIC_AUTH_URL" and .auth_env.target == ["preview"] and .auth_env.git_branch == "develop" and .auth_env.expected_value_sha256 == $authSha and
    (.mutation_count | type == "number" and . == 0) and (.provider_checks | type == "array")' "$CONTEXT_PATH" >/dev/null ||
    preflight_fail ROLLBACK_CONTEXT_INVALID "DEV rollback context identity did not match the validated request"
  DEPLOYMENT_DECISION="$(jq -r '.target.decision' "$CONTEXT_PATH")"
  DEPLOYMENT_ID="$(jq -r '.target.deployment_id // empty' "$CONTEXT_PATH")"
  FROZEN_ALIAS_DEPLOYMENT_ID="$(jq -r '.frozen_authority.deployment_id' "$CONTEXT_PATH")"
  AUTH_ENV_PREFLIGHT_STATE="$(jq -r '.auth_env.preflight_state' "$CONTEXT_PATH")"
  MUTATION_COUNT="$(jq -r '.mutation_count' "$CONTEXT_PATH")"
  PROVIDER_CHECKS="$(jq -c '.provider_checks' "$CONTEXT_PATH")"
  jq -e --arg sha "$COMMIT_SHA" --arg repo "$EXPECTED_REPOSITORY" --arg ref "refs/heads/$EXPECTED_REF" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg domain "$STABLE_DOMAIN" --arg decision "$DEPLOYMENT_DECISION" --arg target "$DEPLOYMENT_ID" --arg prior "$FROZEN_ALIAS_DEPLOYMENT_ID" --arg authState "$AUTH_ENV_PREFLIGHT_STATE" --arg authSha "$AUTH_ENV_VALUE_SHA256" '
    .schema_version == 2 and .kind == "vercel-dev-rollback-contract" and
    .source.repository == $repo and .source.commit_sha == $sha and .source.ref == $ref and
    .target.decision == $decision and (.target.deployment_id == null or .target.deployment_id == $target) and
    .rollback.alias == $domain and .rollback.stable_domain == $domain and .rollback.project_id == $project and .rollback.team_id == $team and .rollback.deployment_id == $prior and
    .rollback.auth_env.preflight_state == $authState and .rollback.auth_env.key == "NEXT_PUBLIC_AUTH_URL" and .rollback.auth_env.target == ["preview"] and .rollback.auth_env.git_branch == "develop" and .rollback.auth_env.expected_value_sha256 == $authSha' "$ROLLBACK_PATH" >/dev/null ||
    preflight_fail ROLLBACK_ARTIFACT_INVALID "DEV rollback contract identity did not match the validated request"
  ROLLBACK_CONTRACT_SHA256="$(sha256sum "$ROLLBACK_PATH" | awk '{print $1}')"
}

validate_artifact_handoff() {
  if [[ ! "$ROLLBACK_ARTIFACT_ID" =~ ^[1-9][0-9]*$ || ! "$ROLLBACK_ARTIFACT_URL" =~ ^https://github\.com/$EXPECTED_REPOSITORY/actions/runs/[0-9]+/artifacts/[0-9]+$ || ! "$ROLLBACK_ARTIFACT_DIGEST" =~ ^[0-9a-f]{64}$ ]]; then
    preflight_fail ROLLBACK_ARTIFACT_INVALID "durable DEV rollback artifact handoff was missing or malformed"
  fi
}

reconcile_authority() {
  local alias_response inventory
  alias_response="$(read_alias 2>/dev/null)" || return 1
  inventory="$(read_alias_inventory 2>/dev/null)" || return 1
  OBSERVED_ALIAS_DEPLOYMENT_ID="$(jq -r '.deploymentId // empty' <<< "$alias_response" 2>/dev/null || true)"
  OBSERVED_ALIAS_PROJECT_ID="$(jq -r '.projectId // empty' <<< "$alias_response" 2>/dev/null || true)"
  jq -e --arg domain "$STABLE_DOMAIN" --arg project "$VERCEL_PROJECT_ID" --arg expected "$FROZEN_ALIAS_DEPLOYMENT_ID" '
    .alias == $domain and .projectId == $project and .deploymentId == $expected' <<< "$alias_response" >/dev/null || return 1
  jq -e --arg domain "$STABLE_DOMAIN" --arg project "$VERCEL_PROJECT_ID" --arg expected "$FROZEN_ALIAS_DEPLOYMENT_ID" '
    ((.aliases // .) | map(select(.alias == $domain and .projectId == $project and .deploymentId == $expected)) | length == 1)' <<< "$inventory" >/dev/null || return 1
}

alias_set() {
  local error_path
  error_path="$(mktemp)"
  MUTATION_COUNT=$((MUTATION_COUNT + 1))
  PROVIDER_CHECKS="$(jq -c '. + ["alias_mutation_attempted"]' <<< "$PROVIDER_CHECKS")"
  if timeout --signal=TERM --kill-after=5s "${ALIAS_TIMEOUT}s" env -u GITHUB_TOKEN vercel alias set "$DEPLOYMENT_ID" "$STABLE_DOMAIN" --scope "$VERCEL_SCOPE" >/dev/null 2>"$error_path"; then
    rm -f "$error_path"
    return 0
  fi
  rm -f "$error_path"
  return 1
}

create_auth_env() {
  local payload
  payload="$(jq -cn --arg key "$AUTH_ENV_KEY" --arg value "$AUTH_ENV_VALUE" --arg type "$AUTH_ENV_TYPE" --arg target "$AUTH_ENV_TARGET" --arg branch "$AUTH_ENV_GIT_BRANCH" '{key: $key, value: $value, type: $type, target: [$target], gitBranch: $branch}')"
  if [[ "$AUTH_ENV_MUTATION_COUNT" == 0 ]]; then
    MUTATION_COUNT=$((MUTATION_COUNT + 1))
  fi
  AUTH_ENV_MUTATION_COUNT=1
  AUTH_ENV_CONFIGURED_STATE="create_uncertain"
  AUTH_ENV_STATE="create_uncertain"
  PROVIDER_CHECKS="$(jq -c '. + ["auth_env_create_attempted"]' <<< "$PROVIDER_CHECKS")"
  write_auth_env_state
  if ! api_post "/v10/projects/$VERCEL_PROJECT_ID/env?teamId=$VERCEL_TEAM_ID" "$payload" >/dev/null; then
    write_auth_env_state
    partial_fail AUTH_ENV_CREATE_UNCERTAIN "DEV Auth env creation failed or became uncertain"
  fi
  AUTH_ENV_CONFIGURED_STATE="created"
  PROVIDER_CHECKS="$(jq -c '. + ["auth_env_created"]' <<< "$PROVIDER_CHECKS")"
  if read_and_classify_auth_env; then
    :
  else
    local read_status=$?
    AUTH_ENV_READBACK_STATE="not_available"
    write_auth_env_state
    if [[ "$read_status" == 2 ]]; then
      partial_fail AUTH_ENV_READBACK_FAILED "DEV Auth env read-back failed after creation"
    fi
    partial_fail AUTH_ENV_READBACK_MISMATCH "DEV Auth env read-back was not the exact bounded contract after creation"
  fi
  if [[ "$AUTH_ENV_CURRENT_STATE" != exact ]]; then
    AUTH_ENV_READBACK_STATE="not_exact"
    write_auth_env_state
    partial_fail AUTH_ENV_READBACK_MISMATCH "DEV Auth env read-back was not the exact bounded contract after creation"
  fi
  AUTH_ENV_READBACK_STATE="exact"
  AUTH_ENV_STATE="terminal_exact"
  PROVIDER_CHECKS="$(jq -c '. + ["auth_env_exact_readback"]' <<< "$PROVIDER_CHECKS")"
  write_auth_env_state
}

run_configure() {
  validate_inputs
  validate_artifact_handoff
  load_context
  load_auth_env_state
  if [[ "$AUTH_ENV_CONFIGURED_STATE" == create_uncertain ]]; then
    preflight_fail AUTH_ENV_RECONCILIATION_REQUIRED "prior DEV Auth env creation was uncertain; rerun preflight to reconcile provider state before retry"
  fi
  [[ "$AUTH_ENV_STATE" == create_attempted || "$AUTH_ENV_STATE" == terminal_exact ]] ||
    preflight_fail AUTH_ENV_GUARD_MISSING "durable DEV Auth env mutation guard was not uploaded before configuration"
  if read_and_classify_auth_env; then
    :
  else
    local read_status=$?
    [[ "$read_status" == 2 ]] && preflight_fail AUTH_ENV_READ_FAILED "DEV Auth env metadata read failed immediately before configuration"
    preflight_fail "$AUTH_ENV_REASON_CODE" "DEV Auth env metadata was not the exact bounded contract immediately before configuration"
  fi
  if [[ "$AUTH_ENV_CURRENT_STATE" == exact ]]; then
    AUTH_ENV_STATE="terminal_exact"
    AUTH_ENV_CONFIGURED_STATE="already_exact"
    AUTH_ENV_READBACK_STATE="exact"
    AUTH_ENV_MUTATION_COUNT=0
    PROVIDER_CHECKS="$(jq -c '. + ["auth_env_already_exact"]' <<< "$PROVIDER_CHECKS")"
    write_auth_env_state
  elif [[ "$AUTH_ENV_CURRENT_STATE" == absent ]]; then
    if [[ "$AUTH_ENV_PREFLIGHT_STATE" == exact ]]; then
      preflight_fail AUTH_ENV_DRIFT "DEV Auth env changed after exact preflight; refusing to create or overwrite provider state"
    fi
    create_auth_env
  else
    preflight_fail "$AUTH_ENV_REASON_CODE" "DEV Auth env metadata was not the exact bounded contract immediately before configuration"
  fi
  STATUS="SUCCESS"
  REASON_CODE="SUCCESS"
  REASON="exact DEV Auth env configuration was already present or created once and matched read-back"
  NEXT_ACTION="Proceed to DEV deployment promotion."
  printf '%s\n' "$STATUS"
}

run_promote() {
  validate_inputs
  validate_artifact_handoff
  load_context
  load_auth_env_state
  if [[ "$AUTH_ENV_CONFIGURED_STATE" == create_uncertain ]]; then
    preflight_fail AUTH_ENV_RECONCILIATION_REQUIRED "prior DEV Auth env creation was uncertain and requires provider reconciliation before promotion"
  fi
  if read_and_classify_auth_env; then
    :
  else
    local read_status=$?
    [[ "$read_status" == 2 ]] && preflight_fail AUTH_ENV_READ_FAILED "DEV Auth env metadata read failed before promotion"
    preflight_fail AUTH_ENV_NOT_EXACT "DEV Auth env was not the exact bounded contract before promotion"
  fi
  if [[ "$AUTH_ENV_CURRENT_STATE" != exact ]]; then
    AUTH_ENV_READBACK_STATE="$AUTH_ENV_CURRENT_STATE"
    write_auth_env_state
    preflight_fail AUTH_ENV_NOT_EXACT "DEV Auth env was not the exact bounded contract before promotion"
  fi
  AUTH_ENV_READBACK_STATE="exact"
  AUTH_ENV_STATE="terminal_exact"
  PROVIDER_CHECKS="$(jq -c '. + ["auth_env_promotion_gate_exact"]' <<< "$PROVIDER_CHECKS")"
  write_auth_env_state
  if ! reconcile_authority; then
    preflight_fail ROLLBACK_FREEZE_CHANGED "current DEV alias authority no longer matches the frozen rollback handle"
  fi
  resolve_deployment
  poll_deployment
  if ! alias_set; then
    reconcile_authority || true
    partial_fail MUTATION_UNCERTAIN "DEV alias mutation failed or became uncertain"
  fi
  local alias_response inventory deployment_response
  alias_response="$(read_alias 2>/dev/null)" || partial_fail POSTCHECK_MISMATCH "post-mutation DEV alias read failed"
  inventory="$(read_alias_inventory 2>/dev/null)" || partial_fail POSTCHECK_MISMATCH "post-mutation DEV alias inventory read failed"
  OBSERVED_ALIAS_DEPLOYMENT_ID="$(jq -r '.deploymentId // empty' <<< "$alias_response")"
  OBSERVED_ALIAS_PROJECT_ID="$(jq -r '.projectId // empty' <<< "$alias_response")"
  jq -e --arg domain "$STABLE_DOMAIN" --arg project "$VERCEL_PROJECT_ID" --arg target "$DEPLOYMENT_ID" '.alias == $domain and .projectId == $project and .deploymentId == $target' <<< "$alias_response" >/dev/null || partial_fail POSTCHECK_MISMATCH "post-mutation exact alias read-back did not converge"
  jq -e --arg domain "$STABLE_DOMAIN" --arg project "$VERCEL_PROJECT_ID" --arg target "$DEPLOYMENT_ID" '((.aliases // .) | map(select(.alias == $domain and .projectId == $project and .deploymentId == $target)) | length == 1)' <<< "$inventory" >/dev/null || partial_fail POSTCHECK_MISMATCH "post-mutation project alias inventory did not converge"
  deployment_response="$(inspect_deployment 2>/dev/null)" || partial_fail POSTCHECK_MISMATCH "post-mutation DEV deployment inspection failed"
  normalize_deployment "$deployment_response"
  deployment_matches "$deployment_response" || partial_fail POSTCHECK_MISMATCH "post-mutation deployment inspection did not agree with exact READY DEV source"
  PROVIDER_CHECKS="$(jq -c '. + ["post_alias_exact","post_deployment_exact"]' <<< "$PROVIDER_CHECKS")"
  STATUS="SUCCESS"
  REASON_CODE="SUCCESS"
  REASON="one allowlisted DEV alias mutation converged to the exact READY deployment and matched post-readback"
  NEXT_ACTION="No retry is required."
  printf '%s\n' "$STATUS"
}

if [[ "${VERCEL_DEV_DEPLOYMENT_LIBRARY:-}" == 1 ]]; then
  :
elif [[ "$MODE" == validate ]]; then
  validate_exact_sha
  STATUS="VALIDATED"
  REASON_CODE="VALIDATED"
  REASON="requested SHA matched checked-out HEAD, origin/develop, and exact canonical CI success"
  NEXT_ACTION="Proceed to DEV provider preflight."
  printf '%s\n' "$STATUS"
elif [[ "$MODE" == preflight ]]; then
  run_preflight
elif [[ "$MODE" == prepare ]]; then
  run_prepare
elif [[ "$MODE" == configure ]]; then
  run_configure
else
  run_promote
fi
