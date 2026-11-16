#!/usr/bin/env node
/* eslint-disable no-console -- CLI tool, console output is the interface */
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';

import { checkFile } from './check';
import { loadConfig } from './config';
import { renderReport } from './report';
import type { Child } from './resolve';
import { buildRepoIndex } from './resolve';
import { collectSurface } from './surface';

// These files instruct agents rather than humans, so a reference that no longer resolves does not merely read
// badly — it sends an agent to a file that is not there, and nothing else in the toolchain notices. Kept
// mechanical on purpose: a review agent should spend its judgement on what a rule says, not on whether the
// rule's target still exists.
//
// CLI entry only; everything worth a test lives in the modules beside it. See ./CONTEXT.md for the file map.

// The root is the repository the command runs in, asked of git from the working directory. This file's own
// location is no guide: installed as a dependency it sits in the consumer's `node_modules`.
function repoRoot(): string {
  return execFileSync('git', [ 'rev-parse', '--show-toplevel' ], { cwd: process.cwd(), encoding: 'utf8' }).trim();
}

function trackedFiles(root: string): Array<string> {
  return execFileSync('git', [ 'ls-files' ], { cwd: root, encoding: 'utf8' }).split('\n').filter(Boolean);
}

// `--child <dir>`, once per child cloned inside the repository: home passes each of its children. A missing
// child would turn every path into it into a finding, so it stops the run instead.
function children(root: string): Array<Child> {
  const { values } = parseArgs({ options: { child: { type: 'string', multiple: true } } });
  return (values.child ?? []).map((dir) => {
    const childRoot = path.resolve(root, dir);
    if (!existsSync(path.join(childRoot, '.git'))) {
      throw new Error(`--child ${ dir }: no clone at ${ childRoot }. Clone the children first (scripts/bootstrap.sh).`);
    }
    return { root: childRoot, tracked: trackedFiles(childRoot) };
  });
}

async function main(): Promise<void> {
  const root = repoRoot();
  const repo = buildRepoIndex(root, trackedFiles(root), children(root));
  const files = await collectSurface(root, repo.tracked, loadConfig(root).exclude);

  const findings = [];
  for (const file of files) {
    findings.push(...await checkFile(repo, file));
  }

  const report = renderReport(findings, files.length);
  for (const line of report.output) {
    (line.stream === 'err' ? console.error : console.log)(line.text);
  }

  process.exitCode = report.exitCode;
}

void main();
