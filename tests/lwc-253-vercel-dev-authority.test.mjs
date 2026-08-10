import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createHash } from 'node:crypto';
import { load as parseYaml } from 'js-yaml';

const execFileAsync = promisify(execFile);
const repoRoot = new URL('..', import.meta.url).pathname;
const commitSha = '0123456789abcdef0123456789abcdef01234567';
const deploymentId = 'dpl_devready';
const projectId = 'prj_dev123';
const teamId = 'team_dev123';
const rollbackArtifactDigestBare = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const stableDomain = 'llm-wiki-frontend-dev.vercel.app';
const authEnvKey = 'NEXT_PUBLIC_AUTH_URL';
const authEnvUrl = 'https://auth-dev.rayer.idv.tw';
const authEnvValueSha = createHash('sha256').update(authEnvUrl).digest('hex');
const deploymentAuthMarker = `lwc-auth-env-v1:${authEnvValueSha}`;
const authEnvStateKey = createHash('sha256').update(JSON.stringify({
  repository: 'Rayer/llm-wiki-frontend',
  project_id: projectId,
  team_id: teamId,
  scope: 'rayer-tung-s-projects',
  key: authEnvKey,
  target: ['preview'],
  value_sha256: authEnvValueSha,
})).digest('hex');

async function setupCase(scenario = 'authority-conflict') {
  const root = await mkdtemp(join(tmpdir(), 'lwc-253-'));
  const bin = join(root, 'bin');
  const evidenceDir = join(root, 'evidence');
  await mkdir(bin);
  await mkdir(evidenceDir);
  await writeFile(join(root, 'scenario'), scenario);
  await writeFile(join(root, 'mutation-log'), '');
  await writeFile(join(root, 'deployment-post-log'), '');
  await writeFile(join(root, 'env-post-log'), '');
  await writeFile(join(root, 'curl-calls'), '');
  const durableStateSuffix = scenario === 'prior-auth-create-attempted'
    ? '9001-create_attempted'
    : ['prior-auth-terminal-success', 'prior-auth-terminal-exact-spoofed', 'prior-auth-terminal-owner-spoofed'].includes(scenario)
      ? '9001-terminal_exact'
      : ['prior-auth-terminal-absent', 'prior-auth-unpaired-terminal-absent', 'prior-auth-spoofed-terminal-absent', 'prior-auth-terminal-absent-later-attempted', 'prior-auth-terminal-absent-later-attempted-reordered', 'prior-auth-terminal-absent-duplicate'].includes(scenario)
        ? '9001-terminal_absent'
      : null;
  let terminalArchiveSize;
  if (['prior-auth-terminal-success', 'prior-auth-terminal-exact-spoofed', 'prior-auth-terminal-owner-spoofed', 'prior-auth-terminal-absent', 'prior-auth-unpaired-terminal-absent', 'prior-auth-spoofed-terminal-absent', 'prior-auth-terminal-absent-later-attempted', 'prior-auth-terminal-absent-later-attempted-reordered', 'prior-auth-terminal-absent-duplicate'].includes(scenario)) {
    const terminalState = scenario.includes('terminal-success') || scenario.includes('terminal-exact') || scenario.includes('terminal-owner') ? 'terminal_exact' : 'terminal_absent';
    await writeFile(join(root, 'auth-env-state.json'), JSON.stringify({
      schema_version: 2,
      kind: 'vercel-dev-auth-env-state',
      state: terminalState,
      repository: 'Rayer/llm-wiki-frontend',
      project_id: projectId,
      team_id: teamId,
      scope: 'rayer-tung-s-projects',
      key: authEnvKey,
      target: ['preview'],
      git_branch: 'develop',
      expected_value_sha256: authEnvValueSha,
      state_key: scenario === 'prior-auth-terminal-exact-spoofed' ? 'spoofed' : authEnvStateKey,
      workflow_run_id: scenario === 'prior-auth-spoofed-terminal-absent' ? '9999' : '9001',
      original_run_id: scenario === 'prior-auth-spoofed-terminal-absent' ? '9999' : '9001',
      original_run_attempt: '1',
      provider_checks: ['auth_env_reconciliation_absent'],
      mutation_count: 0,
    }));
    await execFileAsync('zip', ['-q', join(root, `${terminalState}.zip`), 'auth-env-state.json'], { cwd: root });
    terminalArchiveSize = (await stat(join(root, `${terminalState}.zip`))).size;
  }
  const durableArtifacts = durableStateSuffix ? [{
      id: ['prior-auth-terminal-absent', 'prior-auth-unpaired-terminal-absent', 'prior-auth-spoofed-terminal-absent', 'prior-auth-terminal-success', 'prior-auth-terminal-exact-spoofed', 'prior-auth-terminal-owner-spoofed', 'prior-auth-terminal-absent-later-attempted', 'prior-auth-terminal-absent-later-attempted-reordered'].includes(scenario) ? 9002 : 9001,
      name: `vercel-dev-auth-state-${authEnvStateKey}-${durableStateSuffix}`,
      expired: false,
      workflow_run: { id: ['prior-auth-terminal-absent', 'prior-auth-unpaired-terminal-absent', 'prior-auth-spoofed-terminal-absent', 'prior-auth-terminal-success', 'prior-auth-terminal-exact-spoofed', 'prior-auth-terminal-owner-spoofed', 'prior-auth-terminal-absent-later-attempted', 'prior-auth-terminal-absent-later-attempted-reordered', 'prior-auth-terminal-absent-duplicate'].includes(scenario) ? 2002 : 9001 },
      size_in_bytes: terminalArchiveSize ?? 512,
    }, ...(['prior-auth-terminal-absent', 'prior-auth-unpaired-terminal-absent', 'prior-auth-spoofed-terminal-absent', 'prior-auth-terminal-success', 'prior-auth-terminal-exact-spoofed', 'prior-auth-terminal-owner-spoofed', 'prior-auth-terminal-absent-duplicate'].includes(scenario) ? [{
      id: 9001,
      name: `vercel-dev-auth-state-${authEnvStateKey}-${scenario === 'prior-auth-unpaired-terminal-absent' ? 9002 : 9001}-create_attempted`,
      expired: false,
      workflow_run: { id: scenario === 'prior-auth-unpaired-terminal-absent' ? 9002 : 9001 },
      size_in_bytes: 512,
    }] : scenario === 'prior-auth-terminal-absent-later-attempted' || scenario === 'prior-auth-terminal-absent-later-attempted-reordered' ? [
      {
        id: 9001,
        name: `vercel-dev-auth-state-${authEnvStateKey}-9001-create_attempted`,
        expired: false,
        workflow_run: { id: 9001 },
        size_in_bytes: 512,
      },
      {
        id: 9003,
        name: `vercel-dev-auth-state-${authEnvStateKey}-9003-create_attempted`,
        expired: false,
        workflow_run: { id: 9003 },
        size_in_bytes: 512,
      },
    ] : [])] : [];
  if (scenario === 'prior-auth-terminal-absent-later-attempted-reordered') durableArtifacts.reverse();
  if (scenario === 'prior-auth-terminal-absent-duplicate') durableArtifacts.push({ ...durableArtifacts[0], id: 9004 });
  await writeFile(join(root, 'github-artifacts.json'), JSON.stringify({
    artifacts: durableArtifacts,
    total_count: durableArtifacts.length,
  }));
  const authEnv = ['auth-env-absent', 'prior-auth-terminal-absent', 'prior-auth-unpaired-terminal-absent', 'prior-auth-spoofed-terminal-absent'].includes(scenario)
    ? { envs: [] }
    : scenario === 'auth-env-wrong-value'
      ? { envs: [{ key: authEnvKey, value: 'https://auth-wrong.example', type: 'plain', target: ['preview'], gitBranch: 'develop' }] }
      : scenario === 'auth-env-wrong-type'
        ? { envs: [{ key: authEnvKey, value: authEnvUrl, type: 'secret', target: ['preview'], gitBranch: 'develop' }] }
        : scenario === 'auth-env-wrong-target'
          ? { envs: [{ key: authEnvKey, value: authEnvUrl, type: 'plain', target: ['production'], gitBranch: 'develop' }] }
          : scenario === 'auth-env-wrong-branch'
            ? { envs: [{ key: authEnvKey, value: authEnvUrl, type: 'plain', target: ['preview'], gitBranch: 'main' }] }
            : scenario === 'auth-env-duplicate'
              ? { envs: [
                { key: authEnvKey, value: authEnvUrl, type: 'plain', target: ['preview'], gitBranch: 'develop' },
                { key: authEnvKey, value: authEnvUrl, type: 'plain', target: ['preview'], gitBranch: 'develop' },
              ] }
              : scenario === 'auth-env-ambiguous'
                ? { envs: [
                  { key: authEnvKey, value: authEnvUrl, type: 'plain', target: ['preview'], gitBranch: 'develop' },
                  { key: authEnvKey, value: authEnvUrl, type: 'plain', target: ['preview'], gitBranch: 'main' },
                ] }
                : { envs: [{ key: authEnvKey, value: authEnvUrl, type: 'plain', target: ['preview'], gitBranch: 'develop' }] };
  await writeFile(join(root, 'auth-env.json'), JSON.stringify(authEnv));
  const deployment = {
    id: deploymentId,
    url: 'https://dpl_dev_ready.vercel.app',
    projectId,
    teamId,
    ownerId: teamId,
    readyState: 'READY',
    target: null,
    meta: {
      githubDeployment: '1',
      githubOrg: 'Rayer',
      githubRepo: 'llm-wiki-frontend',
      githubCommitRef: 'develop',
      githubCommitSha: commitSha,
      lwcAuthEnvProvenance: deploymentAuthMarker,
    },
  };
  if (scenario === 'unmarked-old-deployment') delete deployment.meta.lwcAuthEnvProvenance;
  await writeFile(join(root, 'deployment.json'), JSON.stringify(deployment));
  await writeFile(join(root, 'aliases.json'), JSON.stringify({
    [stableDomain]: 'dpl_devold',
  }));
  await writeFile(join(root, 'project.json'), JSON.stringify({
    id: projectId,
    name: 'llm-wiki-frontend-dev',
    accountId: teamId,
  }));
  await writeFile(join(root, 'domains.json'), JSON.stringify({
    domains: [{ name: stableDomain }],
  }));
  await writeFile(join(root, 'ci.json'), JSON.stringify({
    workflow_runs: [{
      path: '.github/workflows/ci.yml',
      head_branch: 'develop',
      head_sha: commitSha,
      event: 'push',
      status: 'completed',
      conclusion: 'success',
      id: 987654321,
      html_url: 'https://github.test/Rayer/llm-wiki-frontend/actions/runs/987654321',
    }],
  }));
  await execFileAsync('cp', [
    join(repoRoot, 'tests/fixtures/lwc-253-fake-curl.sh'),
    join(bin, 'curl'),
  ]);
  await execFileAsync('cp', [
    join(repoRoot, 'tests/fixtures/lwc-253-fake-vercel.sh'),
    join(bin, 'vercel'),
  ]);
  await execFileAsync('cp', [
    join(repoRoot, 'tests/fixtures/lwc-253-fake-timeout.sh'),
    join(bin, 'timeout'),
  ]);
  await execFileAsync('chmod', ['+x', join(bin, 'curl'), join(bin, 'vercel'), join(bin, 'timeout')]);
  return { root, bin, evidenceDir };
}

