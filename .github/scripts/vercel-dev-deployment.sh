#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-}"
if [[ "${VERCEL_DEV_DEPLOYMENT_LIBRARY:-}" != 1 && "$MODE" != "validate" && "$MODE" != "preflight" && "$MODE" != "prepare" && "$MODE" != "configure" && "$MODE" != "promote" && "$MODE" != "reconcile-auth-env" && "$MODE" != "bootstrap-domain" ]]; then
  printf 'usage: %s {validate|preflight|prepare|configure|promote|reconcile-auth-env|bootstrap-domain}\n' "$0" >&2
  exit 2
fi

readonly EXPECTED_REPOSITORY="Rayer/llm-wiki-frontend"
readonly EXPECTED_PROJECT_NAME="llm-wiki-frontend-dev"
readonly EXPECTED_SCOPE="rayer-tung-s-projects"
readonly STABLE_DOMAIN="wiki.dev.rayer.idv.tw"
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
readonly AUTH_ENV_VALUE="https://auth.dev.rayer.idv.tw"
readonly AUTH_ENV_TYPE="plain"
readonly AUTH_ENV_TARGET="preview"
readonly AUTH_ENV_GIT_BRANCH="develop"
readonly AUTH_ENV_VALUE_SHA256="$(printf '%s' "$AUTH_ENV_VALUE" | sha256sum | awk '{print $1}')"
readonly DEPLOYMENT_AUTH_ENV_MARKER="lwc-auth-env-v${AUTH_ENV_PROVENANCE_SCHEMA_VERSION}:$AUTH_ENV_VALUE_SHA256"
readonly AUTH_ENV_STATE_PATH="$EVIDENCE_DIR/auth-env-state.json"
readonly AUTH_ENV_ARTIFACT_MAX_ARCHIVE_BYTES=65536
readonly AUTH_ENV_ARTIFACT_MAX_ENTRIES=1
readonly AUTH_ENV_ARTIFACT_MAX_UNCOMPRESSED_BYTES=16384
readonly AUTH_ENV_ARTIFACT_MAX_ENTRY_BYTES=16384

