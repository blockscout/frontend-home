import { describe, it, expect } from 'vitest';

import { parseConfig } from './config';

const MINIMAL = { roots: [ 'src/' ], maxCognitiveJsx: 25, maxCognitiveBehavior: 20, maxCrap: 80 };

function parse(config: Record<string, unknown>): ReturnType<typeof parseConfig> {
  return parseConfig(JSON.stringify(config));
}

describe('parseConfig', () => {
  it('fills what a minimal config leaves out', () => {
    expect(parse(MINIMAL)).toEqual({
      scope: {
        roots: [ 'src/' ],
        extensions: [ '.ts', '.tsx', '.mjs', '.js', '.cjs' ],
        specPatterns: [ '\\.spec\\.', '\\.config\\.' ],
        generatedPatterns: [ '/dist/' ],
      },
      maxCognitiveJsx: 25,
      maxCognitiveBehavior: 20,
      maxCrap: 80,
      baseRef: 'origin/main',
      coverage: { kind: 'vitest', vitestConfig: undefined },
    });
  });

  it('takes the scope, the base ref and the coverage vitest config from the file', () => {
    const config = parse({
      ...MINIMAL,
      extensions: [ '.ts' ],
      specPatterns: [ '\\.test\\.' ],
      generatedPatterns: [ '^src/generated/' ],
      baseRef: 'upstream/main',
      coverage: { vitestConfig: 'vitest.coverage.config.ts' },
    });
    expect(config.scope).toEqual({
      roots: [ 'src/' ],
      extensions: [ '.ts' ],
      specPatterns: [ '\\.test\\.' ],
      generatedPatterns: [ '^src/generated/' ],
    });
    expect(config.baseRef).toBe('upstream/main');
    expect(config.coverage).toEqual({ kind: 'vitest', vitestConfig: 'vitest.coverage.config.ts' });
  });

  it('lets a consumer switch a pattern list off with an empty array', () => {
    expect(parse({ ...MINIMAL, specPatterns: [], generatedPatterns: [] }).scope).toMatchObject({
      specPatterns: [],
      generatedPatterns: [],
    });
  });

  it('needs no CRAP cap when coverage is off', () => {
    const { maxCrap: _maxCrap, ...withoutCrap } = MINIMAL;
    expect(parse({ ...withoutCrap, coverage: false })).toMatchObject({ maxCrap: null, coverage: { kind: 'off' } });
  });

  it('keeps a CRAP cap given with coverage off, for a run fed by --coverage-file', () => {
    expect(parse({ ...MINIMAL, coverage: false }).maxCrap).toBe(80);
  });

  it('has no default for the roots and the caps', () => {
    const { roots: _roots, ...withoutRoots } = MINIMAL;
    const { maxCognitiveJsx: _jsx, ...withoutJsxCap } = MINIMAL;
    const { maxCognitiveBehavior: _behavior, ...withoutBehaviorCap } = MINIMAL;
    const { maxCrap: _maxCrap, ...withoutCrap } = MINIMAL;
    expect(() => parse(withoutRoots)).toThrow('code-complexity.config.json: roots is required');
    expect(() => parse(withoutJsxCap)).toThrow('maxCognitiveJsx is required');
    expect(() => parse(withoutBehaviorCap)).toThrow('maxCognitiveBehavior is required');
    expect(() => parse(withoutCrap)).toThrow('maxCrap is required');
  });

  it('rejects an empty list of roots', () => {
    expect(() => parse({ ...MINIMAL, roots: [] })).toThrow('roots must be a non-empty array of strings');
  });

  it('rejects a cap that is not a positive number', () => {
    expect(() => parse({ ...MINIMAL, maxCrap: 0 })).toThrow('maxCrap must be a positive number');
    expect(() => parse({ ...MINIMAL, maxCognitiveJsx: '25' })).toThrow('maxCognitiveJsx must be a positive number');
  });

  it('rejects a pattern that is not a regular expression', () => {
    expect(() => parse({ ...MINIMAL, specPatterns: [ '(' ] })).toThrow('specPatterns has an invalid regular expression: (');
  });

  it('rejects a key it does not know, at the top level and under coverage', () => {
    expect(() => parse({ ...MINIMAL, exclude: [ 'src/' ] })).toThrow('unknown key exclude');
    expect(() => parse({ ...MINIMAL, coverage: { config: 'vitest.config.ts' } })).toThrow('unknown key coverage.config');
  });

  it('rejects a coverage value other than false or an object', () => {
    expect(() => parse({ ...MINIMAL, coverage: true })).toThrow('coverage must be false or an object');
  });
});
