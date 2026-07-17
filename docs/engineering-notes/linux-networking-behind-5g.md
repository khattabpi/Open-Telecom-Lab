# Linux Networking Behind 5G

> How Linux kernel networking primitives implement the 5G user plane — namespaces, TUN devices, GTP-U tunnels, and NAT.

---

## Why This Matters

In a production 5G network, the user plane runs on specialized hardware (SmartNICs, DPDK-accelerated UPFs). In this lab, the entire user plane — from UE application to internet — runs on **standard Linux networking primitives**. Understanding these primitives explains both how the lab works and what production systems are optimizing away.

---

## The Complete Packet Journey

```mermaid
graph TD
    A["📱 UE Application<br/>ping 8.8.8.8"] --> B["uesimtun0<br/>(TUN device in UE namespace)<br/>IP: 10.45.0.5"]
    B --> C["UERANSIM UE Process<br/>GTP-U Encapsulation"]
    C --> D["Loopback Interface<br/>UDP/2152<br/>src: 127.0.0.1 → dst: 127.0.0.7"]
    D --> E["UPF Process (open5gs-upfd)<br/>GTP-U Decapsulation"]
    E --> F["ogstun<br/>(TUN device in default namespace)<br/>IP: 10.45.0.1/16"]
    F --> G["Linux Routing Table<br/>default route → physical NIC"]
    G --> H["iptables POSTROUTING<br/>MASQUERADE<br/>10.45.0.5 → host public IP"]
    H --> I["Physical NIC<br/>(eth0 / ens33 / etc.)"]
    I --> J["🌐 Internet"]

    style A fill:#E3F2FD,stroke:#1565C0
    style B fill:#E8F5E9,stroke:#2E7D32
    style C fill:#FFF3E0,stroke:#E65100
    style D fill:#F3E5F5,stroke:#6A1B9A
    style E fill:#FFF3E0,stroke:#E65100
    style F fill:#E8F5E9,stroke:#2E7D32
    style H fill:#FCE4EC,stroke:#C62828
    style J fill:#E0F7FA,stroke:#006064
```

Each layer in this diagram maps to a specific Linux networking concept.

---

## Network Namespaces

### What They Are

A Linux network namespace is an **isolated copy of the network stack**. Each namespace has its own interfaces, routing tables, iptables rules, and socket bindings. Processes inside a namespace cannot see or interact with interfaces in other namespaces unless explicitly connected.

### How UERANSIM Uses Them

When `useNamespace: true` is set in `open5gs-ue.yaml`, UERANSIM creates a dedicated namespace for the UE's data traffic:

```
Namespace name: ueransim-{IMSI}-{DNN}-psi{PSI}
In this lab:    ueransim-001010000000001-internet-psi1
```

This isolates UE traffic from host traffic, simulating how a real UE would have its own IP stack independent of the network infrastructure.

```bash
# List all namespaces
sudo ip netns list
# Output: ueransim-001010000000001-internet-psi1

# Execute commands inside the UE namespace
sudo ip netns exec ueransim-001010000000001-internet-psi1 ip addr
sudo ip netns exec ueransim-001010000000001-internet-psi1 ip route
sudo ip netns exec ueransim-001010000000001-internet-psi1 ping 8.8.8.8
```

### Namespace Layout

```mermaid
graph LR
    subgraph DEFAULT ["Default Namespace (Host)"]
        LO["lo<br/>127.0.0.0/8"]
        OGSTUN["ogstun<br/>10.45.0.1/16"]
        ETH["eth0/ens33<br/>Host IP"]
        AMF_P["AMF, SMF, UPF<br/>NRF, AUSF, ..."]
        GNB_P["UERANSIM gNB"]
    end

    subgraph UE_NS ["UE Namespace"]
        TUN["uesimtun0<br/>10.45.0.5/16"]
        UE_APP["UE applications<br/>(ping, curl, etc.)"]
    end

    UE_APP --> TUN
    TUN -.->|"GTP-U via<br/>UERANSIM process"| GNB_P
    GNB_P -.->|"UDP/2152<br/>on loopback"| AMF_P

    style DEFAULT fill:#FAFAFA,stroke:#666
    style UE_NS fill:#E3F2FD,stroke:#1565C0
```

