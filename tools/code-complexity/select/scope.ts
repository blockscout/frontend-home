import type { ScopeConfig } from '../config';

export type ScopeRule = (filePath: string) => boolean;

// An allowlist of roots rather than a prefix test plus exclusions: a consumer names the directories it
// gates, and a new top-level directory stays out until it is added. The spec patterns are tested against
// the file name, the generated patterns against the whole path.
export function createScopeRule(scope: ScopeConfig): ScopeRule {
  const specPatterns = scope.specPatterns.map((pattern) => new RegExp(pattern));
  const generatedPatterns = scope.generatedPatterns.map((pattern) => new RegExp(pattern));

  return (filePath) => {
    const path = filePath.replace(/\\/g, '/');

    if (!scope.roots.some((root) => path.startsWith(root))) return false;
    if (!scope.extensions.some((extension) => path.endsWith(extension))) return false;
    if (path.endsWith('.d.ts')) return false;
    if (generatedPatterns.some((pattern) => pattern.test(path))) return false;

    const base = path.slice(path.lastIndexOf('/') + 1);
    return !specPatterns.some((pattern) => pattern.test(base));
  };
}
