# Kamailio IMS Service Layer for 5G SA Lab

This directory contains the Kubernetes manifests and configurations to deploy a complete, production-grade 3GPP IMS (IP Multimedia Subsystem) service layer on top of Open5GS 5G Standalone core.

---

## 🏛️ Architecture Overview

```
                          5G SA User Plane (GTP-U / N3)
                                       │
                                       ▼
                  UPF (ogstun on kind node, IP: 10.46.0.1)
                                       │
                  ┌────────────────────┴────────────────────┐
                  │                                         │
       [UE1: 10.46.0.7:5060]                     [UE2: 10.46.0.8:5060]
       IMSI: 001010000000001                     IMSI: 001010000000002
       SIP: sip:ue1@ims.lab                      SIP: sip:ue2@ims.lab
                  │                                         │
                  └────────────────────┬────────────────────┘
                                       │ SIP Signaling
                                       ▼
    ┌─────────────────────────────────────────────────────────────────────────┐
    │ Kubernetes Namespace: ims                                               │
    │                                                                         │
    │  ┌───────────────────────────────────────────────────────────────────┐  │
    │  │ P-CSCF (Proxy-CSCF) — kamailio-pcscf                              │  │
    │  │ • Listener: 10.46.0.1:5060 (hostNetwork: true)                    │  │
    │  │ • Path Header Insertion (RFC 3327)                                │  │
    │  │ • Outbound / Inbound Proxy for 5G UE Subnet 10.46.0.0/16          │  │
    │  └──────────────────┬─────────────────────────────▲──────────────────┘  │
    │                     │                             │                     │
    │                     ▼                             │                     │
    │  ┌────────────────────────────────────┐           │                     │
    │  │ I-CSCF (Interrogating-CSCF)        │           │ Terminating Leg     │
    │  │ • kamailio-icscf:5060              │           │                     │
    │  │ • Ingress Router for Home Network  │           │                     │
    │  └──────────────────┬─────────────────┘           │                     │
    │                     │                             │                     │
    │                     ▼                             │                     │
    │  ┌────────────────────────────────────────────────┴──────────────────┐  │
    │  │ S-CSCF (Serving-CSCF) — kamailio-scscf                            │  │
    │  │ • kamailio-scscf:5060                                             │  │
    │  │ • User Registration (usrloc) & SQLite Subscriber Auth (auth_db)   │  │
    │  │ • SIP Routing (Originating & Terminating Session Legs)            │  │
    │  └───────────────────────────────────────────────────────────────────┘  │
    │                                                                         │
    │  ┌───────────────────────────────────────────────────────────────────┐  │
    │  │ RTPEngine (Media Relay Daemon) — rtpengine                        │  │
    │  │ • Control: rtpengine:22222 (UDP NG protocol)                      │  │
    │  │ • Media Relay Port Range: 20000-20100                             │  │
    │  └───────────────────────────────────────────────────────────────────┘  │
    └─────────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Manifest Files

| File | Type | Description |
| :--- | :--- | :--- |
| `namespace.yaml` | `Namespace` | Creates isolated `ims` namespace |
| `configmap.yaml` | `ConfigMap` | Kamailio configuration files (`pcscf.cfg`, `icscf.cfg`, `scscf.cfg`) and SQLite DB init |
| `rtpengine.yaml` | `Deployment`, `Service` | Next-generation RTP media proxy daemon |
| `scscf.yaml` | `Deployment`, `Service` | Serving-CSCF with SQLite subscriber backend |
| `icscf.yaml` | `Deployment`, `Service` | Interrogating-CSCF |
| `pcscf.yaml` | `Deployment`, `Service` | Proxy-CSCF binding to hostNetwork `10.46.0.1:5060` |

---

## 👥 Provisioned IMS Subscribers

| Subscriber | IMSI | IMPU (SIP URI) | IMPI (Auth User) | Password | IMS IP |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **UE1** | `001010000000001` | `sip:ue1@ims.lab` | `ue1` | `password123` | `10.46.0.7` |
| **UE2** | `001010000000002` | `sip:ue2@ims.lab` | `ue2` | `password123` | `10.46.0.8` |

---

## 🚀 Deployment & Operation

### 1. Deploy the IMS Stack
```bash
kubectl apply -f k8s/ims/
```

### 2. Check Status of IMS Pods
```bash
kubectl -n ims get pods -o wide
```

### 3. Test End-to-End SIP Call & Bidirectional RTP Stream
```bash
sudo bash scripts/test-ims-call.sh
```

### 4. Run Full Regression Verification
```bash
sudo bash scripts/verify-lab.sh
```
