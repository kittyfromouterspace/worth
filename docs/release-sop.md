# Release SOP

Standard operating procedure for releasing Worth. Covers switching between dev and prod modes, tagging dependencies in order, and CI considerations.

## Repos (tag order matters)

Dependencies must be tagged first so their git refs can be referenced in downstream `mix.exs`:

1. **recollect** — `git@github.com:kittyfromouterspace/recollect.git`
2. **agentic** — `git@github.com:kittyfromouterspace/agentic.git`
3. **worth** — `git@github.com:kittyfromouterspace/worth.git`

## Mode switching

Worth's `mix.exs` uses the `WORTH_DEPS_MODE` environment variable to select between local dev (path deps) and prod (git deps with tags).

- **Dev mode** (default): `WORTH_DEPS_MODE=dev` or unset — uses `path: "../recollect"` and `path: "../agentic"`
- **Prod mode**: `WORTH_DEPS_MODE=prod` — uses git deps with tags from GitHub

CI workflows set `WORTH_DEPS_MODE=prod` automatically.

### Switch to prod mode locally

```bash
WORTH_DEPS_MODE=prod rm -rf deps _build
WORTH_DEPS_MODE=prod mix deps.get
WORTH_DEPS_MODE=prod mix compile
WORTH_DEPS_MODE=prod mix test
```

Or export it for the session:

```bash
export WORTH_DEPS_MODE=prod
rm -rf deps _build && mix deps.get && mix compile && mix test
```

### Switch to dev mode

```bash
unset WORTH_DEPS_MODE
rm -rf deps _build
mix deps.get
mix compile
```

Note: `mix.lock` tracks resolved deps. Always `rm -rf deps _build` when switching modes to avoid stale artifacts.

## Release process

### Pre-release checklist

- [ ] All three repos are on `main` with clean working trees
- [ ] `mix test` passes locally in dev mode
- [ ] Decide: **release** (tag + push) or **dry run** (test prod mode locally only)

### Step 1 — Version bump

Determine the new version numbers for each repo. Update them in order:

| Repo | File to update | Notes |
|------|---------------|-------|
| recollect | `mix.exs` `version:` field | |
| agentic | `mix.exs` `version:` field | |
| worth | `mix.exs` `version:` field | Semver OK (e.g. `0.2.1-alpha.5`) |
| worth | `rel/desktop/src-tauri/tauri.conf.json` `version` field | Must be valid semver (e.g. `0.2.1-alpha.5`) |
| worth | `rel/desktop/src-tauri/tauri.conf.json` `bundle.windows.wix.version` | Must be numeric-only 4-part (e.g. `0.2.1.5`) — MSI/WiX rejects pre-release identifiers. Map: strip `-alpha.N` → `.N`, strip `-beta.N` → `.N`, stable → `.0` |

### Step 2 — Commit and tag recollect

```bash
cd ../recollect
git add mix.exs
git commit -m "v0.x.y"
git tag v0.x.y
```

- If **releasing**: `git push origin main --tags`
- If **dry run**: skip push

### Step 3 — Commit and tag agentic

```bash
cd ../agentic
# Update recollect dep tag in mix.exs to the version from Step 2
git add mix.exs
git commit -m "v0.x.y"
git tag v0.x.y
```

- If **releasing**: `git push origin main --tags`
- If **dry run**: skip push

### Step 4 — Update worth for prod mode

Edit `worth/mix.exs`:

1. Update the `version:` field to the new version
2. Update the git dep tags to the versions from Steps 2 and 3
3. Update `rel/desktop/src-tauri/tauri.conf.json` version

Test with prod mode:

```bash
cd ../worth
WORTH_DEPS_MODE=prod rm -rf deps _build
WORTH_DEPS_MODE=prod mix deps.get
WORTH_DEPS_MODE=prod mix compile
WORTH_DEPS_MODE=prod mix test
```

If tests fail, fix issues or abort.

### Step 4b — Validate the OTP release build locally

`mix test` only exercises `:test` env. The desktop bundle ships a
`mix release` OTP artifact, which compiles in `:prod` env and pulls a
different subset of files — bugs that only surface there (missing
consumer-visible modules, missing assets, priv/ contents, NIF load
order, etc.) won't be caught by tests. Run a release build before
tagging:

```bash
cd ../worth
WORTH_DEPS_MODE=prod MIX_ENV=prod mix deps.get --only prod
WORTH_DEPS_MODE=prod MIX_ENV=prod mix assets.deploy
WORTH_DEPS_MODE=prod MIX_ENV=prod mix release desktop --overwrite --path _build/release-check
_build/release-check/bin/desktop eval 'IO.puts "release boots OK"'
```

If the release build fails or the eval call errors, fix before tagging.
The CI workflow runs the exact same `mix release desktop` invocation on
all three platforms, so catching problems locally beats another red
`desktop-release.yml` run.

### Step 5 — Commit and tag worth

```bash
cd ../worth
git add mix.exs rel/desktop/src-tauri/tauri.conf.json
git commit -m "v0.x.y"
git tag v0.x.y
```

- If **releasing**: `git push origin main --tags`
- If **dry run**: skip push

### Step 6 — Post-release

- If **releasing**: the `desktop-release.yml` workflow triggers automatically on the `v*` tag push. It builds all desktop artifacts and creates a draft GitHub Release. Review and publish from the GitHub Releases page.
- If **dry run**: verify everything looks good, then repeat the process with pushes when ready.

### Step 7 — Back to dev mode

After the release is published, continue local development with path deps:

```bash
unset WORTH_DEPS_MODE
rm -rf deps _build
mix deps.get
mix compile
```

## CI

Both CI workflows (`ci.yml` and `desktop-release.yml`) set `WORTH_DEPS_MODE=prod`, so they always resolve git deps regardless of what's in the local `mix.exs`. No manual dep swapping is needed before pushing to `main` or tagging.

The git dep tags in `mix.exs` (currently `recollect v0.4.2`, `agentic v0.1.6`) must be kept up to date during releases — CI uses whatever tags are hardcoded there.

## Quick reference

| Action | Command |
|--------|---------|
| Local prod test | `WORTH_DEPS_MODE=prod rm -rf deps _build && mix deps.get && mix test` |
| Switch to dev | Edit `mix.exs` (path deps), then `rm -rf deps _build && mix deps.get` |
| Tag recollect | `git tag v0.x.y && git push origin main --tags` |
| Tag agentic | `git tag v0.x.y && git push origin main --tags` |
| Tag worth | `git tag v0.x.y && git push origin main --tags` |
| Publish release | GitHub Releases page → publish draft |
