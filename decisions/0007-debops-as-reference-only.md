---
status: accepted
date: 2026-05-17
decision-makers: Andrew Krull (with chat-Claude as collaborator)
---

# Use DebOps as Reference Only, Not as a Dependency

## Context and Problem Statement

DebOps (https://github.com/debops/debops) is a mature, opinionated Debian platform automation framework. It offers high-quality, battle-tested Ansible roles for the boring-but-essential hardening concerns the `roles/hardening/` and `roles/baseline/` work will eventually need: SSH config, sudo, firewall, unattended upgrades, auditd, kernel sysctl, console baseline, locale, NTP, and more.

The question for the bootstrap repo is whether to consume DebOps directly (as a dependency installed via `ansible-galaxy` or git submodule) or to use it as a reference and write our own roles.

DebOps is also not a *library* — it's a *system*. Its roles assume DebOps inventory structure, variable plumbing through `debops.all`, and (often) the `debops` CLI runner. Cherry-picking individual roles is technically possible but inherits coupling that fights the bootstrap repo's stated discipline: the 3am rule, explicit-over-clever, simplicity wins unless complexity meaningfully justifies itself.

The naive alternatives are equally unattractive: writing every hardening task from scratch with no reference is slow and produces a worse result than DebOps would, while adopting DebOps wholesale rewrites the bootstrap repo's structure to fit DebOps' conventions.

## Decision Drivers

* The 3am rule — roles must be readable enough to debug when tired
* Explicit-over-clever — the bootstrap repo's stated stance
* Speed vs. ownership trade-off — DebOps' depth is valuable; its coupling is costly
* Compatibility with the scope-discipline conventions in `bootstrap/CLAUDE.md`
* Future supersession — if the chosen approach is wrong, the cost of switching should be bounded
* Forkability — the bootstrap repo is mirrored to GitHub for public consumption; downstream forkers should be able to read the roles without learning a separate framework first

## Considered Options

* DebOps as reference only — write our own roles informed by DebOps' design
* Adopt DebOps wholesale — change the bootstrap repo to use DebOps' inventory layout and runner
* Cherry-pick DebOps roles via `requirements.yml` / `ansible-galaxy install`
* Vendor specific DebOps roles into `roles/external/` as git submodules
* Write roles entirely from scratch, no DebOps consultation

## Decision Outcome

Chosen option: **"DebOps as reference only — write our own roles informed by DebOps' design"**, because it captures DebOps' design value without inheriting its coupling, keeps the bootstrap repo legible to readers who haven't encountered DebOps before, and preserves the option of revisiting if the workload changes.

Specifically:

* When `roles/hardening/`, `roles/baseline/`, and related roles are written, the corresponding DebOps role is consulted as a design reference.
* The role's `README.md` notes which DebOps role(s) informed its design, in a "Design references" section. Pattern-level attribution is sufficient; no DebOps code is copied verbatim.
* The role's `tasks/` files are written in this repo's conventions (tagged task-file splits, `log`-style debug output where appropriate, idempotency-first task structure).
* DebOps is **never** added to `requirements.yml`, **never** added as a git submodule, and **never** assumed to be installed on commander.
* If a specific DebOps template or configuration snippet (e.g., a sshd_config template) is borrowed near-verbatim, it gets explicit attribution in the file and a copy of DebOps' license note is added near it.

### Consequences

* Good, because the bootstrap repo stays readable in its own conventions. A forker doesn't need to learn DebOps first.
* Good, because cross-cutting roles like `hardening` and `baseline` stay coherent — they don't compose with DebOps' variable plumbing or its `debops.all` super-role.
* Good, because each role's design rationale is anchored to DebOps where DebOps is the authority. Pattern attribution makes the design auditable.
* Good, because the cost of revisiting is bounded: if a future Andrew decides DebOps was the right call after all, switching is "adopt DebOps" not "untangle a hybrid."
* Bad, because more work upfront — we write the roles ourselves instead of installing them.
* Bad, because we may miss DebOps' edge-case handling. Mitigated by reading the DebOps role carefully when ours is being written.
* Bad, because we don't get DebOps' breadth-of-services "for free" (mail, LDAP, identity). Acceptable: those aren't in scope for bootstrap; when they are, we write our own or revisit.
* Neutral, because DebOps' license (GPLv3) doesn't bind us if we're consulting designs rather than copying code. Pattern-level inspiration isn't license-encumbered.

### Confirmation

When the first hardening or baseline role lands, this ADR is confirmed if:

* `bootstrap/requirements.yml` contains no DebOps reference.
* `bootstrap/roles/external/` doesn't exist, or exists with non-DebOps content only.
* `bootstrap/roles/hardening/README.md` contains a "Design references" section that names which DebOps role(s) informed the design, with one-line summaries.
* `bootstrap/roles/hardening/tasks/*.yml` are written in this repo's task-file-split + tag convention, not DebOps' role-defaults-template convention.

## Pros and Cons of the Options

### DebOps as reference only

* Good, because roles stay self-contained and readable.
* Good, because no runtime dependency on DebOps' machinery.
* Good, because forkers can read our roles without learning DebOps.
* Good, because supersession is straightforward: this ADR can be revisited if circumstances change.
* Bad, because more upfront work.
* Bad, because we may miss edge cases DebOps already handles.

### Adopt DebOps wholesale

* Good, because we get hardening + many other roles immediately, at high quality.
* Good, because DebOps has been operated in real environments for years.
* Bad, because the bootstrap repo's structure conforms to DebOps' rather than our own conventions.
* Bad, because the 3am-debuggability of our role tree drops — debugging requires understanding DebOps' variable flow, not just our task files.
* Bad, because forkers inherit a DebOps learning curve before they can read our work.
* Bad, because supersession is expensive — once DebOps' inventory layout and variable plumbing are embedded, replacing it is rewriting from scratch.

### Cherry-pick DebOps roles via `requirements.yml`

* Good, because gets specific high-value roles (e.g., `debops.sshd`, `debops.unattended_upgrades`) at marginal cost.
* Bad, because DebOps roles assume DebOps inventory and variable scaffolding. Cherry-picked roles work, but you spend time understanding *why* they work and what variables they expect.
* Bad, because the `requirements.yml` becomes a list of opaque third-party dependencies. The 3am rule fails: at 3am, the operator can't read our `roles/external/debops.sshd/` and reason about it without the DebOps documentation.
* Bad, because Galaxy version pinning is real maintenance burden. The role's behavior may change on a Galaxy refresh.
* Bad, because forkers get a `requirements.yml` they have to install before the repo works.

### Vendor specific DebOps roles into `roles/external/` as git submodules

* Good, because pins exact code at a specific commit (better than Galaxy version pinning).
* Bad, because git submodules add operational complexity (forgetting `git submodule update --init`, detached HEADs, sub-repo update workflows).
* Bad, because the same coupling problem as cherry-picking — DebOps roles need DebOps' variable scaffolding.
* Bad, because forkers inherit the submodule complexity.

### Write roles entirely from scratch, no DebOps consultation

* Good, because zero external coupling.
* Bad, because we throw away years of DebOps' production-tested hardening knowledge.
* Bad, because likely produces worse results, especially in subtle areas like sysctl tuning, sshd config nuances, and auditd rules where the right answers aren't obvious.
* Bad, because reinventing security baselines is exactly the kind of work the 3am rule warns against — high stakes, easy to get wrong, no learning compounded.

## More Information

### Status of this ADR relative to actual work

This ADR is written **before any hardening or baseline role exists**. It is forward-looking — capturing the stance toward DebOps while the reasoning is fresh, so that when the roles are implemented, the choice is already made.

The ADR is `accepted` rather than `proposed` because the reasoning held up under examination in the originating session. The future reader should scrutinize it when actually writing the first hardening tasks — if DebOps turns out to be more useful as a direct dependency than the reasoning here anticipates, supersede this ADR with a new one.

### Specific DebOps roles likely to inform our work

When the relevant tasks are written, these DebOps roles are the consultation candidates (not commitments — the actual list depends on what we end up needing):

| Our task                       | DebOps role likely to inform     | What we'd consult                                                              |
|--------------------------------|----------------------------------|--------------------------------------------------------------------------------|
| `hardening/tasks/sshd.yml`     | `debops.sshd`                    | sshd_config template shape; `Match User` blocks; `AllowUsers` discipline       |
| `hardening/tasks/auth.yml`     | `debops.auth`                    | Admin vs service user separation pattern                                       |
| `hardening/tasks/sysctl.yml`   | `debops.sysctl`                  | Kernel hardening parameter defaults                                            |
| `hardening/tasks/apt.yml`      | `debops.unattended_upgrades`     | `50unattended-upgrades` template; reboot policy                                |
| `baseline/tasks/console.yml`   | `debops.console`                 | `/etc/profile`, `/etc/inputrc`, bashrc baseline                                |

We do **not** plan to consult `debops.ferm` because we've chosen nftables (see ADR-0006). The DebOps firewall story is ferm-based and not directly applicable.

### Trade-offs explicitly accepted

* **More work upfront.** We write more code ourselves. Mitigated by consulting DebOps designs and being explicit about which patterns we're borrowing.
* **Risk of missing edge cases DebOps already handles.** Mitigated by reading the consulted DebOps role carefully — not just its `tasks/main.yml` but its `defaults/main.yml` and its `README.md` — when writing ours.
* **No DebOps breadth-of-services.** Mail, LDAP, identity, monitoring agents — DebOps has roles for these we won't get for free. Acceptable: none are in current scope. When they are, we either write our own at that time or revisit this ADR for the specific case.

### When this is the wrong choice

* **If the platform scope grows to many DebOps-covered services.** If a year from now bootstrap is also doing mail, LDAP, identity, and monitoring agents, the cumulative cost of writing each role ourselves may exceed the cost of adopting DebOps wholesale. Revisit when that scope expansion is real, not anticipated.
* **If multi-operator workflow surfaces and others know DebOps.** DebOps is a real ecosystem with real users. If the bootstrap repo gets contributors who are already DebOps-fluent, adoption becomes more attractive.
* **If a specific DebOps role offers something genuinely hard to replicate.** Some DebOps roles do unusually sophisticated work (LDAP integration, mail stack composition). Cherry-picking one *specific* role for *specific* reasons would be a deviation from this ADR and warrant either an amendment or a superseding ADR for that case.

### Cross-references

* `decisions/0006-nftables-for-host-firewall.md` — sibling ADR from the same session, governing firewall tooling. The two ADRs together set the shape of `roles/hardening/`.
* DebOps project: https://github.com/debops/debops
* DebOps role index: https://docs.debops.org/en/master/ansible/roles/index.html
* `bootstrap/CLAUDE.md` § Repo-specific hard rules — the 3am rule and explicit-over-clever principles this ADR operationalizes
* `bootstrap/CONTEXT.md` §7 Phase 5 — the eventual hardening role this ADR governs
