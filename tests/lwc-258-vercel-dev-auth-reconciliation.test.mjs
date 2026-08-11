import assert from 'node:assert/strict';
import { test } from 'node:test';
import { chmod, mkdtemp, mkdir, readFile, readdir, rename, stat, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createHash, randomBytes } from 'node:crypto';
import { load as parseYaml } from 'js-yaml';

const execFileAsync = promisify(execFile);
const repoRoot = new URL('..', import.meta.url).pathname;
const executionCommitSha = '0b03be3ecb3709e3a59d46ac08cebd0c52be3506';
const attemptCommitSha = '774d00dcb316a640aafb0f5e1674f9b42247e727';
const attemptRunId = '31357440769';
const currentRunId = '40000000000';
const projectId = 'prj_dev123';
const teamId = 'team_dev123';
const scope = 'rayer-tung-s-projects';
const repository = 'Rayer/llm-wiki-frontend';
const key = 'NEXT_PUBLIC_AUTH_URL';
const valueSha = createHash('sha256').update('https://auth-dev.rayer.idv.tw').digest('hex');
const stateKey = createHash('sha256').update(JSON.stringify({ repository, project_id: projectId, team_id: teamId, scope, key, target: ['preview'], value_sha256: valueSha })).digest('hex');

async function setup(scenario = 'exact', artifact = 'valid') {
  const root = await mkdtemp(join(tmpdir(), 'lwc-258-reconcile-'));
  const bin = join(root, 'bin');
  const evidenceDir = join(root, 'evidence');
  await mkdir(bin);
  await mkdir(evidenceDir);
  await writeFile(join(root, 'scenario'), scenario);
  await writeFile(join(root, 'artifact-scenario'), artifact);
  await writeFile(join(root, 'mutation-log'), '');
  await writeFile(join(root, 'github-run.json'), JSON.stringify({ id: Number(attemptRunId), run_attempt: 1, event: 'workflow_dispatch', path: '.github/workflows/vercel-dev-deployment.yml', head_sha: attemptCommitSha, repository: { full_name: repository } }));
  const state = { schema_version: 2, kind: 'vercel-dev-auth-env-state', state: 'create_attempted', repository, project_id: projectId, team_id: teamId, scope, key, target: ['preview'], git_branch: 'develop', expected_value_sha256: valueSha, state_key: stateKey, workflow_run_id: attemptRunId, execution_commit_sha: attemptCommitSha, attempt_commit_sha: null, provider_checks: ['auth_env_create_attempted'], mutation_count: 1 };
  if (artifact === 'legacy-wrong-workflow-run-id') state.workflow_run_id = '99999999999';
  if (artifact === 'legacy-missing-workflow-run-id') delete state.workflow_run_id;
  if (artifact === 'legacy-missing-state-key') delete state.state_key;
  if (artifact === 'archive-too-large') state.padding = randomBytes(50000).toString('base64');
  if (artifact === 'uncompressed-too-large') state.padding = 'x'.repeat(20000);
  await writeFile(join(root, 'auth-env-state.json'), JSON.stringify(state));
  if (artifact === 'extra-file') await writeFile(join(root, 'unexpected.txt'), 'unexpected');
  if (artifact === 'symlink') {
    await rename(join(root, 'auth-env-state.json'), join(root, 'state-target.json'));
    await symlink('state-target.json', join(root, 'auth-env-state.json'));
  }
  const zipArgs = ['-q', ...(artifact === 'symlink' ? ['--symlinks'] : []), join(root, 'artifact.zip'), ...(artifact === 'extra-file' ? ['auth-env-state.json', 'unexpected.txt'] : ['auth-env-state.json'])];
  await execFileAsync('zip', zipArgs, { cwd: root });
  const archiveSize = (await stat(join(root, 'artifact.zip'))).size;
  const listedSize = artifact === 'metadata-too-large' ? 65537 : artifact === 'metadata-mismatch' ? archiveSize - 1 : archiveSize;
  await writeFile(join(root, 'github-artifacts.json'), JSON.stringify({ artifacts: artifact === 'missing' ? [] : [{ id: 7001, name: `vercel-dev-auth-state-${stateKey}-${attemptRunId}-create_attempted`, expired: artifact === 'expired', workflow_run: { id: Number(attemptRunId), head_sha: attemptCommitSha }, size_in_bytes: listedSize, archive_download_url: 'https://github.test/repos/Rayer/llm-wiki-frontend/actions/artifacts/7001/zip' }], total_count: artifact === 'missing' ? 0 : 1 }));
  await writeFile(join(root, 'ci.json'), JSON.stringify({ workflow_runs: [{ path: '.github/workflows/ci.yml', head_branch: 'develop', head_sha: executionCommitSha, event: 'push', status: 'completed', conclusion: 'success', id: 313, html_url: 'https://github.test/actions/runs/313' }] }));
  await writeFile(join(root, 'project.json'), JSON.stringify({ id: projectId, name: 'llm-wiki-frontend-dev', accountId: teamId }));
  await writeFile(join(root, 'domains.json'), JSON.stringify({ domains: [{ name: 'wiki.dev.rayer.idv.tw' }] }));
  await execFileAsync('cp', [join(repoRoot, 'tests/fixtures/lwc-258-auth-reconciliation-fake-curl.sh'), join(bin, 'curl')]);
  await chmod(join(bin, 'curl'), 0o755);
  return { root, bin, evidenceDir };
}

