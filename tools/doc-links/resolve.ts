import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

// A repository cloned inside the one being checked: one of home's children.
export interface Child {
  readonly root: string;
  readonly tracked: ReadonlyArray<string>;
}

export interface RepoIndex {
  readonly root: string;
  readonly tracked: ReadonlyArray<string>;
  // Derived rather than listed, so a new top-level directory needs no edit here. A path is only expected to
  // resolve when its first segment is one of these: `types/api.ts` names a kind of file, `src/api/types.ts`
  // a location. A child's directories count too, so a broken path into a child is still reported.
  readonly topLevel: ReadonlySet<string>;
  // A shared skill or rule in home names a child's file by its path from the child's root, so a
  // root-relative path may resolve in a child as well.
  readonly childRoots: ReadonlyArray<string>;
}

const topLevelOf = (tracked: ReadonlyArray<string>): Array<string> =>
  tracked.filter((file) => file.includes('/')).map((file) => file.split('/')[0]);

export function buildRepoIndex(root: string, tracked: ReadonlyArray<string>, children: ReadonlyArray<Child> = []): RepoIndex {
  return {
    root,
    tracked,
    topLevel: new Set([ tracked, ...children.map((child) => child.tracked) ].flatMap(topLevelOf)),
    childRoots: children.map((child) => child.root),
  };
}

export const isPlaceholder = (target: string): boolean => /[<>{}*]|__/.test(target);

// Resolved against the file's realpath, so a symlinked entry point (`.claude/CLAUDE.md` → `.agents/AGENTS.md`)
// resolves its relative links from where the file really lives.
export function resolves(repo: RepoIndex, realDir: string, target: string): string | undefined {
  const clean = target.replace(/^\.\//, '');
  return [ realDir, repo.root, ...repo.childRoots ]
    .map((base) => path.resolve(base, clean))
    .find((candidate) => existsSync(candidate));
}

// A path that resolves nowhere may still name a real file written short — `toolkit/theme/theme.ts` for
// `src/toolkit/theme/theme.ts`. Reported only when exactly one tracked file ends with it, which makes the
// intended file certain; `types/api.ts` matches thirty of them and so asserts no single location to check.
// Files only: a bare directory such as `hooks/` names a convention every slice follows, not one location,
// and nothing distinguishes that from shorthand.
export function shorthandFor(repo: RepoIndex, target: string): string | undefined {
  const matches = repo.tracked.filter((file) => file.endsWith(`/${ target }`));
  return matches.length === 1 ? matches[0] : undefined;
}

// A path whose parent directory sits beside the file was written relative to it — `components/Provider.tsx`
// in a CONTEXT.md is a reference to a neighbour, and its absence is a break. Without this the whole relative
// class goes unprotected: once broken, such a path is indistinguishable from `types/api.ts` naming a kind of
// file, so a renamed neighbour would fail silently.
export function nearby(realDir: string, target: string): boolean {
  const parent = path.dirname(target);
  return parent !== '.' && !target.endsWith('/') && existsSync(path.resolve(realDir, parent));
}

// GitHub's heading slug.
export const slugify = (heading: string): string => heading
  .toLowerCase()
  .replace(/`/g, '')
  .replace(/[^\w\s-]/g, '')
  .trim()
  .replace(/\s+/g, '-');

export async function headingSlugs(absPath: string): Promise<Set<string>> {
  const body = await readFile(absPath, 'utf8');
  return new Set(
    body.split('\n')
      .filter((line) => /^#{1,6}\s/.test(line))
      .map((line) => slugify(line.replace(/^#{1,6}\s+/, ''))),
  );
}