async function runScript(mode, env) {
  try {
    return await execFileAsync('bash', ['.github/scripts/vercel-dev-deployment.sh', mode], {
      cwd: repoRoot,
      env,
      maxBuffer: 1024 * 1024,
    });
  } catch (error) {
    return error;
  }
}

function buildEnv(fixture, overrides = {}) {
  const env = { ...process.env };
  delete env.GITHUB_ACTIONS;
  delete env.CI;
  return {
    ...env,
    PATH: fixture.bin + ':' + process.env.PATH,
    FIXTURE_ROOT: fixture.root,
    GITHUB_REPOSITORY: 'Rayer/llm-wiki-frontend',
    GITHUB_TOKEN: 'github-sentinel-token',
    VERCEL_TOKEN: 'vercel-sentinel-token',
    VERCEL_API_BASE_URL: 'https://vercel.test',
    GITHUB_API_URL: 'https://github.test',
    GITHUB_RUN_ID: '1001',
    VERCEL_PROJECT_ID: projectId,
    VERCEL_TEAM_ID: teamId,
    VERCEL_SCOPE: 'rayer-tung-s-projects',
    COMMIT_SHA: commitSha,
    DEPLOYMENT_ID: deploymentId,
    CURRENT_HEAD_SHA: commitSha,
    CURRENT_REMOTE_DEVELOP_SHA: commitSha,
    EVIDENCE_DIR: fixture.evidenceDir,
    STABLE_DOMAIN: stableDomain,
    LWC253_TEST_MODE: '1',
    VERCEL_POLL_ATTEMPTS: '2',
    VERCEL_POLL_INTERVAL_SECONDS: '0',
    ROLLBACK_ARTIFACT_ID: '123456789',
    ROLLBACK_ARTIFACT_URL: 'https://github.com/Rayer/llm-wiki-frontend/actions/runs/123456789/artifacts/123456789',
    ROLLBACK_ARTIFACT_DIGEST: rollbackArtifactDigestBare,
    ...overrides,
  };
}

