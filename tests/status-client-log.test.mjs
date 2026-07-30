import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { getPipelineTimelineState } from '../src/lib/pipeline-timeline.ts';

test('status client renders pipeline log in a scrollable expandable pre block', async () => {
  const statusClient = await readFile(
    new URL('../src/components/StatusClient.tsx', import.meta.url),
    'utf8',
  );

  assert.match(statusClient, /getStatus/);
  assert.match(statusClient, /getPipelineLog/);
  assert.doesNotMatch(statusClient, /getPipelineStatus/);
  assert.match(statusClient, /LOG_PREVIEW_BYTES\s*=\s*10 \* 1024/);
  assert.match(statusClient, /LOG_PREVIEW_LINES\s*=\s*50/);
  assert.match(statusClient, /slice\(-LOG_PREVIEW_LINES\)/);
  assert.match(statusClient, /overflow-y-auto/);
  assert.match(statusClient, /<pre/);
  assert.match(statusClient, /showFullLog/);
});

test('status client recognizes Cloud Run uppercase running status', async () => {
  const statusClient = await readFile(
    new URL('../src/components/StatusClient.tsx', import.meta.url),
    'utf8',
  );

  assert.match(statusClient, /execStatus === 'RUNNING'/);
});

test('status loading is metadata-only and log loading is explicit', async () => {
  const statusClient = await readFile(
    new URL('../src/components/StatusClient.tsx', import.meta.url),
    'utf8',
  );

  assert.doesNotMatch(
    statusClient,
    /const logUrl = apiStatus\.lastExecution\?\.log_url[\s\S]*?getPipelineLog\(/,
    'status refresh must not fetch the raw log body',
  );
  assert.match(statusClient, /onOpenLog/);
  assert.match(statusClient, /onClick=\{onOpenLog\}/);
});

test('pipeline log states gate fetching and expose typed diagnostic rendering', async () => {
  const statusClient = await readFile(
    new URL('../src/components/StatusClient.tsx', import.meta.url),
    'utf8',
  );
  const api = await readFile(new URL('../src/lib/api.ts', import.meta.url), 'utf8');

  assert.match(statusClient, /log_state/);
  assert.match(statusClient, /available/);
  assert.match(statusClient, /pending/);
  assert.match(statusClient, /unavailable/);
  assert.match(statusClient, /missing/);
  assert.match(statusClient, /error_class/);
  assert.match(statusClient, /detail_code/);
  assert.match(statusClient, /child_command/);
  assert.match(statusClient, /exit_code/);
  assert.match(statusClient, /stage unavailable/);
  assert.doesNotMatch(statusClient, /isFailed\s*\?\s*2/);
  assert.match(api, /diagnostic\??:/);
  assert.match(api, /log_state\??:/);
  assert.match(api, /log_state_reason\??:/);
});

test('typed diagnostics select only the reported known failed stage', () => {
  assert.deepEqual(
    getPipelineTimelineState({
      status: 'FAILED',
      diagnostic: { stage: 'concept_reconciliation' },
    }),
    { completedSteps: 0, failedStep: null, stageLabel: 'Concept reconciliation' },
  );
  assert.deepEqual(
    getPipelineTimelineState({
      status: 'FAILED',
      diagnostic: { stage: 'compile' },
    }),
    { completedSteps: 1, failedStep: 'compile', stageLabel: 'Compile' },
  );
  assert.equal(getPipelineTimelineState({ status: 'FAILED' }).stageLabel, 'stage unavailable');
  assert.equal(getPipelineTimelineState({ status: 'RUNNING' }).completedSteps, 1);
  assert.equal(getPipelineTimelineState({ status: 'SUCCEEDED' }).completedSteps, 4);
});
