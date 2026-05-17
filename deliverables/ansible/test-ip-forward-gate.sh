#!/usr/bin/env bash
# test-ip-forward-gate.sh
#
# Validate preflight-ip-forward.yml against DR (safe environment) before
# pointing it at prod for the Apr 30 window.
#
# Run sequence:
#   1. ansible-playbook --syntax-check  (catch YAML/Ansible errors before SSH)
#   2. --check --diff                   (no host changes; confirms reachability,
#                                        sysctl-file presence, and gate logic)
#   3. live run on DR                   (must return GREEN before prod)
#
# Expected outcomes
# -----------------
#   PASS: 18/18 hosts green. The 8 k3s nodes show v4=v6=1 persisted; the
#         10 non-k3s show v4=v6=0 persisted. No drift on any host.
#   FAIL: One or more hosts misconfigured. Re-run cis_hardening role on
#         the named host(s) before continuing.
#
# After this passes on DR, run on prod with:
#   ansible-playbook -i inventories/prod.ini preflight-ip-forward.yml \
#     -e target_env=prod
#
# Usage: ./test-ip-forward-gate.sh

set -euo pipefail

cd "$(dirname "$0")"

INVENTORY="inventories/dr.ini"
PLAYBOOK="preflight-ip-forward.yml"
ENV_NAME="dr"

echo "============================================================"
echo " ip_forward gate — DR validation"
echo "============================================================"

echo
echo "[1/3] Syntax check..."
ansible-playbook --syntax-check -i "$INVENTORY" "$PLAYBOOK" -e target_env="$ENV_NAME"

echo
echo "[2/3] Dry-run (--check, no host changes)..."
ansible-playbook -i "$INVENTORY" "$PLAYBOOK" -e target_env="$ENV_NAME" --check --diff

echo
echo "[3/3] Live run on DR..."
ansible-playbook -i "$INVENTORY" "$PLAYBOOK" -e target_env="$ENV_NAME"

echo
echo "============================================================"
echo " DR validation complete. If all 18 hosts are GREEN above,"
echo " you are clear to point this at prod tonight:"
echo
echo "   ansible-playbook -i inventories/prod.ini \\"
echo "     preflight-ip-forward.yml -e target_env=prod"
echo "============================================================"