function envFor(fixture, overrides = {}) {
  const env = { ...process.env };
  delete env.GITHUB_ACTIONS;
  delete env.CI;
  return { ...env, PATH: `${fixture.bin}:${process.env.PATH}`, FIXTURE_ROOT: fixture.root, GITHUB_REPOSITORY: repository, GITHUB_TOKEN: 'github-sentinel-token', VERCEL_TOKEN: 'vercel-sentinel-token', VERCEL_API_BASE_URL: 'https://vercel.test', GITHUB_API_URL: 'https://github.test', VERCEL_PROJECT_ID: projectId, VERCEL_TEAM_ID: teamId, VERCEL_SCOPE: scope, EXECUTION_COMMIT_SHA: executionCommitSha, ATTEMPT_COMMIT_SHA: attemptCommitSha, ATTEMPT_RUN_ID: attemptRunId, GITHUB_RUN_ID: currentRunId, CURRENT_HEAD_SHA: executionCommitSha, CURRENT_REMOTE_DEVELOP_SHA: executionCommitSha, EVIDENCE_DIR: fixture.evidenceDir, LWC253_TEST_MODE: '1', ...overrides };
}

async function run(fixture, overrides = {}) {
  try {
    return await execFileAsync('bash', ['.github/scripts/vercel-dev-deployment.sh', 'reconcile-auth-env'], { cwd: repoRoot, env: envFor(fixture, overrides), maxBuffer: 1024 * 1024 });
  } catch (error) {
    return error;
  }
}

async function readEvidence(fixture) {
  return JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
}

for (const [scenario, status, state] of [['exact', 'RECONCILED_TERMINAL_EXACT', 'terminal_exact'], ['absent', 'RECONCILED_TERMINAL_ABSENT', 'terminal_absent']]) {
  test(`reconciles ${scenario} with zero provider mutation`, async () => {
    const fixture = await setup(scenario);
    const result = await run(fixture);
    assert.equal(result.code, undefined, result.stderr);
    const evidence = await readEvidence(fixture);
    assert.equal(evidence.status, status);
    assert.equal(evidence.source.execution_commit_sha, executionCommitSha);
    assert.equal(evidence.source.attempt_commit_sha, attemptCommitSha);
    assert.equal(evidence.source.checked_out_sha, executionCommitSha);
    assert.equal(evidence.source.current_remote_develop_sha, executionCommitSha);
    assert.equal(evidence.source.canonical_ci.head_sha, executionCommitSha);
    assert.equal(evidence.auth_env.state, state);
    assert.equal(evidence.provider_verification.provider_mutation_count, 0);
    assert.equal(evidence.provider_verification.alias_deployment_mutation_count, 0);
    assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8')).trim(), '');
    const terminal = JSON.parse(await readFile(join(fixture.evidenceDir, 'auth-env-state.json'), 'utf8'));
    assert.equal(terminal.state, state);
    assert.equal(terminal.workflow_run_id, currentRunId);
    assert.equal(terminal.original_run_id, attemptRunId);
    assert.equal(terminal.execution_commit_sha, executionCommitSha);
    assert.equal(terminal.attempt_commit_sha, attemptCommitSha);
  });
}

