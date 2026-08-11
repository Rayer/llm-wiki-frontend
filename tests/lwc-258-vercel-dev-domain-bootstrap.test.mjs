import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
import test from 'node:test';

const execFileAsync = promisify(execFile);
const repoRoot = process.cwd();
const projectId = 'prj_test123';
const teamId = 'team_test123';
const domain = 'wiki.dev.rayer.idv.tw';

async function setup(scenario) {
  const root = await mkdtemp(join(tmpdir(), 'lwc-258-domain-bootstrap-'));
  const bin = join(root, 'bin');
  const evidence = join(root, 'evidence');
  await execFileAsync('mkdir', ['-p', bin, evidence]);
  await writeFile(join(root, 'scenario'), scenario);
  await writeFile(join(root, 'domains.json'), JSON.stringify({ domains: ['absent', 'ambiguous-write'].includes(scenario) ? [] : [{ name: domain, configuredBy: 'manual' }] }));
  await execFileAsync('cp', [join(repoRoot, 'tests/fixtures/lwc-258-domain-bootstrap-fake-curl.sh'), join(bin, 'curl')]);
  await execFileAsync('chmod', ['+x', join(bin, 'curl')]);
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
  return execFileAsync('bash', ['.github/scripts/vercel-dev-deployment.sh', 'bootstrap-domain'], {
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
  assert.match(workflow, /bootstrap-domain/);
});

for (const scenario of ['exact', 'absent', 'already-present']) {
  test(`bootstrap ${scenario} is bounded`, async () => {
    const fixture = await setup(scenario);
    const result = await run(fixture);
    assert.equal(result.code, undefined, result.stderr);
    const output = await evidence(fixture);
    assert.equal(output.target.stable_domain, domain);
    assert.equal(output.target.project_id, projectId);
    assert.equal(output.provider_verification.provider_mutation_count, scenario === 'absent' ? 1 : 0);
    assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8').catch(() => '')).trim(), scenario === 'absent' ? 'POST' : '');
  });
}

test('bootstrap rejects wrong-domain provider state without mutation', async () => {
  const fixture = await setup('wrong-domain');
  const result = await run(fixture);
  assert.equal(result.code, 1);
  assert.equal((await evidence(fixture)).reason_code, 'DOMAIN_NOT_ALLOWLISTED');
  assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8').catch(() => '')).trim(), '');
});

test('bootstrap fails closed after an ambiguous POST and does not retry', async () => {
  const fixture = await setup('ambiguous-write');
  const result = await run(fixture);
  assert.equal(result.code, 1);
  const output = await evidence(fixture);
  assert.equal(output.reason_code, 'DOMAIN_CREATE_UNCERTAIN');
  assert.equal(output.provider_verification.provider_mutation_count, 1);
  assert.equal((await readFile(join(fixture.root, 'mutation-log'), 'utf8').catch(() => '')).trim(), 'POST');
});
