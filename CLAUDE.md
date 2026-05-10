# CLAUDE.md — bootstrap

Operational rules for Claude Code working in this repo. Auto-loaded on session start.

For full repo context and rationale, read `CONTEXT.md`. For detailed operational guidance, read `INSTRUCTIONS.md`. This file is the load-bearing minimum.

---

## Read these on every session

1. `CONTEXT.md` — what this repo is, architectural decisions, current state
2. `INSTRUCTIONS.md` — operational rules for working in this repo
3. Any `decisions/` ADR relevant to your task

## Identity

This is the **bootstrap** repo in the **scaffoldrack** organization. It holds:

- One shell script (`scripts/bootstrap-control-node.sh`) — Docker + devops-toolkit container only
- All Ansible automation for managing the Scaffold Rack platform — inventory, roles, playbooks

This repo's job ends at "host is configured, hardened, and ready for whatever comes next." Application deployment, Kubernetes provisioning, and GitOps live elsewhere.

## Hard rules

- **Idempotency is non-negotiable.** Every script and playbook must be safe to re-run. Re-runs detect existing state and skip with a `warn` log; they never fail or do destructive work.
- **Always read files before editing.** Never reconstruct file contents from memory or assumption. This is project-wide and applies without exception.
- **No heredocs in scripts.** Use external configuration files when needed.
- **Markdown only for documentation.** No `.docx`, `.pdf`, or other formats.
- **Secrets never committed.** ed25519 *public* keys are fine to commit; private keys never. Tokens come from `~/.blackwell` on the control node, sourced at runtime.
- **`tmp/` is for ephemeral work.** Never commit work products from `tmp/` directly — move them to their proper location first.

## The two-identity model

Every managed host has two identities:

- **andrew** — manual foothold for one-time bootstrap. Sudo with password.
- **bob** — automation identity created by `bootstrap.yml`. UID 990, ed25519 key auth, NOPASSWD sudo. Used for everything after bootstrap.

Be acutely aware which identity is active when writing tasks that affect SSH or sudo. Lockout is a real risk. The `bootstrap.yml` playbook MUST verify bob can sudo before disabling SSH password auth.

## The runtime model

All `ansible*`, `kubectl`, `helm`, `vault`, etc. commands run inside the `devops-toolkit:latest` container, invoked via zsh aliases set up by `roles/control_node/`. Do not install Ansible, kubectl, or other tools directly on hosts. The container IS the runtime.

If something doesn't work in the container, fix the container or the Ansible code. Do not bypass by installing tools on the host.

## Conventions

- Color-coded shell helpers: `log()` (green INFO), `warn()` (yellow WARN), `die()` (red ERR, exits non-zero)
- `.example` suffix for templated files; real values gitignored
- ADRs in `decisions/` with format: Status, Date, Context, Decision, Consequences, Alternatives Considered, Trade-offs Accepted, When This Is the Wrong Choice
- README.md is human-facing; INSTRUCTIONS.md is for AI; CONTEXT.md is the living source of truth
- Use `~/bin/kubectl` only for *work* cluster commands — this repo doesn't touch the work cluster

## On scope and pushback

- This repo does platform infrastructure, not application code or personal preferences
- Personal dotfiles (custom prompt, vim config, non-toolkit aliases) belong in a separate dotfiles repo
- If a request would expand the script `bootstrap-control-node.sh` beyond Docker + container image, push back and propose an Ansible role instead
- Don't add features beyond what was asked
- Don't introduce new tools without discussion

## On uncertainty

- Convention questions → re-read CONTEXT.md
- Decision rationale → check `decisions/`
- Scope ambiguity → ask, don't guess
- Multiple valid implementations → present options briefly, ask which to pursue

The user values explicit-over-clever and the 3am rule. Lead with the simpler version. Complexity must justify itself.

## On end-of-session

- Confirm git state is clean or intentionally staged
- Propose CONTEXT.md updates for significant work (especially §12 Current state)
- Draft ADR for any decision that emerged
- Push to gitea (`git push gitea main`); verify mirror to GitHub fired
- Surface gotchas, workarounds, or non-obvious dependencies for future sessions
