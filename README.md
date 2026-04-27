# cliwrap

[![CI](https://github.com/Mikbol/cliwrap/actions/workflows/ci.yml/badge.svg)](https://github.com/Mikbol/cliwrap/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Mikbol/cliwrap?include_prereleases&sort=semver)](https://github.com/Mikbol/cliwrap/releases)

**A consistent framework for extending, overriding, and enriching any CLI.**

`cliwrap` lets you add custom subcommands, run pre/post hooks, inject new
arguments, and hook into tab completion — for any CLI (`aws`, `git`, `docker`,
`kubectl`, `terraform`, …) — using a single extension format. No special
cases, no per-CLI framework. One file = one extension.

---

## Install

### Requirements

- **bash 4.0+** (associative arrays, `${var@Q}`). macOS still ships bash 3.2 — run `brew install bash` first.
- POSIX `grep`, `sed`, `tr`.

### From source (recommended)

```bash
git clone https://github.com/Mikbol/cliwrap
cd cliwrap
./install.sh                              # installs to ~/.local by default
echo 'eval "$(cliwrap init)"' >> ~/.bashrc   # or ~/.zshrc
exec $SHELL
```

### From release tarball

```bash
curl -L https://github.com/Mikbol/cliwrap/releases/latest/download/cliwrap-1.0.0.tar.gz | tar xz
cd cliwrap-1.0.0
./install.sh
echo 'eval "$(cliwrap init)"' >> ~/.bashrc
exec $SHELL
```

### Verify

```bash
cliwrap --version
cliwrap doctor
```

---

## Mental model

```
┌────────────────────────────────────────────────────────────┐
│  user runs:  aws secretsmanager get-secret-value --id foo  │
└────────────────────────────────────────────────────────────┘
                           │
           aws() shell function (installed by cliwrap)
                           │
                    cliwrap_dispatch
                           │
   ┌───────────────────────┼───────────────────────┐
   │                       │                       │
   ▼                       ▼                       ▼
 PRE hooks         REPLACE (or real CLI)      POST hooks
 (in order)           (exactly one)          (in order)
```

Every extension file declares:

- **`@match`** — which invocations it applies to (`whoami`, `s3 cp`, or `*`)
- **`@mode`** — `pre`, `post`, or `replace`
- **`@arg`**  — flags the extension consumes (stripped from passthrough, exposed as `ARG_*`)
- **`@desc`** — one-line description (appears in `--help` and `cliwrap list`)

That's the whole spec. Same format whether you're adding a new command,
wrapping an existing one, or defining global defaults.

---

## Quickstart

```bash
cliwrap wrap aws                                       # enable wrapping for aws
cliwrap new aws whoami --desc "Show current identity"
$EDITOR ~/.cliwrap/aws/whoami.sh                       # fill in run()
exec $SHELL                                            # reload
aws whoami                                             # it works
aws whoami --he<TAB>                                   # completion works too
```

---

## The extension file format

A complete extension:

```bash
# @match  secretsmanager get-secret-value
# @mode   pre
# @desc   Auto-select AWS profile based on secret-id prefix
# @arg    --skip-auto    Don't auto-select a profile

run() {
    [[ -n "${ARG_SKIP_AUTO:-}" ]] && return 0

    local secret="" prev=""
    for a in "$@"; do
        [[ "$prev" == "--secret-id" ]] && { secret="$a"; break; }
        [[ "$a" == --secret-id=* ]]    && { secret="${a#--secret-id=}"; break; }
        prev="$a"
    done

    case "$secret" in
        prod/*) export AWS_PROFILE="prod-readonly" ;;
        dev/*)  export AWS_PROFILE="dev" ;;
    esac
}
```

### Metadata

| Directive | Repeatable | Description |
|-----------|------------|-------------|
| `@match <pattern>` | no  | Space-separated positional words that must match the start of the invocation. `*` matches everything. |
| `@mode <m>`        | no  | `pre` (run before the real CLI), `post` (after), `replace` (instead of). Default: `pre`. |
| `@desc <text>`     | no  | Shown in `--help` and `cliwrap list`. |
| `@arg <flag> <desc>` | yes | Flag this extension consumes. Use `--foo` for booleans, `--foo=VALUE` for valued flags. |

### The `run()` function

Every extension defines a single function named `run`. It is called in the
**current shell** (so `export` propagates to the real CLI) with the remaining
positional arguments — declared flags already stripped.

Access declared args via env vars:

```bash
# @arg --region=NAME      Override region
# @arg --verbose          Be loud

run() {
    local region="${ARG_REGION:-eu-north-1}"
    [[ -n "${ARG_VERBOSE:-}" ]] && echo "region=$region" >&2
}
```

Names are UPPER_SNAKE_CASE of the flag: `--dry-run` → `ARG_DRY_RUN`,
`--output` → `ARG_OUTPUT`.

### Calling the real CLI

Use `command <cli>` to bypass the wrapper function:

```bash
run() {
    command aws s3 ls "$@"
}
```

### Post-hook context

Post hooks additionally get `CLIWRAP_EXIT_CODE` — the real CLI's exit code.

---

## Examples

### AWS

| File                          | What it does                                       |
|-------------------------------|----------------------------------------------------|
| `aws/_defaults.sh`            | Global pre-hook: set `AWS_REGION`, disable pager   |
| `aws/whoami.sh`               | New `aws whoami` command with enriched output     |
| `aws/smart-secrets.sh`        | Auto-select profile for `secretsmanager get-secret-value` based on secret-id |

### Git

| File                | What it does                                               |
|---------------------|------------------------------------------------------------|
| `git/sync.sh`       | New `git sync` = fetch + rebase + push-with-lease         |
| `git/safe-push.sh`  | Pre-hook on `git push --force` that protects main/master  |

### Docker

| File                  | What it does                                      |
|-----------------------|---------------------------------------------------|
| `docker/clean.sh`     | New `docker clean` = prune containers/images/volumes |
| `docker/audit.sh`     | Post-hook: log every invocation with exit code      |

Copy any file from `examples/` into `~/.cliwrap/<cli>/` to use it:

```bash
cliwrap wrap aws
cp examples/aws/*.sh ~/.cliwrap/aws/
exec $SHELL
```

---

## Lifecycle in detail

For `aws secretsmanager get-secret-value --secret-id X`:

1. `aws()` function (installed at register time) calls `cliwrap_dispatch aws ...`
2. Runtime scans `~/.cliwrap/aws/*.sh` and tests each file's `@match` against the args
3. Matching files are classified: `pre` (all run), `replace` (at most one), `post` (all run)
4. For each matching file, declared flags are extracted into `ARG_*` and removed from the arg list
5. Pre hooks run in filename order
6. Either the replace hook runs, OR `command aws ...` runs (with declared flags stripped)
7. Post hooks run in filename order, with `CLIWRAP_EXIT_CODE` set
8. Exit code of the replace hook (or real CLI) is returned

Ordering tip: prefix files to control order. `00-defaults.sh` runs before
`10-safety.sh`.

---

## Completion

Completion is automatic. `cliwrap_register` replaces the native `complete` spec
with one that:

1. Offers all `@match` names as top-level subcommand candidates
2. Offers `@arg` flags of every matching extension at the current position
3. Merges those with the native completer's suggestions

Works for both `complete -F` style (git, docker) and `complete -C` style (aws).

**Zsh:** add `autoload bashcompinit && bashcompinit` to `~/.zshrc` before the
`eval "$(cliwrap init)"` line.

---

## `cliwrap` command reference

```
cliwrap init                       Shell init code (eval this in .bashrc)
cliwrap wrap <cli>                 Enable wrapping for <cli>
cliwrap unwrap <cli>               Remove all extensions for <cli>
cliwrap new <cli> <n> [opts]    Scaffold a new extension
    --match <pattern>              Default: <n>
    --mode  <pre|post|replace>     Default: replace
    --desc  <text>
cliwrap list [<cli>]               List extensions (optionally filter)
cliwrap edit <cli> <n>          Open in $EDITOR
cliwrap remove <cli> <n>        Delete an extension
cliwrap doctor                     Diagnose setup
cliwrap version                    Print version
```

---

## FAQ

**Why not aliases?** Aliases can't do pre/post logic, conditional behavior, or
merge with completion.

**Why not per-CLI plugin systems?** `aws` has CLI aliases, `git` has
subcommand scripts, `docker` has plugins — each different. cliwrap gives you
one model that works everywhere.

**Does it slow things down?** One file-glob + one grep per invocation. ~5ms.

**Can I test an extension without reloading the shell?**
```bash
source ~/.cliwrap/aws/myext.sh && run --my-arg value
```

**Which bash version?** Requires bash 4.0+ for associative arrays. macOS ships
3.2 — install a newer bash via `brew install bash` and point your shell at it,
or run cliwrap under a modern bash subshell.

---

## Development

```bash
git clone https://github.com/Mikbol/cliwrap
cd cliwrap
make help     # list tasks
make check    # lint + test
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

[MIT](LICENSE)
