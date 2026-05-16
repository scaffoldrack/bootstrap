#!/usr/bin/env bash
#
# bootstrap-control-node.sh — stage 1 of the scaffoldrack control-node
# bootstrap. Does exactly two things on a fresh Debian host:
#
#   1. Install Docker (via https://get.docker.com).
#   2. Clone andrewjkrull/docker-devops and `make build` + `make smoke`
#      the `devops-toolkit:latest` image.
#
# Stops there. Prints a next-step message for stage 2.
#
# Scope is fixed by ADR-0003 and ADR-0005:
#   - decisions/0003-bootstrap-control-node-scope.md
#   - decisions/0005-no-docker-group-modification.md
#
# This script DOES NOT:
#   - modify ~/.zshrc, ~/.bashrc, or any shell rc files
#   - install any apt package other than what get.docker.com installs
#   - create or modify user accounts
#   - add any user to the docker group (ADR-0005 — stage 2 uses `sudo docker run`)
#   - deploy aliases, generate keys, or set up zsh/oh-my-zsh
#
# Anything beyond Docker + container image is Ansible's job
# (roles/control_node/ and onward).

set -euo pipefail

TOOLKIT_REPO_URL="https://github.com/andrewjkrull/docker-devops"
TOOLKIT_CLONE_PARENT="$HOME/Projects/docker"
TOOLKIT_CLONE_DIR="$TOOLKIT_CLONE_PARENT/docker-devops"
TOOLKIT_IMAGE="devops-toolkit:latest"

log()  { printf '\033[0;32mINFO:\033[0m  %s\n' "$*" >&2; }
warn() { printf '\033[0;33mWARN:\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[0;31mERR:\033[0m   %s\n' "$*" >&2; exit 1; }

install_docker() {
  if command -v docker >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    warn "Docker present and daemon reachable, skipping install"
    return
  fi
  log "Installing Docker via https://get.docker.com"
  local installer="$TMPDIR_DOCKER_INSTALL/get-docker.sh"
  curl -fsSL https://get.docker.com -o "$installer" \
    || die "Failed to download get-docker.sh"
  sudo sh "$installer" \
    || die "get-docker.sh failed; see output above"
  sudo docker info >/dev/null 2>&1 \
    || die "Docker installed but daemon not reachable"
  log "Docker installed; daemon reachable"
}

clone_docker_devops() {
  mkdir -p "$TOOLKIT_CLONE_PARENT"
  if [[ -d "$TOOLKIT_CLONE_DIR/.git" ]]; then
    local origin
    origin=$(git -C "$TOOLKIT_CLONE_DIR" remote get-url origin 2>/dev/null || true)
    if [[ "$origin" == "$TOOLKIT_REPO_URL" ]]; then
      warn "$TOOLKIT_CLONE_DIR already cloned from expected remote, skipping clone (no auto-pull)"
      return
    fi
    die "$TOOLKIT_CLONE_DIR exists but origin is '$origin' (expected '$TOOLKIT_REPO_URL')"
  fi
  log "Cloning $TOOLKIT_REPO_URL into $TOOLKIT_CLONE_DIR"
  git clone "$TOOLKIT_REPO_URL" "$TOOLKIT_CLONE_DIR" \
    || die "git clone failed; verify $TOOLKIT_REPO_URL is reachable"
}

build_toolkit_image() {
  if sudo docker image inspect "$TOOLKIT_IMAGE" >/dev/null 2>&1; then
    warn "$TOOLKIT_IMAGE already present, skipping build (remove image to force rebuild)"
    return
  fi
  log "Building $TOOLKIT_IMAGE via 'make build' in $TOOLKIT_CLONE_DIR"
  sudo make -C "$TOOLKIT_CLONE_DIR" build \
    || die "'make build' failed in $TOOLKIT_CLONE_DIR; see output above"
}

smoke_toolkit_image() {
  log "Validating $TOOLKIT_IMAGE via 'make smoke' in $TOOLKIT_CLONE_DIR"
  sudo make -C "$TOOLKIT_CLONE_DIR" smoke \
    || die "'make smoke' failed in $TOOLKIT_CLONE_DIR; see output above"
}

print_next_steps() {
  cat >&2 <<'EOF'

Stage 1 complete.
When playbooks/control-node.yml exists, run stage 2:
  sudo docker run --rm -it -v "$PWD":/work -w /work devops-toolkit:latest \
    ansible-playbook playbooks/control-node.yml --ask-become-pass

EOF
}

main() {
  TMPDIR_DOCKER_INSTALL=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_DOCKER_INSTALL"' EXIT

  install_docker
  clone_docker_devops
  build_toolkit_image
  smoke_toolkit_image
  print_next_steps
}

main "$@"