async function runCase(scenario = 'success', overrides = {}) {
  const fixture = await setupCase(scenario);
  const env = buildEnv(fixture, overrides);
  const preflight = await runScript('preflight', env);
  const preflightMutationLog = (await readFile(join(fixture.root, 'mutation-log'), 'utf8')).trim().split('\n').filter(Boolean);
  const preflightDeploymentPostLog = (await readFile(join(fixture.root, 'deployment-post-log'), 'utf8')).trim().split('\n').filter(Boolean);
  const preflightEvidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  let result = preflight;
  if (preflight.code === undefined) result = await runScript('promote', env);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  const mutationLog = (await readFile(join(fixture.root, 'mutation-log'), 'utf8')).trim().split('\n').filter(Boolean);
  const deploymentPostLog = (await readFile(join(fixture.root, 'deployment-post-log'), 'utf8')).trim().split('\n').filter(Boolean);
  const curlCalls = (await readFile(join(fixture.root, 'curl-calls'), 'utf8')).trim().split('\n').filter(Boolean);
  return { fixture, env, preflight, result, evidence, preflightEvidence, mutationLog, deploymentPostLog, curlCalls, preflightMutationLog, preflightDeploymentPostLog };
}

async function readContext(fixture) {
  return JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment-context.json'), 'utf8'));
}

async function readRollbackContract(fixture) {
  return JSON.parse(await readFile(join(fixture.evidenceDir, 'rollback-contract.json'), 'utf8'));
}

async function readLines(path) {
  return (await readFile(path, 'utf8')).trim().split('\n').filter(Boolean);
}

async function prepareAuthEnv(fixture, env) {
  const prepared = await runScript('prepare', env);
  assert.equal(prepared.code, undefined, prepared.stderr);
  return prepared;
}

test('fails closed on contradictory DEV alias authority before mutation', async () => {
  const fixture = await setupCase();
  const env = buildEnv(fixture);
  const result = await runScript('preflight', env);

  assert.equal(result.code, 1, result.stderr);
  assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8')).trim(), '');
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.status, 'PREFLIGHT_FAILED');
  assert.equal(evidence.reason_code, 'ALIAS_AUTHORITY_CONFLICT');
});

test('rejects the retired Vercel scope slug', async () => {
  const fixture = await setupCase('success');
  const result = await runScript('preflight', buildEnv(fixture, { VERCEL_SCOPE: 'rayer-team' }));

  assert.equal(result.code, 1, result.stderr);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.status, 'PREFLIGHT_FAILED');
  assert.equal(evidence.reason_code, 'TEAM_NOT_ALLOWLISTED');
  assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8')).trim(), '');
});

test('uses bounded project-scoped alias inventory without the unsupported domain filter', async () => {
  const run = await runCase('success');
  assert.equal(run.result.code, undefined, run.result?.stderr);
  const aliasRead = run.curlCalls.find((url) => url.includes('/v4/aliases/'));
  const inventoryReads = run.curlCalls.filter((url) => url.includes('/v4/aliases?'));
  assert.match(aliasRead, /\/v4\/aliases\/llm-wiki-frontend-dev\.vercel\.app\?teamId=team_dev123$/);
  assert.equal(inventoryReads.length, 3);
  for (const url of inventoryReads) {
    assert.match(url, /\/v4\/aliases\?projectId=prj_dev123&teamId=team_dev123&limit=100$/);
    assert.doesNotMatch(url, /(?:^|[?&])domain=/);
  }
});

for (const [scenario, overrides, reasonCode] of [
  ['ci-failure', {}, 'CI_NOT_GREEN'],
  ['ci-wrong-sha', {}, 'CI_NOT_GREEN'],
  ['success', { COMMIT_SHA: 'not-a-sha' }, 'INPUT_SHA_INVALID'],
  ['success', { CURRENT_HEAD_SHA: 'fedcba9876543210fedcba9876543210fedcba98' }, 'CHECKED_OUT_SHA_MISMATCH'],
  ['success', { CURRENT_REMOTE_DEVELOP_SHA: 'fedcba9876543210fedcba9876543210fedcba98' }, 'REMOTE_DEVELOP_SHA_MISMATCH'],
  ['project-mismatch', {}, 'PROJECT_METADATA_MISMATCH'],
  ['team-mismatch', {}, 'PROJECT_METADATA_MISMATCH'],
  ['domain-mismatch', {}, 'DOMAIN_NOT_ALLOWLISTED'],
  ['alias-absent', {}, 'ALIAS_AUTHORITY_CONFLICT'],
  ['alias-divergent', {}, 'ALIAS_AUTHORITY_CONFLICT'],
  ['alias-project-mismatch', {}, 'ALIAS_AUTHORITY_CONFLICT'],
  ['rollback-freeze-failure', {}, 'ALIAS_READ_FAILED'],
]) {
  test(`fails closed before mutation for ${scenario}`, async () => {
    const run = await runCase(scenario, overrides);
    assert.equal(run.result.code, 1, run.result.stderr);
    assert.equal(run.evidence.status, 'PREFLIGHT_FAILED');
    assert.equal(run.evidence.reason_code, reasonCode);
    assert.equal(run.mutationLog.length, 0);
  });
}

