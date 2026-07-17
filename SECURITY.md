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
| SUPI/IMSI | `001010000000001` | Test subscriber identity |
| K | `465B5CE8...` | Test authentication key |
| OPc | `E8ED2441...` | Test operator code |
| PLMN | `001/01` | 3GPP test network MCC/MNC |

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
- Use test PLMN values (`001/01`) — never real operator credentials.
- Regularly update Open5GS and UERANSIM to patched versions.
- Review `iptables` rules before enabling NAT forwarding.