COMMIT_SHA="${COMMIT_SHA:-}"
EXECUTION_COMMIT_SHA="${EXECUTION_COMMIT_SHA:-$COMMIT_SHA}"
ATTEMPT_COMMIT_SHA="${ATTEMPT_COMMIT_SHA:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
VERCEL_TOKEN="${VERCEL_TOKEN:-}"
VERCEL_PROJECT_ID="${VERCEL_PROJECT_ID:-}"
VERCEL_TEAM_ID="${VERCEL_TEAM_ID:-}"
VERCEL_SCOPE="${VERCEL_SCOPE:-}"
GITHUB_RUN_ID="${GITHUB_RUN_ID:-}"
ATTEMPT_RUN_ID="${ATTEMPT_RUN_ID:-}"
ORIGINATING_WORKFLOW_RUN_ID="${ORIGINATING_WORKFLOW_RUN_ID:-}"
TICKET_REF="${TICKET_REF:-}"
DEPLOYMENT_ID="${DEPLOYMENT_ID:-}"
DEPLOYMENT_DECISION="deployment_needed"
DEPLOYMENT_CREATED=0
PROJECT_REPOSITORY_ID=""
CI_RUN_ID=""
CI_RUN_URL=""
PRIOR_RUN_ATTEMPT=""
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
AUTH_ENV_ORIGINAL_RUN_ID="${ORIGINAL_ATTEMPT_RUN_ID:-${ORIGINATING_WORKFLOW_RUN_ID:-$GITHUB_RUN_ID}}"
AUTH_ENV_ORIGINAL_RUN_ATTEMPT="${ORIGINATING_WORKFLOW_RUN_ATTEMPT:-${ORIGINAL_RUN_ATTEMPT:-}}"
AUTH_ENV_DURABLE_STATE="none"
AUTH_ENV_HTTP_STATUS="000"
AUTH_ENV_PROVIDER_ERROR_CODE=""
DOMAIN_CONFIG_EVIDENCE='{}'
LAST_HTTP_STATUS="000"
LAST_PROVIDER_ERROR_CODE=""
ACTION="deploy_and_promote"
RECONCILIATION_TERMINAL_STATE=""
PROVIDER_MUTATION_COUNT=0
ALIAS_DEPLOYMENT_MUTATION_COUNT=0
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
    --arg executionCommitSha "$EXECUTION_COMMIT_SHA" \
    --arg attemptCommitSha "$ATTEMPT_COMMIT_SHA" \
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
    --arg executionRunId "$GITHUB_RUN_ID" \
    --argjson domainConfig "$DOMAIN_CONFIG_EVIDENCE" \
    --arg authEnvPreflightState "$AUTH_ENV_PREFLIGHT_STATE" \
    --arg authEnvConfiguredState "$AUTH_ENV_CONFIGURED_STATE" \
    --arg authEnvReadbackState "$AUTH_ENV_READBACK_STATE" \
    --arg authEnvMutationCount "$AUTH_ENV_MUTATION_COUNT" \
    --arg authEnvState "$AUTH_ENV_STATE" \
    --arg authEnvHttpStatus "$AUTH_ENV_HTTP_STATUS" \
    --arg authEnvProviderErrorCode "$AUTH_ENV_PROVIDER_ERROR_CODE" \
    --arg authEnvValueSha "$AUTH_ENV_VALUE_SHA256" \
    --arg action "$ACTION" \
    --arg status "$STATUS" \
    --arg reasonCode "$REASON_CODE" \
    --arg reason "$REASON" \
    --arg nextAction "$NEXT_ACTION" \
    --argjson providerChecks "$PROVIDER_CHECKS" \
    --arg mutationCount "$MUTATION_COUNT" \
    --arg providerMutationCount "$PROVIDER_MUTATION_COUNT" \
    --arg aliasDeploymentMutationCount "$ALIAS_DEPLOYMENT_MUTATION_COUNT" \
    'def num_or_null: if test("^[0-9]+$") then tonumber else null end;
     def str_or_null: if . == "" then null else . end;
     {
       schema_version: 1,
       ticket_ref: $ticketRef | str_or_null,
       environment: "development",
       action: $action,
       source: (if $action == "reconcile_auth_env" then {
         execution_commit_sha: $executionCommitSha | str_or_null,
         execution_run_id: ($executionRunId | num_or_null),
         attempt_commit_sha: $attemptCommitSha | str_or_null,
         ref: $expectedRef,
         checked_out_sha: $currentHead | str_or_null,
         current_remote_develop_sha: $currentRemote | str_or_null,
         canonical_ci: {
           workflow: "ci.yml",
           head_branch: "develop",
           head_sha: $executionCommitSha | str_or_null,
           conclusion: (if $ciRunId == "" then null else "success" end),
           run_id: ($ciRunId | num_or_null),
           run_url: ($ciRunUrl | str_or_null)
         }
       } else {
         commit_sha: $commitSha | str_or_null,
         execution_commit_sha: $executionCommitSha | str_or_null,
         execution_run_id: ($executionRunId | num_or_null),
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
       } end),
       target: {
         project_name: "llm-wiki-frontend-dev",
         project_id: ($targetProjectId | str_or_null),
         team_id: ($targetTeamId | str_or_null),
         stable_domain: $stableDomain
         ,domain_config: $domainConfig
       },
       auth_env: {
         state: ($authEnvState | str_or_null),
         key: "NEXT_PUBLIC_AUTH_URL",
         target: ["preview"],
         git_branch: "develop",
         expected_value_sha256: $authEnvValueSha,
         preflight_state: ($authEnvPreflightState | str_or_null),
         configured_state: ($authEnvConfiguredState | str_or_null),
         readback_state: ($authEnvReadbackState | str_or_null),
         mutation_count: ($authEnvMutationCount | num_or_null),
         http_status: ($authEnvHttpStatus | num_or_null),
         provider_error_code: ($authEnvProviderErrorCode | str_or_null)
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
         mutation_count: ($mutationCount | num_or_null),
         provider_mutation_count: ($providerMutationCount | num_or_null),
         alias_deployment_mutation_count: ($aliasDeploymentMutationCount | num_or_null)
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
  if [[ "$MODE" == reconcile-auth-env ]]; then
    if [[ ! "$EXECUTION_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
      preflight_fail EXECUTION_SHA_INVALID "execution_commit_sha must be exactly 40 lowercase hexadecimal characters"
    fi
    if [[ ! "$ATTEMPT_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
      preflight_fail ATTEMPT_SHA_INVALID "attempt_commit_sha must be exactly 40 lowercase hexadecimal characters"
    fi
    COMMIT_SHA="$EXECUTION_COMMIT_SHA"
  fi
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
  if [[ "$MODE" == reconcile-auth-env ]]; then
    if [[ ! "$ATTEMPT_RUN_ID" =~ ^[1-9][0-9]*$ || "$ATTEMPT_RUN_ID" == "$GITHUB_RUN_ID" ]]; then
      preflight_fail ATTEMPT_RUN_ID_INVALID "attempt_run_id must be a positive decimal ID different from the current run"
    fi
    if [[ -z "$GITHUB_RUN_ID" || ! "$GITHUB_RUN_ID" =~ ^[1-9][0-9]*$ ]]; then
      preflight_fail CURRENT_RUN_ID_INVALID "current GitHub run ID was missing or malformed"
    fi
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
    local_commands=(curl jq sha256sum timeout vercel unzip head wc)
    if [[ "$MODE" == reconcile-auth-env ]]; then
      local_commands=(curl jq sha256sum unzip head wc)
    fi
    for command in "${local_commands[@]}"; do
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
  local page=1 response page_count total_count prefix page_digest previous_digest
  local artifacts='[]' attempted_runs terminal_runs run attempted_count attempted_owner resolution_count resolution_kind artifact_id artifact_owner artifact_size attempted_id attempted_size attempted_kind
  local latest_run=0 latest_state="" unresolved=0 terminal_attempted_count
  local -i max_pages=10
  prefix="vercel-dev-auth-state-${AUTH_ENV_STATE_KEY}-"
  AUTH_ENV_DURABLE_STATE="none"
  while (( page <= max_pages )); do
    response="$(github_query "/repos/$GITHUB_REPOSITORY/actions/artifacts?per_page=100&page=$page")" || return 1
    jq -e 'type == "object" and (.artifacts | type == "array") and (.total_count | type == "number" and floor == . and . >= 0)' <<< "$response" >/dev/null || return 1
    jq -e --arg prefix "$prefix" '
      [.artifacts[] | select(.name | startswith($prefix)) |
        (.expired == true) or
        (.expired == false and (.id | type == "number" and floor == . and . > 0) and
          (.size_in_bytes | type == "number" and floor == . and . >= 0) and
          (.workflow_run.id | type == "number" and floor == . and . > 0) and
          (.name | test("^" + $prefix + "[0-9]+-(create_attempted|create_uncertain|terminal_exact|terminal_absent|already_exact)$")))] |
      all(.[]; . == true)
    ' <<< "$response" >/dev/null || return 1
    page_digest="$(printf '%s' "$response" | sha256sum | awk '{print $1}')"
    [[ "$page_digest" != "${previous_digest:-}" ]] || return 1
    previous_digest="$page_digest"
    artifacts="$(jq -cn --argjson all "$artifacts" --argjson page "$(jq -c '.artifacts' <<< "$response")" '$all + $page')" || return 1
    total_count="$(jq -r '.total_count' <<< "$response")"
    page_count="$(jq '.artifacts | length' <<< "$response")"
    if (( page_count < AUTH_ENV_PAGE_LIMIT || page * AUTH_ENV_PAGE_LIMIT >= total_count )); then
      break
    fi
    page=$((page + 1))
  done
  (( page <= max_pages )) || return 1
  attempted_runs="$(jq -r --arg prefix "$prefix" '[.[] | select(.expired == false and (.name | startswith($prefix))) | .name | capture(("^" + $prefix) + "(?<run>[0-9]+)-(?<kind>create_attempted|create_uncertain)$").run] | unique | .[]' <<< "$artifacts")"
  terminal_runs="$(jq -r --arg prefix "$prefix" '[.[] | select(.expired == false and (.name | startswith($prefix))) | .name | capture(("^" + $prefix) + "(?<run>[0-9]+)-(?<kind>terminal_exact|terminal_absent|already_exact)$").run] | unique | .[]' <<< "$artifacts")"
  [[ -n "$attempted_runs$terminal_runs" ]] || return 0

  while IFS= read -r run; do
    [[ -n "$run" ]] || continue
    attempted_count="$(jq --arg prefix "$prefix" --arg run "$run" '[.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>create_attempted|create_uncertain)$").id) == $run))] | length' <<< "$artifacts")"
    [[ "$attempted_count" == 1 ]] || return 1
    attempted_owner="$(jq -r --arg prefix "$prefix" --arg run "$run" '.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>create_attempted|create_uncertain)$").id) == $run)) | .workflow_run.id' <<< "$artifacts")"
    [[ "$attempted_owner" == "$run" ]] || return 1
    resolution_count="$(jq --arg prefix "$prefix" --arg run "$run" '[.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>terminal_exact|terminal_absent|already_exact)$").id) == $run))] | length' <<< "$artifacts")"
    if [[ "$resolution_count" == 0 ]]; then
      unresolved=1
      continue
    fi
    [[ "$resolution_count" == 1 ]] || return 1
    attempted_id="$(jq -r --arg prefix "$prefix" --arg run "$run" '.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>create_attempted|create_uncertain)$").id) == $run)) | .id' <<< "$artifacts")"
    attempted_size="$(jq -r --arg prefix "$prefix" --arg run "$run" '.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>create_attempted|create_uncertain)$").id) == $run)) | .size_in_bytes' <<< "$artifacts")"
    attempted_kind="$(jq -r --arg prefix "$prefix" --arg run "$run" '.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>create_attempted|create_uncertain)$").id) == $run)) | .name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>create_attempted|create_uncertain)$").kind' <<< "$artifacts")"
    resolution_kind="$(jq -r --arg prefix "$prefix" --arg run "$run" '.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>terminal_exact|terminal_absent|already_exact)$").id) == $run)) | .name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>terminal_exact|terminal_absent|already_exact)$").kind' <<< "$artifacts")"
    artifact_id="$(jq -r --arg prefix "$prefix" --arg run "$run" '.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>terminal_exact|terminal_absent|already_exact)$").id) == $run)) | .id' <<< "$artifacts")"
    artifact_owner="$(jq -r --arg prefix "$prefix" --arg run "$run" '.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>terminal_exact|terminal_absent|already_exact)$").id) == $run)) | .workflow_run.id' <<< "$artifacts")"
    artifact_size="$(jq -r --arg prefix "$prefix" --arg run "$run" '.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>terminal_exact|terminal_absent|already_exact)$").id) == $run)) | .size_in_bytes' <<< "$artifacts")"
    [[ "$resolution_kind" == terminal_absent ]] && expected_terminal_state="terminal_absent" || expected_terminal_state="terminal_exact"
    if [[ "$artifact_owner" == "$run" ]]; then
      validate_auth_env_artifact "$attempted_id" "$attempted_owner" "$attempted_size" "$run" "$attempted_kind" || return 1
    fi
    validate_auth_env_artifact "$artifact_id" "$artifact_owner" "$artifact_size" "$run" "$expected_terminal_state" || return 1
    if (( run > latest_run )); then
      latest_run="$run"
      latest_state="$expected_terminal_state"
    fi
  done <<< "$attempted_runs"

  while IFS= read -r run; do
    [[ -n "$run" ]] || continue
    terminal_attempted_count="$(jq --arg prefix "$prefix" --arg run "$run" '[.[] | select(.expired == false and (.name | startswith($prefix)) and ((.name | capture(("^" + $prefix) + "(?<id>[0-9]+)-(?<kind>create_attempted|create_uncertain)$").id) == $run))] | length' <<< "$artifacts")"
    [[ "$terminal_attempted_count" == 1 ]] || unresolved=1
  done <<< "$terminal_runs"

  if [[ "$unresolved" == 1 ]]; then
    AUTH_ENV_DURABLE_STATE="uncertain"
  elif [[ "$latest_state" == terminal_exact ]]; then
    AUTH_ENV_DURABLE_STATE="terminal_exact"
  elif [[ "$latest_state" == terminal_absent ]]; then
    AUTH_ENV_DURABLE_STATE="terminal_absent"
  fi
  return 0
}

