import { describe, it, expect } from 'vitest';

import { createScopeRule } from './scope';

const isInScope = createScopeRule({
  roots: [ 'src/', 'tools/', 'deploy/tools/' ],
  extensions: [ '.ts', '.tsx', '.mjs', '.js', '.cjs' ],
  specPatterns: [ '\\.spec\\.', '\\.pw\\.tsx$', '\\.stories\\.tsx$', '\\.config\\.' ],
  generatedPatterns: [ '^src/toolkit/package/', '/dist/', '(^|/)envs\\.js$' ],
});

describe('a scope rule built from a config', () => {
  it('includes files with a listed extension under a root', () => {
    expect(isInScope('src/lib/foo.ts')).toBe(true);
    expect(isInScope('src/ui/Button.tsx')).toBe(true);
    expect(isInScope('src/server/redirects.js')).toBe(true);
    expect(isInScope('tools/mutation-testing/eslint/well-formed-disable.mjs')).toBe(true);
    expect(isInScope('tools/release/legacy.cjs')).toBe(true);
  });

  it('includes a root nested in a directory that is not a root itself', () => {
    expect(isInScope('deploy/tools/envs-validator/index.ts')).toBe(true);
    expect(isInScope('deploy/scripts/run.ts')).toBe(false);
  });

  it('excludes everything outside the roots', () => {
    expect(isInScope('startup.node.ts')).toBe(false);
    expect(isInScope('playwright/TestApp.tsx')).toBe(false);
    expect(isInScope('docs/example.ts')).toBe(false);
  });

  it('excludes extensions that are not listed', () => {
    expect(isInScope('src/lib/data.json')).toBe(false);
    expect(isInScope('tools/release/run.sh')).toBe(false);
  });

  it('excludes declaration files whatever the config lists', () => {
    expect(isInScope('src/types/global.d.ts')).toBe(false);
  });

  it('excludes a file whose name matches a spec pattern', () => {
    expect(isInScope('src/lib/foo.spec.ts')).toBe(false);
    expect(isInScope('src/ui/Button.pw.tsx')).toBe(false);
    expect(isInScope('src/ui/Button.stories.tsx')).toBe(false);
    expect(isInScope('tools/profiling/vitest.config.ts')).toBe(false);
  });

  it('tests a spec pattern against the file name only', () => {
    expect(isInScope('src/app.config.d/loader.ts')).toBe(true);
  });

  it('excludes a file whose path matches a generated pattern', () => {
    expect(isInScope('src/toolkit/package/src/index.ts')).toBe(false);
    expect(isInScope('tools/profiling/dist/index.js')).toBe(false);
    expect(isInScope('src/public/envs.js')).toBe(false);
    expect(isInScope('src/toolkit/components/Button.tsx')).toBe(true);
    expect(isInScope('src/lib/parseEnvs.js')).toBe(true);
  });

  it('reads a path written with backslashes', () => {
    expect(isInScope('src\\lib\\foo.ts')).toBe(true);
  });
});