test('read-only preflight records a typed create-needed decision without provider mutation', async () => {
  const run = await runCase('deployment-missing');
  assert.equal(run.result.code, undefined, run.result?.stderr);
  const context = await readContext(run.fixture);
  const contract = await readRollbackContract(run.fixture);
  assert.equal(context.target.decision, 'deployment_needed');
  assert.equal(context.target.deployment_id, null);
  assert.equal(context.source.commit_sha, commitSha);
  assert.equal(context.source.ref, 'refs/heads/develop');
  assert.equal(context.source.repository, 'Rayer/llm-wiki-frontend');
  assert.equal(context.frozen_authority.deployment_id, 'dpl_devold');
  assert.equal(context.mutation_count, 0);
  assert.equal(contract.rollback.project_id, projectId);
  assert.equal(contract.rollback.team_id, teamId);
  assert.equal(contract.rollback.alias, stableDomain);
  assert.equal(contract.rollback.deployment_id, 'dpl_devold');
  assert.equal(run.preflight.code, undefined);
  assert.equal(run.preflight.stdout.trim(), 'PREFLIGHT_READY');
  assert.equal(run.preflightMutationLog.length, 0);
  assert.equal(run.preflightDeploymentPostLog.length, 0);
  assert.equal(run.preflightEvidence.status, 'PREFLIGHT_READY');
  assert.equal(run.preflightEvidence.provider_verification.mutation_count, 0);
  assert.equal(run.evidence.status, 'SUCCESS');
  assert.equal(run.evidence.provider_verification.mutation_count, 2);
  assert.equal(run.deploymentPostLog.length, 1);
  assert.equal(run.mutationLog.length, 1);
  const deploymentPayload = JSON.parse(run.deploymentPostLog.find((entry) => entry.startsWith('{')));
  assert.equal(deploymentPayload.target, undefined);
  assert.equal(run.evidence.deployment.target, 'preview');
  assert.ok(run.evidence.provider_verification.checks.includes('deployment_create_attempted'));
  assert.ok(run.evidence.provider_verification.checks.includes('alias_mutation_attempted'));
  assert.match(run.mutationLog[0], /^alias set dpl_devready llm-wiki-frontend-dev\.vercel\.app/);
});

test('creates through historical deployments and counts deployment plus alias mutations', async () => {
  const run = await runCase('historical-deployment');
  assert.equal(run.preflightDeploymentPostLog.length, 0);
  assert.equal(run.preflightEvidence.provider_verification.mutation_count, 0);
  assert.equal(run.result.code, undefined, run.result?.stderr);
  assert.equal(run.evidence.status, 'SUCCESS');
  assert.equal(run.deploymentPostLog.length, 1);
  assert.equal(run.curlCalls.filter((url) => url === 'https://vercel.test/v13/deployments?teamId=team_dev123&forceNew=1').length, 1);
  assert.equal(run.evidence.provider_verification.mutation_count, 2);
  assert.ok(run.evidence.provider_verification.checks.includes('deployment_created'));
  assert.equal(run.mutationLog.length, 1);
});

test('ignores an old same-SHA deployment without Auth provenance and creates with forceNew', async () => {
  const run = await runCase('unmarked-old-deployment');
  assert.equal(run.result.code, undefined, run.result?.stderr);
  assert.equal(run.deploymentPostLog.length, 1);
  const deploymentCreate = run.curlCalls.find((url) => url.includes('/v13/deployments?'));
  assert.match(deploymentCreate, /[?&]forceNew=1(?:&|$)/);
  assert.equal(JSON.parse(run.deploymentPostLog[0]).meta.lwcAuthEnvProvenance, deploymentAuthMarker);
  assert.equal(run.evidence.deployment.id, deploymentId);
});

test('reuses a same-SHA deployment only when its exact Auth provenance marker is present', async () => {
  const run = await runCase('success');
  assert.equal(run.result.code, undefined, run.result?.stderr);
  assert.equal(run.deploymentPostLog.length, 0);
  assert.equal(run.evidence.deployment.id, deploymentId);
});

test('fails closed when a newly created deployment read-back marker mismatches', async () => {
  const fixture = await setupCase('unmarked-old-deployment');
  const env = buildEnv(fixture);
  const preflight = await runScript('preflight', env);
  assert.equal(preflight.code, undefined, preflight.stderr);
  await writeFile(join(fixture.root, 'scenario'), 'marker-mismatch');
  const result = await runScript('promote', env);
  assert.equal(result.code, 1, result.stderr);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.reason_code, 'DEPLOYMENT_SOURCE_MISMATCH');
  assert.equal(evidence.provider_verification.mutation_count, 1);
  assert.equal((await readLines(join(fixture.root, 'mutation-log'))).length, 0);
});

test('promote without durable artifact handoff performs no provider mutation', async () => {
  const fixture = await setupCase('deployment-missing');
  const env = buildEnv(fixture, { ROLLBACK_ARTIFACT_ID: '' });
  const preflight = await runScript('preflight', env);
  const result = await runScript('promote', env);
  assert.equal(preflight.code, undefined, preflight.stderr);
  assert.equal(result.code, 1, result.stderr);
  assert.equal((await readFile(join(fixture.root, 'deployment-post-log'), 'utf8')).trim(), '');
  assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8')).trim(), '');
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.status, 'PREFLIGHT_FAILED');
  assert.equal(evidence.reason_code, 'ROLLBACK_ARTIFACT_INVALID');
  assert.equal(evidence.provider_verification.mutation_count, 0);
});

