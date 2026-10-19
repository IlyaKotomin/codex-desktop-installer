#!/usr/bin/env bash
# Install or update OpenAI's Codex desktop app (the ChatGPT desktop app for
# Linux, Codex inside) on Fedora or Arch. Run it as your user; it asks sudo
# for the steps that need root. Re-run it any time to update.
#
# Fedora: first run downloads OpenAI's signed RPM, checks the signature
#   against the pinned key below, and installs it. The package brings
#   OpenAI's dnf repo, so later runs (and any plain `dnf upgrade`) update
#   from there.
# Arch: first run uses OpenAI's own install-arch.sh, which adds their signed
#   pacman repo. Later runs do `pacman -Syu chatgpt-bin`; Arch has no
#   supported partial upgrade, so that is a full system upgrade.
#
# Usage: install-codex-desktop.sh [-y|--yes]
#   -y  answer yes to dnf/pacman prompts (OpenAI's first-time Arch
#       installer still asks once)
#
# Everything runs from main at the very end, so a download cut short
# (bash <(curl ...)) does nothing instead of half the work.
set -euo pipefail

BASE=https://persistent.oaistatic.com/codex-app-prod/linux
# "Codex Linux Repository" key, the one OpenAI's install-arch.sh pins. If
# OpenAI rotates it, check the new one at learn.chatgpt.com before changing.
KEY_FPR=3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { local c; for c; do command -v "$c" >/dev/null || die "missing $c"; done; }
fetch() { curl --proto '=https' --tlsv1.2 -fL --retry 3 "$@"; }

family() {
  local ids=""
  # shellcheck disable=SC1091
  [[ -r /etc/os-release ]] && ids=$(. /etc/os-release; echo " ${ID:-} ${ID_LIKE:-} ")
  case "$ids" in
    *" arch "*) echo arch ;;
    *" fedora "*) echo fedora ;;
    *) if command -v pacman >/dev/null; then echo arch
       elif command -v dnf >/dev/null; then echo fedora
       else echo unknown; fi ;;
  esac
}

# Fails unless the RPM carries a valid signature from the pinned key.
verify_rpm() {
  local rpm=$1 fprs out
  need gpg rpmkeys
  fetch -sS -o "$work/key.gpg" "$BASE/repository-signing-key.gpg"
  mkdir -m 0700 "$work/gnupg" "$work/rpmdb"
  fprs=$(gpg --homedir "$work/gnupg" --batch --quiet --show-keys --with-colons "$work/key.gpg" |
    awk -F: '$1 == "pub" { p=1 } $1 == "sub" { p=0 } $1 == "fpr" && p { print $10; p=0 }') ||
    die "could not read OpenAI's signing key"
  grep -qxF "$KEY_FPR" <<<"$fprs" ||
    die "OpenAI's signing key is no longer $KEY_FPR (got: ${fprs:-none}); not installing"
  gpg --homedir "$work/gnupg" --batch --quiet --import "$work/key.gpg"
  gpg --homedir "$work/gnupg" --batch --quiet --armor --export "$KEY_FPR" >"$work/key.asc"
  # A private rpmdb and keyring, so only the pinned key can vouch for the
  # package and nothing is imported into the system.
  local rk=(rpmkeys --dbpath "$work/rpmdb" --define "_keyring fs"
    --define "_keyringpath $work/rpmdb/pubkeys/")
  "${rk[@]}" --import "$work/key.asc"
  out=$("${rk[@]}" --checksig "$rpm" 2>&1) || true
  [[ $out == *"signatures OK" ]] ||
    die "$(basename "$rpm") is not signed by $KEY_FPR; not installing ($out)"
  say "signature OK (key $KEY_FPR)"
}

install_fedora() {
  need dnf rpm
  [[ ! -e /run/ostree-booted ]] ||
    die "Fedora Atomic is not supported: OpenAI's RPM skips its repo setup there"
  local repo_file=/etc/yum.repos.d/chatgpt.repo y=()
  # dnf would otherwise skip the repo quietly when it cannot load it.
  local strict=(--setopt=openai-chatgpt.skip_if_unavailable=False)
  (( yes )) && y=(-y)
  if rpm -q chatgpt >/dev/null 2>&1 && [[ -f $repo_file ]]; then
    say "installed: $(rpm -q chatgpt); updating from OpenAI's dnf repo"
    "${sudo[@]}" dnf upgrade --refresh "${strict[@]}" "${y[@]}" chatgpt
  else
    local rpm="$work/chatgpt.$rpm_arch.rpm"
    say "downloading the latest RPM"
    fetch --progress-bar -o "$rpm" "$BASE/rpm/latest/chatgpt.$rpm_arch.rpm"
    verify_rpm "$rpm"
    "${sudo[@]}" dnf install "${y[@]}" "$rpm"
    # Until someone accepts the repo key, every plain `dnf upgrade` skips
    # the repo without a word. That key file came in the package verified
    # above, so accept it now.
    if [[ -f $repo_file ]]; then
      say "trusting OpenAI's repo key for future updates"
      "${sudo[@]}" dnf makecache -y --refresh --repo openai-chatgpt "${strict[@]}"
    fi
  fi
  say "now installed: $(rpm -q chatgpt)"
}

install_arch() {
  need pacman
  # OpenAI's package script calls cmp but does not depend on diffutils.
  command -v cmp >/dev/null || die "missing cmp: sudo pacman -S diffutils, then re-run"
  local conf=/etc/pacman.d/openai-chatgpt.conf y=()
  (( yes )) && y=(--noconfirm)
  if [[ -f $conf ]] && grep -qxF "Include = $conf" /etc/pacman.conf; then
    say "updating from OpenAI's pacman repo (full system upgrade)"
    "${sudo[@]}" pacman -Syu --needed "${y[@]}" chatgpt-bin
  else
    say "adding OpenAI's pacman repo with their installer"
    fetch -sS -o "$work/install-arch.sh" "$BASE/install-arch.sh"
    "${sudo[@]}" bash "$work/install-arch.sh"
  fi
  # 2>/dev/null: right after the first install the repo's database is not
  # synced yet, and pacman -Q warns about it.
  say "now installed: $(pacman -Q chatgpt-bin 2>/dev/null)"
}

usage() {
  echo "usage: install-codex-desktop.sh [-y|--yes]"
  echo "Installs or updates OpenAI's Codex desktop app on Fedora or Arch."
  echo "  -y  answer yes to dnf/pacman prompts"
}

# Globals, not locals: the functions above and the EXIT trap read them.
main() {
  yes=0
  case "${1:-}" in
    "") ;;
    -y|--yes) yes=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac

  if [[ $EUID -eq 0 ]]; then sudo=(); else need sudo; sudo=(sudo); fi
  need curl
  case "$(uname -m)" in
    x86_64) rpm_arch=x86_64 ;;
    aarch64|arm64) rpm_arch=aarch64 ;;
    *) die "OpenAI only builds for x86_64 and aarch64, not $(uname -m)" ;;
  esac

  # Disk-backed scratch: the RPM is over 500 MB, too big for a tmpfs /tmp.
  work=$(mktemp -d "${TMPDIR:-/var/tmp}/codex-desktop.XXXXXX")
  trap 'rm -rf "$work"' EXIT

  case "$(family)" in
    fedora) install_fedora ;;
    arch) install_arch ;;
    *) die "only Fedora and Arch are supported" ;;
  esac
  say "start it with: chatgpt   (native Wayland, experimental: chatgpt --ozone-platform=wayland)"
}

main "$@"