write_github_output() {
  local state_suffix="$AUTH_ENV_STATE"
  [[ "$AUTH_ENV_CONFIGURED_STATE" == already_exact ]] && state_suffix="already_exact"
  [[ "$MODE" == reconcile-auth-env ]] && state_suffix="$RECONCILIATION_TERMINAL_STATE"
  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  printf 'state_key=%s\nstate_suffix=%s\nterminal_state=%s\n' "$AUTH_ENV_STATE_KEY" "$state_suffix" "$RECONCILIATION_TERMINAL_STATE" >> "$GITHUB_OUTPUT"
}

github_query() {
  curl --fail-with-body --silent --show-error --location \
    --connect-timeout 10 --max-time 30 \
    --header "Authorization: Bearer $GITHUB_TOKEN" \
    --header 'Accept: application/vnd.github+json' \
    "$GITHUB_BASE_URL$1" 2>/dev/null
}

github_download() {
  curl --fail --silent --show-error --location \
    --connect-timeout 10 --max-time 30 --max-filesize "$AUTH_ENV_ARTIFACT_MAX_ARCHIVE_BYTES" \
    --header "Authorization: Bearer $GITHUB_TOKEN" \
    --header 'Accept: application/vnd.github+json' \
    --output "$2" \
    "$GITHUB_BASE_URL$1" 2>/dev/null
}

validate_auth_env_zip() {
  local archive="$1" expected_archive_size="${2:-}" entries entry_count metadata total_uncompressed
  [[ -f "$archive" ]] || return 1
  local archive_size
  archive_size="$(wc -c < "$archive" | awk '{print $1}')"
  [[ "$archive_size" =~ ^[0-9]+$ && "$archive_size" -le "$AUTH_ENV_ARTIFACT_MAX_ARCHIVE_BYTES" ]] || return 1
  [[ -z "$expected_archive_size" || "$archive_size" == "$expected_archive_size" ]] || return 1
  entries="$(unzip -Z1 "$archive" 2>/dev/null || true)"
  entry_count="$(printf '%s\n' "$entries" | awk 'NF { count++ } END { print count + 0 }')"
  [[ "$entry_count" == "$AUTH_ENV_ARTIFACT_MAX_ENTRIES" && "$entries" == "auth-env-state.json" ]] || return 1
  [[ "$entries" != /* && "$entries" != *'../'* && "$entries" != *'/..'* && "$entries" != */ ]] || return 1
  metadata="$(unzip -Z -v "$archive" 2>/dev/null)" || return 1
  total_uncompressed="$(printf '%s\n' "$metadata" | awk -v max="$AUTH_ENV_ARTIFACT_MAX_UNCOMPRESSED_BYTES" -v entryMax="$AUTH_ENV_ARTIFACT_MAX_ENTRY_BYTES" '
    /^  uncompressed size:/ {
      if ($3 !~ /^[0-9]+$/ || $3 > entryMax) bad = 1
      total += $3
      entries++
    }
    /^  Unix file attributes/ {
      attributes++
      if ($NF !~ /^-[rwx-]{9}$/) bad = 1
    }
    END {
      if (bad || entries != 1 || attributes != 1 || total > max) exit 1
      print total
    }')" || return 1
  [[ "$total_uncompressed" =~ ^[0-9]+$ && "$total_uncompressed" -le "$AUTH_ENV_ARTIFACT_MAX_UNCOMPRESSED_BYTES" ]] || return 1
}

