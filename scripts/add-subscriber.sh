#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Open Telecom Lab — Add Test Subscriber to Open5GS MongoDB
# ─────────────────────────────────────────────────────────────────
# Usage: sudo bash add-subscriber.sh
#
# This script adds a test subscriber matching the UERANSIM UE config.
# Credentials must match between this script and open5gs-ue.yaml.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Subscriber Parameters ──────────────────────────────────────
IMSI="001010000000001"
KI="465B5CE8B199B49FAA5F0A2EE238A6BC"
OPC="E8ED2441347B7990E92C19B0316CD6FC"
APN="internet"
SST=1

echo "═══════════════════════════════════════════════════"
echo "  Open Telecom Lab — Subscriber Provisioning"
echo "═══════════════════════════════════════════════════"
echo ""
echo "  IMSI:  ${IMSI}"
echo "  K:     ${KI}"
echo "  OPc:   ${OPC}"
echo "  APN:   ${APN}"
echo "  SST:   ${SST}"
echo ""

# Check if open5gs-dbctl is available
if command -v open5gs-dbctl &> /dev/null; then
    echo "[+] Using open5gs-dbctl..."
    open5gs-dbctl add "${IMSI}" "${KI}" "${OPC}"
    echo "[✓] Subscriber added successfully."
else
    echo "[+] Using mongosh directly..."
    mongosh --quiet --eval "
    db = db.getSiblingDB('open5gs');
    db.subscribers.updateOne(
        { imsi: '${IMSI}' },
        {
            \$set: {
                imsi: '${IMSI}',
                subscribed_rau_tau_timer: 12,
                network_access_mode: 0,
                subscriber_status: 0,
                access_restriction_data: 32,
                security: {
                    k: '${KI}',
                    amf: '8000',
                    op: '',
                    opc: '${OPC}',
                    sqn: NumberLong(0)
                },
                ambr: {
                    uplink: { value: 1, unit: 3 },
                    downlink: { value: 1, unit: 3 }
                },
                slice: [{
                    sst: ${SST},
                    default_indicator: true,
                    session: [{
                        name: '${APN}',
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
                    }]
                }],
                schema_version: 1
            }
        },
        { upsert: true }
    );
    print('[✓] Subscriber added/updated successfully.');
    "
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Done. Verify with: mongosh open5gs --eval"
echo "    \"db.subscribers.find({imsi:'${IMSI}'}).pretty()\""
echo "═══════════════════════════════════════════════════"