for (const [label, digest] of [
  ['prefixed-sha256', `sha256:${rollbackArtifactDigestBare}`],
  ['uppercase', rollbackArtifactDigestBare.toUpperCase()],
  ['too-short-63', rollbackArtifactDigestBare.substring(0, 63)],
  ['too-long-65', `${rollbackArtifactDigestBare}0`],
  ['empty', ''],
]) {
  test(`rejects invalid durable artifact digest ${label} before mutation`, async () => {
    const run = await runCase('success', { ROLLBACK_ARTIFACT_DIGEST: digest });
    const evidence = JSON.parse(await readFile(join(run.fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
    assert.equal(run.result.code, 1, run.result?.stderr);
    assert.equal(evidence.status, 'PREFLIGHT_FAILED');
    assert.equal(evidence.reason_code, 'ROLLBACK_ARTIFACT_INVALID');
    assert.equal(run.mutationLog.length, 0);
    assert.equal(run.deploymentPostLog.length, 0);
  });
}

test('page-one and page-two uid deployments are normalized and reused without deployment creation', async () => {
  const run = await runCase('page-2-exact');
  assert.equal(run.result.code, undefined, run.result?.stderr);
  assert.equal(run.deploymentPostLog.length, 0);
  assert.equal(run.mutationLog.length, 1);
  assert.equal(run.evidence.deployment.id, deploymentId);
  assert.equal(run.evidence.provider_verification.mutation_count, 1);
  assert.ok(run.curlCalls.some((url) => url.includes('/v6/deployments?') && url.includes('until=cursor-2')));
  const deploymentCalls = run.curlCalls.filter((url) => url.includes('/v6/deployments?'));
  assert.equal(deploymentCalls.length, 2);
  assert.ok(!deploymentCalls[0].includes('until='));
  assert.ok(deploymentCalls[1].includes('until=cursor-2'));
});

test('existing candidate source failure remains zero-mutation blocked', async () => {
  const run = await runCase('existing-source-mismatch');
  assert.equal(run.result.code, 1);
  assert.equal(run.evidence.status, 'PREFLIGHT_FAILED');
  assert.equal(run.evidence.reason_code, 'DEPLOYMENT_SOURCE_MISMATCH');
  assert.equal(run.evidence.provider_verification.mutation_count, 0);
  assert.equal(run.deploymentPostLog.length, 0);
  assert.equal(run.mutationLog.length, 0);
});

test('reconciles a partial mutation and records the uncertain state without retrying', async () => {
  const run = await runCase('partial-mutation');
  assert.equal(run.result.code, 1);
  assert.equal(run.evidence.status, 'PARTIAL_MUTATION');
  assert.equal(run.evidence.reason_code, 'MUTATION_UNCERTAIN');
  assert.equal(run.evidence.observed_alias.deployment_id, deploymentId);
  assert.equal(run.mutationLog.length, 1);
});

test('refuses to mutate without a durable rollback artifact handoff', async () => {
  const run = await runCase('success', { ROLLBACK_ARTIFACT_ID: '' });
  assert.equal(run.result.code, 1);
  assert.equal(run.evidence.status, 'PREFLIGHT_FAILED');
  assert.equal(run.evidence.reason_code, 'ROLLBACK_ARTIFACT_INVALID');
  assert.equal(run.mutationLog.length, 0);
});

test('fails closed when post-mutation alias or deployment read-back diverges', async () => {
  const run = await runCase('post-read-mismatch');
  assert.equal(run.result.code, 1);
  assert.equal(run.evidence.status, 'PARTIAL_MUTATION');
  assert.equal(run.evidence.reason_code, 'POSTCHECK_MISMATCH');
  assert.match(run.evidence.next_action, /reconcile/i);
  assert.equal(run.mutationLog.length, 1);
});

for (const [scenario, reasonCode] of [
  ['create-uncertain', 'DEPLOYMENT_CREATE_UNCERTAIN'],
  ['create-poll-timeout', 'DEPLOYMENT_POLL_TIMEOUT'],
  ['create-source-mismatch', 'DEPLOYMENT_SOURCE_MISMATCH'],
  ['create-read-failure', 'DEPLOYMENT_INSPECT_FAILED'],
]) {
  test(`classifies ${scenario} as partial mutation and preserves rollback identity`, async () => {
    const run = await runCase(scenario);
    assert.equal(run.result.code, 1, run.result.stderr);
    assert.equal(run.evidence.status, 'PARTIAL_MUTATION');
    assert.equal(run.evidence.reason_code, reasonCode);
    assert.equal(run.evidence.provider_verification.mutation_count, 1);
    assert.equal(run.evidence.rollback.deployment_id, 'dpl_devold');
    assert.equal(run.deploymentPostLog.length, 1);
    assert.equal(run.mutationLog.length, 0);
  });
}

test('configures an absent Auth URL env exactly once and requires exact readback', async () => {
  const fixture = await setupCase('auth-env-absent');
  const env = buildEnv(fixture);
  const preflight = await runScript('preflight', env);
  assert.equal(preflight.code, undefined, preflight.stderr);
  const contract = await readRollbackContract(fixture);
  assert.equal(contract.rollback.auth_env.preflight_state, 'absent');
  assert.equal(contract.rollback.auth_env.key, authEnvKey);
  assert.deepEqual(contract.rollback.auth_env.target, ['preview']);
  assert.equal(contract.rollback.auth_env.git_branch, 'develop');
  assert.match(contract.rollback.auth_env.expected_value_sha256, /^[0-9a-f]{64}$/);

  await prepareAuthEnv(fixture, env);
  const configured = await runScript('configure', env);
  assert.equal(configured.code, undefined, configured.stderr);
  const posts = await readLines(join(fixture.root, 'env-post-log'));
  assert.equal(posts.length, 1);
  assert.deepEqual(JSON.parse(posts[0]), {
    key: authEnvKey,
    value: authEnvUrl,
    type: 'plain',
    target: ['preview'],
    gitBranch: 'develop',
  });
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.status, 'SUCCESS');
  assert.equal(evidence.auth_env.preflight_state, 'absent');
  assert.equal(evidence.auth_env.configured_state, 'created');
  assert.equal(evidence.auth_env.readback_state, 'exact');
  assert.equal(evidence.auth_env.mutation_count, 1);
  assert.equal(evidence.provider_verification.provider_mutation_count, 1);

  const promoted = await runScript('promote', env);
  assert.equal(promoted.code, undefined, promoted.stderr);
  const promotedEvidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.ok(promotedEvidence.provider_verification.checks.includes('auth_env_create_attempted'));
  assert.ok(promotedEvidence.provider_verification.checks.includes('auth_env_created'));
  assert.ok(promotedEvidence.provider_verification.checks.includes('auth_env_exact_readback'));
  assert.ok(promotedEvidence.provider_verification.checks.includes('auth_env_promotion_gate_exact'));
});

test('counts one provider Auth env mutation when the durable attempt counter is zero', async () => {
  const fixture = await setupCase('auth-env-absent');
  const env = buildEnv(fixture);
  assert.equal((await runScript('preflight', env)).code, undefined);
  await prepareAuthEnv(fixture, env);
  const statePath = join(fixture.evidenceDir, 'auth-env-state.json');
  const state = JSON.parse(await readFile(statePath, 'utf8'));
  state.mutation_count = 0;
  await writeFile(statePath, JSON.stringify(state));

  const configured = await runScript('configure', env);
  assert.equal(configured.code, undefined, configured.stderr);
  assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 1);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.provider_verification.provider_mutation_count, 1);
});

