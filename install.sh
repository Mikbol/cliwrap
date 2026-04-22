#!/usr/bin/env bash
# Install cliwrap. Usage: ./install.sh [--prefix ~/.local]
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        *) echo "unknown: $1"; exit 1 ;;
    esac
done

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$PREFIX/share/cliwrap"

mkdir -p "$PREFIX/bin" "$DEST"
cp -r "$SRC/bin" "$SRC/lib" "$DEST/"
cp "$SRC/VERSION" "$DEST/"
chmod +x "$DEST/bin/cliwrap"

# Symlink the binary; structure (bin/ + lib/ + VERSION siblings) is preserved,
# so cliwrap's default lib resolution keeps working through the symlink.
ln -sf "$DEST/bin/cliwrap" "$PREFIX/bin/cliwrap"

cat <<EOF

✓ Installed cliwrap to $PREFIX/bin/cliwrap

Add to your shell rc file (~/.bashrc or ~/.zshrc):

    eval "\$(cliwrap init)"

Then reload your shell:

    exec \$SHELL

Get started:

    cliwrap wrap aws
    cliwrap new aws whoami --desc "Show current identity"
    cliwrap list
EOF