test('validates execution and attempt SHAs independently', async () => {
  const wrongAttemptFixture = await setup('exact');
  const wrongAttempt = await run(wrongAttemptFixture, { ATTEMPT_COMMIT_SHA: 'fedcba9876543210fedcba9876543210fedcba98' });
  assert.equal(wrongAttempt.code, 1);
  assert.equal((await readEvidence(wrongAttemptFixture)).reason_code, 'AUTH_ENV_PRIOR_RUN_INVALID');

  const fixture = await setup('exact');
  const wrongExecution = await run(fixture, { EXECUTION_COMMIT_SHA: attemptCommitSha });
  assert.equal(wrongExecution.code, 1);
  assert.equal((await readEvidence(fixture)).reason_code, 'CHECKED_OUT_SHA_MISMATCH');
});

test('binds a modern original artifact to the attempt SHA across remediation execution SHAs', async () => {
  const fixture = await setup('absent');
  const result = await run(fixture);
  assert.equal(result.code, undefined, result.stderr);
  assert.equal((await readEvidence(fixture)).auth_env.state, 'terminal_absent');
  assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8')).trim(), '');
});

for (const scenario of ['mismatch', 'duplicate', 'pagination-malformed', 'pagination-loop', 'pagination-max']) {
  test(`fails closed for provider ${scenario} without a terminal artifact`, async () => {
    const fixture = await setup(scenario);
    const result = await run(fixture);
    assert.equal(result.code, 1);
    const evidence = await readEvidence(fixture);
    assert.equal(evidence.status, 'PREFLIGHT_FAILED');
    assert.equal(evidence.provider_verification.provider_mutation_count, 0);
    await assert.rejects(readFile(join(fixture.evidenceDir, 'auth-env-state.json')));
    assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8')).trim(), '');
  });
}

for (const artifact of ['missing', 'expired', 'duplicate', 'wrong-run', 'wrong-sha', 'wrong-workflow', 'wrong-state-key', 'malformed', 'legacy-wrong-workflow-run-id', 'legacy-missing-workflow-run-id']) {
  test(`rejects ${artifact} prior create-attempt artifact`, async () => {
    const fixture = await setup('absent', artifact);
    const result = await run(fixture);
    assert.equal(result.code, 1);
    const evidence = await readEvidence(fixture);
    assert.equal(evidence.status, 'PREFLIGHT_FAILED');
    const expected = ['wrong-sha', 'wrong-workflow'].includes(artifact) ? 'AUTH_ENV_PRIOR_RUN_INVALID' : 'AUTH_ENV_PRIOR_ARTIFACT_INVALID';
    assert.equal(evidence.reason_code, expected, JSON.stringify(evidence));
    assert.equal(evidence.provider_verification.provider_mutation_count, 0);
  });
}

test('accepts the real legacy create-attempt shape whose state key is bound by the artifact name', async () => {
  const fixture = await setup('exact', 'legacy-missing-state-key');
  const result = await run(fixture);
  assert.equal(result.code, undefined, result.stderr);
  const terminal = JSON.parse(await readFile(join(fixture.evidenceDir, 'auth-env-state.json'), 'utf8'));
  assert.equal(terminal.state, 'terminal_exact');
  assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8')).trim(), '');
});

for (const artifact of ['metadata-too-large', 'metadata-mismatch', 'archive-too-large', 'download-too-large', 'uncompressed-too-large', 'extra-file', 'symlink']) {
  test(`rejects bounded archive violation ${artifact} before trusting state`, async () => {
    const fixture = await setup('absent', artifact);
    const result = await run(fixture);
    assert.equal(result.code, 1);
    const evidence = await readEvidence(fixture);
    assert.equal(evidence.reason_code, 'AUTH_ENV_PRIOR_ARTIFACT_INVALID', JSON.stringify(evidence));
    assert.equal((await readdir(fixture.evidenceDir)).some((name) => name.includes('prior-auth-env') || name.endsWith('.zip')), false);
    if (artifact === 'download-too-large') assert.equal((await readFile(join(fixture.root, 'max-filesize'), 'utf8')).trim(), '65536');
  });
}

