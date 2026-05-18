# Troubleshooting

Every solution in this document is backed by a test in `tests/e2e.sh`.

## "My extension doesn't run"

Run with `CLIWRAP_DEBUG=1`:

```bash
CLIWRAP_DEBUG=1 aws whoami
# cliwrap[debug]: run() in /home/you/.cliwrap/aws/whoami.sh
```

If you don't see your extension's file mentioned, the `@match` pattern
doesn't match the invocation. Check:

- Pattern words must match the *first* positional args. `@match whoami`
  matches `aws whoami` but not `aws sts whoami`.
- Pattern must be space-separated words. `@match "s3 cp"` matches `aws s3 cp`.
- Use `@match *` to apply to every invocation.

## "My flag isn't being parsed"

In debug mode, look for the `ARG_<NAME>=...` lines. If missing:

- Confirm the `@arg` line exists and matches the flag exactly (`@arg --my-flag`
  matches `--my-flag`, not `-my-flag` or `--myflag`).
- For value flags, declare with `=VALUE`: `@arg --output=FORMAT`.
- `--` ends flag parsing — anything after `--` is not parsed as a flag.

## "Extension runs but native CLI also receives my flag"

This is by design only if the flag isn't declared. If you declared
`# @arg --my-flag` and the native CLI still sees it, check:

- The declaration must be in the same extension that matches the
  invocation (a flag declared in one extension is only stripped if
  that extension is matched).
- For value flags, declare with `=VALUE`. Without `=VALUE`, cliwrap
  treats it as a boolean and only consumes the flag itself, leaving the
  next arg in place.

## "I get 'expects a value'"

You declared `# @arg --foo=VALUE` but invoked it as `--foo` with nothing
after it. Either supply a value or change the declaration to boolean
(`# @arg --foo`).

## "My pre-hook stopped the chain"

A pre-hook returning non-zero is treated as a veto: the native CLI is
not called and no post-hooks run. This is intentional. If you don't
want that, ensure the hook returns 0:

```bash
run() {
  some_check || return 0   # explicit non-veto
}
```

## "My post-hook didn't run"

If a pre-hook failed, post-hooks don't run. Otherwise, all post-hooks
should run regardless of failures. Run with `CLIWRAP_DEBUG=1` to see
the dispatch order.

## "Completion suggests nothing"

- For zsh: ensure `autoload bashcompinit && bashcompinit` is in `~/.zshrc`
  *before* `eval "$(cliwrap init)"`.
- For bash: ensure `bash-completion` package is installed and sourced
  (typically `/etc/profile.d/bash_completion.sh`).
- Run `complete -p <cli>` after registration to confirm cliwrap installed
  its completer; if not, `cliwrap_register` failed silently — re-source
  with `CLIWRAP_DEBUG=1`.

## "Wrapped CLI A calls wrapped CLI B"

This works — both wrappers dispatch normally. There's no state leakage
between them; each dispatch is self-contained.

## "I'm on macOS and cliwrap says bash 4 is required"

macOS ships bash 3.2 (last GPL-2 release). Install a newer bash:

```bash
brew install bash
```

Then either:
- Change your login shell: `chsh -s /opt/homebrew/bin/bash`
- Or run cliwrap commands via the newer bash explicitly:
  `/opt/homebrew/bin/bash -c 'cliwrap doctor'`

## "Two replace hooks match the same invocation"

Behavior is undefined (currently: last in filename order wins). This
shouldn't happen — fix one of the `@match` patterns to be more specific.
Use `cliwrap list <cli>` to see all extensions and their patterns.

## "How do I roll back v1.1 if it breaks something?"

```bash
make uninstall
git checkout v1.0.0
./install.sh
```

Extensions in `$CLIWRAP_HOME` are untouched.
