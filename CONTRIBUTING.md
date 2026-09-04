# Contributing

Welcome. This guide is the canonical source for how PRs get reviewed
and merged in this repository — both for human contributors and for
AI coding agents.

## Workflow

1. Branch from main: `git checkout -b <type>/<short-name>`. Every change
   goes through a branch and a PR — nothing lands directly on `main`.
2. Make focused commits — one logical change per PR.
3. Verify locally before opening the PR (see *Checks* below). There is no
   test suite; the real gate is that the change **builds and works on a
   real machine**.
4. Open a PR; the template lists the per-merge checks.
5. Merge with a merge commit: `gh pr merge --merge`. This repo blocks
   squash and rebase merges.

## Checks

Run these before pushing. CI (`.github/workflows/check.yml`) runs the same
three on every PR and push to `main`:

```bash
nix flake check --no-build --show-trace          # flake evaluates, outputs well-formed
nix fmt                                          # nixfmt; tree is already clean
nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
```

Then actually apply it on the target machine before you consider the change
done:

```bash
sudo nixos-rebuild switch --flake .#<host>
```

A change that evaluates in CI but breaks the running session is still a
broken change — CI only proves the closure evaluates, never that the
desktop comes back up.

## What gets a PR rejected

- **It doesn't build or activate.** Evaluating is not the same as working.
- **It's not reproducible.** Config belongs in the flake, home-manager, or
  the generated `~/TODO.md`. Never a runtime-only edit to a file on the
  machine — the repo is the source of truth, and drift is the bug this
  repo exists to prevent.
- **It's unformatted.** `nix fmt --check` is a hard CI gate.
- **Secrets.** LUKS *UUIDs* are identifiers and are fine to commit; tokens,
  passphrases, and keys are not. Don't add this repo as a flake input —
  that would force a token into `nix.settings.access-tokens`.
- **Stale comments or docs.** If you rename an option or swap a component,
  update `CLAUDE.md`, `README.md`, and `INSTALL.md` in the same PR.
  Out-of-date guidance actively misleads the next reader.
- **Unrelated reformatting** mixed into a functional change.
- **`stateVersion` bumps** without a link to the relevant release notes.

## Style

- Format with the language's standard tool (`nix fmt` here; gofmt, prettier,
  etc. elsewhere).
- Don't reformat unrelated lines; keep diffs minimal.
- Comments explain WHY, not WHAT. This repo leans on long explanatory
  comments deliberately — they're the rationale record. Keep them true.

## Asking for help

Open a draft PR or an issue. Don't sit on a stuck branch.
