# Architecture

cliwrap has two halves:

1. **`bin/cliwrap`** — A management CLI users invoke directly to create,
   list, edit, and remove extensions. It never runs inside the wrapped
   command's process; it just edits files in `$CLIWRAP_HOME`.

2. **`lib/runtime.sh`** — Sourced into the user's interactive shell by
   `eval "$(cliwrap init)"`. Defines `cliwrap_register`, `cliwrap_dispatch`,
   `_cliwrap_complete`, and supporting helpers.

## Dispatch flow

When the user runs a wrapped command:

```
user runs:  aws secretsmanager get-secret-value --secret-id prod/db
             │
             ▼
    aws()                       ← function installed by cliwrap_register
             │
             ▼
    cliwrap_dispatch aws ...    ← entry point in runtime.sh
             │
             ├── --help / -h / no-args?  → call native, append CUSTOM section, return
             │
             ├── scan $CLIWRAP_HOME/aws/*.sh
             │     for each file, parse @match; keep matchers
             │     classify by @mode → pre_hooks[], replace_hook, post_hooks[]
             │
             ├── for f in pre_hooks:
             │       _cliwrap_run_hook "$f" "$@"   ← extracts ARG_*, sources, run()
             │       failure → return immediately (chain aborted, native NOT run)
             │
             ├── if replace_hook set:
             │       _cliwrap_run_hook "$replace_hook" "$@"
             │   else:
             │       stripped=$(_cliwrap_strip_declared_args ...)
             │       eval "command aws $stripped"
             │
             └── for f in post_hooks:
                     CLIWRAP_EXIT_CODE=$exit_code _cliwrap_run_hook "$f" "$@"
                     (failures are ignored; chain continues)
```

## Environment contract for extensions

A `run()` function inside an extension sees:

| Variable | Set by | Lifetime | Notes |
|----------|--------|----------|-------|
| `ARG_<NAME>` | `_cliwrap_extract_args` | Duration of `run()` only | One per `@arg` declared; UPPER_SNAKE_CASE of flag without dashes |
| `CLIWRAP_EXIT_CODE` | dispatcher | post-hooks only | Exit code of the replace hook OR real CLI |
| `CLIWRAP_HOME` | `cliwrap init` | shell session | `$HOME/.cliwrap` by default |
| `CLIWRAP_DEBUG` | user-set | shell session | When non-empty, emits debug lines to stderr |
| `"$@"` | extracted residual | run() args | Positional args after declared flags removed (and after `--` if any) |

After `run()` returns, all `ARG_*` are `unset` by `_cliwrap_clear_args`.

## Hook ordering & failure semantics

- **Filename order**: All hooks of a given mode are sorted by glob expansion
  order, i.e. lexicographic filename. Prefix with `00-`, `10-`, etc. to
  control order.
- **Pre-hook failure**: STOPS the chain. Native CLI is NOT called. No
  post-hooks run. The dispatcher returns the pre-hook's exit code.
  (Rationale: pre-hooks act as gates, e.g. `safe-push.sh`.)
- **Replace hook**: At most one matches. If multiple `@mode replace`
  extensions match, behavior is undefined (last one wins in current
  implementation; do not rely on this).
- **Post-hook failure**: IGNORED. All post-hooks always run.
  `CLIWRAP_EXIT_CODE` is the native CLI's (or replace hook's) exit, not
  affected by earlier post-hook failures.

## Argument extraction

`_cliwrap_extract_args` reads each `@arg` declaration:

- `# @arg --flag` → boolean. `ARG_FLAG=1` if present.
- `# @arg --flag=VALUE` → takes a value. Accepts both `--flag=v` and `--flag v`.
- `--` POSIX terminator: everything after `--` (inclusive) is preserved
  verbatim in `CLIWRAP_REMAINING`; no flag parsing occurs.

When the native CLI is called (no replace hook), `_cliwrap_strip_declared_args`
removes all flags declared by any matching extension from the argv. Native
CLI never sees them.

## Sourcing model

Extensions are sourced into the current shell (not subshells). This is
intentional — it allows extensions to `export` env vars (like AWS_PROFILE)
that affect the subsequent native CLI invocation. The price is that
extensions can theoretically pollute the shell. The runtime mitigates this
by `unset -f run` after each extension and `unset ARG_*` for declared
flags. Extensions should not define globals; if they must, prefix with
the extension's name.
