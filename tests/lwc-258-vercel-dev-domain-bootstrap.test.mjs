import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
import test from 'node:test';
import { load as parseYaml } from 'js-yaml';

const execFileAsync = promisify(execFile);
const repoRoot = process.cwd();
const projectId = 'prj_test123';
const teamId = 'team_test123';
const domain = 'wiki.dev.rayer.idv.tw';
const commitSha = '0123456789abcdef0123456789abcdef01234567';

function canonicalConfig(scenario = 'exact') {
  return {
    configuredBy: 'CNAME',
    acceptedChallenges: ['http', 'dns-01'],
    misconfigured: !['ready', 'already-present', 'exact'].includes(scenario),
    recommendedCNAME: [
      { rank: 1, value: 'cname.vercel-dns-123.vercel-dns.com' },
      { rank: 2, value: 'cname.vercel-dns-legacy.vercel-dns.com' },
    ],
    recommendedIPv4: [
      { rank: 1, value: ['76.76.21.21', '76.76.21.22'] },
      { rank: 2, value: ['192.0.2.1'] },
    ],
    verification: [{ value: 'secret-verification-value' }],
    unknownSecret: 'classified',
  };
}

async function writeConfig(root, config) {
  await writeFile(join(root, 'config.json'), JSON.stringify(config));
}

async function setup(scenario) {
  const root = await mkdtemp(join(tmpdir(), 'lwc-258-domain-bootstrap-'));
  const bin = join(root, 'bin');
  const evidence = join(root, 'evidence');
  await execFileAsync('mkdir', ['-p', bin, evidence]);
  await writeFile(join(root, 'scenario'), scenario);
  await writeFile(join(root, 'domains.json'), JSON.stringify({ domains: ['absent', 'ambiguous-write'].includes(scenario) ? [] : scenario === 'unrelated-domain' ? [{ name: 'other.dev.rayer.idv.tw' }] : scenario === 'spoofed-canonical' ? [{ name: domain, projectId: 'prj_other' }] : [{ name: domain, configuredBy: 'manual' }] }));
  await writeConfig(root, canonicalConfig(scenario));
  await execFileAsync('cp', [join(repoRoot, 'tests/fixtures/lwc-258-domain-bootstrap-fake-curl.sh'), join(bin, 'curl')]);
  await execFileAsync('cp', [join(repoRoot, 'tests/fixtures/lwc-253-fake-vercel.sh'), join(bin, 'vercel')]);
  await execFileAsync('chmod', ['+x', join(bin, 'curl'), join(bin, 'vercel')]);
  return { root, bin, evidence };
}

function envFor(fixture, extra = {}) {
  return {
    ...process.env,
    PATH: `${fixture.bin}:${process.env.PATH}`,
    FIXTURE_ROOT: fixture.root,
    EVIDENCE_DIR: fixture.evidence,
    GITHUB_REPOSITORY: 'Rayer/llm-wiki-frontend',
    GITHUB_ACTIONS: '',
    GITHUB_API_URL: 'https://github.test',
    GITHUB_TOKEN: 'github-sentinel-token',
    GITHUB_RUN_ID: '777',
    COMMIT_SHA: commitSha,
    CURRENT_HEAD_SHA: commitSha,
    CURRENT_REMOTE_DEVELOP_SHA: commitSha,
    LWC253_TEST_MODE: '1',
    VERCEL_API_BASE_URL: 'https://vercel.test',
    VERCEL_TOKEN: 'vercel-sentinel-token',
    VERCEL_PROJECT_ID: projectId,
    VERCEL_TEAM_ID: teamId,
    VERCEL_SCOPE: 'rayer-tung-s-projects',
    ...extra,
  };
}

async function run(fixture, extra) {
  const validation = await runMode(fixture, 'validate', extra);
  if (validation.code !== undefined) return validation;
  return execFileAsync('bash', ['.github/scripts/vercel-dev-deployment.sh', 'bootstrap-domain'], {
    cwd: repoRoot,
    env: envFor(fixture, extra),
    maxBuffer: 1024 * 1024,
  }).catch((error) => error);
}

async function runMode(fixture, mode, extra) {
  return execFileAsync('bash', ['.github/scripts/vercel-dev-deployment.sh', mode], {
    cwd: repoRoot,
    env: envFor(fixture, extra),
    maxBuffer: 1024 * 1024,
  }).catch((error) => error);
}

async function evidence(fixture) {
  return JSON.parse(await readFile(join(fixture.evidence, 'vercel-dev-deployment.json'), 'utf8'));
}