**Key insight:** The UERANSIM UE process straddles both namespaces. It reads packets from `uesimtun0` in the UE namespace, encapsulates them in GTP-U, and sends them via the default namespace's loopback to the UPF.

---

## TUN Interfaces

### What They Are

A TUN (network TUNnel) device is a **virtual network interface** that operates at Layer 3 (IP). Instead of receiving packets from a physical wire, a TUN device receives packets from a userspace process (and vice versa). Any packet routed to a TUN interface is delivered to the process that created it.

### TUN Devices in This Lab

| TUN Device | Created By | Namespace | IP Address | Purpose |
|------------|-----------|-----------|------------|---------|
| `uesimtun0` | UERANSIM UE | `ueransim-*` | 10.45.0.x | UE data interface (N3 endpoint, UE side) |
| `ogstun` | Open5GS UPF | Default | 10.45.0.1/16 | UPF data interface (N6 endpoint) |

### How uesimtun0 Works

1. UE application sends a packet (e.g., ICMP echo to `8.8.8.8`)
2. The packet is routed to `uesimtun0` (default route in UE namespace)
3. The UERANSIM UE process reads the raw IP packet from the TUN device
4. UERANSIM wraps it in a **GTP-U header** (TEID, sequence number)
5. UERANSIM sends the GTP-U packet as UDP to the UPF (`127.0.0.7:2152`)

### How ogstun Works

1. The UPF process receives the GTP-U packet on `127.0.0.7:2152`
2. UPF strips the GTP-U header, extracting the inner IP packet
3. UPF writes the inner IP packet to the `ogstun` TUN device
4. The Linux kernel receives the packet on `ogstun` and routes it normally
5. IP forwarding + NAT sends it to the internet

---

## GTP-U Tunneling

### Protocol Stack

When the UE sends an ICMP ping, the packet on the wire (loopback) looks like:

```
┌──────────────────────────────────────────────────────┐
│ IP Header (Outer)                                    │
│   src: 127.0.0.1 (gNB GTP-U addr)                   │
│   dst: 127.0.0.7 (UPF GTP-U addr)                   │
├──────────────────────────────────────────────────────┤
│ UDP Header                                           │
│   src port: (ephemeral)                              │
│   dst port: 2152 (GTP-U)                             │
├──────────────────────────────────────────────────────┤
│ GTP-U Header                                         │
│   Version: 1                                         │
│   Message Type: 0xFF (T-PDU)                         │
│   TEID: (assigned during PDU session establishment)  │
├──────────────────────────────────────────────────────┤
│ IP Header (Inner)                                    │
│   src: 10.45.0.5 (UE IP)                             │
│   dst: 8.8.8.8                                       │
├──────────────────────────────────────────────────────┤
│ ICMP Echo Request                                    │
│   Payload data                                       │
└──────────────────────────────────────────────────────┘
```

### Capturing GTP-U Traffic

```bash
# Capture GTP-U on loopback
sudo tcpdump -i lo -w gtpu.pcap udp port 2152

# Capture the inner (decapsulated) traffic on ogstun
sudo tcpdump -i ogstun -w ogstun.pcap

# Wireshark filter for GTP-U user data
# gtp && ip.addr == 10.45.0.5
```

---

## Routing Tables

### Default Namespace (Host)

```bash
ip route
# Key routes:
# 10.45.0.0/16 dev ogstun  proto kernel  scope link  src 10.45.0.1
# default via <gateway> dev <physical NIC>
```

The `10.45.0.0/16` route ensures that return traffic destined for UE IPs is routed to `ogstun`, where the UPF picks it up and tunnels it back via GTP-U.

### UE Namespace

```bash
sudo ip netns exec ueransim-001010000000001-internet-psi1 ip route
# Key routes:
# default dev uesimtun0
```

The UE namespace has a single default route pointing to `uesimtun0`. Every packet the UE application sends goes through the TUN device and into the GTP-U tunnel.

---

## iptables NAT

### The Rule

```bash
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
```

Breaking this down:

| Component | Meaning |
|-----------|---------|
| `-t nat` | Operate on the NAT table |
| `-A POSTROUTING` | Apply after routing decision, just before leaving the host |
| `-s 10.45.0.0/16` | Match packets with source IP in the UE subnet |
| `! -o ogstun` | Only if the outgoing interface is NOT ogstun |
| `-j MASQUERADE` | Replace source IP with the outgoing interface's IP |

