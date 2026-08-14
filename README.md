# 5G-IMS-Lab

Multi-UE 5G SA + IMS testbed with end-to-end SIP and RTP validation

Badges: 5G SA (Open5GS) | RAN (UERANSIM) | IMS (Kamailio) | Media (RTPEngine) | Validation 55/55 | License MIT

---

5G-IMS-Lab is a software-based 5G Standalone (SA) and IMS testbed built with Open5GS, UERANSIM, Kamailio, RTPEngine, and Kubernetes.

The lab uses multiple simulated UEs and validates the path from 5G registration and PDU session establishment to IMS SIP registration, call signaling, SDP negotiation, RTP media relay, and session teardown.

## Architecture

RAN (UERANSIM): UE1, UE2 -> GNB
GNB -> AMF (N2 / NGAP / SCTP)
GNB -> UPF (N3 / GTP-U)

5G SA Core / Kubernetes:
AMF -- AUSF/UDM/UDR/PCF/NRF/BSF -- MongoDB
AMF -- SMF -> UPF (N4 / PFCP)

IMS Service Layer / Kubernetes:
UE -> UPF (IMS PDU Session / IP)
UE --SIP--> P-CSCF
P-CSCF -> I-CSCF -> S-CSCF
P-CSCF <-> RTPEngine (NG Control)

UE1 ==RTP== RTPEngine ==RTP== UE2

The 5G SA user plane provides IP connectivity between the UEs and the IMS service layer. Kamailio handles SIP signaling, while RTPEngine anchors and relays the RTP media path.

## Deployment Model

The lab uses a hybrid deployment model.

### Host
- UERANSIM gNodeB
- Multiple simulated UEs
- Linux network namespaces
- UE TUN interfaces

### Kubernetes / kind
- Open5GS 5G Core
- MongoDB
- Kamailio IMS
- RTPEngine

The RAN and UE emulation runs directly on the Linux host, while the 5G Core and IMS service layer are containerized and orchestrated using Kubernetes.

## Components

| Component | Role                        | Protocols                  | Runtime                       |
|-----------|------------------------------|------------------------------|--------------------------------|
| Open5GS   | 5G SA Core network functions | NGAP / SBI / PFCP / GTP-U   | Kubernetes (open5gs)          |
| MongoDB   | 5G subscriber database       | MongoDB wire protocol       | Kubernetes (open5gs)          |
| UERANSIM  | gNodeB + UE emulation         | NGAP / SCTP / GTP-U         | Host processes / Linux netns  |
| P-CSCF    | IMS SIP ingress proxy        | SIP                          | Kubernetes (ims)              |
| I-CSCF    | IMS routing proxy            | SIP                          | Kubernetes (ims)              |
| S-CSCF    | Registrar and SIP service logic | SIP                       | Kubernetes (ims)              |
| RTPEngine | SDP rewriting and RTP relay  | SDP / RTP / RTCP             | Kubernetes (ims)              |
| kind      | Kubernetes cluster runtime    | -                             | Docker                         |

## Validation Results

Validated with two simulated UEs.

| Area                   | Result                                                        |
|-------------------------|----------------------------------------------------------------|
| 5G SA Core             | 10/10 Open5GS pods Running and Ready                          |
| 5G-AKA registration    | UE1 and UE2 successfully registered                           |
| PDU sessions           | Internet and IMS sessions established for both UEs            |
| Internet connectivity  | Ping and HTTPS verified from both UE namespaces               |
| IMS connectivity       | Both UEs reached the IMS gateway                                |
| SIP registration       | Digest MD5 challenge/response completed with 200 OK           |
| Registration stability | Repeated REGISTER requests passed with valid CSeq progression |
| Subscriber location    | UE contacts verified through S-CSCF runtime state               |
| SIP call signaling     | INVITE -> 180 Ringing -> 200 OK -> ACK completed                |
| SDP handling           | RTPEngine rewrote media endpoints                               |
| RTP media              | 25/25 packets delivered in each direction with 0% loss          |
| Call teardown          | BYE -> 200 OK completed and RTPEngine session was removed       |
| IMS validation         | 22/22 passed                                                     |
| Full lab regression    | 55/55 passed                                                     |

