import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('shell exposes Admin navigation only for admin users', async () => {
  const shell = await readFile(new URL('../src/components/Shell.tsx', import.meta.url), 'utf8');

  assert.match(shell, /Shield/);
  assert.match(shell, /user\?\.role === 'admin'/);
  assert.match(shell, /href: '\/admin'/);
  assert.match(shell, /label: 'Admin'/);
});
