# Lab 01 — 5G SA Core Network Setup

## Objective

Deploy a complete 5G Standalone (SA) core network using Open5GS on Ubuntu 24.04 LTS, including all control plane and user plane network functions.

## Prerequisites

- Ubuntu 22.04+ LTS (fresh install recommended)
- Minimum 4 GB RAM, 2 CPU cores, 20 GB disk
- Internet access for package downloads
- Root or sudo access

## Steps

### 1. System Preparation

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y software-properties-common wget curl gnupg
```

### 2. Install MongoDB

```bash
# Follow official MongoDB installation for Ubuntu
# https://www.mongodb.com/docs/manual/tutorial/install-mongodb-on-ubuntu/
sudo systemctl start mongod
sudo systemctl enable mongod
```

### 3. Install Open5GS

```bash
sudo add-apt-repository ppa:open5gs/latest
sudo apt update
sudo apt install -y open5gs
```

### 4. Verify All NFs Are Running

```bash
# Check each network function
for nf in amf smf upf nrf ausf udm udr pcf nssf bsf scp; do
    echo -n "open5gs-${nf}d: "
    sudo systemctl is-active open5gs-${nf}d
done
```

### 5. Build UERANSIM

```bash
sudo apt install -y make gcc g++ libsctp-dev lksctp-tools iproute2
git clone https://github.com/aligungr/UERANSIM
cd UERANSIM && make
```

### 6. Configure NAT

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
```

## Verification

- [ ] All 11 Open5GS NFs report `active (running)`
- [ ] MongoDB is running on `localhost:27017`
- [ ] UERANSIM builds successfully (`build/nr-gnb` and `build/nr-ue` exist)
- [ ] `ogstun` interface is up with IP `10.45.0.1`
- [ ] IP forwarding is enabled

## Expected Outcome

A fully operational 5G SA core network ready to accept gNB connections and UE registrations.
