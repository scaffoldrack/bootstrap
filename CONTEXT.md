# CONTEXT.md — bootstrap

**Repo purpose:** Ansible automation that takes raw scaffoldrack hosts (commander, ai, pve1, pve2) from "fresh OS install with andrew having sudo" to "fully bootstrapped, hardened, and ready for the platform layers above." Plus the one shell script that bootstraps the control node itself.

**Last updated:** 2026-05-16 (post-session: bootstrap-control-node.sh authored and validated on valkyrie)

---

## 1. What this repo is

This repo is the **foundation layer** of The Scaffold Rack platform. It owns:

- **The control-node bootstrap shell script** — `scripts/bootstrap-control-node.sh`. Installs Docker and builds/pulls the `devops-toolkit:latest` container image. Nothing else.
- **The Ansible runtime** — inventory, roles, playbooks for configuring all scaffoldrack hosts.
- **The two-identity model implementation** — `andrew` (manual foothold) → `bob` (automation identity) per the playbook in `playbooks/bootstrap.yml`.
- **The control-node configuration** — `roles/control_node/` deploys zsh, oh-my-zsh, and the toolkit aliases that wrap the devops-toolkit container.
- **The dev-environment configuration** (anticipated; per the tooling-vs-declarative-state distinction) — `roles/dev_environment/` will eventually handle umask, CLAUDE.md symlinks, and other declarative per-developer-machine state.
- **Host hardening** — `roles/hardening/` (one role, task-file splits, tags). SSH, UFW, sysctl, fail2ban, etc.
- **Eventually, Proxmox conversion** — `roles/proxmox/` for Debian-to-Proxmox conversion on pve1 and pve2.

This repo's job ends at "host is configured, hardened, and ready." Application deployment, Kubernetes provisioning, GitOps, and observability live in other scaffoldrack repos.

## 2. Repo conventions

These match the broader Scaffold Rack project conventions. **Most working
agreements live higher up in the three-scope CLAUDE.md model:**

- **Scope 1 (universal):** `~/CLAUDE.md` — symlinked from
  `kb/CLAUDE.md`. Communication register, file/document conventions,
  the 3am rule, deliver-complete-files-or-deterministic-commands.
- **Scope 2 (scaffoldrack-org-wide):** `~/Projects/scaffoldrack/CLAUDE.md`
  — symlinked from `kb/projects/scaffoldrack/CLAUDE.md`. Runtime model
  (devops-toolkit container), two-identity model (andrew → bob), host
  inventory, Gitea/GitHub push pattern, `~/.blackwell` token convention,
  per-repo `.githooks/` with `core.hooksPath`.
- **Scope 3 (this repo):** `CLAUDE.md` in the repo root.

See `kb/meta/2026-05-09-claude-md-three-scopes.md` for the full model.

