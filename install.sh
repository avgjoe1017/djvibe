#!/usr/bin/env bash
# install.sh — bootstrap vibedj.
# Checks mpv + socat, copies the binary to ~/.local/bin, creates the audio
# folders, and prints the Claude Code hook snippet to merge.
#
# Idempotent: safe to re-run to upgrade the binary or re-print the snippet.

set -euo pipefail

INSTALL_DIR="${VIBEDJ_INSTALL_DIR:-$HOME/.local/bin}"
VIBEDJ_DIR="${VIBEDJ_DIR:-$HOME/.vibedj}"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- platform --------------------------------------------------------------

case "$(uname -s)" in
  Darwin)
    PLATFORM=mac
    ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      PLATFORM=wsl
    else
      PLATFORM=linux
    fi
    ;;
  MINGW*|CYGWIN*|MSYS*)
    echo "error: native Windows is not supported. Run install.sh inside WSL2." >&2
    exit 1
    ;;
  *)
    echo "error: unsupported platform: $(uname -s)" >&2
    exit 1
    ;;
esac

echo "platform: $PLATFORM"

# --- dependency checks -----------------------------------------------------

install_hint() {
  case "$PLATFORM" in
    mac) echo "brew install $1" ;;
    linux|wsl)
      if   command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install -y $1"
      elif command -v dnf     >/dev/null 2>&1; then echo "sudo dnf install -y $1"
      elif command -v pacman  >/dev/null 2>&1; then echo "sudo pacman -S --noconfirm $1"
      elif command -v zypper  >/dev/null 2>&1; then echo "sudo zypper install -y $1"
      else                                            echo "install $1 with your package manager"
      fi
      ;;
  esac
}

missing=()
for dep in mpv socat; do
  if command -v "$dep" >/dev/null 2>&1; then
    echo "found:    $dep ($(command -v "$dep"))"
  else
    missing+=("$dep")
  fi
done

if [ ${#missing[@]} -gt 0 ]; then
  echo
  echo "missing:  ${missing[*]}"
  echo "install with:"
  for dep in "${missing[@]}"; do
    echo "    $(install_hint "$dep")"
  done
  echo
  echo "then re-run ./install.sh"
  exit 1
fi

# --- copy binary -----------------------------------------------------------

if [ ! -f "$SRC_DIR/vibedj" ]; then
  echo "error: vibedj binary not found at $SRC_DIR/vibedj" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
install -m 0755 "$SRC_DIR/vibedj" "$INSTALL_DIR/vibedj"
echo "installed: $INSTALL_DIR/vibedj"

case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    ;;
  *)
    echo
    echo "warning: $INSTALL_DIR is not on your PATH."
    echo "add this to your shell rc (~/.zshrc, ~/.bashrc, etc.):"
    echo "    export PATH=\"$INSTALL_DIR:\$PATH\""
    echo
    ;;
esac

# --- runtime directories ---------------------------------------------------

mkdir -p "$VIBEDJ_DIR/podcast" "$VIBEDJ_DIR/ambient"
echo "audio folders ready:"
echo "    $VIBEDJ_DIR/podcast/   <- drop podcasts / audiobooks here"
echo "    $VIBEDJ_DIR/ambient/   <- drop ambient / drone here"

# --- hook snippet ----------------------------------------------------------

echo
echo "----------------------------------------------------------------"
echo "Final step: merge the following into ~/.claude/settings.json"
echo "----------------------------------------------------------------"
if [ -f "$SRC_DIR/hooks-snippet.json" ]; then
  cat "$SRC_DIR/hooks-snippet.json"
else
  echo "warning: hooks-snippet.json not found in $SRC_DIR" >&2
fi
echo "----------------------------------------------------------------"
echo
echo "Done. Drop audio into the folders above, then start a new Claude"
echo "Code session — vibedj will boot on the SessionStart hook."
