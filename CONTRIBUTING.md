# Contributing to cliwrap

Thanks for your interest! This document explains how to contribute.

## Quick start

```bash
git clone https://github.com/Mikbol/cliwrap
cd cliwrap
make check       # runs lint + tests
```

## Development workflow

1. **Fork and branch** off `main`: `git checkout -b my-feature`
2. **Make your changes** — small, focused commits
3. **Add tests** in `tests/e2e.sh` for any behavioral change
4. **Run `make check`** and make sure it's green
5. **Update CHANGELOG.md** under `## [Unreleased]`
6. **Open a PR** with a clear description of what and why

## Project layout

```
bin/cliwrap          Management CLI (user-facing)
lib/runtime.sh       Dispatcher, matching, hooks, completion (sourced into user shells)
examples/            Reference extensions for aws/git/docker
tests/e2e.sh         Test suite using fake binaries on PATH
install.sh           Installs to $PREFIX
Makefile             Dev tasks (test, lint, dist, release-check)
VERSION              Single source of truth for version
```

## Coding standards

- **Bash 3.2+ compatible** (macOS ships bash 3.2; don't use `declare -A` in
  runtime without a version guard; don't use `${var@Q}` in code paths that
  need to run on old bash — it's only used in registration which is 4.4+)
- **Pass `shellcheck`** — run `make lint`. Project-wide disables live in `.shellcheckrc`.
- **Quote variable expansions** (`"$var"`, not `$var`).
- **Prefer `[[ ]]` over `[ ]`**.
- **`local` all function variables**.
- **Use `command <cli>`** (not `\<cli>` or `builtin`) when invoking the real CLI — it's the documented pattern.

## Adding a new example

Examples live under `examples/<cli>/`. Each file is a self-contained
extension. Keep them:

- Focused on one clear use case
- Commented to explain the *why*, not the *what*
- Safe by default (don't do destructive things without confirmation)

Add a row to the README table if you introduce a new example.

## Testing changes to the runtime

The test suite uses fake `aws`/`git`/`docker` binaries on PATH, so you don't
need AWS credentials or a Docker daemon. Add new test cases to `tests/e2e.sh`
using the `check "<description>" "<expected-substring>" "$actual"` helper.

Run a single flow manually:

```bash
export CLIWRAP_HOME=$(mktemp -d)
mkdir -p $CLIWRAP_HOME/aws
cp examples/aws/whoami.sh $CLIWRAP_HOME/aws/
source lib/runtime.sh
cliwrap_register aws
aws whoami
```

## Releasing (maintainers)

```bash
# 1. Bump version
echo "1.2.3" > VERSION

# 2. Update CHANGELOG.md — move Unreleased items under [1.2.3]

# 3. Verify everything
make release-check

# 4. Commit, tag, push
git commit -am "Release 1.2.3"
git tag v1.2.3
git push && git push --tags
```

GitHub Actions will build the release tarball and attach it to the tag.

## Questions

Open an issue with the "question" label.