validate_auth_env_artifact() (
  local artifact_id="$1" artifact_owner="$2" artifact_size="$3" original_run_id="$4" expected_state="$5"
  local temp_dir archive state_path extracted_size expected_owner expected_workflow_run_id
  local attempt_commit_state execution_commit_state reconciliation_terminal owner_run_sha original_run_sha original_run owner_run owner_workflow expected_execution_commit
  [[ "$artifact_id" =~ ^[1-9][0-9]*$ && "$artifact_owner" =~ ^[1-9][0-9]*$ && "$artifact_size" =~ ^[0-9]+$ && "$artifact_size" -le "$AUTH_ENV_ARTIFACT_MAX_ARCHIVE_BYTES" ]] || exit 1
  if [[ "$expected_state" == terminal_exact || "$expected_state" == terminal_absent ]]; then
    owner_run="$(github_query "/repos/$GITHUB_REPOSITORY/actions/runs/$artifact_owner")" || exit 1
    jq -e --arg owner "$artifact_owner" --arg original "$original_run_id" --arg repository "$GITHUB_REPOSITORY" --arg sha "$EXECUTION_COMMIT_SHA" '
      type == "object" and (.id | tostring) == $owner and .repository.full_name == $repository and .head_sha == $sha and .event == "workflow_dispatch" and
      ((.path == ".github/workflows/vercel-dev-deployment.yml" and (.id | tostring) == $original) or
       (.path == ".github/workflows/vercel-dev-auth-env-reconciliation.yml" and (.id | tostring) != $original))
    ' <<< "$owner_run" >/dev/null || exit 1
    owner_workflow="$(jq -r '.path // empty' <<< "$owner_run")"
    owner_run_sha="$(jq -r '.head_sha // empty' <<< "$owner_run")"
    if [[ "$artifact_owner" != "$original_run_id" ]] && [[ "$owner_workflow" == ".github/workflows/vercel-dev-auth-env-reconciliation.yml" ]]; then
      original_run="$(github_query "/repos/$GITHUB_REPOSITORY/actions/runs/$original_run_id")" || exit 1
      jq -e --arg original "$original_run_id" --arg repository "$GITHUB_REPOSITORY" '
        type == "object" and (.id | tostring) == $original and .repository.full_name == $repository and
        .path == ".github/workflows/vercel-dev-deployment.yml" and .event == "workflow_dispatch" and
        (.head_sha | type == "string" and test("^[0-9a-f]{40}$"))
      ' <<< "$original_run" >/dev/null || exit 1
      original_run_sha="$(jq -r '.head_sha' <<< "$original_run")"
      [[ "$owner_run_sha" =~ ^[0-9a-f]{40}$ ]] || exit 1
      reconciliation_terminal=1
    else
      reconciliation_terminal=0
    fi
    expected_workflow_run_id="$artifact_owner"
  else
    expected_owner="$original_run_id"
    [[ "$artifact_owner" == "$expected_owner" ]] || exit 1
    expected_workflow_run_id="$original_run_id"
    reconciliation_terminal=0
  fi
  expected_execution_commit="$EXECUTION_COMMIT_SHA"
  if [[ "$MODE" == reconcile-auth-env ]] && [[ "$expected_state" == create_attempted || "$expected_state" == create_uncertain ]]; then
    expected_execution_commit="$ATTEMPT_COMMIT_SHA"
  fi
  temp_dir="$(mktemp -d "$EVIDENCE_DIR/auth-env-artifact.XXXXXX")" || exit 1
  trap 'rm -rf -- "$temp_dir"' EXIT
  archive="$temp_dir/artifact.zip"
  github_download "/repos/$GITHUB_REPOSITORY/actions/artifacts/$artifact_id/zip" "$archive" || exit 1
  validate_auth_env_zip "$archive" "$artifact_size" || exit 1
  state_path="$temp_dir/auth-env-state.json"
  unzip -p "$archive" auth-env-state.json | head -c "$((AUTH_ENV_ARTIFACT_MAX_ENTRY_BYTES + 1))" > "$state_path" || exit 1
  extracted_size="$(wc -c < "$state_path" | awk '{print $1}')"
  [[ "$extracted_size" =~ ^[0-9]+$ && "$extracted_size" -le "$AUTH_ENV_ARTIFACT_MAX_ENTRY_BYTES" ]] || exit 1
  attempt_commit_state="$(jq -r '.attempt_commit_sha // empty' "$state_path")"
  execution_commit_state="$(jq -r '.execution_commit_sha // empty' "$state_path")"
  if [[ "$expected_state" == terminal_exact || "$expected_state" == terminal_absent ]]; then
    if [[ "$reconciliation_terminal" == 1 ]]; then
      [[ "$execution_commit_state" == "$owner_run_sha" ]] || exit 1
      [[ "$attempt_commit_state" == "$original_run_sha" ]] || exit 1
      [[ "$execution_commit_state" =~ ^[0-9a-f]{40}$ ]] || exit 1
      [[ "$attempt_commit_state" =~ ^[0-9a-f]{40}$ ]] || exit 1
    else
      if [[ -n "$attempt_commit_state" ]]; then
        original_run="$owner_run"
        jq -e --arg repository "$GITHUB_REPOSITORY" --arg workflow ".github/workflows/vercel-dev-deployment.yml" --arg runId "$original_run_id" --arg sha "$attempt_commit_state" '
          type == "object" and (.id | tostring) == $runId and .repository.full_name == $repository and .path == $workflow and .head_sha == $sha and .event == "workflow_dispatch"
        ' <<< "$original_run" >/dev/null || exit 1
      fi
    fi
  fi
  if [[ "$reconciliation_terminal" == 1 ]]; then
    jq -e --arg repository "$GITHUB_REPOSITORY" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg scope "$VERCEL_SCOPE" --arg valueSha "$AUTH_ENV_VALUE_SHA256" --arg stateKey "$AUTH_ENV_STATE_KEY" --arg owner "$artifact_owner" --arg original "$original_run_id" --arg expectedWorkflowRun "$expected_workflow_run_id" --arg runAttempt "$PRIOR_RUN_ATTEMPT" --arg expectedState "$expected_state" --arg executionCommit "$execution_commit_state" --arg attemptCommit "$attempt_commit_state" '
      type == "object" and .schema_version == 2 and .kind == "vercel-dev-auth-env-state" and .state == $expectedState and
      .repository == $repository and .project_id == $project and .team_id == $team and .scope == $scope and
      .key == "NEXT_PUBLIC_AUTH_URL" and .target == ["preview"] and .git_branch == "develop" and
      .expected_value_sha256 == $valueSha and .state_key == $stateKey and
      (.workflow_run_id | tostring) == $expectedWorkflowRun and
      .execution_commit_sha == $executionCommit and .attempt_commit_sha == $attemptCommit and
      (if $expectedState == "create_attempted" or $expectedState == "create_uncertain" or $owner == $original then
         (.original_run_id == null or (.original_run_id | tostring) == $original) and
         (.original_run_attempt == null or ((.original_run_attempt | tostring | test("^[1-9][0-9]*$")) and ($runAttempt == "" or (.original_run_attempt | tostring) == $runAttempt)))
       else
         (.original_run_id != null and (.original_run_id | tostring) == $original) and
         (.original_run_attempt == null or ((.original_run_attempt | tostring | test("^[1-9][0-9]*$")) and ($runAttempt == "" or (.original_run_attempt | tostring) == $runAttempt)))
       end) and
      (.provider_checks | type == "array") and
      (.mutation_count | type == "number" and floor == . and
        if $expectedState == "create_attempted" or $expectedState == "create_uncertain" then . == 1
        elif $expectedState == "terminal_exact" and $owner == $original then . == 0 or . == 1
        else . == 0 end) and
      ($owner | test("^[1-9][0-9]*$"))
    ' "$state_path" >/dev/null || exit 1
  else
    jq -e --arg repository "$GITHUB_REPOSITORY" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg scope "$VERCEL_SCOPE" --arg valueSha "$AUTH_ENV_VALUE_SHA256" --arg stateKey "$AUTH_ENV_STATE_KEY" --arg owner "$artifact_owner" --arg original "$original_run_id" --arg expectedWorkflowRun "$expected_workflow_run_id" --arg runAttempt "$PRIOR_RUN_ATTEMPT" --arg expectedState "$expected_state" --arg executionCommit "$expected_execution_commit" --arg attemptCommit "$ATTEMPT_COMMIT_SHA" '
      type == "object" and .schema_version == 2 and .kind == "vercel-dev-auth-env-state" and .state == $expectedState and
      .repository == $repository and .project_id == $project and .team_id == $team and .scope == $scope and
      .key == "NEXT_PUBLIC_AUTH_URL" and .target == ["preview"] and .git_branch == "develop" and
      .expected_value_sha256 == $valueSha and
      (.state_key == $stateKey or ($expectedState == "create_attempted" and .state_key == null)) and
      (.workflow_run_id | tostring) == $expectedWorkflowRun and
      (.execution_commit_sha == null or .execution_commit_sha == $executionCommit) and
      ($attemptCommit == "" or .attempt_commit_sha == null or .attempt_commit_sha == $attemptCommit) and
      (if $expectedState == "create_attempted" or $expectedState == "create_uncertain" or $owner == $original then
         (.original_run_id == null or (.original_run_id | tostring) == $original) and
         (.original_run_attempt == null or ((.original_run_attempt | tostring | test("^[1-9][0-9]*$")) and ($runAttempt == "" or (.original_run_attempt | tostring) == $runAttempt)))
       else
         (.original_run_id != null and (.original_run_id | tostring) == $original) and
         (.original_run_attempt == null or ((.original_run_attempt | tostring | test("^[1-9][0-9]*$")) and ($runAttempt == "" or (.original_run_attempt | tostring) == $runAttempt)))
       end) and
      (.provider_checks | type == "array") and
      (.mutation_count | type == "number" and floor == . and
        if $expectedState == "create_attempted" or $expectedState == "create_uncertain" then . == 1
        elif $expectedState == "terminal_exact" and $owner == $original then . == 0 or . == 1
        else . == 0 end) and
      ($owner | test("^[1-9][0-9]*$"))
    ' "$state_path" >/dev/null || exit 1
  fi
)

api_query() {
  curl --fail-with-body --silent --show-error --location \
    --connect-timeout 10 --max-time 30 \
    --header "Authorization: Bearer $VERCEL_TOKEN" \
    --header 'Accept: application/json' \
    "$API_BASE_URL$1" 2>/dev/null
}

sanitize_provider_error_code() {
  local body="$1" code
  code="$(jq -r '(.error.code // .code // .errorCode // empty) | if type == "string" then . else empty end' "$body" 2>/dev/null || true)"
  if [[ "$code" =~ ^[A-Z0-9_]{1,64}$ ]]; then
    printf '%s' "$code"
  else
    printf ''
  fi
}

