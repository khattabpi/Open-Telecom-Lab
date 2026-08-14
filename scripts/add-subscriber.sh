#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Open Telecom Lab — Add Test Subscriber(s) to Open5GS MongoDB
# ─────────────────────────────────────────────────────────────────
# Usage:
#   bash scripts/add-subscriber.sh            # Provision all test UEs (UE1 & UE2)
#   bash scripts/add-subscriber.sh all        # Provision all test UEs (UE1 & UE2)
#   bash scripts/add-subscriber.sh 1          # Provision UE1 (001010000000001)
#   bash scripts/add-subscriber.sh 2          # Provision UE2 (001010000000002)
#   bash scripts/add-subscriber.sh [IMSI] [K] [OPC]  # Provision custom subscriber
#
# Supports Kubernetes (open5gs/mongodb-0), Docker Compose (mongodb),
# or native mongod.
# Provisions dual-slice sessions: 'internet' (QCI 9) and 'ims' (QCI 5).
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

exec_mongo() {
    local script="$1"
    # Method 1: Kubernetes Pod (mongodb-0)
    if kubectl get pod -n open5gs mongodb-0 >/dev/null 2>&1 && [ "$(kubectl get pod -n open5gs mongodb-0 -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ]; then
        printf "${BLUE}[+] Using Kubernetes mongodb-0 pod in open5gs namespace...${NC}\n"
        kubectl -n open5gs exec -i mongodb-0 -- mongosh --quiet --eval "${script}"

    # Method 2: Docker Compose container
    elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^mongodb$'; then
        printf "${BLUE}[+] Using Docker Compose mongodb container...${NC}\n"
        docker exec -i mongodb mongosh --quiet --eval "${script}"

    # Method 3: Local mongosh
    elif command -v mongosh &>/dev/null; then
        printf "${BLUE}[+] Using local mongosh on host...${NC}\n"
        mongosh --quiet --eval "${script}"

    # Method 4: Local mongo legacy shell
    elif command -v mongo &>/dev/null; then
        printf "${BLUE}[+] Using local mongo shell on host...${NC}\n"
        mongo --quiet --eval "${script}"

    else
        printf "${RED}[✗] Error: No MongoDB instance accessible (checked K8s pod, Docker container, local mongosh).${NC}\n" >&2
        exit 1
    fi
}

provision_subscriber() {
    local imsi="$1"
    local ki="$2"
    local opc="$3"
    local sst=1
    local sd="ffffff"

    echo "═══════════════════════════════════════════════════"
    echo "  Open Telecom Lab — Subscriber Provisioning"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "  IMSI:      ${imsi}"
    echo "  K:         ${ki}"
    echo "  OPc:       ${opc}"
    echo "  S-NSSAI:   SST=${sst}, SD=0x${sd}"
    echo "  Sessions:  'internet' (IPv4, QCI 9) & 'ims' (IPv4, QCI 5)"
    echo ""

    local mongo_script="
db = db.getSiblingDB('open5gs');
db.subscribers.updateOne(
    { imsi: '${imsi}' },
    {
        \$set: {
            imsi: '${imsi}',
            subscribed_rau_tau_timer: 12,
            network_access_mode: 0,
            subscriber_status: 0,
            access_restriction_data: 32,
            security: {
                k: '${ki}',
                amf: '8000',
                op: '',
                opc: '${opc}',
                sqn: NumberLong("0")
            },
            ambr: {
                uplink: { value: 1, unit: 3 },
                downlink: { value: 1, unit: 3 }
            },
            slice: [{
                sst: ${sst},
                sd: '${sd}',
                default_indicator: true,
                session: [
                    {
                        name: 'internet',
                        type: 1,
                        qos: {
                            index: 9,
                            arp: {
                                priority_level: 8,
                                pre_emption_capability: 1,
                                pre_emption_vulnerability: 1
                            }
                        },
                        ambr: {
                            uplink: { value: 1, unit: 3 },
                            downlink: { value: 1, unit: 3 }
                        }
                    },
                    {
                        name: 'ims',
                        type: 1,
                        qos: {
                            index: 5,
                            arp: {
                                priority_level: 1,
                                pre_emption_capability: 1,
                                pre_emption_vulnerability: 1
                            }
                        },
                        ambr: {
                            uplink: { value: 1, unit: 3 },
                            downlink: { value: 1, unit: 3 }
                        }
                    }
                ]
            }],
            schema_version: 1
        }
    },
    { upsert: true }
);
print('[✓] Subscriber ' + '${imsi}' + ' added/updated successfully with dual-slice sessions.');
"
    exec_mongo "${mongo_script}"
}

# ─── Main Dispatcher ────────────────────────────────────────────
TARGET="${1:-all}"

if [ "${TARGET}" = "all" ]; then
    provision_subscriber "001010000000001" "465B5CE8B199B49FAA5F0A2EE238A6BC" "E8ED2441347B7990E92C19B0316CD6FC"
    provision_subscriber "001010000000002" "465B5CE8B199B49FAA5F0A2EE238A6BD" "E8ED2441347B7990E92C19B0316CD6FC"
elif [ "${TARGET}" = "1" ] || [ "${TARGET}" = "ue1" ]; then
    provision_subscriber "001010000000001" "465B5CE8B199B49FAA5F0A2EE238A6BC" "E8ED2441347B7990E92C19B0316CD6FC"
elif [ "${TARGET}" = "2" ] || [ "${TARGET}" = "ue2" ]; then
    provision_subscriber "001010000000002" "465B5CE8B199B49FAA5F0A2EE238A6BD" "E8ED2441347B7990E92C19B0316CD6FC"
else
    IMSI="${1}"
    KI="${2:-465B5CE8B199B49FAA5F0A2EE238A6BC}"
    OPC="${3:-E8ED2441347B7990E92C19B0316CD6FC}"
    provision_subscriber "${IMSI}" "${KI}" "${OPC}"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Subscriber provisioning complete."
echo "═══════════════════════════════════════════════════"
