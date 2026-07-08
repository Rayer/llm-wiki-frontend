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

test('shell explicitly allows admin route content without a selected project', async () => {
  const shell = await readFile(new URL('../src/components/Shell.tsx', import.meta.url), 'utf8');

  assert.match(shell, /pathname === '\/admin'/);
  assert.match(shell, /token && isAdminRoute \?/);
  assert.match(shell, /token && isAdminRoute \?[\s\S]*\{children\}/);
});

test('admin route renders AdminClient', async () => {
  const page = await readFile(
    new URL('../src/app/admin/page.tsx', import.meta.url),
    'utf8',
  );

  assert.match(page, /import \{ AdminClient \} from '@\/components\/AdminClient';/);
  assert.match(page, /return <AdminClient \/>;/);
});

test('AdminClient gates access, renders tabs, and loads admin tables', async () => {
  const adminClient = await readFile(
    new URL('../src/components/AdminClient.tsx', import.meta.url),
    'utf8',
  );

  assert.match(adminClient, /useAuth/);
  assert.match(adminClient, /user\?\.role !== 'admin'/);
  assert.match(adminClient, /Admin access required/);
  assert.match(adminClient, /Projects/);
  assert.match(adminClient, /Users/);
  assert.match(adminClient, /getAdminProjects/);
  assert.match(adminClient, /getAdminUsers/);
  assert.match(adminClient, /<table/);
  assert.match(adminClient, /Project name/);
  assert.match(adminClient, /Concept count/);
  assert.match(adminClient, /Source count/);
  assert.match(adminClient, /Project count/);
});