Conventions specific to this repo (don't restate Scope 1 or Scope 2):

- **Idempotency is the bright-line requirement.** Re-runs detect existing state and skip with a `warn` log; never destructive, never failing on second-or-later invocation.
- **`bootstrap-control-node.sh` is allowed to do exactly two things:** install Docker, build/pull the toolkit container. Anything else belongs in an Ansible role.
- **Hardening as one role with task-file splits and tags.** `--tags ssh` allows targeted re-runs.
- **Validation order:** commander → ai → pve2 → pve1 → parity.

## 3. Directory structure

```
bootstrap/
├── README.md              # human-facing entry point
├── CONTEXT.md             # this file — read on every session
├── CLAUDE.md              # Scope 3 working agreements for this repo
├── LICENSE                # Apache 2.0
├── .gitignore
├── .githooks/             # per-repo git hooks (set core.hooksPath = .githooks)
│   └── pre-commit         # normalizes permissions on staged files
├── decisions/             # Scope 3 ADRs (MADR 4.0.0 format)
│   ├── 0001-automation-user-bob.md
│   ├── 0002-toolkit-container-as-runtime.md
│   ├── 0003-bootstrap-control-node-scope.md
│   ├── 0004-validation-order.md
│   └── 0005-no-docker-group-modification.md
├── files/                 # committed support files (bob.pub, etc.)
│   └── bob.pub
├── inventory/             # Ansible inventory (placeholder)
│   └── .gitkeep
├── roles/                 # Ansible roles (placeholder)
│   └── .gitkeep
├── playbooks/             # Ansible playbooks (placeholder)
│   └── .gitkeep
├── scripts/               # Shell scripts (placeholder; bootstrap-control-node.sh lands here)
│   └── .gitkeep
└── tmp/
    └── .gitkeep
```

The directories are placeholders today — they materialize content as work progresses. The structure is in place so the repo's shape is clear from the start.

## 4. Hosts in scope

The four scaffoldrack hosts this repo manages:

| Host | Address | OS | Role |
|---|---|---|---|
| commander | 172.31.200.x | Debian 12 (Bookworm) on Pi 5 | Ansible control node, Gitea host, kb host |
| ai | 172.31.200.20 | Debian | Dedicated AI host (dual GTX 1070 Ti, Ollama, Open WebUI) |
| pve1 | 172.31.200.11 | Debian 13 (Trixie) → Proxmox | Hypervisor |
| pve2 | 172.31.200.12 | Debian 13 (Trixie) → Proxmox | Hypervisor |

commander is both control node and managed host (`ansible_connection: local`). The detailed inventory will land in `inventory/hosts.yml` when the inventory work begins.

The host inventory is also restated at the org level in Scope 2 CLAUDE.md (`kb/projects/scaffoldrack/CLAUDE.md` §3). Where they overlap, this file is the operational truth for bootstrap-specific work; Scope 2 is the umbrella view.

## 5. The two identities

Per ADR-0001 (`decisions/0001-automation-user-bob.md`) and Scope 2 CLAUDE.md §2:

- **andrew** — human-provisioned foothold. Created during OS install with sudo (password required, NOT NOPASSWD). Used exactly once per host: to run `bootstrap.yml` and create bob. Andrew passwords differ per host (security hygiene); this only matters at bootstrap time.
- **bob** — automation identity. Created by `bootstrap.yml` running as andrew. UID 990, ed25519 key authentication, NOPASSWD: ALL sudo. Every Ansible playbook from `site.yml` onward runs as bob. Andrew is dormant after bootstrap.

The model means there's one irreducibly manual prerequisite per host: andrew must exist with sudo before Ansible can do anything. Everything past that is automated.

## 6. The runtime

Per ADR-0002 (`decisions/0002-toolkit-container-as-runtime.md`) and Scope 2 CLAUDE.md §1:

All `ansible*`, `kubectl`, `helm`, `vault`, etc. commands run inside the
`devops-toolkit:latest` container, invoked via zsh aliases set up by
`roles/control_node/`. The container is the runtime; the aliases are the
user interface.

The one-time bootstrap-the-bootstrap step: after `bootstrap-control-node.sh`
finishes, the user manually runs
`docker run ... ansible-playbook playbooks/control-node.yml --ask-become-pass`
once. That playbook configures the shell, drops the aliases, sets up
oh-my-zsh, generates completions. Subsequent ansible runs use the alias.

Do not install Ansible, kubectl, helm, vault, etc. directly on hosts. The
container IS the runtime.

## 7. The phase plan

Bootstrap progresses through these phases. Each phase validates against the previous before moving on.

### Phase 0 — Prerequisites

- commander has Debian 12 + andrew with sudo
- ai, pve1, pve2 have their respective OSes + andrew with SSH key auth
- Andrew can `ssh ai/pve1/pve2 'hostname'` from commander without password

**Status:** Done.

### Phase 1 — Control node

- Run `bootstrap-control-node.sh` on commander. Result: Docker installed, `devops-toolkit:latest` image present.
- Run `playbooks/control-node.yml` once via raw `docker run` (the bootstrap-the-bootstrap step). Result: zsh, oh-my-zsh, toolkit aliases configured on commander.
- Validate: `type ansible-playbook` on commander shows the toolkit alias. `ansible localhost -m ping` works through the alias.

**Status:** Script written and merged to main. Idempotency path verified on valkyrie test machine (Docker already installed; clone, build, smoke all exercised, then re-run exercises all three short-circuit warns). The clean-host install path (Docker-not-installed) remains unverified — deferred to a clean VM or spare Pi session. The bootstrap-the-bootstrap manual run (`playbooks/control-node.yml`) is the next concrete unit of work.

### Phase 2 — Bootstrap one managed host (ai)

- Generate bob's ed25519 keypair on commander.
- Write inventory entry for ai.
- Run `playbooks/bootstrap.yml` against ai with `--ask-become-pass`. Result: bob exists on ai with SSH key auth and NOPASSWD: ALL sudo. SSH password auth disabled (after verification that bob can sudo).
- Validate: `ansible ai -m ping` works as bob without prompting.

**Status:** Not started. ai is the low-stakes validation target.

### Phase 3 — Bootstrap pve2

- Same pattern as Phase 2, against pve2.
- Validates that the bootstrap.yml works on Debian 13 Trixie (pve2 is Trixie; ai may be a different version).

**Status:** Not started.

### Phase 4 — Bootstrap pve1

- Same pattern as Phase 3, against pve1. By this point bootstrap.yml is well-validated.

**Status:** Not started.

### Phase 5 — Hardening

- `roles/hardening/` applied via `site.yml` to all four hosts.
- Tags: ssh, ufw, sysctl, fail2ban (initial set; expandable).
- Validation order matches the bootstrap order.

**Status:** Not started.

### Phase 6 — Proxmox conversion

- `roles/proxmox/` for Debian-to-Proxmox conversion. Applied to pve2 first, then pve1.
- This is the original goal that motivated the whole bootstrap project.

**Status:** Not started.

### Phase 7 — `dev_environment` role

- Per the tooling-vs-declarative-state distinction (`kb/meta/2026-05-10-tooling-vs-declarative-state.md`), per-developer-machine declarative state belongs here.
- Tasks: umask 0027 in shell rc, CLAUDE.md symlinks (Scope 1 and Scope 2 per `kb/projects/scaffoldrack/00-DO-THIS-FIRST-symlink-setup.md`), per-clone `core.hooksPath` configuration for scaffoldrack repos (see §11), eventually the git template trampoline if that pattern returns.
- Applied to commander and other scaffoldrack-developer machines (work machine, etc.).

**Status:** Not started. Captured here so the role's scope is anticipated.

## 8. Current state

**Phase 1 is in flight.** `scripts/bootstrap-control-node.sh` is written, merged to main, and validated on the valkyrie test machine for the idempotency path. The next concrete unit is `playbooks/control-node.yml` plus the `roles/control_node/` it consumes.

**Code-Claude on commander is verified-operational** as of 2026-05-10. The first-run verification (Milestones 1–4 of the crawl-phase plan) confirmed: three-scope CLAUDE.md walk-up resolves correctly, file reads are accurate (no confabulation), safe write/read/delete in `tmp/` works cleanly, and the `.githooks/pre-commit` is the perm-normalizing hook.

**`core.hooksPath` is now configured locally** on commander's bootstrap clone (set during Milestone 4). It was not previously set; see §11.

Specifically, what exists today:

- This `CONTEXT.md`
- `CLAUDE.md` (Scope 3, composes with Scopes 1 and 2)
- `README.md`
- `scripts/bootstrap-control-node.sh` — stage 1 of the control-node bootstrap (validated on valkyrie 2026-05-16)
- Empty placeholder directories: `inventory/`, `roles/`, `playbooks/`
- Five ADRs in `decisions/` (MADR 4.0.0 format) capturing the foundational decisions
- `.githooks/pre-commit` from the canonical source in tools repo
- `files/bob.pub` — bob's ed25519 public key

What's NOT here yet:

- `inventory/hosts.yml` — to be written when bootstrap.yml is being written
- `roles/control_node/` — unblocked; next concrete unit of work alongside `playbooks/control-node.yml`
- `roles/bootstrap_bob/` — to be written when bootstrap.yml is being written
- `roles/baseline/`, `roles/hardening/`, `roles/proxmox/` — later phases
- `playbooks/control-node.yml`, `playbooks/bootstrap.yml`, `playbooks/site.yml`, `playbooks/ping.yml` — to be written as the corresponding roles materialize

## 9. Backlog (bootstrap-specific items)

Items captured here so they don't get lost. Most belong in future ADRs or work cycles.

- Verify docker-devops state on commander (cloned? built? at what path?). Observed on valkyrie 2026-05-16: docker-devops repo includes a `files/custom-ca/` directory committed in the repo itself; the build pulls it directly from the clone, so `bootstrap-control-node.sh` does no CA staging and does not need to. The CA material flows from Caddy's internal CA (copied to the NAS so the same CA is used both places); eventual migration to Vault.
- Validate `bootstrap-control-node.sh` on a clean host — fresh VM or spare Pi — to exercise the Docker-install-from-scratch path that valkyrie skipped (Docker was already present on valkyrie, so only the short-circuit warn was exercised on that path)
- Build `roles/control_node/` (zsh, oh-my-zsh, toolkit aliases adapted from PoC version)
- Write `playbooks/control-node.yml`
- Build inventory and `playbooks/ping.yml` for the smoke test
- Write `roles/bootstrap_bob/` and `playbooks/bootstrap.yml`
- Apply bootstrap to ai (Phase 2 validation), then pve2 (Phase 3), then pve1 (Phase 4)
- Build `roles/baseline/` and `roles/hardening/` (Phase 5)
- Build `roles/proxmox/` for Debian-to-Proxmox conversion (Phase 6)
- Build `roles/dev_environment/` for declarative per-machine state (Phase 7)
- Get pve1 and pve2 actually running Proxmox (the original goal that motivated this repo)
- End-to-end validation of `bootstrap-control-node.sh` on a fresh throwaway VM

## 10. Cross-references

- **Platform meta-repo:** `gitea.mercnet.info/scaffoldrack/platform`
- **Tools repo (templates, scaffolding, hooks):** `gitea.mercnet.info/scaffoldrack/tools`
- **Personal kb:** `gitea.mercnet.info/scaffoldrack/kb` (private)
- **Token storage:** `~/.blackwell` on each control node (per ADR-014 in `kb/projects/scaffoldrack/decisions/`)
- **Three-scope CLAUDE.md model:** `kb/meta/2026-05-09-claude-md-three-scopes.md`
- **Tooling vs. declarative state:** `kb/meta/2026-05-10-tooling-vs-declarative-state.md`
- **Scope 2 hooks decision:** `kb/projects/scaffoldrack/decisions/012-per-repo-githooks-with-corehookspath.md`
- **Code-Claude first-run session:** `kb/sessions/2026-05-10-code-claude-first-run.md`
- **Chat-Claude / code-Claude handoff lessons:** `kb/meta/2026-05-10-chat-claude-code-claude-handoff-lessons.md`
- **MADR adoption and conventions:** `kb/meta/2026-05-16-madr-adoption-conventions.md`

## 11. Cross-cutting backlog (not bootstrap-specific)

Items that aren't bootstrap's job but were noted during sessions and don't yet have a home elsewhere. These should migrate to the right place when that place exists. Tracked here as a temporary catch-all.

- **`core.hooksPath` is per-clone state, not committed config.** A new clone of any scaffoldrack repo on any machine starts with `core.hooksPath` unset, and the per-repo perm-normalizing hook does not run until it's configured. Surfaced during 2026-05-10 first-run verification on commander's bootstrap clone. Short-term: every new clone needs `git config core.hooksPath .githooks` once. Durable answer: `roles/dev_environment/` (Phase 7) configures it declaratively for managed dev machines, possibly via a per-repo discovery loop. Not urgent.
- **`kb/decisions-index.md` (or similar discoverability layer)** — with ADRs landing in multiple locations across the kb (`kb/projects/scaffoldrack/decisions/`, `kb/projects/scaffoldrack/tracks/<track>/decisions/`, per-repo `decisions/`), there's a real risk of an ADR getting missed because someone looks in the wrong place. A small index — possibly auto-generated by walking `**/decisions/*.md` and pulling titles — would consolidate "where do I find decisions about X" into one lookup. Not urgent but increasingly valuable as the count grows.
- **Operational runbooks for git history rewriting** — when a commit lands that should have been excluded (secrets, large files, anything that needs to be unfindable in mirror history), the recovery procedure should be a runbook in `scaffoldrack/runbooks` rather than re-derived each time.
- **`tools/scripts/audit-mirrors.sh`** — formalize the curl+yq audit loop that confirms every Gitea push-mirror is configured and not erroring.
- **Gitea push-mirror does not appear to propagate branch deletions to GitHub.** Observed 2026-05-16: deleting `bootstrap-control-node-draft` from Gitea (`git push gitea --delete …`) successfully removed the branch from Gitea, but the GitHub mirror retained the stale ref pointing at the same SHA as `main` (harmless content-wise, cosmetic stale ref). Worth understanding whether this is Gitea push-mirror config (mirror-on-add only, not mirror-on-delete) or expected behavior. Affects the cleanliness of the public GitHub view of every scaffoldrack repo.
- **URL validation for `setup-gitea-mirrors.sh` (now superseded by `scaffold-repo.sh`)** — backlog item from the 2026-05-09 incident; the new scaffold-repo path doesn't have the old script's bug, but new mirror-touching scripts should be reviewed for similar fat-finger risk.
- **Custom git-credential-blackwell helper** — replace HTTPS-with-stored-token with a credential helper that reads from `~/.blackwell` directly. Cleaner than the current pattern.
- **Custom Gitea SSH on alternate port** — long-term fix for the port-22 conflict that currently has Gitea SSH disabled. (Documented backlog item; not urgent.)
- **Self-host `thescaffoldrack.com`** — when Traefik/ingress is up. Not bootstrap's job but worth tracking.
- **Personal dotfiles repo at `blackwell/dotfiles`** — private, not mirrored. For Andrew's personal-preference shell config that doesn't belong in scaffoldrack.

When any of these items land in their proper home (a runbook, a tools script, a kb meta artifact, etc.), remove from this list.