test('does not mutate an already exact Auth URL env', async () => {
  const fixture = await setupCase('success');
  const env = buildEnv(fixture);
  assert.equal((await runScript('preflight', env)).code, undefined);
  await prepareAuthEnv(fixture, env);
  const configured = await runScript('configure', env);
  assert.equal(configured.code, undefined, configured.stderr);
  assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 0);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.auth_env.preflight_state, 'exact');
  assert.equal(evidence.auth_env.configured_state, 'already_exact');
  assert.equal(evidence.auth_env.readback_state, 'exact');
  assert.equal(evidence.auth_env.mutation_count, 0);
});

for (const [scenario, reasonCode] of [
  ['auth-env-wrong-value', 'AUTH_ENV_VALUE_MISMATCH'],
  ['auth-env-wrong-type', 'AUTH_ENV_METADATA_MISMATCH'],
  ['auth-env-wrong-target', 'AUTH_ENV_METADATA_MISMATCH'],
  ['auth-env-wrong-branch', 'AUTH_ENV_METADATA_MISMATCH'],
  ['auth-env-duplicate', 'AUTH_ENV_DUPLICATE'],
  ['auth-env-ambiguous', 'AUTH_ENV_AMBIGUOUS'],
]) {
  test(`rejects ${scenario} before any Auth env mutation`, async () => {
    const fixture = await setupCase(scenario);
    const result = await runScript('preflight', buildEnv(fixture));
    assert.equal(result.code, 1, result.stderr);
    const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
    assert.equal(evidence.reason_code, reasonCode);
    assert.equal(evidence.provider_verification.mutation_count, 0);
    assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 0);
  });
}

for (const scenario of ['auth-env-create-failed', 'auth-env-create-uncertain']) {
  test(`classifies ${scenario} as partial Auth env mutation`, async () => {
    const fixture = await setupCase('auth-env-absent');
    await writeFile(join(fixture.root, 'scenario'), scenario);
    const env = buildEnv(fixture);
    assert.equal((await runScript('preflight', env)).code, undefined);
    await prepareAuthEnv(fixture, env);
    const result = await runScript('configure', env);
    assert.equal(result.code, 1, result.stderr);
    const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
    assert.equal(evidence.status, 'PARTIAL_MUTATION');
    assert.equal(evidence.reason_code, 'AUTH_ENV_CREATE_UNCERTAIN');
    assert.equal(evidence.auth_env.configured_state, 'create_uncertain');
    assert.equal(evidence.auth_env.mutation_count, 1);
    assert.match(evidence.next_action, /reconcile/i);
    assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 1);
  });
}

test('requires provider reconciliation before retrying after uncertain Auth env creation', async () => {
  const fixture = await setupCase('auth-env-absent');
  const env = buildEnv(fixture);
  assert.equal((await runScript('preflight', env)).code, undefined);
  await prepareAuthEnv(fixture, env);

  await writeFile(join(fixture.root, 'scenario'), 'auth-env-create-uncertain');
  const firstConfigure = await runScript('configure', env);
  assert.equal(firstConfigure.code, 1, firstConfigure.stderr);

  await writeFile(join(fixture.root, 'scenario'), 'success');
  const retry = await runScript('configure', env);
  assert.equal(retry.code, 1, retry.stderr);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.reason_code, 'AUTH_ENV_RECONCILIATION_REQUIRED');
  assert.equal(evidence.auth_env.configured_state, 'create_uncertain');
  assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 1);
});

test('blocks a fresh run on a durable prior Auth env create attempt before POST', async () => {
  const fixture = await setupCase('prior-auth-create-attempted');
  const env = buildEnv(fixture, { GITHUB_RUN_ID: '2002' });
  const result = await runScript('preflight', env);
  assert.equal(result.code, 1, result.stderr);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.reason_code, 'AUTH_ENV_RECONCILIATION_REQUIRED');
  assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 0);
});

test('terminal-success Auth env state permits exact idempotent configuration without POST', async () => {
  const fixture = await setupCase('prior-auth-terminal-success');
  const env = buildEnv(fixture, { GITHUB_RUN_ID: '2002' });
  assert.equal((await runScript('preflight', env)).code, undefined);
  await prepareAuthEnv(fixture, env);
  const configured = await runScript('configure', env);
  assert.equal(configured.code, undefined, configured.stderr);
  assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 0);
});

test('standard terminal Auth env state binds its original run identity', async () => {
  const fixture = await setupCase('success');
  const env = buildEnv(fixture);
  assert.equal((await runScript('preflight', env)).code, undefined);
  await prepareAuthEnv(fixture, env);
  assert.equal((await runScript('configure', env)).code, undefined);
  const state = JSON.parse(await readFile(join(fixture.evidenceDir, 'auth-env-state.json'), 'utf8'));
  assert.equal(state.workflow_run_id, '1001');
  assert.equal(state.original_run_id, '1001');
});

test('terminal-exact artifacts are downloaded and bound to their exact owner and state identity', async () => {
  const fixture = await setupCase('prior-auth-terminal-exact-spoofed');
  const env = buildEnv(fixture, { GITHUB_RUN_ID: '2002' });
  const result = await runScript('preflight', env);
  assert.equal(result.code, 1, result.stderr);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.reason_code, 'AUTH_ENV_DURABLE_READ_FAILED');
  assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 0);
});

test('terminal artifacts reject an owner from an unrelated workflow', async () => {
  const fixture = await setupCase('prior-auth-terminal-owner-spoofed');
  const env = buildEnv(fixture, { GITHUB_RUN_ID: '2002' });
  const result = await runScript('preflight', env);
  assert.equal(result.code, 1, result.stderr);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.reason_code, 'AUTH_ENV_DURABLE_READ_FAILED');
  assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 0);
});

test('paired terminal-absent Auth env state clears uncertainty and permits exactly one standard POST', async () => {
  const fixture = await setupCase('prior-auth-terminal-absent');
  const env = buildEnv(fixture, { GITHUB_RUN_ID: '2002' });
  assert.equal((await runScript('preflight', env)).code, undefined);
  await prepareAuthEnv(fixture, env);
  assert.equal((await runScript('configure', env)).code, undefined);
  assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 1);
});

