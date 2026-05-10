# Conversation summary — 2026-05-09

For priming the next chat-Claude conversation. Captures decisions, current state, open threads, and lessons. Not for committing anywhere; this is a handoff document.

---

## What this conversation set out to do

Andrew came in wanting to get Ansible going so he could automate Proxmox installation on pve1 and pve2 (Z's website is down waiting for a new home; Wyatt's setup is similar). The conversation did not get to Ansible. It spent the day on prerequisite foundation work — Gitea-as-canonical, repo conventions, scaffolding tools, and incident recovery — that turned out to be necessary before Ansible work could start cleanly.

End-of-session honest assessment: foundation is now in place for Ansible to actually move next session.

## Major decisions landed

### Cross-cutting (eventually go in `notes/decisions/`)

- **Gitea push-primary, GitHub push-mirror.** Push to Gitea on commander; Gitea push-mirrors to GitHub. Reasoning: Gitea is on Andrew's desk (recoverable), GitHub is a vendor (not). External SSH with 2FA on commander makes Gitea reachable from anywhere, removing the friction objection. GitHub flakiness during the conversation reinforced the choice.

- **kb (Stanford) structure.** When migration happens, projects under `kb/projects/<name>/` (working state, ADRs, brand) versus dated knowledge artifacts under `kb/work/`, `kb/personal/`, `kb/meta/`. Both in one repo for native cross-referencing. Sync between home and work via Gitea + external SSH (no Google Drive — Drive corrupts `.git`).

- **Repo conventions** (already established): markdown only, INSTRUCTIONS.md vs README.md, no heredocs, idempotent, `tmp/.gitkeep`, `.example` suffix, color-coded log/warn/die helpers, secrets from `~/.blackwell` (renamed from `.blackwell_tokens` for security), 3am rule, always-read-files-before-editing, ADRs in `decisions/`.

### Bootstrap repo (Ansible) decisions

- **Repo unification:** bootstrap repo holds both the shell script and all Ansible content. Considered splitting and rejected it.

- **Automation user `bob`, UID 990, ed25519 key, NOPASSWD: ALL sudo.** UID 990 chosen high enough to never collide with packages. NOPASSWD: ALL is documented as wrong for FedRAMP, fine for now.

- **Two-identity model:** andrew is the human-provisioned foothold (created during OS install, sudo with password, used once for bootstrap). bob is the automation identity (created by `bootstrap.yml`, NOPASSWD, key auth, used forever after). Andrew passwords differ per host; bootstrap runs per-host with `--ask-become-pass`.

- **`bootstrap-control-node.sh` is narrowly scoped:** Docker + devops-toolkit container image, period. Does NOT install Ansible, zsh, oh-my-zsh, toolkit aliases. Those happen via `roles/control_node/` and `playbooks/control-node.yml` running inside the container.

- **Toolkit consumed via zsh aliases**, modeled on Andrew's existing PoC pattern (`poc-toolkit.zsh`). Aliases wrap `docker run` invocations of devops-toolkit. Functions, completions, helper commands. zsh is required not as preference but as runtime — the toolkit interface IS the shell config.

- **One-time bootstrap-the-bootstrap step:** after `bootstrap-control-node.sh` finishes, user manually runs `docker run ... ansible-playbook playbooks/control-node.yml --ask-become-pass` once. That playbook configures the shell, drops the aliases, sets up oh-my-zsh, generates completions. Subsequent ansible runs use the alias.

- **Hardening as one role with task-file splits and tags.** UFW for firewall. Tags allow `--tags ssh` for targeted re-runs.

- **Validation order:** commander → ai → pve2 → pve1 → parity. ai is the low-stakes managed-host validation target. pve2 before pve1 because pve1 is more "production-feeling."

### Tools repo

- Scaffolded today with templates/, repos.yaml, scripts/.
- Templates produced: `.gitignore.{default,python,ansible,hugo,gitops,ai}`, README.md.template, CONTEXT.md.template, LICENSE.
- repos.yaml as source of truth for the scaffoldrack org's repos with name/private/type/created metadata.
- Two scripts written and validated: `setup-gitea-mirrors.sh`, `configure-remotes.sh`.

## Current state of all 11 scaffoldrack repos

All exist on Gitea, all (except notes) push-mirror to GitHub, all mirror states clean (no last_error) as of 2026-05-09. Validated end-to-end via API audit.

