// Per-repository settings, read from `doc-links.config.json` at the root of the repository being checked.
// The file is optional; a repository without one gets the defaults.

import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

export interface DocLinksConfig {
  // Paths, relative to the repository root, left out of the check together with everything below them.
  readonly exclude: ReadonlyArray<string>;
}

export const CONFIG_FILE = 'doc-links.config.json';

export function loadConfig(root: string): DocLinksConfig {
  const file = path.join(root, CONFIG_FILE);
  if (!existsSync(file)) return { exclude: [] };

  const parsed = JSON.parse(readFileSync(file, 'utf8')) as { exclude?: unknown };
  const exclude = parsed.exclude ?? [];
  if (!Array.isArray(exclude) || exclude.some((item) => typeof item !== 'string')) {
    throw new Error(`${ CONFIG_FILE }: exclude must be an array of strings`);
  }

  return { exclude: exclude as Array<string> };
}
