import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { describe, it, expect, beforeEach, afterEach } from 'vitest';

import { CONFIG_FILE, loadConfig } from './config';

let root: string;

beforeEach(() => {
  root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'doc-links-')));
});

afterEach(() => {
  fs.rmSync(root, { recursive: true, force: true });
});

const writeConfig = (content: unknown): void => fs.writeFileSync(path.join(root, CONFIG_FILE), JSON.stringify(content));

describe('loadConfig', () => {
  it('excludes nothing in a repository without the file', () => {
    expect(loadConfig(root)).toEqual({ exclude: [] });
  });

  it('excludes nothing when the file has no exclude', () => {
    writeConfig({});

    expect(loadConfig(root)).toEqual({ exclude: [] });
  });

  it('reads the excluded paths from doc-links.config.json at the repository root', () => {
    fs.writeFileSync(path.join(root, 'doc-links.config.json'), JSON.stringify({ exclude: [ 'src/toolkit/package' ] }));

    expect(loadConfig(root)).toEqual({ exclude: [ 'src/toolkit/package' ] });
  });

  it.each([
    [ 'a string', 'src/toolkit/package' ],
    [ 'a list with a non-string', [ 'src', 1 ] ],
  ])('rejects %s as exclude', (_, exclude) => {
    writeConfig({ exclude });

    expect(() => loadConfig(root)).toThrow('doc-links.config.json: exclude must be an array of strings');
  });
});