for (const scenario of ['prior-auth-terminal-absent-later-attempted', 'prior-auth-terminal-absent-later-attempted-reordered']) {
  test(`${scenario} does not let an older terminal absence mask a newer attempt`, async () => {
    const fixture = await setupCase(scenario);
    const env = buildEnv(fixture, { GITHUB_RUN_ID: '2002' });
    const result = await runScript('preflight', env);
    assert.equal(result.code, 1, result.stderr);
    const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
    assert.equal(evidence.reason_code, 'AUTH_ENV_RECONCILIATION_REQUIRED');
    assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 0);
  });
}

test('duplicate durable terminal resolution fails closed before any POST', async () => {
  const fixture = await setupCase('prior-auth-terminal-absent-duplicate');
  const env = buildEnv(fixture, { GITHUB_RUN_ID: '2002' });
  const result = await runScript('preflight', env);
  assert.equal(result.code, 1, result.stderr);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.reason_code, 'AUTH_ENV_DURABLE_READ_FAILED');
  assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 0);
});

for (const scenario of ['prior-auth-unpaired-terminal-absent', 'prior-auth-spoofed-terminal-absent']) {
  test(`${scenario} cannot clear durable Auth env uncertainty`, async () => {
    const fixture = await setupCase(scenario);
    const env = buildEnv(fixture, { GITHUB_RUN_ID: '2002' });
    const result = await runScript('preflight', env);
    assert.equal(result.code, 1, result.stderr);
    const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
    assert.equal(evidence.reason_code, scenario === 'prior-auth-spoofed-terminal-absent' ? 'AUTH_ENV_DURABLE_READ_FAILED' : 'AUTH_ENV_RECONCILIATION_REQUIRED');
    assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 0);
  });
}

for (const [scenario, status, code] of [
  ['auth-env-http-400', 400, 'ENV_CONFLICT'],
  ['auth-env-http-403', 403, null],
]) {
  test(`records sanitized Auth env HTTP ${status} diagnostics without response body`, async () => {
    const fixture = await setupCase('auth-env-absent');
    await writeFile(join(fixture.root, 'scenario'), scenario);
    const env = buildEnv(fixture);
    assert.equal((await runScript('preflight', env)).code, undefined);
    await prepareAuthEnv(fixture, env);
    const result = await runScript('configure', env);
    assert.equal(result.code, 1);
    const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
    assert.equal(evidence.auth_env.http_status, status);
    assert.equal(evidence.auth_env.provider_error_code, code);
    assert.equal(evidence.reason_code, 'AUTH_ENV_CREATE_REJECTED');
    assert.doesNotMatch(JSON.stringify(evidence), /arbitrary provider text|forbidden message/);
    assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 1);
  });
}

test('network failure records HTTP 000 and remains uncertain', async () => {
  const fixture = await setupCase('auth-env-absent');
  await writeFile(join(fixture.root, 'scenario'), 'auth-env-create-uncertain');
  const env = buildEnv(fixture);
  assert.equal((await runScript('preflight', env)).code, undefined);
  await prepareAuthEnv(fixture, env);
  assert.equal((await runScript('configure', env)).code, 1);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.auth_env.http_status, 0);
  assert.equal(evidence.auth_env.provider_error_code, null);
  assert.equal(evidence.reason_code, 'AUTH_ENV_CREATE_UNCERTAIN');
});

for (const [scenario, reasonCode] of [
  ['auth-env-page-2-exact', 'SUCCESS'],
  ['auth-env-page-2-duplicate', 'AUTH_ENV_DUPLICATE'],
  ['auth-env-pagination-malformed', 'AUTH_ENV_READ_FAILED'],
  ['auth-env-pagination-cursor-loop', 'AUTH_ENV_READ_FAILED'],
  ['auth-env-pagination-max-pages', 'AUTH_ENV_READ_FAILED'],
]) {
  test(`handles ${scenario} with bounded Auth env pagination`, async () => {
    const fixture = await setupCase(scenario);
    const result = await runScript('preflight', buildEnv(fixture));
    assert.equal(result.code, reasonCode === 'SUCCESS' ? undefined : 1, result.stderr);
    const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
    if (reasonCode === 'SUCCESS') {
      assert.equal(evidence.status, 'PREFLIGHT_READY');
      assert.ok((await readLines(join(fixture.root, 'curl-calls'))).some((url) => url.includes('until=auth-cursor-2')));
    } else {
      assert.equal(evidence.reason_code, reasonCode);
      assert.equal((await readLines(join(fixture.root, 'env-post-log'))).length, 0);
    }
  });
}

test('promotion refuses an absent Auth URL env before deployment lookup or alias mutation', async () => {
  const fixture = await setupCase('auth-env-absent');
  const env = buildEnv(fixture);
  assert.equal((await runScript('preflight', env)).code, undefined);
  const beforePromote = await readLines(join(fixture.root, 'curl-calls'));
  const result = await runScript('promote', env);
  assert.equal(result.code, 1, result.stderr);
  const afterPromote = (await readLines(join(fixture.root, 'curl-calls'))).slice(beforePromote.length);
  assert.equal(afterPromote.filter((url) => url.includes('/v6/deployments?')).length, 0);
  assert.equal((await readLines(join(fixture.root, 'deployment-post-log'))).length, 0);
  assert.equal((await readLines(join(fixture.root, 'mutation-log'))).length, 0);
  const evidence = JSON.parse(await readFile(join(fixture.evidenceDir, 'vercel-dev-deployment.json'), 'utf8'));
  assert.equal(evidence.reason_code, 'AUTH_ENV_NOT_EXACT');
});

