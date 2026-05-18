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

This file holds **only what's specific to bootstrap**. Don't restate
Scope 1 or Scope 2 rules here. For the larger context and rationale,
read `CONTEXT.md`.

---

## Read these on every session

In addition to walking up the tree for Scope 1 and Scope 2 CLAUDE.md files,
on every session in this repo:

1. `CLAUDE.md` (this file) — repo-specific rules
2. `CONTEXT.md` — what this repo is, architectural decisions, current state
3. Any `decisions/` ADR relevant to your task
4. `git status` and `git log -5` to see current state and recent activity

If the user references "the script," "that role," "this playbook" — clarify which one before proceeding. Ambiguity in this repo costs time.

Verify which host you're working against. `commander` (control node, `ansible_connection: local`) and managed hosts (`ai`, `pve1`, `pve2`) have different operational models.

## Repo identity

This is the **bootstrap** repo. It holds:

- **One shell script** (`scripts/bootstrap-control-node.sh`) — installs Docker
  and builds/pulls the `devops-toolkit:latest` container image. Nothing else.
- **All Ansible automation** for managing the scaffoldrack platform —
  inventory, roles, playbooks. Includes the `control_node` role that
  configures the control node itself (zsh, toolkit aliases, completions),
  and the eventual `dev_environment` role that handles per-developer-machine
  state (umask, CLAUDE.md symlinks).

The shell script is the only thing that exists outside Ansible because there's
no way to use Ansible to set up the thing that runs Ansible. Once the script
finishes and the container image is available, Ansible takes over for
everything else.

