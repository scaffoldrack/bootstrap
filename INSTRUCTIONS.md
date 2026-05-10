# INSTRUCTIONS.md — bootstrap

**Audience:** Code-Claude operating in this repo.

**Purpose:** Operational rules for working in the bootstrap repo. Read CONTEXT.md first for what the repo is and why; this file is for *how to work* in it.

---

## On every session

1. Read `CONTEXT.md` first. Then this file. Then any relevant `decisions/` files for the area you're working in.
2. Check `git status` and `git log -5` to see current state and recent activity.
3. If the user references "the script," "that role," "this playbook" — clarify which one before proceeding. Ambiguity in this repo costs time.
4. Verify which host you're working against. `commander` (control node, ansible_connection=local) and managed hosts (`ai`, `pve1`, `pve2`) have different operational models.

## On idempotency

Every script and playbook in this repo MUST be idempotent. Definition: re-running produces no error and no destructive change. Specifically:

- Detect existing state before making changes
- Skip with a `warn` log when nothing to do
- Never delete or recreate where update would suffice
- Validation steps (e.g., "bob can sudo") must succeed before destructive steps (e.g., "disable SSH password auth") are reached

When writing or modifying scripts, the question to ask is: "If this runs twice in a row, does the second run produce 'WARN: already done, skipping' messages and exit cleanly?" If not, fix the script.

## On scripts in this repo

There is exactly one shell script: `scripts/bootstrap-control-node.sh`. It:

- Installs Docker
- Builds or pulls the `devops-toolkit:latest` container image
- Does NOT install Ansible, zsh, or any other tool on the host
- Does NOT configure shell environments or aliases

Anything beyond Docker + container image belongs in an Ansible role, not in this script. If a request would expand the script's scope, push back and propose a role instead.

The script uses color-coded helpers: `log()` (green INFO), `warn()` (yellow WARN), `die()` (red ERR, exits non-zero). Use these consistently. Do not use heredocs; use external configuration files when needed.

## On Ansible roles

Roles live in `roles/<name>/` with the standard Ansible layout: `tasks/`, `handlers/`, `templates/`, `files/`, `defaults/`, `vars/`, `meta/`, `README.md`.

When creating a new role:

- Start with `tasks/main.yml` that includes other task files via `import_tasks` or `include_tasks`
- Use tags on each task file so `--tags <tag>` allows targeted re-runs
- Document in the role's `README.md`: purpose, variables, dependencies, tags
- Test with `--check --diff` against a known-good host before applying for real

When modifying an existing role:

- Read the existing `tasks/main.yml` and any included task files first
- Read the role's `README.md` for context
- Preserve existing tags and structure unless explicitly changing them

## On playbooks

Playbooks compose roles. Keep them thin — most logic belongs in roles, not playbooks.

- `playbooks/site.yml` is the daily driver. Idempotent. Runs everything appropriate for each host group.
- `playbooks/bootstrap.yml` is the one-time-per-host onboarding playbook. Runs as andrew with `--ask-become-pass`.
- `playbooks/control-node.yml` configures the control node itself. Run manually inside the container the first time, via alias afterwards.
- `playbooks/ping.yml` is the smoke test. Always runnable.

When adding a playbook, ask: "Does this need to exist as its own playbook, or is it a tag invocation of an existing playbook?" Most narrow needs are tag invocations.

## On the two-identity model

Every managed host has two identities (see CONTEXT.md §4):

- **andrew** — manual foothold, used once for bootstrap, NOPASSWD: NO
- **bob** — automation identity, used forever after, NOPASSWD: ALL

In playbooks:

- `playbooks/bootstrap.yml` runs with `ansible_user: andrew` and `--ask-become-pass`
- All other playbooks run with `ansible_user: bob` and key auth (no password)
- commander uses `ansible_connection: local` and ignores both

When writing tasks that affect SSH or sudo configuration, be acutely aware which identity is making the change and which identity will be used for subsequent operations. Lockout is a real risk.

## On secrets

- bob's private key lives at `~/.ssh/bob_ed25519` on the control node. Never commit, never reference by content.
- bob's public key is `files/bob.pub`. Committed.
- Tokens (Gitea, GitHub) come from `~/.blackwell` on the control node. Source it; never hardcode.
- ansible-vault is not in use yet. When it lands, vault password handling will be designed deliberately. Don't pre-empt that decision.

If a task or script requires a secret that isn't already covered above, stop and ask. Don't invent a secret-handling pattern.

## On the toolkit container

All `ansible*`, `kubectl`, `helm`, `vault`, etc. commands run inside the `devops-toolkit:latest` container, invoked via zsh aliases set up by `roles/control_node/`. The aliases mount the current directory and `~/.ssh` (for bob's key) into the container.

When debugging an Ansible run that's misbehaving:

- Check whether the alias is invoking the container correctly: `type ansible-playbook` should show the alias definition
- Check whether the container can reach the target host: `docker run ... ssh bob@<host>` from inside the container
- Check whether the container has the expected tools: `docker run --rm devops-toolkit:latest which ansible kubectl helm`

The toolkit aliases file at `roles/control_node/files/scaffoldrack-toolkit.zsh` is committed. If aliases need to change, change the committed file and re-run the control_node role; don't edit the deployed file directly on commander.

## On end-of-session

When wrapping a session:

1. Confirm git state is clean or intentionally staged. Don't leave uncommitted changes undocumented.
2. If significant work happened, propose CONTEXT.md updates to reflect current state of the repo. Section 12 (Current state) is the most likely target.
3. If a decision was made (e.g., "we're going to use X for Y"), draft an ADR in `decisions/` following the existing numbering. Don't bury decisions in commit messages.
4. If something was discovered that future-Code-Claude or future-Andrew will need (a gotcha, a workaround, a non-obvious dependency), capture it. Either as a comment in the relevant file, an ADR, or a note Andrew can add to backlog.
5. Push to gitea (`git push gitea main`). Verify the push mirror to GitHub fired (check Gitea repo settings → Mirror Settings → Last update timestamp).

## On things NOT to do

- **Don't reconstruct files from memory or assumption.** Always read the file first before editing. This is a hard rule across the project.
- **Don't add features beyond what was asked.** This repo's scope is "Ansible automation for managing the platform." Application-level concerns belong elsewhere.
- **Don't write comments that just narrate what the code does.** Comments should explain *why*, not *what*.
- **Don't introduce new tools without discussion.** If a task seems to require a new tool (a new linter, a new dependency, a new Ansible collection), pause and ask.
- **Don't disable error checking.** `set -euo pipefail` in shell scripts. `ignore_errors: yes` in Ansible only with explicit justification in a comment.
- **Don't bypass the toolkit container** by running `apt install ansible` on the host. The container IS the runtime. If something doesn't work in the container, fix the container or the Ansible code, not by sidestepping it.

## On asking the user

When uncertain:

- If it's about repo conventions: re-read CONTEXT.md
- If it's about a specific decision rationale: check `decisions/`
- If it's about scope: ask. Don't guess.
- If multiple valid implementations exist: present the options briefly, ask which to pursue. Don't sprawl into all of them in parallel.

The user values explicit-over-clever and the 3am rule. When proposing solutions, lead with the simpler version. Complexity must justify itself.
