import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const repoRoot = new URL('..', import.meta.url).pathname;
const script = '.github/scripts/vercel-dev-deployment.sh';
const identity = { key: 'NEXT_PUBLIC_AUTH_URL', type: 'sensitive', target: ['preview'], gitBranch: 'develop' };

async function classify(envs) {
  const result = await execFileAsync('bash', ['-c', `source "$1"; set +e; classify_auth_env "$CLASSIFY_RESPONSE"; printf '%s|%s' "$AUTH_ENV_CURRENT_STATE" "$AUTH_ENV_REASON_CODE"`, 'bash', script], {
    cwd: repoRoot,
    env: { ...process.env, VERCEL_DEV_DEPLOYMENT_LIBRARY: '1', CLASSIFY_RESPONSE: JSON.stringify({ envs }) },
  });
  return result.stdout;
}

test('Preview env creation is pinned to the Vercel CLI-compatible sensitive type', async () => {
  const source = await readFile(`${repoRoot}${script}`, 'utf8');
  assert.match(source, /readonly AUTH_ENV_TYPE="sensitive"/);
});

test('accepts one sensitive Preview/develop record with Vercel redaction without calling it exact', async () => {
  assert.equal(await classify([{ ...identity, value: '[REDACTED]' }]), 'sensitive_redacted|AUTH_ENV_CONFLICT');
});

for (const [name, record] of [
  ['wrong type', { ...identity, type: 'encrypted', value: '[REDACTED]' }],
  ['wrong target', { ...identity, target: ['production'], value: '[REDACTED]' }],
  ['wrong branch', { ...identity, gitBranch: 'main', value: '[REDACTED]' }],
  ['readable wrong value', { ...identity, value: 'wrong' }],
]) {
  test(`rejects ${name}`, async () => {
    const result = await classify([record]);
    assert.notEqual(result, 'sensitive_redacted|AUTH_ENV_CONFLICT');
  });
}

test('rejects duplicate sensitive records as ambiguous', async () => {
  const result = await classify([{ ...identity, value: '[REDACTED]' }, { ...identity, value: '[REDACTED]' }]);
  assert.equal(result, '|AUTH_ENV_DUPLICATE');
});

test('rejects malformed provider response records', async () => {
  const result = await classify([{ key: 'NEXT_PUBLIC_AUTH_URL', value: '[REDACTED]' }]);
  assert.notEqual(result, 'sensitive_redacted|AUTH_ENV_CONFLICT');
});
