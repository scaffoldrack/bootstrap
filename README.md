# bootstrap

Ansible automation for The Scaffold Rack platform — takes raw scaffoldrack hosts (commander, ai, pve1, pve2) from "fresh OS install" to "fully bootstrapped, hardened, and ready for the platform layers above." Plus the one shell script (`scripts/bootstrap-control-node.sh`) that bootstraps the control node itself.

For the project overview, see **[platform](https://github.com/scaffoldrack/platform)**.
For narrative and design decisions, see **[thescaffoldrack.com](https://thescaffoldrack.com)**.

---

## What this repo does

This is the **foundation layer** of the platform. It owns:

- **Control-node bootstrap** (`scripts/bootstrap-control-node.sh`) — installs Docker and the `devops-toolkit:latest` container image. Nothing else.
- **The Ansible runtime** — inventory, roles, playbooks for configuring all scaffoldrack hosts.
- **The two-identity model** — `andrew` (manual foothold) → `bob` (automation identity), implemented in `playbooks/bootstrap.yml`.
- **Control-node configuration** — `roles/control_node/` deploys zsh, oh-my-zsh, and the toolkit aliases that wrap the devops-toolkit container.
- **Host hardening** — `roles/hardening/` (one role, task-file splits, tags).
- **Eventually, Proxmox conversion** — `roles/proxmox/` for Debian-to-Proxmox on pve1 and pve2.
- **Eventually, developer-environment setup** — `roles/dev_environment/` for declarative per-developer-machine state (umask, CLAUDE.md symlinks).

The repo's job ends at "host is configured, hardened, and ready." Everything above (Kubernetes, GitOps, applications, observability) lives in other scaffoldrack repos.

## Hosts in scope

| Host | Role |
|---|---|
| commander | Ansible control node, Gitea host, kb host |
| ai | Dedicated AI host (Ollama, Open WebUI) |
| pve1 | Hypervisor (becoming Proxmox) |
| pve2 | Hypervisor (becoming Proxmox) |

## How to use it

This repo is in early-phase development. The eventual workflow:

1. **First-time control-node setup** — `bash scripts/bootstrap-control-node.sh` on commander. Result: Docker installed, toolkit image present.
2. **Bootstrap-the-bootstrap** — `docker run ... ansible-playbook playbooks/control-node.yml --ask-become-pass`. Result: zsh, toolkit aliases configured.
3. **All subsequent operations** — via toolkit aliases (`ansible-playbook`, `ansible`, etc. — these become aliases that invoke the container).
4. **Onboarding a new managed host** — `ansible-playbook playbooks/bootstrap.yml --ask-become-pass --limit <new-host>`. Creates bob, hardens, validates.
5. **Daily operations** — `ansible-playbook playbooks/site.yml`. Idempotent. Apply to all hosts.

For the detailed phase plan and current state, see [CONTEXT.md](CONTEXT.md).

For working in this repo (operational rules, conventions, what's in and out of scope), see [CLAUDE.md](CLAUDE.md).

## Conventions

- All commands run via `~/.zshrc.d/scaffoldrack-toolkit.zsh` aliases, which invoke the `devops-toolkit:latest` container. Don't install Ansible/kubectl/helm directly on the host.
- Idempotency is non-negotiable. Every script and playbook is safe to re-run.
- bob's private key lives at `~/.ssh/bob_ed25519` on the control node. Public key is committed at `files/bob.pub`.
- Tokens live in `~/.blackwell` (per `kb/projects/scaffoldrack/decisions/014-blackwell-token-storage-convention.md`).
- Per-repo `.githooks/pre-commit` normalizes file permissions on staged files.

## License

Apache 2.0. See [LICENSE](LICENSE).