| Repo | Local content | Pushed to Gitea | Mirror status |
|---|---|---|---|
| platform | README.md only | Yes | Working |
| blog | Full Hugo site | Yes | Working (after token scope fix) |
| ai | Placeholder README | Yes | Working |
| bootstrap | CONTEXT.md (today's draft, needs commit) | Yes | Working |
| network | LICENSE + tmp/ | Yes | Working |
| observability | LICENSE + tmp/ | Yes | Working |
| platform-services | LICENSE + tmp/ | Yes | Working |
| proxmox | LICENSE + tmp/ | Yes | Working |
| tools | Full scaffolding | Yes | Working (validated first) |
| notes | Empty (just `git init -b main`) | Not pushed | No mirror (private) |
| .github | Org profile | Yes | Working |

## Hosts and prerequisites

- **commander** (172.31.200.x): Debian 12 Bookworm on Pi 5. Gitea host. Will be Ansible control node. Has docker-devops checked out somewhere (verify path). bob keypair NOT yet generated.

- **ai** (172.31.200.20): Debian. Andrew has SSH key auth + sudo with password.

- **pve1** (172.31.200.11): Debian 13 Trixie. Andrew has SSH key auth + sudo with password.

- **pve2** (172.31.200.12): Debian 13 Trixie. Andrew has SSH key auth + sudo with password. Andrew passwords differ per host.

`ssh ai/pve1/pve2 'hostname; uptime'` from commander works without password — the foothold is in place.

## What happened today (incidents and recoveries)

Today included one real production incident worth remembering: **the ai mirror got recreated by hand with blog's URL (fat-finger), pushed ai content to blog's GitHub repo, force-push from local recovered.** Lessons:

- Mirror destination URLs need validation in scripts (backlog item)
- Gitea API is the diagnostic source of truth, not the UI display
- Local repos as canonical source-of-truth saved the day
- Force-push from local SSH'd github remote is the recovery mechanism

Three other gotchas surfaced and were resolved:

- **GITHUB_PUSH_TOKEN needs `workflow` scope** if any mirror target has GitHub Actions workflows (blog has the deploy workflow). Token edited in place; no re-credentialing needed across mirrors.
- **Empty Gitea repo → mirror tries to delete GitHub branch → GitHub refuses.** Fix: push local content to Gitea before relying on the mirror. Affected 6 repos, all resolved by pushing local content.
- **Gitea SSH disabled** (Andrew's docker-compose has `DISABLE_SSH=true` to avoid port 22 conflict with host sshd) — git ops use HTTPS with credential helper storing `GITEA_TOKEN`. Long-term fix: alternate SSH port for Gitea. Backlog.

## What's already drafted in chat that needs to land in repos

- **bootstrap/CONTEXT.md** — final clean version produced this session, downloaded by Andrew. Needs committing to bootstrap repo.
- **bootstrap/INSTRUCTIONS.md** — produced as part of this handoff (separate file).

## Open threads / not-yet-done

### Immediate next session
- Commit CONTEXT.md and INSTRUCTIONS.md to bootstrap repo, push to Gitea
- Generate bob's ed25519 keypair on commander: `ssh-keygen -t ed25519 -f ~/.ssh/bob_ed25519 -C "bob@scaffoldrack" -N ""`
- Verify docker-devops state on commander (cloned? built?)
- Code-Claude writes `bootstrap-control-node.sh`
- Andrew runs the script on commander to validate idempotency
- Write four ADRs from CONTEXT.md content (mechanical, parallel to code work)

### Near-term backlog
- Build `roles/control_node/` (zsh, oh-my-zsh, toolkit aliases adapted from PoC version)
- Build `playbooks/control-node.yml`
- Build inventory and `playbooks/ping.yml`
- Build `roles/bootstrap_bob/` and `playbooks/bootstrap.yml`
- Apply bootstrap to ai (low-stakes validation), then pve2, then pve1
- Build `roles/baseline/` and `roles/hardening/`
- Build `roles/proxmox/` for Debian-to-Proxmox conversion
- Get pve1 and pve2 actually running Proxmox (the original goal)
- Get Z's site and Wyatt's site running on the new infrastructure

### Documented backlog items (also captured separately by Andrew)
- Set up project/conversation tracking system on commander
- Decide on `proxmox` repo type (provisional gitops, revisit when contents emerge)
- Write `rotate-github-token.sh` when PAT expires (~Aug 2026)
- Migrate `scaffoldrack-notes/` content into `notes/` repo on Gitea
- Decide fate of `homelab` repo (archive or absorb selectively)
- Document the Gitea-primary decision as ADR
- Add URL validation to `setup-gitea-mirrors.sh`
- Build `tools/scripts/audit-mirrors.sh` (formalize the curl+yq audit loop)
- Audit checklist for any new mirror config
- Document `workflow` scope requirement for `GITHUB_PUSH_TOKEN`
- Document the "push local content to Gitea first" gotcha
- Replace HTTPS-with-stored-token with custom git-credential-blackwell helper
- Custom Gitea SSH on alternate port
- Self-host thescaffoldrack.com when Traefik/ingress is up
- End-to-end validation of `bootstrap-control-node.sh` on fresh throwaway VM
- Clean up `public/` from blog repo and update `.gitignore.hugo`
- Personal dotfiles repo at `blackwell/dotfiles` (private, not mirrored)

## Tone notes for the next conversation

Andrew is excited to start writing actual code (Ansible specifically). He's been patient through a long foundation session and an incident. The next conversation should respect that he's been waiting to make Ansible-shaped progress.

He works iteratively — pushes back productively when something feels wrong (multiple times today his pushback was correct and changed direction). Don't be defensive when corrected; update the model and move on.

He values explicit-over-clever and the 3am rule. When proposing things, lead with the simplest version. Complexity needs justification.

He noted today that organic conversations weave between threads, and that he wants to capture loose threads before they're lost. The backlog file pattern (date-stamped, in kb or notes) is the answer; gently encourage updating it when threads surface.

His Code-Claude on commander is now part of the workflow. The handoff pattern: chat-Claude (here) for architecture and decisions; Code-Claude on commander for writing files, running commands, debugging against real hosts. CONTEXT.md and INSTRUCTIONS.md in each repo are the bridge.

## Files produced today (in the conversation, may or may not be committed)

- `tools/repos.yaml` — committed
- `tools/templates/*` (10 files) — committed
- `tools/scripts/setup-gitea-mirrors.sh` — committed
- `tools/scripts/configure-remotes.sh` — should be committed if not yet
- `bootstrap/CONTEXT.md` — produced today, awaiting commit
- `bootstrap/INSTRUCTIONS.md` — produced today (this handoff package), awaiting commit
- `tools/README.md`, `tools/CONTEXT.md` — produced earlier in session, committed