IMS validation:        22/22 passed
End-to-end SIP/RTP:    PASSED
Full lab validation:   55/55 passed

The RTP test uses generated G.711 PCMU packets to validate the media path. It does not represent physical voice capture or playback.

## Validation Evidence

### Kubernetes Deployment
![Kubernetes Deployment](docs/images/kubernetes-deployment.png)

### SIP Call Flow
![SIP Call Flow](docs/images/sip-call-flow.png)

### RTP Media Validation
![RTP Media Validation](docs/images/rtp-validation.png)

## Repository Structure

5G-IMS-Lab/
├── configs/
│   ├── ueransim/              # gNodeB and UE configuration
│   └── sipp/                  # SIP test scenarios and test data
├── docs/
│   ├── IMS-CALL-FLOW-VALIDATION.md
│   └── engineering-notes/
├── k8s/
│   ├── control-plane.yaml
│   ├── upf.yaml
│   ├── mongodb.yaml
│   └── ims/
├── scripts/
│   ├── start-lab.sh
│   ├── run-gnb.sh
│   ├── run-ue.sh
│   ├── validate-ims-call.sh
│   ├── test-ims-call.sh
│   └── verify-lab.sh
├── LICENSE
└── README.md

## Requirements

- Ubuntu 24.04 LTS
- Docker Engine
- kind
- kubectl
- UERANSIM
- Linux tun and sctp support
- iproute2
- iptables
- curl
- tcpdump
- Python 3

Tested on Ubuntu 24.04 LTS.

## Quick Start

1) Start the 5G Core and IMS Layer:
sudo bash scripts/start-lab.sh

2) Start the Simulated gNodeB:
bash scripts/run-gnb.sh

3) Start UE1:
sudo bash scripts/run-ue.sh 1

4) Start UE2:
sudo bash scripts/run-ue.sh 2

UE IPv4 addresses are allocated dynamically by the 5G core and may change after a restart.

## Validation

Run the IMS validation suite:
sudo bash scripts/validate-ims-call.sh

Run the focused SIP/RTP call test:
sudo bash scripts/test-ims-call.sh

Run the complete 5G SA + IMS regression suite:
sudo bash scripts/verify-lab.sh

Expected results:
IMS validation:        22/22 passed
End-to-end SIP/RTP:    PASSED
Full lab validation:   55/55 passed

## Troubleshooting

### SCTP / gNodeB Connection
lsmod | grep sctp
ss -A sctp -l -n | grep 38412

### IMS Connectivity
sudo ip netns exec <ue-netns> ping 10.46.0.1
(namespace name is generated from the UE identity)

### Dynamic UE Addresses
Internet traffic: 10.45.0.0/16
IMS traffic: 10.46.0.0/16
Validation scripts discover the current UE addresses at runtime.

### RTPEngine
kubectl get pods -n ims
kubectl logs -n ims deployment/rtpengine
NG control interface uses UDP port 22222.

### RTP Media Debugging
sudo tcpdump -i ogstun -n
sudo ip netns exec <ue-netns> tcpdump -i uesimtun0 -n -s 0 -w sip.pcap

## Documentation
- IMS Call Flow Validation (docs/IMS-CALL-FLOW-VALIDATION.md)
- 5G Registration Protocol Analysis (docs/engineering-notes/5g-registration-analysis.md)
- Linux Networking and Namespace Architecture (docs/engineering-notes/linux-networking-behind-5g.md)
- PDU Session Establishment and Debugging (docs/engineering-notes/debugging-pdu-session.md)
- IMS Manifest Architecture (k8s/ims/README.md)

## Limitations
- UERANSIM provides software-based RAN and UE emulation; no physical 5G radio hardware is used.
- RTP validation uses generated G.711 PCMU packets rather than physical audio hardware.
- UE IPv4 addresses are dynamically allocated and may change between sessions.
- Intended for laboratory testing, protocol validation, and experimentation rather than commercial carrier deployment.
- Current validation covers the implemented 5G SA, SIP, SDP, and RTP paths and does not claim full 3GPP Release compliance.

## License
MIT License. See LICENSE for details.
