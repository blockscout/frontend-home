# Shared cspell config — context

`base.jsonc` holds the cspell settings and the words the Blockscout frontend repositories share. A consumer
imports it from the home dependency and adds what is its own:

```jsonc
{
    "import": [ "frontend-home/configs/cspell/base.jsonc" ],
    "gitignoreRoot": ".",
    "ignorePaths": [ ".git", "pnpm-lock.yaml" ],
    "words": [ "..." ]
}
```

Home is a consumer too. Its root `cspell.jsonc` imports the base by relative path, so `pnpm lint:cspell` in
home is the check that the base loads.

## What an editor here must keep true

- **Every path is the consumer's.** cspell resolves a path against the file that states it. For the base
  that is a directory inside the consumer's `node_modules`.
  - `gitignoreRoot` in the base makes every consumer's run check no files.
  - An `ignorePaths` entry in the base is dropped without a warning, unless it starts with `**/`.
- **Each consumer sets `gitignoreRoot` to its own root.** Without it a child in a task worktree checks no
  files and passes: cspell climbs to home's `.gitignore`, which ignores the worktree.
- **A full run that checks no files fails.** A consumer's `lint:cspell` is `cspell .` with no
  `--no-must-find-files`. Only a pre-commit run takes the flag, because every staged file may be an ignored
  one.
- **`files` in home's `package.json` ships this directory.** Without the entry the consumer's import
  resolves to nothing and its run stops with a configuration error.
- **A change here reaches a consumer when its pin moves**, and not before.

## Which list a word goes in

A new word goes in the list of the repository that needs it. That takes no change in home and no pin bump.

Move a word to the base when a second repository needs it. Until then the same word in two lists costs
nothing.

The base also holds words that only `frontend` uses today. They were shared ahead of need, by kind: chain
and network names, protocol and EVM terms, Blockscout products and the products of its ecosystem, and the
toolchain the repositories share.
