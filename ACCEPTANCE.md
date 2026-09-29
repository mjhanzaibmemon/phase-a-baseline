# Acceptance matrix

Each condition maps to a check in `tests/acceptance.sh` and the evidence it writes into `evidence/`.
A condition is not met because the code looks right. It is met because the check passes on a machine
that was destroyed and rebuilt from this repository.

| ID | Condition | How it is proven | Evidence |
|----|-----------|------------------|----------|
| A1 | Fresh deploy succeeds from a clean VPS using only this repo and README | `scripts/rebuild.sh` runs destroy, apply, converge with no manual steps | `rebuild.log` |
| A2 | Second Ansible run is idempotent | Playbook re-run, recap parsed, fails if `changed` is not 0 | `idempotence.log` |
| A3 | Hardening checks pass | sshd drop-in asserted: no root login, no password auth, MaxAuthTries | `sshd.txt` |
| A4a | No unexpected users | `/etc/passwd` compared against the allowlist in `tests/expected-users.txt` | `users.txt` |
| A4b | No unexpected SSH keys | every `authorized_keys` on the box hashed and listed | `ssh-keys.txt` |
| A4c | No unexpected listeners | `ss -tulpn` compared against the allowlist in `tests/expected-listeners.txt` | `listeners.txt` |
| A5 | Service health checks pass | health timer ran, stamp file fresh, dead man's switch reported OK | `health.txt` |
| A6 | Backup completes | restic snapshot exists and is newer than the configured age limit | `backup.txt` |
| A7 | Restore completes | latest snapshot restored to scratch, canary file checksum matches | `restore.txt` |
| A8 | The VPS can be destroyed completely | `tofu destroy` leaves no resources in state or at the provider | `destroy.log` |
| A9 | The environment can be recreated from source | second full cycle produces the same passing evidence | `rebuild.log` |
| A10 | Independent security review passes | intentionally not self-certified, see note below | n/a |
| A11 | Documentation matches the deployment process | README commands are the ones `rebuild.sh` runs, nothing extra | `rebuild.log` |
| A12 | No undocumented manual configuration | rebuild runs unattended, any prompt is a failure | `rebuild.log` |

## A10

The person who builds a system should not be the person who signs off that it is safe.
This repo produces the evidence an independent reviewer needs. It does not claim to be that review.

## Running the checks

    ./tests/acceptance.sh              # against the host in ansible/inventory/hosts.yml
    ./scripts/rebuild.sh               # full cycle, writes every file listed above

Exit code is non-zero if any condition fails, so this drops into CI unchanged.