for (const artifact of ['artifact-pagination-malformed', 'artifact-pagination-loop', 'artifact-pagination-max']) {
  test(`rejects ${artifact} prior artifact pagination`, async () => {
    const fixture = await setup('absent', artifact);
    const result = await run(fixture);
    assert.equal(result.code, 1);
    const evidence = await readEvidence(fixture);
    assert.equal(evidence.reason_code, 'AUTH_ENV_PRIOR_ARTIFACT_INVALID', JSON.stringify(evidence));
    assert.equal(evidence.provider_verification.provider_mutation_count, 0);
    await assert.rejects(readFile(join(fixture.evidenceDir, 'auth-env-state.json')));
  });
}

test('reconciliation workflow is manual, exact-SHA gated, paired, and read-only', async () => {
  const source = await readFile(join(repoRoot, '.github/workflows/vercel-dev-auth-env-reconciliation.yml'), 'utf8');
  const workflow = parseYaml(source);
  assert.deepEqual(Object.keys(workflow.on.workflow_dispatch.inputs), ['execution_commit_sha', 'attempt_commit_sha', 'attempt_run_id', 'ticket_ref']);
  assert.equal(workflow.on.push, undefined);
  assert.equal(workflow.permissions.contents, 'read');
  assert.equal(workflow.permissions.actions, 'read');
  assert.equal(workflow.concurrency.group, 'vercel-development-deployment');
  assert.equal(workflow.concurrency['cancel-in-progress'], false);
  assert.equal(workflow.jobs.reconcile.if, "github.ref == 'refs/heads/develop'");
  assert.equal(workflow.jobs.reconcile.environment.name, 'Development');
  const steps = workflow.jobs.reconcile.steps;
  assert.equal(steps[0].with.ref, '${{ inputs.execution_commit_sha }}');
  const reconcile = steps.find(({ run }) => run?.includes('reconcile-auth-env'));
  assert.ok(reconcile);
  assert.deepEqual(Object.keys(reconcile.env).sort(), ['EVIDENCE_DIR', 'GITHUB_TOKEN', 'VERCEL_PROJECT_ID', 'VERCEL_SCOPE', 'VERCEL_TEAM_ID', 'VERCEL_TOKEN'].sort());
  assert.ok(steps.find(({ name }) => name === 'Upload normalized Auth env reconciliation evidence').if.includes('always'));
  const terminal = steps.find(({ name }) => name === 'Upload terminal Auth env state');
  assert.match(terminal.with.name, /inputs\.attempt_run_id/);
  assert.match(terminal.with.name, /outputs\.terminal_state/);
  const evidence = steps.find(({ name }) => name === 'Upload normalized Auth env reconciliation evidence');
  assert.match(evidence.with.name, /inputs\.execution_commit_sha/);
  assert.match(evidence.with.name, /inputs\.attempt_commit_sha/);
  assert.equal(terminal.if, "success() && (steps.reconcile_auth_env.outputs.terminal_state == 'terminal_exact' || steps.reconcile_auth_env.outputs.terminal_state == 'terminal_absent')");
  assert.doesNotMatch(source, /vercel\s+(deploy|alias\s+set)|api_post|forceNew/);
});

test('POST diagnostics are status plus bounded sanitized code and never body text', async () => {
  const script = await readFile(join(repoRoot, '.github/scripts/vercel-dev-deployment.sh'), 'utf8');
  assert.match(script, /AUTH_ENV_HTTP_STATUS/);
  assert.match(script, /provider_error_code/);
  assert.match(script, /\^\[A-Z0-9_\]\{1,64\}\$/);
  assert.match(script, /error\.message \/\/ \.message/);
  assert.doesNotMatch(script, /response_body|error_text/);
  assert.match(script, /000/);
});
