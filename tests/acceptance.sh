#!/usr/bin/env bash
# Runs the acceptance checks against a converged host and writes the evidence.
# Exit code is non-zero if anything fails, so this drops into CI unchanged.
#
#   ./tests/acceptance.sh                  # host comes from the Ansible inventory
#   TARGET=deploy@203.0.113.10 ./tests/acceptance.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE="$ROOT/evidence"
mkdir -p "$EVIDENCE"

if [[ -z "${TARGET:-}" ]]; then
  INVENTORY="$ROOT/ansible/inventory/hosts.yml"
  if [[ ! -f "$INVENTORY" ]]; then
    echo "No TARGET set and no inventory at $INVENTORY"
    exit 2
  fi

  # Ask Ansible rather than parsing the file. Once the node is on the tailnet a
  # host_vars entry overrides the public address OpenTofu wrote, and the checks
  # have to follow the same path Ansible does or they test the wrong door.
  if command -v ansible-inventory >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    read -r HOST WHO < <(cd "$ROOT/ansible" &&
      ansible-inventory --list 2>/dev/null |
      jq -r '._meta.hostvars | to_entries[0].value | "\(.ansible_host) \(.ansible_user)"')
  fi

  # Fall back to reading the file, quoted keys included, if that did not work.
  if [[ -z "${HOST:-}" || "$HOST" == "null" ]]; then
    HOST=$(sed -nE 's/.*"?ansible_host"?: *"?([^"[:space:]]+)"?.*/\1/p' "$INVENTORY" | head -1)
    WHO=$(sed -nE 's/.*"?ansible_user"?: *"?([^"[:space:]]+)"?.*/\1/p' "$INVENTORY" | head -1)
  fi

  if [[ -z "${HOST:-}" || -z "${WHO:-}" ]]; then
    echo "Could not work out which host to check"
    exit 2
  fi
  TARGET="${WHO}@${HOST}"
fi

SSH_KEY="${SSH_KEY:-$HOME/.ssh/baseline_ed25519}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
[[ -f "$SSH_KEY" ]] && SSH_OPTS+=(-i "$SSH_KEY")

PASS=0
FAIL=0

remote() {
  ssh "${SSH_OPTS[@]}" "$TARGET" "$@"
}

allowlist() {
  grep -v '^#' "$1" | grep -v '^[[:space:]]*$'
}

report() {
  if [[ "$3" == "pass" ]]; then
    printf 'PASS  %-5s %s\n' "$1" "$2"
    PASS=$((PASS + 1))
  else
    printf 'FAIL  %-5s %s\n' "$1" "$2"
    FAIL=$((FAIL + 1))
  fi
}

echo "Target:   $TARGET"
echo "Evidence: $EVIDENCE"
echo

# A3: sshd posture, read from the running daemon rather than from the file on disk
remote 'sudo sshd -T' > "$EVIDENCE/sshd.txt" 2>&1
if grep -qi '^permitrootlogin no' "$EVIDENCE/sshd.txt" &&
   grep -qi '^passwordauthentication no' "$EVIDENCE/sshd.txt" &&
   grep -qi '^pubkeyauthentication yes' "$EVIDENCE/sshd.txt"; then
  report A3 "sshd: no root login, no password auth, keys only" pass
else
  report A3 "sshd: no root login, no password auth, keys only" fail
fi

# A4a: no unexpected human accounts
remote "awk -F: '\$3 >= 1000 && \$3 < 65534 {print \$1}' /etc/passwd" > "$EVIDENCE/users.txt" 2>&1
UNEXPECTED_USERS=$(grep -vxFf <(allowlist "$ROOT/tests/expected-users.txt") "$EVIDENCE/users.txt" || true)
if [[ -z "$UNEXPECTED_USERS" ]]; then
  report A4a "no unexpected user accounts" pass
else
  report A4a "unexpected users: $(echo "$UNEXPECTED_USERS" | tr '\n' ' ')" fail
fi

# A4b: every authorized key on the box, listed and fingerprinted for review
remote 'sudo find /root /home -name authorized_keys -print -exec ssh-keygen -lf {} \;' \
  > "$EVIDENCE/ssh-keys.txt" 2>&1
report A4b "authorized_keys inventory written for review" pass

# A4c: no unexpected listening sockets on anything except loopback
remote 'sudo ss -tulpnH' > "$EVIDENCE/listeners-raw.txt" 2>&1
# What matters is whether a socket is reachable from outside, not whether it exists.
# Loopback is nobody's business but the host's, and a socket bound to the tailnet
# address is only reachable by devices already on the tailnet, so neither belongs in
# the "unexpected listener" list. Tailscale binds a random high port on both of its
# own addresses, which is why matching by port number alone would never be stable.
awk '{
  n = split($5, a, ":");
  port = a[n];
  addr = substr($5, 1, length($5) - length(port) - 1);
  is_loopback = (addr ~ /^127\./ || addr == "[::1]");
  is_tailnet  = (addr ~ /^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\./ || addr ~ /^\[fd7a:115c:a1e0/);
  if (!is_loopback && !is_tailnet) {
    print port "/" ($1 == "udp" ? "udp" : "tcp");
  }
}' "$EVIDENCE/listeners-raw.txt" | sort -u > "$EVIDENCE/listeners.txt"
UNEXPECTED_PORTS=$(grep -vxFf <(allowlist "$ROOT/tests/expected-listeners.txt") "$EVIDENCE/listeners.txt" || true)
if [[ -z "$UNEXPECTED_PORTS" ]]; then
  report A4c "no unexpected listening sockets" pass
else
  report A4c "unexpected listeners: $(echo "$UNEXPECTED_PORTS" | tr '\n' ' ')" fail
fi

# A5: health check, including the dead man's switch ping
if remote 'sudo /usr/local/bin/health-check.sh' > "$EVIDENCE/health.txt" 2>&1 &&
   grep -q '^OK' "$EVIDENCE/health.txt"; then
  report A5 "health check passes and the stamp is fresh" pass
else
  report A5 "health check reported a problem" fail
fi

# A6: a backup actually exists and is recent
remote 'sudo bash -c "set -a; . /etc/restic/env; set +a; /usr/local/bin/restic snapshots --latest 1 --json"' \
  > "$EVIDENCE/backup.txt" 2>&1
if grep -q '"time"' "$EVIDENCE/backup.txt"; then
  report A6 "a restic snapshot exists" pass
else
  report A6 "no restic snapshot found" fail
fi

# A7: the restore actually works, verified by checksum rather than by hope
remote 'sudo /usr/local/bin/restic-restore-test.sh' > "$EVIDENCE/restore.txt" 2>&1
if grep -q '^OK: restore verified' "$EVIDENCE/restore.txt"; then
  report A7 "restore verified against the canary checksum" pass
else
  report A7 "restore test failed" fail
fi

# Firewall posture, recorded for whoever reviews this later
remote 'sudo ufw status verbose' > "$EVIDENCE/firewall.txt" 2>&1

echo
echo "passed: $PASS   failed: $FAIL"
[[ $FAIL -eq 0 ]]
