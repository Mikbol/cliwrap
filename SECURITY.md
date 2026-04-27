# Security Policy

## Supported versions

Only the latest minor release receives security updates.

| Version | Supported |
|---------|-----------|
| 1.x     | ✅        |

## Reporting a vulnerability

**Do not open a public GitHub issue for security problems.**

Instead, use GitHub's private vulnerability reporting:
<https://github.com/Mikbol/cliwrap/security/advisories/new>

Please include:

- A description of the issue and its impact
- Steps to reproduce, or a proof of concept
- Your name/handle if you'd like to be credited

We'll acknowledge receipt within 72 hours and aim to have a fix released
within 30 days for confirmed vulnerabilities.

## Threat model

cliwrap runs as part of the user's interactive shell and executes extension
files from `$CLIWRAP_HOME` (default `~/.cliwrap`). **Extension files are
trusted shell code** — only add extensions you wrote or have audited, the
same way you'd treat anything in your `.bashrc`.

Specifically, cliwrap:

- Does **not** run any network code
- Does **not** elevate privileges
- Does **not** fetch or install remote extensions

If you find a way for an extension loaded from `$CLIWRAP_HOME` to affect a
user in a way they wouldn't expect given the extension's source, that's a
bug — please report it.
