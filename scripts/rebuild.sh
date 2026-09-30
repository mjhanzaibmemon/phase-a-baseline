#!/usr/bin/env bash
# The whole claim in one command: destroy it, build it again from source, converge
# it twice, prove it, and write the evidence down.
#
# Nothing here should ever prompt for anything. If it does, there is a manual step
# hiding in the process and the run has failed on its own terms.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE="$ROOT/evidence"
mkdir -p "$EVIDENCE"

export ANSIBLE_FORCE_COLOR=0
STARTED=$(date -u --iso-8601=seconds)

# init comes first. On a fresh clone the modules and providers are not installed
# yet, so a destroy would fail before it ever reached the apply. Someone rebuilding
# this from nothing hits that on their first run, which is the run that matters.
echo "=== init ===" | tee "$EVIDENCE/rebuild.log"
(cd "$ROOT/tofu" && tofu init -input=false) 2>&1 | tee -a "$EVIDENCE/rebuild.log"

echo "=== destroy ===" | tee "$EVIDENCE/destroy.log"
(cd "$ROOT/tofu" && tofu destroy -auto-approve) 2>&1 | tee -a "$EVIDENCE/destroy.log"

# The tailnet address of a machine that no longer exists is worse than no address:
# the next converge would sit there knocking on a dead host until it timed out.
# The tailscale role writes this again as soon as the new node joins.
rm -f "$ROOT/ansible/inventory/host_vars"/*.yml
echo "cleared stale host_vars from the destroyed host" | tee -a "$EVIDENCE/destroy.log"

echo "=== apply ===" | tee -a "$EVIDENCE/rebuild.log"
(cd "$ROOT/tofu" && tofu apply -auto-approve -input=false) 2>&1 |
  tee -a "$EVIDENCE/rebuild.log"

echo "=== wait for ssh ===" | tee -a "$EVIDENCE/rebuild.log"
# OpenTofu writes this file with quoted keys, so match "ansible_host": "1.2.3.4"
# as well as the bare form. Parsing it the naive way silently yields an empty host
# and the wait loop then burns its full timeout against nothing.
HOST=$(sed -nE 's/.*"?ansible_host"?: *"?([^"[:space:]]+)"?.*/\1/p' \
  "$ROOT/ansible/inventory/hosts.yml" | head -1)
for i in $(seq 1 60); do
  if nc -z -w3 "$HOST" 22 2>/dev/null; then
    echo "ssh answered after about $((i * 10))s" | tee -a "$EVIDENCE/rebuild.log"
    break
  fi
  sleep 10
done

echo "=== converge ===" | tee -a "$EVIDENCE/rebuild.log"
(cd "$ROOT/ansible" && ansible-playbook site.yml) 2>&1 | tee -a "$EVIDENCE/rebuild.log"

echo "=== idempotence ===" | tee "$EVIDENCE/idempotence.log"
(cd "$ROOT/ansible" && ansible-playbook site.yml) 2>&1 | tee -a "$EVIDENCE/idempotence.log"

CHANGED=$(grep -Eo 'changed=[0-9]+' "$EVIDENCE/idempotence.log" | tail -1 | cut -d= -f2)
if [[ "${CHANGED:-1}" -ne 0 ]]; then
  echo "A2 failed: the second run reported changed=${CHANGED:-unknown}, it has to be 0" |
    tee -a "$EVIDENCE/idempotence.log"
  exit 1
fi
echo "A2 passed: the second run changed nothing" | tee -a "$EVIDENCE/idempotence.log"

# A freshly built box has never run the backup timer, so the health check is right
# to complain that a backup has never happened. The acceptance criteria ask for a
# completed backup and a verified restore, not for a timer that will fire tomorrow.
echo "=== first backup ===" | tee "$EVIDENCE/first-backup.log"
(cd "$ROOT/ansible" && ansible all -b -m ansible.builtin.systemd_service \
  -a "name=restic-backup.service state=started") 2>&1 | tee -a "$EVIDENCE/first-backup.log"

echo "=== acceptance ==="
"$ROOT/tests/acceptance.sh" | tee "$EVIDENCE/acceptance.txt"

{
  echo "run_started=$STARTED"
  echo "run_finished=$(date -u --iso-8601=seconds)"
  echo "tofu_version=$(tofu version | head -1)"
  echo "ansible_version=$(ansible --version | head -1)"
} > "$EVIDENCE/run-metadata.txt"

echo
echo "Done. Evidence is in $EVIDENCE"