### Why MASQUERADE and Not SNAT

`MASQUERADE` automatically uses the outgoing interface's current IP address. This is preferable over `SNAT` (which requires specifying a fixed IP) because:
- The host's public IP may change (DHCP)
- It works regardless of which physical interface is used
- No reconfiguration needed if network topology changes

### Packet Transformation

```
Before NAT:  src=10.45.0.5  dst=8.8.8.8  → leaving via eth0
After NAT:   src=192.168.1.100  dst=8.8.8.8  → leaving via eth0

Return path:
Incoming:    src=8.8.8.8  dst=192.168.1.100  → arriving on eth0
After NAT:   src=8.8.8.8  dst=10.45.0.5  → conntrack reverses the NAT
             → routed to ogstun → UPF → GTP-U → uesimtun0 → UE app
```

---

## IP Forwarding

```bash
# Check status
sysctl net.ipv4.ip_forward
# Must be: net.ipv4.ip_forward = 1

# Enable (runtime)
sudo sysctl -w net.ipv4.ip_forward=1

# Enable (persistent)
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-open5gs.conf
```

**Why it is required:** When a packet arrives on `ogstun` (destined for `8.8.8.8`), the kernel must **forward** it to the physical NIC. By default, Linux drops packets not addressed to the host itself. `ip_forward=1` tells the kernel to act as a router and forward packets between interfaces.

---

## Relationship Summary

```mermaid
graph TB
    subgraph UE_NS ["UE Namespace<br/>(ueransim-001010000000001-internet-psi1)"]
        APP["App: ping 8.8.8.8"]
        TUN_UE["uesimtun0<br/>10.45.0.5/16"]
    end

    subgraph HOST_NS ["Default Namespace (Host)"]
        LO["Loopback<br/>127.0.0.0/8"]
        OGSTUN["ogstun<br/>10.45.0.1/16"]
        FWD["IP Forward<br/>(sysctl)"]
        NAT["iptables NAT<br/>MASQUERADE"]
        ETH["Physical NIC"]
    end

    INET["🌐 Internet"]

    APP -->|"IP packet"| TUN_UE
    TUN_UE -->|"1. UERANSIM reads from TUN"| LO
    LO -->|"2. GTP-U (UDP/2152)"| LO
    LO -->|"3. UPF decapsulates"| OGSTUN
    OGSTUN -->|"4. Inner IP packet"| FWD
    FWD -->|"5. Forward to NIC"| NAT
    NAT -->|"6. src IP rewritten"| ETH
    ETH -->|"7. On the wire"| INET

    style UE_NS fill:#E3F2FD,stroke:#1565C0
    style HOST_NS fill:#FFF8E1,stroke:#F57F17
```

### Summary Table

| Component | Linux Primitive | 5G Equivalent | Role in This Lab |
|-----------|----------------|---------------|------------------|
| `uesimtun0` | TUN device | UE radio interface (simulated) | UE sends/receives IP packets |
| Network namespace | `ip netns` | UE isolation | Separates UE traffic from host |
| GTP-U encapsulation | UDP socket (port 2152) | N3 user plane tunnel | Carries UE packets between gNB and UPF |
| `ogstun` | TUN device | N6 interface | UPF exit point to data network |
| IP forwarding | `sysctl ip_forward` | Router function | Forwards packets between ogstun and NIC |
| iptables NAT | `MASQUERADE` | NAT gateway | Makes UE traffic internet-routable |
| Routing tables | `ip route` | Forwarding rules | Directs packets to correct interfaces |

---

## References

- [Linux Network Namespaces — man ip-netns(8)](https://man7.org/linux/man-pages/man8/ip-netns.8.html)
- [TUN/TAP — Linux Kernel Documentation](https://www.kernel.org/doc/html/latest/networking/tuntap.html)
- [iptables NAT — netfilter.org](https://www.netfilter.org/documentation/HOWTO/NAT-HOWTO.html)
- [3GPP TS 29.281 — GTP-U](https://www.3gpp.org/dynareport/29281.htm)
