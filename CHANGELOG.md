# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-04-22

Initial release. **Requires bash 4.0+** (associative arrays). On macOS: `brew install bash`.

### Added
- Single extension file format with metadata directives (`@match`, `@mode`, `@arg`, `@desc`)
- Three lifecycle modes: `pre`, `post`, `replace`
- Automatic argument extraction into `ARG_*` environment variables
- Tab completion merging custom candidates with native completer (`complete -F` and `complete -C` styles)
- `--help` integration that appends a `CUSTOM COMMANDS` section to the wrapped CLI's native help
- Management CLI (`cliwrap wrap`, `new`, `list`, `edit`, `remove`, `doctor`, `init`, `version`)
- `install.sh` with symlink-based install layout
- Example extensions for `aws`, `git`, and `docker`
- End-to-end test suite (22 tests) using fake binaries
- ShellCheck clean across all shell sources

[Unreleased]: https://github.com/Mikbol/cliwrap/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Mikbol/cliwrap/releases/tag/v1.0.0
