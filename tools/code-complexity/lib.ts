// The library entry, `frontend-home/code-complexity`: what a consumer's own tools take from the gate so that
// they select and classify as it does. A name leaves this file only when no consumer imports it.

export type { CodeComplexityConfig, ScopeConfig } from './config';
export { loadConfig } from './config';
export type { FunctionComplexity } from './measure/complexity';
export { computeFunctionComplexities } from './measure/complexity';
export type { LineRange } from './select/diff';
export { getAllSourceFiles, getChangedFiles, getChangedLineRanges, resolveBaseCommit } from './select/diff';
export { hasCoLocatedSpec } from './select/eligibility';
export type { ScopeRule } from './select/scope';
export { createScopeRule } from './select/scope';