This repo is the **originator** of two scaffoldrack-org-wide models documented
in Scope 2 (don't restate them here):

- **The runtime model** — `bootstrap-control-node.sh` builds the
  `devops-toolkit:latest` image; `roles/control_node/` deploys the zsh
  aliases that make it reachable.
- **The two-identity model** — `playbooks/bootstrap.yml` plus
  `roles/bootstrap_bob/` is what creates bob on each new managed host.

Other scaffoldrack repos consume these models as inputs; bootstrap creates them.

This repo's job ends at "host is configured, hardened, and ready for whatever comes next." Application deployment, Kubernetes provisioning, GitOps, and observability live elsewhere.

## Repo-specific hard rules

These specialize Scope 1 and Scope 2 rules for this repo's specific concerns.

### Idempotency is the bright-line requirement here

Scope 2 already states this; in this repo, every script and playbook gets
exercised on re-runs constantly during development. Re-runs detect existing
state and skip with a `warn` log. Never destructive, never failing on
second-or-later invocation.

When writing or modifying any script or playbook, the question to ask is:
*"If this runs twice in a row, does the second run produce 'WARN: already
done, skipping' messages and exit cleanly?"* If not, fix it before merging.

### `bootstrap-control-node.sh` is allowed to do exactly two things

Install Docker and build/pull the `devops-toolkit:latest` image. Anything
else (zsh setup, alias deployment, completion generation, oh-my-zsh
installation, toolkit configuration, etc.) belongs in `roles/control_node/`,
not in this script.

If a request would expand the script beyond Docker + container image, push
back and propose an Ansible role instead. The script is deliberately narrow
because everything beyond it can be Ansible-driven.

### `bootstrap.yml` MUST verify bob can sudo before disabling SSH password auth

This is the lockout-prevention discipline. The verification step is
non-optional. Any change to `bootstrap.yml` that weakens this verification
should be flagged loudly and require explicit confirmation.

When writing or modifying tasks that affect SSH or sudo configuration, be
acutely aware which identity is making the change and which identity will
be used for subsequent operations. Lockout is a real risk.

### `ansible_connection: local` for commander

commander is both control node *and* a managed host. To avoid the
2FA-on-external-SSH consideration, it manages itself locally. Don't change
this without considering the consequences for the 2FA posture.

### bob's private key handling

bob's private key lives at `~/.ssh/bob_ed25519` on the control node. Never
commit, never reference by content. bob's public key is `files/bob.pub`,
which IS committed.

If a task or script requires a secret or credential pattern that isn't
already covered above or in the Scope 2 token convention (`~/.blackwell`),
stop and ask. Don't invent a new secret-handling pattern.

## Ansible role conventions

### Role names describe the state the host acquires

Each role is named for what the host gains by running it:

- `control_node` — host becomes a control node (zsh, toolkit aliases, completions)
- `bootstrap_bob` — host gains bob (the automation identity)
- `baseline` — host gains baseline configuration (packages, time, hostname)
- `hardening` — host gains hardening (ssh, firewall, sysctl, fail2ban)
- `dev_environment` — host gains a developer environment (umask, CLAUDE.md symlinks, hooks config)
- `proxmox` — host gains Proxmox (Debian-to-PVE conversion)

The test for a new role name: *"Can I read 'the host gains <role name>' naturally?"* If yes, the name fits the pattern.

Names that don't fit:

- **Verbs describing actions** (`setup_control_node`, `configure_hardening`, `install_proxmox`) — the action is implicit in running a role; the name should describe the outcome.
- **Lifecycle numbering** (`00-baseline`, `10-hardening`) — ordering belongs in `site.yml`, not filenames. Numbering schemes run out of slots and turn into `15a-` workarounds.
- **Mixed concerns** (`network_and_dns`, `monitoring_stack`) — if a role's name uses "and," it's probably two roles.

Roles live in `roles/<name>/` with the standard Ansible layout:
`tasks/`, `handlers/`, `templates/`, `files/`, `defaults/`, `vars/`, `meta/`,
`README.md`.

### Working with roles

When creating a new role:

- Start with `tasks/main.yml` that includes other task files via
  `import_tasks` or `include_tasks`
- Use tags on each task file so `--tags <tag>` allows targeted re-runs
- Document in the role's `README.md`: purpose, variables, dependencies, tags
- Test with `--check --diff` against a known-good host before applying for real

When modifying an existing role:

- Read the existing `tasks/main.yml` and any included task files first
- Read the role's `README.md` for context
- Preserve existing tags and structure unless explicitly changing them

### Hardening is one role with task-file splits and tags

One `roles/hardening/` role that contains the full host hardening surface
(SSH, firewall, sysctl, fail2ban, etc.) split across multiple task files,
tagged so individual concerns can be re-applied via `--tags <tag>` without
re-running the whole role. This avoids both "one giant unmaintainable
playbook" and "ten micro-roles that have to be wired together."

## Playbook conventions

Playbooks compose roles. Keep them thin — most logic belongs in roles,
not playbooks.

- `playbooks/site.yml` — daily driver. Idempotent. Runs everything appropriate
  for each host group.
- `playbooks/bootstrap.yml` — one-time-per-host onboarding. Runs as `andrew`
  with `--ask-become-pass`. Creates `bob`, deploys hardening, validates,
  disables password auth.
- `playbooks/control-node.yml` — configures the control node itself. Run
  manually inside the container the first time; via the toolkit alias
  afterwards.
- `playbooks/ping.yml` — smoke test. Always runnable.

When adding a playbook, ask: *"Does this need to exist as its own playbook,
or is it a tag invocation of an existing playbook?"* Most narrow needs are
tag invocations.

## Validation order

When a change to a role, playbook, or script needs validation, run it against
hosts in this order. Each step has a recoverable target before the next
step's stakes go up.

1. **commander** — for control-node-specific things
   (`bootstrap-control-node.sh`, `control-node.yml`, anything that touches
   the toolkit aliases). commander is the easiest to recover.
2. **ai** — managed-host validation. A real host but not a hypervisor, so
   mistakes are recoverable.
3. **pve2** — first hypervisor. Validates Proxmox-bound work without
   touching pve1.
4. **pve1** — second hypervisor. Same configuration applied via `site.yml`.
   pve1 follows once pve2 is proven.

Don't skip steps. Don't apply changes to pve1 without proving them on pve2 first.

See `decisions/0004-validation-order.md` for the rationale.

## Toolkit container debugging

When debugging an Ansible run that's misbehaving:

- Check whether the alias is invoking the container correctly:
  `type ansible-playbook` should show the alias definition (not a binary path).
- Check whether the container can reach the target host:
  `docker run ... ssh bob@<host>` from inside the container.
- Check whether the container has the expected tools:
  `docker run --rm devops-toolkit:latest which ansible kubectl helm`.

The toolkit aliases file at `roles/control_node/files/scaffoldrack-toolkit.zsh`
is committed. If aliases need to change, change the committed file and
re-run the `control_node` role; don't edit the deployed file directly on
commander.

## Things NOT to do in this repo

- **Don't bypass the toolkit container** by running `apt install ansible` on
  the host. The container IS the runtime. If something doesn't work in the
  container, fix the container or the Ansible code, not by sidestepping it.
- **Don't disable error checking.** `set -euo pipefail` in shell scripts.
  `ignore_errors: yes` in Ansible only with explicit justification in a comment.
- **Don't add features beyond what was asked.** This repo's scope is
  "Ansible automation for managing the platform." Application-level concerns
  belong elsewhere.
- **Don't introduce new tools without discussion.** If a task seems to
  require a new Ansible collection, a new linter, a new dependency,
  pause and ask.
- **Don't commit secrets, ever.** Even values that "look fake." If a task
  wants a secret it doesn't already have access to, that's a design question.
  Stop and ask.

## On end-of-session in this repo

In addition to the Scope 1 universal end-of-session checklist:

- Confirm git state is clean or intentionally staged. Don't leave uncommitted
  changes undocumented.
- If significant work happened, propose CONTEXT.md updates to reflect current
  state of the repo. Section "Current state" is the most likely target.
- If a decision was made (e.g., "we're going to use X for Y"), draft an ADR
  in `decisions/` following the existing numbering. Don't bury decisions in
  commit messages.
- If something was discovered that future-Code-Claude or future-Andrew will
  need (a gotcha, a workaround, a non-obvious dependency), capture it.
  Either as a comment in the relevant file, an ADR, or a note Andrew can
  add to backlog.
- Push to gitea (`git push gitea main`); the GitHub mirror fires automatically.
- File a session summary in the kb at
  `~/Projects/scaffoldrack/kb/sessions/<YYYY-MM-DD>-<topic-slug>.md`,
  per the kb's `session-summarize` skill.
