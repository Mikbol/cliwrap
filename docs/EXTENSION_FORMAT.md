# Extension Format Reference

This is the canonical reference. The README's "extension file format"
section is a quick-start; this document covers edge cases and guarantees.

## File layout

One `.sh` file per extension, lives in `$CLIWRAP_HOME/<cli>/<name>.sh`.

```bash
# @match <pattern>
# @mode  <pre|post|replace>
# @desc  <one-line description>
# @arg   <flag-spec>   <flag-description>
# @arg   <flag-spec>   <flag-description>

run() {
    # body
}
```

Comments use `# @<key> value`. Order doesn't matter. Whitespace between
`#` and `@` is permitted.

## Directives

### `@match <pattern>` (required)

Determines whether the extension applies to a given invocation.

- `@match *` — matches every invocation (global hook)
- `@match whoami` — matches when first positional arg is `whoami`
- `@match s3 cp` — matches `<cli> s3 cp ...` (space-separated words match positionally)

Matching is **prefix-based**: the pattern must match the first N positional
args. Args beyond the pattern length are passed through to `run()`.

If `@match` is empty or missing, the extension never matches.

### `@mode <mode>` (default: `pre`)

- `pre` — runs before the native CLI. Failure aborts the chain (native CLI is NOT called).
- `post` — runs after the native CLI. Failure is ignored. Has access to `CLIWRAP_EXIT_CODE`.
- `replace` — runs *instead of* the native CLI. At most one replace hook should match a given invocation.

### `@desc <text>` (optional)

Shown in `cliwrap list` and the `CUSTOM COMMANDS` section of `<cli> --help`.

### `@arg <flag-spec> <description>` (optional, repeatable)

Declares a flag the extension consumes.

| Spec | Behavior | `run()` sees |
|------|----------|--------------|
| `--verbose` | Boolean flag | `ARG_VERBOSE=1` when present, unset otherwise |
| `--output=FORMAT` | Takes a value | `ARG_OUTPUT=<value>` (accepts both `--output=json` and `--output json`) |
| `--dry-run` | Boolean | `ARG_DRY_RUN=1` |

Name conversion: leading `--` stripped; remaining `-` → `_`; result uppercased.
`--multi-word-flag` → `ARG_MULTI_WORD_FLAG`.

Declared flags are removed from the args before being passed to `run()`'s
`"$@"`, and also stripped from what the native CLI receives.

If a `--flag=VAL`-style flag is declared but invoked without a value
(`--flag` at end of argv with nothing after it), cliwrap exits 64 (EX_USAGE)
with a message naming the flag.

### POSIX `--` terminator

After `--`, no further flag parsing happens. Everything after `--` is
delivered verbatim to `run()` in `"$@"` (including the `--` itself):

```bash
# Extension declares --verbose
aws cmd --verbose foo        → ARG_VERBOSE=1, "$@"=(foo)
aws cmd -- --verbose foo     → ARG_VERBOSE=unset, "$@"=(-- --verbose foo)
aws cmd foo -- --verbose     → ARG_VERBOSE=unset, "$@"=(foo -- --verbose)
```

## The `run()` function

Each extension defines exactly one function named `run`. It is:

- Called in the **current shell** (not a subshell)
- Passed positional args after declared-flag extraction in `"$@"`
- Allowed to `export` env vars (they affect downstream native CLI calls)
- `unset`'d after execution so it doesn't leak into the shell

Return code: pre-hook return non-zero ⇒ chain aborts. Replace hook return
code ⇒ becomes the wrapped command's exit code. Post-hook return code is
ignored.

## Calling the native CLI from inside an extension

Always use `command <cli>`:

```bash
run() {
  command aws sts get-caller-identity --output json
}
```

`command` bypasses shell functions, so you won't recurse into the
cliwrap dispatcher.

## Naming and ordering

- File names define order: `00-defaults.sh` runs before `10-safety.sh`.
- Use lowercase, hyphen-separated. Conventional prefixes:
  - `_<name>` — global hooks (sort first alphabetically)
  - `00-` to `09-` — early setup
  - `99-` — late cleanup

## Common patterns

### Conditional setup based on subcommand args

```bash
# @match secretsmanager get-secret-value
# @mode  pre
run() {
  local secret="" prev=""
  for a in "$@"; do
    [[ "$prev" == "--secret-id" ]] && { secret="$a"; break; }
    prev="$a"
  done
  [[ "$secret" == prod/* ]] && export AWS_PROFILE=prod-readonly
}
```

### Dry-run support

```bash
# @arg --dry-run    Show what would happen
run() {
  local prefix=""
  [[ -n "${ARG_DRY_RUN:-}" ]] && prefix="echo [dry-run]"
  $prefix command git push --force-with-lease
}
```

### Audit logging via post-hook

```bash
# @match *
# @mode  post
run() {
  printf '%s rc=%s %s\n' "$(date -Iseconds)" "${CLIWRAP_EXIT_CODE:-?}" "$*" \
    >> ~/.audit.log
}
```

## Edge cases reference

| Input | Result |
|-------|--------|
| `--flag=""` (declared as value flag) | `ARG_FLAG=""` (empty string, but set) |
| `--flag` (declared as value flag, no value) | exits 64 with "expects a value" |
| `--unknown` (not declared) | Preserved in `"$@"`, passed to native CLI |
| `-` as a positional | Preserved as-is |
| `--` mid-argv | Stops flag parsing; everything after preserved |
| `--match` is empty/missing | Extension never matches |
| Multiple `replace` hooks match | Last one (in filename order) wins — do not rely on this |
| Extension file with no `run()` | Warning to stderr; extension skipped |
