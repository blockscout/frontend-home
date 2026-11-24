import fs from 'node:fs';
import path from 'node:path';

// Per-repository settings, read from `code-complexity.config.json` in the directory the gate runs in. Every
// path in the file is relative to that directory. What each key means for the gate: ./docs/RUNNING.md.

export const CONFIG_FILE = 'code-complexity.config.json';

export interface ScopeConfig {
  readonly roots: ReadonlyArray<string>;
  readonly extensions: ReadonlyArray<string>;
  readonly specPatterns: ReadonlyArray<string>;
  readonly generatedPatterns: ReadonlyArray<string>;
}

export type CoverageConfig =
  { readonly kind: 'off' } |
  { readonly kind: 'vitest'; readonly vitestConfig: string | undefined };

export interface CodeComplexityConfig {
  readonly scope: ScopeConfig;
  readonly maxCognitiveJsx: number;
  readonly maxCognitiveBehavior: number;
  readonly maxCrap: number | null;
  readonly baseRef: string;
  readonly coverage: CoverageConfig;
}

const DEFAULT_EXTENSIONS: ReadonlyArray<string> = [ '.ts', '.tsx', '.mjs', '.js', '.cjs' ];
const DEFAULT_SPEC_PATTERNS: ReadonlyArray<string> = [ '\\.spec\\.', '\\.config\\.' ];
const DEFAULT_GENERATED_PATTERNS: ReadonlyArray<string> = [ '/dist/' ];
const DEFAULT_BASE_REF = 'origin/main';

const KNOWN_KEYS: ReadonlySet<string> = new Set([
  'roots',
  'extensions',
  'specPatterns',
  'generatedPatterns',
  'maxCognitiveJsx',
  'maxCognitiveBehavior',
  'maxCrap',
  'baseRef',
  'coverage',
]);

function fail(message: string): never {
  throw new Error(`${ CONFIG_FILE }: ${ message }`);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readStrings(raw: Record<string, unknown>, key: string, fallback: ReadonlyArray<string> | undefined): ReadonlyArray<string> {
  const value = raw[key];
  if (value === undefined) return fallback ?? fail(`${ key } is required`);
  if (!Array.isArray(value) || value.length === 0 || value.some((item) => typeof item !== 'string')) {
    return fail(`${ key } must be a non-empty array of strings`);
  }
  return value as Array<string>;
}

function readPatterns(raw: Record<string, unknown>, key: string, fallback: ReadonlyArray<string>): ReadonlyArray<string> {
  const value = raw[key];
  if (Array.isArray(value) && value.length === 0) return [];
  const patterns = readStrings(raw, key, fallback);
  for (const pattern of patterns) {
    try {
      new RegExp(pattern);
    } catch {
      fail(`${ key } has an invalid regular expression: ${ pattern }`);
    }
  }
  return patterns;
}

function readCap(raw: Record<string, unknown>, key: string): number {
  const value = raw[key];
  if (value === undefined) return fail(`${ key } is required`);
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 1) return fail(`${ key } must be a positive number`);
  return value;
}

function readCoverage(raw: Record<string, unknown>): CoverageConfig {
  const value = raw.coverage;
  if (value === false) return { kind: 'off' };
  if (value === undefined) return { kind: 'vitest', vitestConfig: undefined };
  if (!isRecord(value)) return fail('coverage must be false or an object');

  const unknownKey = Object.keys(value).find((key) => key !== 'vitestConfig');
  if (unknownKey !== undefined) fail(`unknown key coverage.${ unknownKey }`);

  const { vitestConfig } = value;
  if (vitestConfig !== undefined && typeof vitestConfig !== 'string') return fail('coverage.vitestConfig must be a string');
  return { kind: 'vitest', vitestConfig };
}

export function parseConfig(jsonText: string): CodeComplexityConfig {
  const raw: unknown = JSON.parse(jsonText);
  if (!isRecord(raw)) return fail('must be an object');

  const unknownKey = Object.keys(raw).find((key) => !KNOWN_KEYS.has(key));
  if (unknownKey !== undefined) fail(`unknown key ${ unknownKey }`);

  const coverage = readCoverage(raw);
  if (raw.baseRef !== undefined && typeof raw.baseRef !== 'string') fail('baseRef must be a string');

  return {
    scope: {
      roots: readStrings(raw, 'roots', undefined),
      extensions: readStrings(raw, 'extensions', DEFAULT_EXTENSIONS),
      specPatterns: readPatterns(raw, 'specPatterns', DEFAULT_SPEC_PATTERNS),
      generatedPatterns: readPatterns(raw, 'generatedPatterns', DEFAULT_GENERATED_PATTERNS),
    },
    maxCognitiveJsx: readCap(raw, 'maxCognitiveJsx'),
    maxCognitiveBehavior: readCap(raw, 'maxCognitiveBehavior'),
    // Without a coverage run there is no CRAP score to cap, so the cap may be left out.
    maxCrap: coverage.kind === 'off' && raw.maxCrap === undefined ? null : readCap(raw, 'maxCrap'),
    baseRef: raw.baseRef ?? DEFAULT_BASE_REF,
    coverage,
  };
}

export function loadConfig(root: string): CodeComplexityConfig {
  const file = path.join(root, CONFIG_FILE);
  if (!fs.existsSync(file)) fail(`not found in ${ root }`);
  return parseConfig(fs.readFileSync(file, 'utf8'));
}
