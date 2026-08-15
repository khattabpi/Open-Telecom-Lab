# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| v1.0.x  | ✅ Active |
| < v1.0  | ❌ No     |

## ⚠️ Important Disclaimer

This project is a **laboratory environment** intended for **educational and testing purposes only**. It is **not designed for production telecommunications networks**.

### Sensitive Data Warning

The following configuration values in this repository are **test-only credentials**:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| SUPI/IMSI (UE1) | `602030000000001` | Test subscriber identity (PLMN 602/03) |
| SUPI/IMSI (UE2) | `602040000000002` | Test subscriber identity (PLMN 602/04) |
| K | `465B5CE8...` | Test authentication key |
| OPc | `E8ED2441...` | Test operator code |
| PLMNs | `602/03`, `602/04` | Simulated test network MCC/MNCs |

> **🔒 Never use real subscriber credentials (IMSI, Ki, OPc) in this or any public repository.**

## Reporting a Vulnerability

If you discover a security issue in this project:

1. **Do NOT** open a public issue.
2. **Email** the maintainer directly at: `aaa.khattab10@gmail.com`
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
4. You will receive a response within **72 hours**.

## Security Best Practices for Lab Users

- Run the lab on an **isolated network** or behind a firewall.
- Do not expose Open5GS NF interfaces to the public internet.
- Use lab/test PLMN values (`602/03`, `602/04`) — never real operator credentials.
- Regularly update Open5GS and UERANSIM to patched versions.
- Review `iptables` rules before enabling NAT forwarding.