test('keeps the DEV workflow manual, exact-SHA gated, and secret-scoped', async () => {
  const workflowSource = await readFile(join(repoRoot, '.github/workflows/vercel-dev-deployment.yml'), 'utf8');
  const workflow = parseYaml(workflowSource);
  assert.deepEqual(Object.keys(workflow.on.workflow_dispatch.inputs), ['commit_sha', 'ticket_ref']);
  assert.equal(workflow.on.workflow_dispatch.inputs.commit_sha.required, true);
  assert.equal(workflow.on.workflow_dispatch.inputs.commit_sha.type, 'string');
  assert.equal(workflow.on.push, undefined);
  assert.equal(workflow.concurrency['cancel-in-progress'], false);
  assert.equal(workflow.jobs.promote.environment.name, 'Development');
  assert.equal(workflow.jobs.promote.if, "github.ref == 'refs/heads/develop'");

  const steps = workflow.jobs.promote.steps;
  const checkout = steps.find(({ name }) => name === 'Check out the exact requested SHA');
  assert.equal(checkout.with.ref, '${{ inputs.commit_sha }}');
  assert.equal(checkout.with['persist-credentials'], false);
  const validate = steps.find(({ name }) => name === 'Validate requested SHA, remote develop, and canonical CI');
  const install = steps.find(({ name }) => name === 'Install pinned Vercel CLI');
  const preflight = steps.find(({ name }) => name === 'Preflight exact DEV deployment and rollback contract');
  const rollbackUpload = steps.find(({ name }) => name === 'Upload durable DEV rollback contract');
  const authPrepare = steps.find(({ name }) => name === 'Prepare durable DEV Auth env mutation guard');
  const authAttemptUpload = steps.find(({ name }) => name === 'Upload durable DEV Auth env mutation guard');
  const configure = steps.find(({ name }) => name === 'Ensure exact DEV Auth URL project env');
  const authTerminalUpload = steps.find(({ name }) => name === 'Upload terminal DEV Auth env state');
  const promote = steps.find(({ name }) => name === 'Promote exactly the stable DEV alias');
  assert.ok(steps.indexOf(validate) < steps.indexOf(install));
  assert.ok(steps.indexOf(install) < steps.indexOf(preflight));
  assert.ok(steps.indexOf(preflight) < steps.indexOf(promote));
  assert.ok(steps.indexOf(preflight) < steps.indexOf(rollbackUpload));
  assert.ok(steps.indexOf(rollbackUpload) < steps.indexOf(promote));
  assert.ok(configure);
  assert.ok(authPrepare);
  assert.ok(authAttemptUpload);
  assert.ok(authTerminalUpload);
  assert.ok(steps.indexOf(rollbackUpload) < steps.indexOf(configure));
  assert.ok(steps.indexOf(authPrepare) < steps.indexOf(authAttemptUpload));
  assert.ok(steps.indexOf(authAttemptUpload) < steps.indexOf(configure));
  assert.ok(steps.indexOf(configure) < steps.indexOf(promote));
  assert.ok(steps.indexOf(configure) < steps.indexOf(authTerminalUpload));
  assert.ok(steps.indexOf(authTerminalUpload) < steps.indexOf(promote));
  assert.deepEqual(Object.keys(validate.env), ['EVIDENCE_DIR', 'GITHUB_TOKEN']);
  assert.deepEqual(Object.keys(preflight.env).sort(), ['EVIDENCE_DIR', 'GITHUB_TOKEN', 'VERCEL_PROJECT_ID', 'VERCEL_SCOPE', 'VERCEL_TEAM_ID', 'VERCEL_TOKEN'].sort());
  assert.deepEqual(Object.keys(promote.env).sort(), ['EVIDENCE_DIR', 'ROLLBACK_ARTIFACT_DIGEST', 'ROLLBACK_ARTIFACT_ID', 'ROLLBACK_ARTIFACT_URL', 'VERCEL_PROJECT_ID', 'VERCEL_SCOPE', 'VERCEL_TEAM_ID', 'VERCEL_TOKEN'].sort());
  assert.deepEqual(Object.keys(configure.env).sort(), ['EVIDENCE_DIR', 'ROLLBACK_ARTIFACT_DIGEST', 'ROLLBACK_ARTIFACT_ID', 'ROLLBACK_ARTIFACT_URL', 'VERCEL_PROJECT_ID', 'VERCEL_SCOPE', 'VERCEL_TEAM_ID', 'VERCEL_TOKEN'].sort());
  assert.deepEqual(Object.keys(authPrepare.env).sort(), ['EVIDENCE_DIR', 'GITHUB_TOKEN', 'ROLLBACK_ARTIFACT_DIGEST', 'ROLLBACK_ARTIFACT_ID', 'ROLLBACK_ARTIFACT_URL', 'VERCEL_PROJECT_ID', 'VERCEL_SCOPE', 'VERCEL_TEAM_ID', 'VERCEL_TOKEN'].sort());
  assert.equal(authPrepare.run, 'bash .github/scripts/vercel-dev-deployment.sh prepare');
  assert.equal(authAttemptUpload.uses, 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02');
  assert.equal(authTerminalUpload.uses, 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02');
  assert.match(authAttemptUpload.with.name, /steps\.auth_env_prepare\.outputs\.state_suffix/);
  assert.match(authTerminalUpload.with.name, /terminal_exact/);
  assert.equal(authTerminalUpload.if, 'success()');
  assert.equal(configure.run, 'bash .github/scripts/vercel-dev-deployment.sh configure');
  assert.equal(configure.env.ROLLBACK_ARTIFACT_ID, '${{ steps.rollback_upload.outputs.artifact-id }}');
  assert.equal(configure.env.ROLLBACK_ARTIFACT_URL, '${{ steps.rollback_upload.outputs.artifact-url }}');
  assert.equal(configure.env.ROLLBACK_ARTIFACT_DIGEST, '${{ steps.rollback_upload.outputs.artifact-digest }}');
  assert.match(preflight.env.VERCEL_PROJECT_ID, /^\$\{\{ secrets\.VERCEL_PROJECT_ID \}\}$/);
  assert.match(promote.env.VERCEL_TOKEN, /^\$\{\{ secrets\.VERCEL_TOKEN \}\}$/);
  assert.doesNotMatch(workflowSource, /vercel\s+(build|deploy)|next\s+build/);

  const scriptSource = await readFile(join(repoRoot, '.github/scripts/vercel-dev-deployment.sh'), 'utf8');
  const preflightBody = scriptSource.slice(scriptSource.indexOf('run_preflight()'), scriptSource.indexOf('load_context()'));
  assert.doesNotMatch(preflightBody, /api_post|alias_set/);

  const runBlocks = steps.filter(({ run }) => typeof run === 'string').map(({ run }) => run.replace(/\$\{\{[\s\S]*?\}\}/g, 'VALUE'));
  await execFileAsync('bash', ['-n', '.github/scripts/vercel-dev-deployment.sh']);
  await execFileAsync('bash', ['-n', '-c', runBlocks.join('\n')]);
});
