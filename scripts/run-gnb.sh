#!/usr/bin/env bash
# Launch nr-gnb detached. Run via: bash scripts/run-gnb.sh
cd /home/abdulrhamn/Open-Telecom-Lab
pkill -9 -f 'build/nr-gnb' 2>/dev/null || true
sleep 1
: > /tmp/gnb_new.log
setsid ./UERANSIM/build/nr-gnb -c ./UERANSIM/config/open5gs-gnb.yaml >> /tmp/gnb_new.log 2>&1 < /dev/null &
echo "launched pid $!"