test('bootstrap contract exposes canonical constants and a manual-only workflow', async () => {
  const script = await readFile(join(repoRoot, '.github/scripts/vercel-dev-deployment.sh'), 'utf8');
  const workflow = await readFile(join(repoRoot, '.github/workflows/vercel-dev-domain-bootstrap.yml'), 'utf8');
  assert.match(script, /wiki\.dev\.rayer\.idv\.tw/);
  assert.match(script, /https:\/\/auth\.dev\.rayer\.idv\.tw/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.doesNotMatch(workflow, /on:\s*\n\s*push:/);
  const parsed = parseYaml(workflow);
  assert.equal(parsed.on.workflow_dispatch.inputs.commit_sha.required, true);
  assert.equal(parsed.on.workflow_dispatch.inputs.commit_sha.type, 'string');
  assert.equal(parsed.permissions.contents, 'read');
  assert.equal(parsed.permissions.actions, 'read');
  assert.equal(parsed.jobs.bootstrap.env.COMMIT_SHA, '${{ inputs.commit_sha }}');
  assert.equal(parsed.jobs.bootstrap.steps[0].with.ref, '${{ inputs.commit_sha }}');
  assert.equal(parsed.jobs.bootstrap.steps[0].with['fetch-depth'], 0);
  const validate = parsed.jobs.bootstrap.steps.find(({ name }) => name === 'Validate requested SHA, remote develop, and canonical CI');
  assert.ok(validate);
  assert.equal(validate.run, 'bash .github/scripts/vercel-dev-deployment.sh validate');
  assert.equal(validate.env.GITHUB_TOKEN, '${{ github.token }}');
  const bootstrap = parsed.jobs.bootstrap.steps.find(({ name }) => name === 'Bootstrap exact DEV custom domain');
  assert.equal(bootstrap.env.COMMIT_SHA, '${{ inputs.commit_sha }}');
  assert.equal(bootstrap.env.GITHUB_RUN_ID, '${{ github.run_id }}');
});

for (const scenario of ['exact', 'absent', 'already-present', 'unrelated-domain']) {
  test(`bootstrap ${scenario} is bounded`, async () => {
    const fixture = await setup(scenario);
    const result = await run(fixture);
    assert.equal(result.code, undefined, result.stderr);
    const output = await evidence(fixture);
    assert.equal(output.target.stable_domain, domain);
    assert.equal(output.target.project_id, projectId);
    assert.equal(output.provider_verification.provider_mutation_count, ['absent', 'unrelated-domain'].includes(scenario) ? 1 : 0);
    assert.equal(output.target.domain_config.status, scenario === 'already-present' || scenario === 'exact' ? 'READY' : 'DNS_PENDING');
    assert.equal(output.target.domain_config.recommended_cname, 'cname.vercel-dns-123.vercel-dns.com');
    assert.deepEqual(output.target.domain_config.recommended_ipv4, ['76.76.21.21', '76.76.21.22']);
    assert.equal(output.source.execution_commit_sha, commitSha);
    assert.equal(output.source.execution_run_id, 777);
    assert.equal(output.source.checked_out_sha, commitSha);
    assert.equal(output.source.current_remote_develop_sha, commitSha);
    assert.equal(output.source.canonical_ci.run_id, 123);
    assert.doesNotMatch(JSON.stringify(output), /secret-verification-value/);
    assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8').catch(() => '')).trim(), ['absent', 'unrelated-domain'].includes(scenario) ? 'POST' : '');
  });
}

test('bootstrap rejects a spoofed canonical domain record without mutation', async () => {
  const fixture = await setup('spoofed-canonical');
  const result = await run(fixture);
  assert.equal(result.code, 1);
  assert.equal((await evidence(fixture)).reason_code, 'DOMAIN_METADATA_MISMATCH');
  assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8').catch(() => '')).trim(), '');
});

test('validation rejects a moving origin/develop SHA and canonical CI failure', async () => {
  const moving = await setup('exact');
  const movingResult = await runMode(moving, 'validate', { CURRENT_REMOTE_DEVELOP_SHA: 'fedcba9876543210fedcba9876543210fedcba98' });
  assert.equal(movingResult.code, 1);
  assert.equal((await evidence(moving)).reason_code, 'REMOTE_DEVELOP_SHA_MISMATCH');

  const failedCi = await setup('ci-failure');
  const failedCiResult = await runMode(failedCi, 'validate');
  assert.equal(failedCiResult.code, 1);
  assert.equal((await evidence(failedCi)).reason_code, 'CI_NOT_GREEN');
});

test('bootstrap sends the exact Vercel domain association request and reads config', async () => {
  const fixture = await setup('absent');
  const result = await run(fixture);
  assert.equal(result.code, undefined, result.stderr);
  const requests = (await readFile(join(fixture.root, 'request-log'), 'utf8')).trim().split('\n');
  assert.ok(requests.some((request) => request.startsWith(`GET|https://vercel.test/v9/projects/${projectId}/domains?teamId=${teamId}|`)));
  assert.ok(requests.some((request) => request === `POST|https://vercel.test/v10/projects/${projectId}/domains?teamId=${teamId}|application/json|{"name":"${domain}"}`));
  assert.ok(requests.some((request) => request.startsWith(`GET|https://vercel.test/v6/domains/${domain}/config?teamId=${teamId}&projectIdOrName=${projectId}|`)));
});

for (const scenario of ['config-read-failure', 'misconfigured']) {
  test(`standard preflight fails closed for ${scenario}`, async () => {
    const fixture = await setup(scenario);
    const result = await runMode(fixture, 'preflight', {
      CURRENT_HEAD_SHA: '0123456789abcdef0123456789abcdef01234567',
      CURRENT_REMOTE_DEVELOP_SHA: '0123456789abcdef0123456789abcdef01234567',
      COMMIT_SHA: '0123456789abcdef0123456789abcdef01234567',
    });
    assert.equal(result.code, 1);
    assert.equal((await evidence(fixture)).reason_code, scenario === 'config-read-failure' ? 'DOMAIN_CONFIG_READ_FAILED' : 'DOMAIN_DNS_PENDING');
    assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8').catch(() => '')).trim(), '');
  });
}

test('bootstrap fails closed after an ambiguous POST and does not retry', async () => {
  const fixture = await setup('ambiguous-write');
  const result = await run(fixture);
  assert.equal(result.code, 1);
  const output = await evidence(fixture);
  assert.equal(output.reason_code, 'DOMAIN_CREATE_UNCERTAIN');
  assert.equal(output.provider_verification.provider_mutation_count, 1);
  assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8').catch(() => '')).trim(), 'POST');
});

test('domain config contract uses official CNAME rank selection and redacts non-persistent fields', async () => {
  const fixture = await setup('already-present');
  const config = canonicalConfig('already-present');
  config.recommendedCNAME = [
    { rank: 2, value: 'cname.vercel-dns-legacy.vercel-dns.com' },
    { rank: 1, value: 'cname.vercel-dns-123.vercel-dns.com' },
    { rank: 3, value: 'cname.vercel-dns-unused.vercel-dns.com' },
  ];
  config.recommendedIPv4 = [
    { rank: 1, value: ['76.76.21.21', '76.76.21.22'] },
    { rank: 2, value: ['10.0.0.1', '10.0.0.2'] },
    { rank: 4, value: ['203.0.113.9'] },
  ];
  await writeConfig(fixture.root, config);
  const result = await run(fixture);
  assert.equal(result.code, undefined, result.stderr);
  const output = await evidence(fixture);
  assert.equal(output.target.domain_config.configured_by, 'CNAME');
  assert.equal(output.target.domain_config.recommended_cname, 'cname.vercel-dns-123.vercel-dns.com');
  assert.deepEqual(output.target.domain_config.recommended_ipv4, ['76.76.21.21', '76.76.21.22']);
  assert.deepEqual(
    Object.keys(output.target.domain_config).sort(),
    ['configured_by', 'misconfigured', 'recommended_cname', 'recommended_ipv4', 'status'].sort(),
  );
  assert.doesNotMatch(JSON.stringify(output), /secret-verification-value|unknownSecret|\"verification\"|\"acceptedChallenges\"/);
});

for (const [label, configure] of [
  ['missing', (config) => { config.recommendedCNAME = [{ rank: 2, value: 'cname.vercel-dns-legacy.vercel-dns.com' }]; }],
  ['duplicate', (config) => {
    config.recommendedCNAME = [
      { rank: 1, value: 'cname.vercel-dns-primary.vercel-dns.com' },
      { rank: 1, value: 'cname.vercel-dns-secondary.vercel-dns.com' },
    ];
  }],
  ['malformed', (config) => { config.recommendedCNAME = [{ rank: '1', value: 'cname.vercel-dns-123.vercel-dns.com' }]; }],
]) {
  test(`preflight fails closed for ${label} rank-1 CNAME contract`, async () => {
    const fixture = await setup('exact');
    const config = canonicalConfig('exact');
    configure(config);
    await writeConfig(fixture.root, config);
    const result = await runMode(fixture, 'preflight', {
      CURRENT_HEAD_SHA: '0123456789abcdef0123456789abcdef01234567',
      CURRENT_REMOTE_DEVELOP_SHA: '0123456789abcdef0123456789abcdef01234567',
      COMMIT_SHA: '0123456789abcdef0123456789abcdef01234567',
    });
    assert.equal(result.code, 1);
    assert.equal((await evidence(fixture)).reason_code, 'DOMAIN_CONFIG_INVALID');
    assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8').catch(() => '')).trim(), '');
  });
}
