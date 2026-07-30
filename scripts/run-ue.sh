#!/usr/bin/env bash
# Launch nr-ue detached as root. Run via: echo "$PW" | sudo -S scripts/run-ue.sh
cd /home/abdulrhamn/Open-Telecom-Lab
pkill -9 -f nr-ue 2>/dev/null || true
sleep 1
: > /tmp/ue_run.log
setsid ./UERANSIM/build/nr-ue -c ./UERANSIM/config/open5gs-ue.yaml >> /tmp/ue_run.log 2>&1 < /dev/null &
echo "launched pid $!"
