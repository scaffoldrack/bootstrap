# ADR-001 — Automation User `bob` with NOPASSWD: ALL

**Status:** Accepted
**Date:** 2026-05-09 (decision made), 2026-05-10 (formalized as ADR)
**Decision-makers:** Andrew Krull, with chat-Claude as collaborator

## Context

Ansible automation needs a consistent identity to act as on every managed host: same username, same UID across hosts, same SSH key authentication, same sudo behavior. Without standardization, every playbook risks per-host special cases for "who am I running as" and "do I need a password to escalate."

The first identity on each host is the human-provisioned account (`andrew`) created during OS install with sudo (password required). That account is appropriate for the moment-of-bootstrap but inappropriate for ongoing automation: andrew has different passwords on different hosts (security hygiene), Andrew may be away from his keyboard when automation runs, and tying automation to a personal identity conflates two different concerns.

The platform also needs a clear separation: human-driven ops (where andrew makes decisions, types passwords, has visibility) vs. automation-driven ops (where Ansible runs unattended).

## Decision

A dedicated **automation user named `bob`** is created on every scaffoldrack-managed host. Properties:

- **Username:** `bob` (short, memorable, not a real person; Battletech-flavored consistency with the platform's lore-naming pattern, though `bob` is intentionally generic-seeming)
- **UID:** 990. High enough to avoid collision with any package-installed system user on Debian (which typically uses UIDs in the 100-999 range, with most system packages using 100-300). Below 1000 so bob is conventionally a "system user" rather than a regular human user account.
- **Authentication:** SSH key authentication only. Password authentication is disabled for bob.
- **Key type:** ed25519. One keypair per Andrew (i.e., per platform-operator), stored at `~/.ssh/bob_ed25519` on the control node. The public key is committed to this repo at `files/bob.pub`.
- **Sudo:** `NOPASSWD: ALL`. bob can execute any command as root without a password prompt.

The two-identity model is then:

- **andrew** — manual foothold for one-time bootstrap. Sudo with password. Used exactly once per host (the andrew-runs-`bootstrap.yml` step). Dormant for all subsequent ops.
- **bob** — automation identity. Created by `bootstrap.yml` running as andrew. Used for everything after bootstrap.

`bootstrap.yml` is the only playbook that runs as andrew. All other playbooks run as bob.

`bootstrap.yml` MUST verify bob can sudo (key auth works + NOPASSWD: ALL works) BEFORE disabling SSH password authentication. Lockout-prevention discipline is non-negotiable.

## Consequences

**Positive:**
- Consistent automation identity across all hosts. Playbooks don't need per-host conditionals about who they run as.
- bob's key is one credential to manage and rotate, not N credentials per host.
- Andrew's personal credentials don't have to be present on managed hosts after initial bootstrap. If Andrew's machine is ever compromised, andrew on managed hosts is dormant — only the andrew-on-control-node identity is live.
- Clear separation of concerns: andrew makes decisions, bob carries them out.
- Compatible with unattended automation (cron, systemd timers, eventual GitOps-driven ops).

**Negative:**
- **NOPASSWD: ALL is a significant trust statement.** Anyone with access to bob's private key can become root on any managed host without a password challenge. Mitigated by: bob's key is on the control node only, the control node is itself hardened, the key has a passphrase OR is protected by file perms (current: file perms only). Should be revisited if/when the control node is exposed to a broader attack surface.
- **NOPASSWD: ALL is wrong for FedRAMP and similar compliance regimes.** Andrew's day job has FedRAMP-relevant work; this homelab does not. The decision is fine for current scope and explicitly wrong for any context where compliance matters.
- One more identity to manage. Audit, rotation, key revocation are now things to think about.

**Neutral:**
- bob is a "system user" (UID < 1000) by convention, which means most desktop login managers will hide it from login screens. Fine for our purposes.

## Alternatives Considered

### Alternative 1: Use andrew for everything

Skip bob entirely. Configure andrew on all hosts with SSH key auth and NOPASSWD: ALL.

**Why not chosen:**
- Andrew's identity does double duty as both human and automation. Audit trails get messy.
- If Andrew's personal machine is compromised, andrew's footprint is everywhere.
- Andrew passwords differ per host (intentional security hygiene); reconciling that with NOPASSWD-on-some-hosts but not others is awkward.
- Conflates concerns: when something runs as "andrew," is it Andrew typing or is it Ansible?

### Alternative 2: andrew with sudo + password each time

Skip the automation user; use `--ask-become-pass` for every Ansible run. No NOPASSWD anywhere.

**Why not chosen:**
- Defeats unattended automation entirely. Andrew has to be present and typing passwords for every operation.
- Different andrew password per host means each playbook run involves multiple password prompts on multi-host operations.
- Doesn't scale even to a small fleet of hosts.

### Alternative 3: ansible user with member-of-sudo group, password sudo via vault

Create an `ansible` user, give it sudo via password, store the password in ansible-vault.

**Why not chosen:**
- Adds vault password management to every operation. The password-in-vault is just NOPASSWD with extra steps and a new dependency.
- `become_pass` in ansible-vault works but the vault password itself becomes the credential to manage; the "password" layer adds complexity without adding security in this threat model.
- May reconsider if the threat model changes (e.g., compliance requires audit-able sudo events with passwords).

### Alternative 4: SSH certificates via a CA, no per-host keys

Issue bob's access via SSH certificates from a CA. Rotation by cert reissue rather than file replacement.

**Why not chosen:**
- More machinery than this scope justifies. Cert-based SSH is the right answer at scale; at four hosts and one operator, it's overkill.
- Adds a dependency (the CA) that doesn't exist yet.
- May reconsider when Vault is online (Vault has SSH cert support) — and at that point, this ADR would get amended.

### Alternative 5: Different UID for bob

Use the conventional first-user UID (1000), or a much higher arbitrary UID (like 65000).

**Why not chosen:**
- 1000 collides with andrew on most fresh installs.
- 65000+ is fine but "looks weird" in process listings; 990 reads as "intentional system user" without screaming for attention.
- 990 was an arbitrary-but-defensible pick; the specific number isn't load-bearing.

## Trade-offs Accepted

**NOPASSWD: ALL is the main accepted trade-off.** Mitigations: bob's key is on the control node only, key file perms are 0600, the control node is itself hardened. The trade-off is consciously accepted for a single-operator homelab; explicitly wrong for compliance-scoped contexts. Document: "if scaffoldrack ever bridges into compliance-scoped work, this ADR retires immediately."

**One more identity to manage.** The cost of having bob is the cost of managing bob: rotating the key periodically, revoking it on compromise, etc. We accept this cost because the alternative (using andrew) couples human and automation in ways that get worse over time.

**bob's key has no passphrase.** The key file is unencrypted on disk; it's protected by file perms (0600 owner read/write only). Adding a passphrase would require either: (a) entering it for every Ansible run (defeats automation), (b) using ssh-agent (works but adds a state-keeping dependency), or (c) storing the passphrase elsewhere (which becomes the new credential to protect). For now we accept unencrypted key, file-perms protection. Revisit if Vault is online and can manage the passphrase, or if an SSH cert/CA model replaces this entirely.

## When This Is the Wrong Choice

This decision could be wrong in scenarios where:

- **Compliance requires audit-able sudo events.** FedRAMP, SOC 2, HIPAA, etc. all want to know "who did what" and password-less sudo undermines that. If scaffoldrack ever moves into compliance scope, NOPASSWD: ALL has to go and the model becomes either password-based sudo with vault-managed passwords or cert-based with detailed audit logging.
- **The control node becomes multi-user.** If multiple humans operate the platform from the same control node, bob's key becomes a shared credential. At that point per-operator keys (each operator has their own key authorized to act as bob) or per-operator automation users with their own NOPASSWD become better.
- **bob's key is compromised.** Recovery is non-trivial: rotate the key on the control node, propagate the new public key to every managed host, ensure the old key is revoked everywhere. This is a runbook waiting to be written. (Backlog: write `runbooks/rotate-bob-key.md` in the runbooks repo.)
- **Vault or similar secrets management is online.** Vault can issue dynamic SSH credentials, manage cert-based authentication, and track every access event. When Vault is real, this ADR likely becomes "see ADR-XXX for the Vault-managed bob model."

## Cross-references

- `playbooks/bootstrap.yml` — the playbook that creates bob (when written)
- `roles/bootstrap_bob/` — the role that owns bob's creation logic (when written)
- `files/bob.pub` — bob's public key (committed when keypair is generated)
- `kb/projects/scaffoldrack/CLAUDE.md` §2 — the Scope 2 statement of the two-identity model
- `kb/projects/scaffoldrack/CLAUDE.md` §3 — host inventory at the org level
- `decisions/004-validation-order.md` — the validation order for applying bootstrap to hosts
