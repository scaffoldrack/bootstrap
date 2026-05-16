---
status: accepted
date: 2026-05-09
decision-makers: Andrew Krull (with chat-Claude as collaborator)
---

# Use a Dedicated Automation User `bob` with `NOPASSWD: ALL`

## Context and Problem Statement

Ansible automation needs a consistent identity to act as on every managed host: same username, same UID, same SSH key authentication, same sudo behavior. Without standardization, every playbook risks per-host special cases for "who am I running as" and "do I need a password to escalate."

The first identity on each host is the human-provisioned account (`andrew`) created during OS install with sudo (password required). That account is appropriate for the moment-of-bootstrap but inappropriate for ongoing automation: andrew has different passwords on different hosts (security hygiene), Andrew may be away from his keyboard when automation runs, and tying automation to a personal identity conflates two different concerns.

The platform also needs a clear separation: human-driven ops (where andrew makes decisions, types passwords, has visibility) vs. automation-driven ops (where Ansible runs unattended).

## Decision Drivers

* Consistent automation identity across all managed hosts
* Support unattended automation (no human-typed password per operation)
* Separation between human operator identity and automation identity
* Single credential to manage and rotate, rather than N per-host credentials
* No coupling between andrew's personal credentials and managed hosts after bootstrap

## Considered Options

* Dedicated `bob` user with NOPASSWD: ALL sudo and ed25519 key auth (UID 990)
* Use andrew for everything (skip the automation user)
* Use andrew with `--ask-become-pass` for every Ansible run
* `ansible` user with password-based sudo via ansible-vault
* SSH certificates via a CA, no per-host keys
* Same as the chosen option but with a different UID (1000 or 65000+)

## Decision Outcome

Chosen option: **"Dedicated `bob` user with NOPASSWD: ALL sudo and ed25519 key auth (UID 990)"**, because it cleanly separates human and automation identities, supports unattended automation, and produces a single credential to manage. The NOPASSWD trade-off is consciously accepted for a single-operator homelab and explicitly wrong for compliance-scoped work.

Properties of `bob`:

* **Username:** `bob` — short, memorable, not a real person; Battletech-flavored consistency with the platform's lore-naming pattern, though `bob` is intentionally generic-seeming.
* **UID:** 990. High enough to avoid collision with package-installed system users on Debian, low enough to be conventionally a system user (UID < 1000) rather than a regular human account.
* **Authentication:** SSH key authentication only. Password authentication disabled for bob.
* **Key type:** ed25519. One keypair per platform-operator, stored at `~/.ssh/bob_ed25519` on the control node. Public key committed to this repo at `files/bob.pub`.
* **Sudo:** `NOPASSWD: ALL`. bob can execute any command as root without a password prompt.

The resulting two-identity model:

* **andrew** — manual foothold for one-time bootstrap. Sudo with password. Used exactly once per host (the andrew-runs-`bootstrap.yml` step). Dormant for all subsequent ops.
* **bob** — automation identity. Created by `bootstrap.yml` running as andrew. Used for everything after bootstrap.

`bootstrap.yml` is the only playbook that runs as andrew. All other playbooks run as bob.

`bootstrap.yml` MUST verify bob can sudo (key auth works + NOPASSWD: ALL works) BEFORE disabling SSH password authentication. Lockout-prevention discipline is non-negotiable.

### Consequences

* Good, because automation playbooks don't need per-host conditionals about who they run as.
* Good, because bob's key is one credential to manage and rotate, not N credentials per host.
* Good, because andrew's personal credentials don't have to be present on managed hosts after initial bootstrap; if Andrew's machine is compromised, andrew on managed hosts is dormant.
* Good, because clear separation of concerns: andrew makes decisions, bob carries them out.
* Good, because compatible with unattended automation (cron, systemd timers, eventual GitOps-driven ops).
* Bad, because NOPASSWD: ALL is a significant trust statement — anyone with bob's private key can become root on any managed host without password challenge. Mitigated by: key on control node only, control node hardened, file perms 0600.
* Bad, because NOPASSWD: ALL is wrong for FedRAMP and similar compliance regimes. Fine for current scope; explicitly wrong for any context where compliance matters.
* Bad, because one more identity to audit, rotate, and revoke.
* Neutral, because bob is a "system user" (UID < 1000) by convention, so most desktop login managers hide it from login screens — which is fine for this purpose.

### Confirmation

`bootstrap.yml` verifies bob can sudo via key auth before disabling SSH password auth. Smoke test: `ansible <host> -m ping -u bob` succeeds without password prompt after bootstrap completes.

## Pros and Cons of the Options

### Dedicated `bob` user with NOPASSWD: ALL sudo and ed25519 key auth (UID 990)

