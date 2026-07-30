import type { PipelineExecution } from './api';

export const PIPELINE_STEPS = ['ingest', 'compile', 'lint', 'publish'] as const;

const PIPELINE_STAGE_LABELS: Record<string, string> = {
  ingest: 'Ingest',
  compile: 'Compile',
  concept_reconciliation: 'Concept reconciliation',
  lint: 'Lint',
  publish: 'Publish',
};

export function getPipelineTimelineState(execution?: PipelineExecution | null) {
  const status = execution?.status;
  const diagnosticStage = execution?.diagnostic?.stage ?? null;
  const failedStep = diagnosticStage && PIPELINE_STEPS.includes(diagnosticStage as typeof PIPELINE_STEPS[number])
    ? diagnosticStage as typeof PIPELINE_STEPS[number]
    : null;

  return {
    completedSteps: status === 'SUCCEEDED'
      ? PIPELINE_STEPS.length
      : status === 'RUNNING'
        ? 1
        : status === 'FAILED' && failedStep
          ? PIPELINE_STEPS.indexOf(failedStep)
          : 0,
    failedStep,
    stageLabel: diagnosticStage ? PIPELINE_STAGE_LABELS[diagnosticStage] ?? 'stage unavailable' : 'stage unavailable',
  };
}
