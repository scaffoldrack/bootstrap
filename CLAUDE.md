# CLAUDE.md — bootstrap (Scope 3)

Repo-specific working agreements for the **bootstrap** repo in the scaffoldrack
organization. Auto-loaded by code-Claude on session start in this repo.

This file is **Scope 3** in the three-scope CLAUDE.md model
(see `kb/meta/2026-05-09-claude-md-three-scopes.md`). It composes with:

- **Scope 2** (scaffoldrack-org-wide): `~/Projects/scaffoldrack/CLAUDE.md`
  — runtime model, two-identity model, host inventory, Gitea/GitHub
  push pattern, scaffoldrack-specific conventions.
- **Scope 1** (universal): `~/CLAUDE.md` — communication register, document
  conventions, the 3am rule, deliver-complete-files-or-deterministic-commands,
  the kb's own conventions.

This file holds **only what's specific to the bootstrap repo**. Don't restate
Scope 1 or Scope 2 rules here.

For full repo context and rationale, read `CONTEXT.md`. For detailed
operational guidance, read `INSTRUCTIONS.md`. This file is the load-bearing
minimum.

---

## Read these on every session

In addition to walking up the tree for Scope 1 and Scope 2 CLAUDE.md files,
on every session in this repo:

1. `CLAUDE.md` (this file) — repo-specific rules
2. `CONTEXT.md` — what this repo is, architectural decisions, current state
3. `INSTRUCTIONS.md` — detailed operational rules for working in this repo
4. Any `decisions/` ADR relevant to your task

## Repo identity

This is the **bootstrap** repo in the **scaffoldrack** organization. It holds:

- One shell script (`scripts/bootstrap-control-node.sh`) — installs Docker
  and builds/pulls the `devops-toolkit:latest` container. Nothing else.
- All Ansible automation for managing the scaffoldrack platform — inventory,
  roles, playbooks. Includes the `control_node` role that configures the
  control node itself (zsh, toolkit aliases, completions).

The shell script is the only thing that exists outside Ansible because there's
no way to use Ansible to set up the thing that runs Ansible. Once the script
finishes and the container image is available, Ansible takes over for
everything else.

This repo is the **originator** of two scaffoldrack-org-wide models (which
are documented in the Scope 2 CLAUDE.md, not here):

- **The runtime model** — `bootstrap-control-node.sh` builds the
  `devops-toolkit:latest` image; `roles/control_node/` deploys the zsh
  aliases that make it reachable.
- **The two-identity model** — `playbooks/bootstrap.yml` plus
  `roles/bootstrap_bob/` is what creates bob on each new managed host.

Other scaffoldrack repos consume these models as inputs; bootstrap creates
them.

## Repo-specific hard rules

These specialize Scope 1 and Scope 2 rules for this repo's specific concerns.

- **Idempotency is the bright-line requirement here.** Scope 2 already
  states this; in this repo, every script and playbook gets exercised on
  re-runs constantly during development. Re-runs detect existing state and
  skip with a `warn` log. Never destructive, never failing on second-or-later
  invocation.
- **`bootstrap-control-node.sh` is allowed to do exactly two things:**
  install Docker and build/pull the `devops-toolkit:latest` image. Anything
  else (zsh setup, alias deployment, completion generation, etc.) belongs in
  `roles/control_node/`. If a request would expand the script beyond Docker
  + container image, push back and propose an Ansible role instead.
- **The `bootstrap.yml` playbook MUST verify bob can sudo before disabling
  SSH password auth.** This is the lockout-prevention discipline. The
  verification step is non-optional; any change to `bootstrap.yml` that
  weakens it should be flagged loudly.
- **`ansible_connection: local` for commander.** commander is both control
  node and managed host. To avoid the 2FA-on-external-SSH consideration,
  it manages itself locally. Don't change this without considering the
  consequences for the 2FA posture.

## Repo-specific scope discipline

The Scope 2 CLAUDE.md describes scaffoldrack's whole repo landscape and the
roles each repo plays. This repo's specific scope:

- **In scope here:** host bootstrapping, baseline configuration, hardening,
  Debian-to-Proxmox conversion, the control_node role (zsh, aliases, toolkit
  setup).
- **Not in scope here:** Kubernetes provisioning (proxmox repo, future),
  GitOps app deployment (platform-services repo, future), network
  configuration (network repo, future), application deployment (ArgoCD on
  cluster), backup orchestration (Velero in platform-services), observability
  (Grafana stack in observability repo, future), personal dotfiles
  (separate dotfiles repo).

If a request reaches into out-of-scope territory, push back per Scope 2's
scope discipline rules.

## Repo-specific validation order

When a change to a role, playbook, or script needs to be validated, run it
against hosts in this order. The order is intentional: each step has a
recoverable target before the next step's stakes go up.

1. **commander** for control-node-specific things (`bootstrap-control-node.sh`,
   `control-node.yml`, anything that touches the toolkit aliases).
2. **ai** for managed-host validation — a real host but not a hypervisor, so
   mistakes are recoverable.
3. **pve2** before pve1 — both are hypervisors, but pve2 is the "second" one
   and gets things first; pve1 follows once pve2 is proven.
4. Eventually parity: same configuration applied to all four hosts via
   `site.yml`.

Don't skip steps. Don't apply changes to pve1 without proving them on pve2
first.

## Repo-specific phase plan

This repo is in **Phase 0 — Bootstrap.** Items are sequenced in `CONTEXT.md`
§12. Don't jump ahead — each item validates against the previous one.

When a new role or playbook is added, append to the §12 sequence in
`CONTEXT.md` and propose an ADR if a meaningful decision was made.

## On end-of-session

- Confirm git state is clean or intentionally staged.
- Propose CONTEXT.md updates for significant work (especially §12 Current
  state).
- Draft an ADR for any decision that emerged.
- Push to Gitea (`git push`); verify the GitHub mirror fired by checking
  the Gitea repo's mirror status.
- Surface gotchas, workarounds, or non-obvious dependencies for future
  sessions.
- File a session summary in the kb at
  `~/Projects/scaffoldrack/kb/sessions/<YYYY-MM-DD>-<topic-slug>.md`,
  per the kb's session-summarize skill.