* Good, because clean separation of human and automation identities.
* Good, because unattended automation works without password prompts.
* Good, because one credential to manage across all hosts.
* Bad, because NOPASSWD: ALL is the main accepted security trade-off.
* Bad, because requires lockout-prevention discipline in bootstrap.yml (verify bob can sudo before disabling password auth).

### Use andrew for everything

Skip bob entirely. Configure andrew on all hosts with SSH key auth and NOPASSWD: ALL.

* Bad, because andrew's identity does double duty as both human and automation; audit trails get messy.
* Bad, because if Andrew's personal machine is compromised, andrew's footprint is everywhere.
* Bad, because andrew passwords differ per host (intentional security hygiene); reconciling that with NOPASSWD on some hosts but not others is awkward.
* Bad, because conflates concerns: when something runs as "andrew," is it Andrew typing or is it Ansible?

### Use andrew with `--ask-become-pass` for every Ansible run

* Bad, because defeats unattended automation entirely. Andrew has to be present and typing passwords for every operation.
* Bad, because different andrew password per host means multiple password prompts on multi-host operations.
* Bad, because doesn't scale even to a small fleet of hosts.

### `ansible` user with password-based sudo via ansible-vault

* Bad, because the password-in-vault is just NOPASSWD with extra steps and a new dependency.
* Bad, because `become_pass` via ansible-vault works but the vault password itself becomes the credential to manage; the "password" layer adds complexity without adding security in this threat model.
* Neutral, because may reconsider if the threat model changes (e.g., compliance requires audit-able sudo events with passwords).

### SSH certificates via a CA, no per-host keys

Issue bob's access via SSH certificates from a CA. Rotation by cert reissue rather than file replacement.

* Good, because at scale, cert-based SSH is the right answer.
* Bad, because more machinery than current scope justifies (four hosts, one operator).
* Bad, because adds a dependency (the CA) that doesn't exist yet.
* Neutral, because may reconsider when Vault is online — Vault has SSH cert support — at which point this ADR would get amended.

### Same as the chosen option but with a different UID (1000 or 65000+)

* Bad, because 1000 collides with andrew on most fresh installs.
* Neutral, because 65000+ is fine but "looks weird" in process listings; 990 reads as "intentional system user" without screaming for attention.
* Neutral, because 990 was an arbitrary-but-defensible pick; the specific number isn't load-bearing.

## More Information

### Trade-offs explicitly accepted

* **NOPASSWD: ALL is the main accepted trade-off.** Mitigations: bob's key is on the control node only, key file perms are 0600, the control node is itself hardened. Consciously accepted for a single-operator homelab; explicitly wrong for compliance-scoped contexts. If scaffoldrack ever bridges into compliance-scoped work, this ADR retires immediately.
* **One more identity to manage.** Rotating the key periodically, revoking on compromise, etc. Accepted because the alternative (using andrew) couples human and automation in ways that get worse over time.
* **bob's key has no passphrase.** The key file is unencrypted on disk; protected by file perms (0600 owner read/write only). Adding a passphrase would require either entering it for every Ansible run (defeats automation), using ssh-agent (adds state-keeping dependency), or storing the passphrase elsewhere (which becomes the new credential to protect). Accept unencrypted key with file-perms protection for now. Revisit if Vault is online and can manage the passphrase, or if an SSH cert/CA model replaces this entirely.

### When this is the wrong choice

This decision could be wrong in scenarios where:

* **Compliance requires audit-able sudo events.** FedRAMP, SOC 2, HIPAA, etc. all want to know "who did what" and password-less sudo undermines that. If scaffoldrack ever moves into compliance scope, NOPASSWD: ALL has to go and the model becomes either password-based sudo with vault-managed passwords or cert-based with detailed audit logging.
* **The control node becomes multi-user.** If multiple humans operate the platform from the same control node, bob's key becomes a shared credential. At that point per-operator keys (each authorized to act as bob) or per-operator automation users with their own NOPASSWD become better.
* **bob's key is compromised.** Recovery is non-trivial: rotate the key on the control node, propagate the new public key to every managed host, ensure the old key is revoked everywhere. This is a runbook waiting to be written. (Backlog: write `runbooks/rotate-bob-key.md` in the runbooks repo.)
* **Vault or similar secrets management is online.** Vault can issue dynamic SSH credentials, manage cert-based authentication, and track every access event. When Vault is real, this ADR likely becomes "see ADR-XXX for the Vault-managed bob model."

### Cross-references

* `playbooks/bootstrap.yml` — the playbook that creates bob (when written)
* `roles/bootstrap_bob/` — the role that owns bob's creation logic (when written)
* `files/bob.pub` — bob's public key (committed)
* `kb/projects/scaffoldrack/CLAUDE.md` §2 — the Scope 2 statement of the two-identity model
* `kb/projects/scaffoldrack/CLAUDE.md` §3 — host inventory at the org level
* `decisions/0004-validation-order.md` — validation order for applying bootstrap to hosts