api_post() {
  local body_path status
  body_path="$(mktemp)"
  LAST_HTTP_STATUS="000"
  LAST_PROVIDER_ERROR_CODE=""
  if ! status="$(curl --silent --show-error --location \
    --connect-timeout 10 --max-time 30 --request POST \
    --header "Authorization: Bearer $VERCEL_TOKEN" \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --data "$2" --output "$body_path" --write-out '%{http_code}' "$API_BASE_URL$1" 2>/dev/null)"; then
    [[ "$status" =~ ^[0-9]{3}$ ]] && LAST_HTTP_STATUS="$status"
    rm -f "$body_path"
    return 1
  fi
  [[ "$status" =~ ^[0-9]{3}$ ]] || status="000"
  LAST_HTTP_STATUS="$status"
  LAST_PROVIDER_ERROR_CODE="$(sanitize_provider_error_code "$body_path")"
  cat "$body_path"
  rm -f "$body_path"
  [[ "$status" =~ ^2[0-9][0-9]$ ]]
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

readonly CANONICAL_DEV_DOMAIN="$STABLE_DOMAIN"

read_bootstrap_domains() {
  api_query "/v9/projects/$VERCEL_PROJECT_ID/domains?teamId=$VERCEL_TEAM_ID"
}

read_domain_config() {
  local encoded
  encoded="$(printf '%s' "$CANONICAL_DEV_DOMAIN" | jq -Rr @uri)"
  api_query "/v6/domains/$encoded/config?teamId=$VERCEL_TEAM_ID&projectIdOrName=$VERCEL_PROJECT_ID"
}

validate_bootstrap_inputs() {
  [[ -n "$VERCEL_TOKEN" && -n "$VERCEL_PROJECT_ID" && -n "$VERCEL_TEAM_ID" && "$VERCEL_SCOPE" == "$EXPECTED_SCOPE" ]] ||
    preflight_fail CONFIG_INVALID "bounded DEV Vercel configuration is missing or not allowlisted"
  [[ "$VERCEL_PROJECT_ID" =~ ^prj_[A-Za-z0-9]+$ && "$VERCEL_TEAM_ID" =~ ^team_[A-Za-z0-9]+$ ]] ||
    preflight_fail CONFIG_ID_INVALID "DEV project or team configuration is not a bounded Vercel ID"
  if [[ "${GITHUB_ACTIONS:-}" == true && "$API_BASE_URL" != "https://api.vercel.com" ]]; then
    preflight_fail API_ORIGIN_NOT_ALLOWLISTED "GitHub Actions requires the canonical Vercel API origin"
  fi
  if [[ "${GITHUB_ACTIONS:-}" != true && "${LWC253_TEST_MODE:-}" != 1 && "$API_BASE_URL" != "https://api.vercel.com" ]]; then
    preflight_fail API_ORIGIN_NOT_ALLOWLISTED "API origin overrides require test mode outside GitHub Actions"
  fi
  for command in curl jq; do
    command -v "$command" >/dev/null 2>&1 || preflight_fail TOOL_MISSING "required command is unavailable: $command"
  done
}

load_bootstrap_validation() {
  [[ -f "$VALIDATION_PATH" ]] || preflight_fail VALIDATION_MISSING "exact SHA and canonical CI validation evidence was missing"
  jq -e --arg sha "$COMMIT_SHA" '
    .schema_version == 1 and .status == "VALIDATED" and .commit_sha == $sha and
    .checked_out_sha == $sha and .current_remote_develop_sha == $sha and
    (.ci_run_id | type == "number" and floor == . and . > 0) and
    (.ci_run_url | type == "string")' "$VALIDATION_PATH" >/dev/null ||
    preflight_fail VALIDATION_MISMATCH "exact SHA and canonical CI validation evidence did not match commit_sha"
  CURRENT_HEAD_SHA="$(jq -r '.checked_out_sha' "$VALIDATION_PATH")"
  CURRENT_REMOTE_DEVELOP_SHA="$(jq -r '.current_remote_develop_sha' "$VALIDATION_PATH")"
  CI_RUN_ID="$(jq -r '.ci_run_id' "$VALIDATION_PATH")"
  CI_RUN_URL="$(jq -r '.ci_run_url' "$VALIDATION_PATH")"
  PROVIDER_CHECKS="$(jq -c '. + ["exact_sha_canonical_ci_validated"]' <<< "$PROVIDER_CHECKS")"
}

classify_bootstrap_domains() {
  local response="$1"
  jq -e --arg domain "$CANONICAL_DEV_DOMAIN" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" '
    type == "object" and (.domains | type == "array") and
    all(.domains[]; type == "object" and (.name | type == "string") and
      ((.projectId == null) or (.projectId | type == "string"))) and
    ([.domains[] | select(.name == $domain)] | length <= 1) and
    all([.domains[] | select(.name == $domain)][];
      ((.projectId == null) or .projectId == $project) and
      ((.teamId == null) or .teamId == $team) and
      ((.accountId == null) or .accountId == $team))' <<< "$response" >/dev/null ||
    preflight_fail DOMAIN_METADATA_MISMATCH "DEV domain metadata was malformed or identified a different project"
  if jq -e --arg domain "$CANONICAL_DEV_DOMAIN" '[.domains[] | select(.name == $domain)] | length == 1' <<< "$response" >/dev/null; then
    PROVIDER_CHECKS="$(jq -c '. + ["dev_domain_already_present"]' <<< "$PROVIDER_CHECKS")"
    return 0
  fi
  return 1
}

validate_domain_config() {
  local response="$1" context="${2:-preflight}"
  if ! jq -e '
    def bounded_string($max): type == "string" and (length >= 1 and length <= $max);
    def valid_ipv4:
      type == "string" and
      bounded_string(15) and
      test("^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$");
    type == "object" and
    (.misconfigured | type == "boolean") and
    ((.configuredBy == null) or .configuredBy == "A" or .configuredBy == "CNAME" or .configuredBy == "dns-01" or .configuredBy == "http") and
    ((.acceptedChallenges == null) or ((.acceptedChallenges | type == "array") and
      ((.acceptedChallenges | length) <= 32) and
      all(.acceptedChallenges[]; bounded_string(16) and (. == "dns-01" or . == "http-01"))) and
    ((.recommendedCNAME == null) or ((.recommendedCNAME | type == "array") and
      ((.recommendedCNAME | length) <= 32) and
      all(.recommendedCNAME[]; type == "object" and
        (.rank | type == "number" and floor == . and . > 0) and
        (.value | bounded_string(255))
      ) and
      (([.recommendedCNAME[] | select(.rank == 1)] | length) == 1))) and
    ((.recommendedIPv4 | type == "array") and
      ((.recommendedIPv4 | length) <= 32) and
      (([.recommendedIPv4[] | select(.rank == 1)] | length) == 1) and
      all(.recommendedIPv4[]; type == "object" and
        (.rank | type == "number" and floor == . and . > 0) and
        (.value | type == "array") and
        ((.value | length) >= 1 and (.value | length) <= 32) and
        all(.value[]; valid_ipv4)
      )
    )
  )' <<< "$response" >/dev/null; then
    if [[ "$context" == post ]]; then
      fail "PARTIAL_MUTATION" DOMAIN_CONFIG_INVALID "canonical DEV domain configuration was malformed after POST" "Read provider state manually before any retry."
    fi
    preflight_fail DOMAIN_CONFIG_INVALID "canonical DEV domain configuration was malformed"
  fi
  DOMAIN_CONFIG_EVIDENCE="$(jq -c '{
    configured_by: .configuredBy,
    status: (if .misconfigured then "DNS_PENDING" else "READY" end),
    misconfigured: .misconfigured,
    recommended_cname: (.recommendedCNAME // [] | map(select(.rank == 1) | .value) | first),
    recommended_ipv4: ((.recommendedIPv4 // []) | map(select(.rank == 1) | .value) | flatten)
  }' <<< "$response")"
  PROVIDER_CHECKS="$(jq -c --arg status "$(jq -r '.status' <<< "$DOMAIN_CONFIG_EVIDENCE")" '. + ["dev_domain_config_" + ($status | ascii_downcase)]' <<< "$PROVIDER_CHECKS")"
  if [[ "$context" == ready && "$(jq -r '.status' <<< "$DOMAIN_CONFIG_EVIDENCE")" != READY ]]; then
    preflight_fail DOMAIN_DNS_PENDING "canonical DEV domain DNS configuration is not READY"
  fi
}

run_bootstrap_domain() {
  local project domains post readback config
  ACTION="bootstrap_domain"
  validate_bootstrap_inputs
  load_bootstrap_validation
  project="$(api_query "/v9/projects/$VERCEL_PROJECT_ID?teamId=$VERCEL_TEAM_ID")" || preflight_fail PROJECT_READ_FAILED "DEV project metadata read failed"
  validate_project "$project"
  domains="$(read_bootstrap_domains)" || preflight_fail DOMAIN_READ_FAILED "DEV domain metadata read failed"
  if classify_bootstrap_domains "$domains"; then
    config="$(read_domain_config)" || preflight_fail DOMAIN_CONFIG_READ_FAILED "canonical DEV domain configuration read failed"
    validate_domain_config "$config" bootstrap
    STATUS="SUCCESS"
    REASON_CODE="ALREADY_PRESENT"
    REASON="canonical DEV domain already belongs to the allowlisted project with bounded DNS state"
    NEXT_ACTION="No provider mutation is required."
    printf '%s\n' "$STATUS"
    return
  fi
  post="$(api_post "/v10/projects/$VERCEL_PROJECT_ID/domains?teamId=$VERCEL_TEAM_ID" "$(jq -cn --arg name "$CANONICAL_DEV_DOMAIN" '{name: $name}')")" || {
    PROVIDER_MUTATION_COUNT=1
    MUTATION_COUNT=1
    REASON_CODE="DOMAIN_CREATE_UNCERTAIN"
    AUTH_ENV_HTTP_STATUS="$LAST_HTTP_STATUS"
    AUTH_ENV_PROVIDER_ERROR_CODE="$LAST_PROVIDER_ERROR_CODE"
    fail "PARTIAL_MUTATION" "$REASON_CODE" "canonical DEV domain POST was ambiguous; no retry was attempted" "Read provider state manually before any retry."
  }
  PROVIDER_MUTATION_COUNT=1
  MUTATION_COUNT=1
  jq -e --arg domain "$CANONICAL_DEV_DOMAIN" 'type == "object" and .name == $domain' <<< "$post" >/dev/null ||
    fail "PARTIAL_MUTATION" DOMAIN_CREATE_RESPONSE_INVALID "canonical DEV domain POST did not return the exact domain" "Read provider state manually before any retry."
  readback="$(read_bootstrap_domains)" || fail "PARTIAL_MUTATION" DOMAIN_READBACK_FAILED "canonical DEV domain read-back failed after POST" "Read provider state manually before any retry."
  classify_bootstrap_domains "$readback" ||
    fail "PARTIAL_MUTATION" DOMAIN_READBACK_MISMATCH "canonical DEV domain ownership/configuration did not match after POST" "Read provider state manually before any retry."
  config="$(read_domain_config)" || fail "PARTIAL_MUTATION" DOMAIN_CONFIG_READ_FAILED "canonical DEV domain configuration read failed after POST" "Read provider state manually before any retry."
  validate_domain_config "$config" post
  PROVIDER_CHECKS="$(jq -c '. + ["dev_domain_created", "dev_domain_exact_readback"]' <<< "$PROVIDER_CHECKS")"
  STATUS="SUCCESS"
  REASON_CODE="CREATED"
  REASON="canonical DEV domain was created once and matched exact project-scoped read-back with bounded DNS state"
  NEXT_ACTION="No deployment, alias, or environment mutation was performed."
  printf '%s\n' "$STATUS"
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
    --arg executionCommitSha "$EXECUTION_COMMIT_SHA" \
    --arg attemptCommitSha "$ATTEMPT_COMMIT_SHA" \
    --arg stateKey "$AUTH_ENV_STATE_KEY" \
    --arg runId "$AUTH_ENV_RUN_ID" \
    --arg originalRunId "$AUTH_ENV_ORIGINAL_RUN_ID" \
    --arg originalRunAttempt "$AUTH_ENV_ORIGINAL_RUN_ATTEMPT" \
    --arg httpStatus "$AUTH_ENV_HTTP_STATUS" \
    --arg providerErrorCode "$AUTH_ENV_PROVIDER_ERROR_CODE" \
    --argjson providerChecks "$PROVIDER_CHECKS" \
    '{schema_version: 2, kind: "vercel-dev-auth-env-state", state: $state, repository: $repository, project_id: $project, team_id: $team, scope: $scope, key: "NEXT_PUBLIC_AUTH_URL", target: ["preview"], git_branch: "develop", expected_value_sha256: $valueSha, state_key: $stateKey, execution_commit_sha: ($executionCommitSha | if . == "" then null else . end), attempt_commit_sha: ($attemptCommitSha | if . == "" then null else . end), workflow_run_id: $runId, original_run_id: ($originalRunId | if . == "" then null else . end), original_run_attempt: ($originalRunAttempt | if . == "" then null else . end), provider_checks: $providerChecks, preflight_state: ($preflight | if . == "" then null else . end), configured_state: ($configured | if . == "" then null else . end), readback_state: ($readback | if . == "" then null else . end), mutation_count: ($mutationCount | tonumber), http_status: ($httpStatus | tonumber), provider_error_code: ($providerErrorCode | if . == "" then null else . end)}' > "$AUTH_ENV_STATE_PATH.tmp"
  mv "$AUTH_ENV_STATE_PATH.tmp" "$AUTH_ENV_STATE_PATH"
}

load_auth_env_state() {
  [[ -f "$AUTH_ENV_STATE_PATH" ]] || preflight_fail AUTH_ENV_STATE_MISSING "validated DEV Auth env state is missing"
  jq -e --arg repository "$GITHUB_REPOSITORY" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" --arg scope "$VERCEL_SCOPE" --arg valueSha "$AUTH_ENV_VALUE_SHA256" --arg stateKey "$AUTH_ENV_STATE_KEY" --arg runId "$AUTH_ENV_RUN_ID" '
    .schema_version == 2 and .kind == "vercel-dev-auth-env-state" and (.state == "preflight" or .state == "create_attempted" or .state == "create_uncertain" or .state == "create_rejected" or .state == "terminal_exact" or .state == "terminal_absent") and
    .repository == $repository and .project_id == $project and .team_id == $team and .scope == $scope and .key == "NEXT_PUBLIC_AUTH_URL" and .target == ["preview"] and .git_branch == "develop" and .expected_value_sha256 == $valueSha and .state_key == $stateKey and .workflow_run_id == $runId and
    (.provider_checks | type == "array") and (.preflight_state == "absent" or .preflight_state == "exact" or .preflight_state == null) and (.configured_state | type == "string") and (.readback_state | type == "string") and (.mutation_count | type == "number" and . >= 0 and floor == .) and (.state != "terminal_absent" or .mutation_count == 0) and (.http_status | type == "number" and . >= 0 and . <= 999 and floor == .) and ((.provider_error_code == null) or (.provider_error_code | type == "string" and test("^[A-Z0-9_]{1,64}$")))' "$AUTH_ENV_STATE_PATH" >/dev/null ||
    preflight_fail AUTH_ENV_STATE_INVALID "validated DEV Auth env state was malformed"
  AUTH_ENV_STATE="$(jq -r '.state' "$AUTH_ENV_STATE_PATH")"
  AUTH_ENV_PREFLIGHT_STATE="$(jq -r '.preflight_state' "$AUTH_ENV_STATE_PATH")"
  AUTH_ENV_CONFIGURED_STATE="$(jq -r '.configured_state' "$AUTH_ENV_STATE_PATH")"
  AUTH_ENV_READBACK_STATE="$(jq -r '.readback_state' "$AUTH_ENV_STATE_PATH")"
  AUTH_ENV_MUTATION_COUNT="$(jq -r '.mutation_count' "$AUTH_ENV_STATE_PATH")"
  AUTH_ENV_HTTP_STATUS="$(jq -r '.http_status // 000' "$AUTH_ENV_STATE_PATH")"
  AUTH_ENV_PROVIDER_ERROR_CODE="$(jq -r '.provider_error_code // empty' "$AUTH_ENV_STATE_PATH")"
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
  if [[ "$AUTH_ENV_DURABLE_STATE" == terminal_absent ]]; then
    PROVIDER_CHECKS="$(jq -c '. + ["auth_env_terminal_absent_artifact_paired"]' <<< "$PROVIDER_CHECKS")"
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
  jq -e --arg domain "$STABLE_DOMAIN" --arg project "$VERCEL_PROJECT_ID" --arg team "$VERCEL_TEAM_ID" '
    type == "object" and (.domains | type == "array") and
    all(.domains[]; type == "object" and (.name | type == "string")) and
    ([.domains[] | select(.name == $domain)] | length == 1) and
    all([.domains[] | select(.name == $domain)][];
      ((.projectId == null) or .projectId == $project) and
      ((.teamId == null) or .teamId == $team) and
      ((.accountId == null) or .accountId == $team))' <<< "$domains" >/dev/null ||
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
  PROVIDER_MUTATION_COUNT=$((PROVIDER_MUTATION_COUNT + 1))
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
  local project domains config alias_response inventory deployment_inventory candidate
  project="$(api_query "/v9/projects/$VERCEL_PROJECT_ID?teamId=$VERCEL_TEAM_ID")" || preflight_fail PROJECT_READ_FAILED "DEV project metadata read failed"
  validate_project "$project"
  domains="$(api_query "/v9/projects/$VERCEL_PROJECT_ID/domains?teamId=$VERCEL_TEAM_ID")" || preflight_fail DOMAIN_READ_FAILED "DEV project domain metadata read failed"
  validate_domains "$domains"
  config="$(read_domain_config)" || preflight_fail DOMAIN_CONFIG_READ_FAILED "DEV domain configuration read failed"
  validate_domain_config "$config" ready
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

validate_reconciliation_attempt_run() {
  local attempt_run
  attempt_run="$(github_query "/repos/$GITHUB_REPOSITORY/actions/runs/$ATTEMPT_RUN_ID")" || preflight_fail AUTH_ENV_PRIOR_RUN_READ_FAILED "the original DEV workflow run could not be read"
  jq -e --arg repository "$GITHUB_REPOSITORY" --arg workflow ".github/workflows/vercel-dev-deployment.yml" --arg sha "$ATTEMPT_COMMIT_SHA" --arg runId "$ATTEMPT_RUN_ID" '
    type == "object" and (.id | tostring) == $runId and .repository.full_name == $repository and .path == $workflow and .head_sha == $sha and .event == "workflow_dispatch"
  ' <<< "$attempt_run" >/dev/null || preflight_fail AUTH_ENV_PRIOR_RUN_INVALID "the original run did not belong to this repository, workflow, and exact commit"
  PRIOR_RUN_ATTEMPT="$(jq -r '.run_attempt // empty' <<< "$attempt_run")"
  [[ "$PRIOR_RUN_ATTEMPT" =~ ^[1-9][0-9]*$ ]] || preflight_fail AUTH_ENV_PRIOR_RUN_INVALID "the original run attempt was missing or malformed"
  PROVIDER_CHECKS="$(jq -c '. + ["auth_env_prior_workflow_run_exact"]' <<< "$PROVIDER_CHECKS")"
}

validate_reconciliation_artifact() {
  local page=1 response page_count total_count page_digest previous_digest artifacts='[]' artifact_count artifact_id artifact_name artifact_size
  local -i max_pages=10
  mkdir -p "$EVIDENCE_DIR"
  while (( page <= max_pages )); do
    response="$(github_query "/repos/$GITHUB_REPOSITORY/actions/runs/$ATTEMPT_RUN_ID/artifacts?per_page=100&page=$page")" || preflight_fail AUTH_ENV_PRIOR_ARTIFACT_INVALID "the original run artifact listing could not be read"
    jq -e 'type == "object" and (.artifacts | type == "array") and (.total_count | type == "number" and floor == . and . >= 0) and all(.artifacts[]; type == "object" and (.id | type == "number" and floor == . and . > 0) and (.name | type == "string") and (.expired | type == "boolean") and (.size_in_bytes | type == "number" and floor == . and . >= 0) and (.workflow_run.id | type == "number" and floor == . and . > 0))' <<< "$response" >/dev/null ||
      preflight_fail AUTH_ENV_PRIOR_ARTIFACT_INVALID "the original run artifact listing was malformed"
    page_digest="$(printf '%s' "$response" | sha256sum | awk '{print $1}')"
    [[ "$page_digest" != "${previous_digest:-}" ]] || preflight_fail AUTH_ENV_PRIOR_ARTIFACT_INVALID "the original run artifact pagination repeated a page"
    previous_digest="$page_digest"
    artifacts="$(jq -cn --argjson all "$artifacts" --argjson page "$(jq -c '.artifacts' <<< "$response")" '$all + $page')"
    page_count="$(jq '.artifacts | length' <<< "$response")"
    total_count="$(jq -r '.total_count' <<< "$response")"
    if (( page_count < AUTH_ENV_PAGE_LIMIT || page * AUTH_ENV_PAGE_LIMIT >= total_count )); then break; fi
    page=$((page + 1))
  done
  (( page <= max_pages )) || preflight_fail AUTH_ENV_PRIOR_ARTIFACT_INVALID "the original run artifact pagination exceeded the bounded maximum"
  artifact_count="$(jq --arg name "vercel-dev-auth-state-${AUTH_ENV_STATE_KEY}-${ATTEMPT_RUN_ID}-create_attempted" --arg runId "$ATTEMPT_RUN_ID" '[.[] | select(.name == $name and .expired == false and (.workflow_run.id | tostring) == $runId)] | length' <<< "$artifacts")"
  [[ "$artifact_count" == 1 ]] || preflight_fail AUTH_ENV_PRIOR_ARTIFACT_INVALID "the original run did not have exactly one unexpired create-attempted Auth env artifact"
  artifact_name="vercel-dev-auth-state-${AUTH_ENV_STATE_KEY}-${ATTEMPT_RUN_ID}-create_attempted"
  artifact_id="$(jq -r --arg name "$artifact_name" '.[] | select(.name == $name) | .id // empty' <<< "$artifacts")"
  artifact_size="$(jq -r --arg name "$artifact_name" '.[] | select(.name == $name) | .size_in_bytes // empty' <<< "$artifacts")"
  [[ "$artifact_id" =~ ^[1-9][0-9]*$ ]] || preflight_fail AUTH_ENV_PRIOR_ARTIFACT_INVALID "the original Auth env artifact had no immutable artifact ID"
  [[ "$artifact_size" =~ ^[0-9]+$ ]] || preflight_fail AUTH_ENV_PRIOR_ARTIFACT_INVALID "the original Auth env artifact had no bounded archive size"
  validate_auth_env_artifact "$artifact_id" "$ATTEMPT_RUN_ID" "$artifact_size" "$ATTEMPT_RUN_ID" create_attempted ||
    preflight_fail AUTH_ENV_PRIOR_ARTIFACT_INVALID "the original Auth env artifact was malformed, oversized, or mismatched"
  PROVIDER_CHECKS="$(jq -c '. + ["auth_env_prior_create_attempted_artifact_exact"]' <<< "$PROVIDER_CHECKS")"
}

run_reconcile_auth_env() {
  ACTION="reconcile_auth_env"
  validate_exact_sha
  validate_reconciliation_attempt_run
  validate_reconciliation_artifact
  local project domains
  project="$(api_query "/v9/projects/$VERCEL_PROJECT_ID?teamId=$VERCEL_TEAM_ID")" || preflight_fail PROJECT_READ_FAILED "DEV project metadata read failed during Auth env reconciliation"
  validate_project "$project"
  domains="$(api_query "/v9/projects/$VERCEL_PROJECT_ID/domains?teamId=$VERCEL_TEAM_ID")" || preflight_fail DOMAIN_READ_FAILED "DEV project domain metadata read failed during Auth env reconciliation"
  validate_domains "$domains"
  AUTH_ENV_RUN_ID="$GITHUB_RUN_ID"
  AUTH_ENV_ORIGINAL_RUN_ID="$ATTEMPT_RUN_ID"
  AUTH_ENV_ORIGINAL_RUN_ATTEMPT="$PRIOR_RUN_ATTEMPT"
  if read_and_classify_auth_env; then
    :
  else
    local read_status=$?
    [[ "$read_status" == 2 ]] && preflight_fail AUTH_ENV_READ_FAILED "DEV Auth env metadata read failed during reconciliation"
    preflight_fail "$AUTH_ENV_REASON_CODE" "DEV Auth env metadata was not exact or absent during reconciliation"
  fi
  AUTH_ENV_PREFLIGHT_STATE="$AUTH_ENV_CURRENT_STATE"
  AUTH_ENV_CONFIGURED_STATE="reconciled"
  AUTH_ENV_READBACK_STATE="$AUTH_ENV_CURRENT_STATE"
  AUTH_ENV_MUTATION_COUNT=0
  MUTATION_COUNT=0
  PROVIDER_MUTATION_COUNT=0
  ALIAS_DEPLOYMENT_MUTATION_COUNT=0
  if [[ "$AUTH_ENV_CURRENT_STATE" == exact ]]; then
    AUTH_ENV_STATE="terminal_exact"
    RECONCILIATION_TERMINAL_STATE="terminal_exact"
    STATUS="RECONCILED_TERMINAL_EXACT"
    REASON_CODE="RECONCILED_TERMINAL_EXACT"
    REASON="provider read-back exactly matched the bounded DEV Auth env contract after the prior create attempt"
    PROVIDER_CHECKS="$(jq -c '. + ["auth_env_reconciliation_exact"]' <<< "$PROVIDER_CHECKS")"
  elif [[ "$AUTH_ENV_CURRENT_STATE" == absent ]]; then
    AUTH_ENV_STATE="terminal_absent"
    RECONCILIATION_TERMINAL_STATE="terminal_absent"
    STATUS="RECONCILED_TERMINAL_ABSENT"
    REASON_CODE="RECONCILED_TERMINAL_ABSENT"
    REASON="provider read-back proved that no bounded DEV Auth env exists after the prior create attempt"
    PROVIDER_CHECKS="$(jq -c '. + ["auth_env_reconciliation_absent"]' <<< "$PROVIDER_CHECKS")"
  else
    preflight_fail AUTH_ENV_READ_FAILED "DEV Auth env reconciliation did not produce an exact or absent classification"
  fi
  write_auth_env_state
  write_github_output
  NEXT_ACTION="Pair the terminal Auth env state with the original create-attempted artifact before any standard retry."
  printf '%s\n' "$STATUS"
}

run_prepare() {
  validate_inputs
  validate_artifact_handoff
  load_context
  load_auth_env_state
  validate_durable_auth_env_state
  if [[ "$AUTH_ENV_CONFIGURED_STATE" == create_uncertain || "$AUTH_ENV_CONFIGURED_STATE" == create_rejected || "$AUTH_ENV_STATE" == create_uncertain || "$AUTH_ENV_STATE" == create_rejected ]]; then
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
  ALIAS_DEPLOYMENT_MUTATION_COUNT=$((ALIAS_DEPLOYMENT_MUTATION_COUNT + 1))
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
  payload="$(jq -cn --arg key "$AUTH_ENV_KEY" --arg value "$AUTH_ENV_VALUE" --arg type "$AUTH_ENV_TYPE" --arg target "$AUTH_ENV_TARGET" --arg branch "$AUTH_ENV_GIT_BRANCH" '[{key: $key, value: $value, type: $type, target: [$target], gitBranch: $branch}]')"
  if [[ "$AUTH_ENV_MUTATION_COUNT" == 0 ]]; then
    MUTATION_COUNT=$((MUTATION_COUNT + 1))
  fi
  AUTH_ENV_MUTATION_COUNT=1
  PROVIDER_MUTATION_COUNT=$((PROVIDER_MUTATION_COUNT + 1))
  AUTH_ENV_CONFIGURED_STATE="create_uncertain"
  AUTH_ENV_STATE="create_uncertain"
  AUTH_ENV_HTTP_STATUS="000"
  AUTH_ENV_PROVIDER_ERROR_CODE=""
  PROVIDER_CHECKS="$(jq -c '. + ["auth_env_create_attempted"]' <<< "$PROVIDER_CHECKS")"
  write_auth_env_state
  if ! api_post "/v10/projects/$VERCEL_PROJECT_ID/env?teamId=$VERCEL_TEAM_ID" "$payload" >/dev/null; then
    AUTH_ENV_HTTP_STATUS="$LAST_HTTP_STATUS"
    AUTH_ENV_PROVIDER_ERROR_CODE="$LAST_PROVIDER_ERROR_CODE"
    if [[ "$AUTH_ENV_HTTP_STATUS" =~ ^4[0-9][0-9]$ ]]; then
      AUTH_ENV_CONFIGURED_STATE="create_rejected"
      AUTH_ENV_STATE="create_rejected"
      write_auth_env_state
      partial_fail AUTH_ENV_CREATE_REJECTED "DEV Auth env creation was definitively rejected by the provider"
    fi
    write_auth_env_state
    partial_fail AUTH_ENV_CREATE_UNCERTAIN "DEV Auth env creation failed or became uncertain"
  fi
  AUTH_ENV_HTTP_STATUS="$LAST_HTTP_STATUS"
  AUTH_ENV_PROVIDER_ERROR_CODE="$LAST_PROVIDER_ERROR_CODE"
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
  if [[ "$AUTH_ENV_CONFIGURED_STATE" == create_uncertain || "$AUTH_ENV_CONFIGURED_STATE" == create_rejected ]]; then
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
  if [[ "$AUTH_ENV_CONFIGURED_STATE" == create_uncertain || "$AUTH_ENV_CONFIGURED_STATE" == create_rejected ]]; then
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
elif [[ "$MODE" == reconcile-auth-env ]]; then
  run_reconcile_auth_env
elif [[ "$MODE" == bootstrap-domain ]]; then
  run_bootstrap_domain
else
  run_promote
fi
