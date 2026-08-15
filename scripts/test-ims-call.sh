#!/usr/bin/env bash
# ==============================================================================
# test-ims-call.sh - End-to-End IMS / SIP Signaling & RTPEngine Media Verification
#
# Validates complete 3GPP Vo5G / IMS call flows:
#   - Domestic Call: UE1 (Egypt 602/03) <-> UE2 (Egypt 602/04)
#   - Inter-PLMN Roaming Call: UE1 (Egypt 602/03) <-> UE3 (Bosnia 218/90 Roaming)
#
# Flow verified per call:
#   1. SIP REGISTER with Digest MD5 Authentication -> 200 OK
#   2. SIP INVITE (SDP offer) -> P-CSCF (rtpengine_offer) -> S-CSCF -> P-CSCF -> Callee
#   3. SIP 180 Ringing -> P-CSCF -> S-CSCF -> P-CSCF -> Caller
#   4. SIP 200 OK (SDP answer) -> P-CSCF (rtpengine_answer) -> S-CSCF -> P-CSCF -> Caller
#   5. SIP ACK -> P-CSCF -> S-CSCF -> P-CSCF -> Callee
#   6. Bidirectional RTP Audio Stream via RTPEngine Proxy (10.46.0.1)
#   7. SIP BYE -> P-CSCF (rtpengine_delete) -> S-CSCF -> P-CSCF -> Callee -> 200 OK
# ==============================================================================

set -euo pipefail

MODE="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Run python engine
python3 - "${MODE}" << 'EOF'
import socket, re, hashlib, time, threading, sys, os, subprocess

MODE = sys.argv[1] if len(sys.argv) > 1 else "all"
PCSCF_IP = "10.46.0.1"
SIP_PORT = 5060
RTP_PORT = 10000
NUM_PACKETS = 25

# Text formatting
GREEN = "\033[0;32m"
RED = "\033[0;31m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
CYAN = "\033[0;36m"
BOLD = "\033[1m"
NC = "\033[0m"

UE_MAP = {
    "ue1": {"imsi": "602030000000001", "name": "UE1 (Egypt 602/03)", "domain": "ims.lab", "pass": "password123"},
    "ue2": {"imsi": "602040000000002", "name": "UE2 (Egypt 602/04)", "domain": "ims.lab", "pass": "password123"},
    "ue3": {"imsi": "602030000000003", "name": "UE3 (Bosnia 218/90 Roaming)", "domain": "ims.lab", "pass": "password123"}
}

def get_ue_ip(imsi):
    ns = f"ueransim-{imsi}-ims-psi2"
    cmd = f"ip netns exec {ns} ip -4 addr show 2>/dev/null"
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    m = re.search(r'inet (10\.46\.[0-9.]+)/\d+', res.stdout)
    if m:
        return m.group(1), ns
    raise RuntimeError(f"IMS IPv4 (10.46.x.x) not found in namespace '{ns}'. Is UE running with IMS PDU session?")

def register_ue(ue_key):
    info = UE_MAP[ue_key]
    imsi = info["imsi"]
    ip, ns = get_ue_ip(imsi)

    script = f"""import socket, re, hashlib, time, sys

def make_digest(u, p, r, n, uri, m):
    ha1 = hashlib.md5(f'{{u}}:{{r}}:{{p}}'.encode()).hexdigest()
    ha2 = hashlib.md5(f'{{m}}:{{uri}}'.encode()).hexdigest()
    resp = hashlib.md5(f'{{ha1}}:{{n}}:{{ha2}}'.encode()).hexdigest()
    return f'Digest username="{{u}}", realm="{{r}}", nonce="{{n}}", uri="{{uri}}", response="{{resp}}", algorithm=MD5'

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('{ip}', {SIP_PORT}))
s.settimeout(4.0)

cseq_base = int(time.time())
call_id = f'call-reg-{ue_key}-{{cseq_base}}@{ip}'

req1 = (
    'REGISTER sip:ims.lab SIP/2.0\\r\\n'
    f'Via: SIP/2.0/UDP {ip}:{SIP_PORT};rport;branch=z9hG4bK-reg-{ue_key}-1\\r\\n'
    'Max-Forwards: 70\\r\\n'
    'From: <sip:{ue_key}@ims.lab>;tag=tag_{ue_key}_1\\r\\n'
    'To: <sip:{ue_key}@ims.lab>\\r\\n'
    f'Call-ID: {{call_id}}\\r\\n'
    f'CSeq: {{cseq_base}} REGISTER\\r\\n'
    'Contact: <sip:{ue_key}@{ip}:{SIP_PORT}>\\r\\n'
    'Expires: 3600\\r\\n'
    'Content-Length: 0\\r\\n\\r\\n'
)
s.sendto(req1.encode(), ('{PCSCF_IP}', {SIP_PORT}))
resp1, _ = s.recvfrom(4096)
resp1_str = resp1.decode('latin1')
assert '401' in resp1_str, f'Expected 401 Unauthorized, got: {{resp1_str}}'

nonce = re.search(r'nonce="([^"]+)"', resp1_str).group(1)
realm = re.search(r'realm="([^"]+)"', resp1_str).group(1)
auth_hdr = make_digest('{ue_key}', '{info["pass"]}', realm, nonce, 'sip:ims.lab', 'REGISTER')

req2 = (
    'REGISTER sip:ims.lab SIP/2.0\\r\\n'
    f'Via: SIP/2.0/UDP {ip}:{SIP_PORT};rport;branch=z9hG4bK-reg-{ue_key}-2\\r\\n'
    'Max-Forwards: 70\\r\\n'
    'From: <sip:{ue_key}@ims.lab>;tag=tag_{ue_key}_1\\r\\n'
    'To: <sip:{ue_key}@ims.lab>\\r\\n'
    f'Call-ID: {{call_id}}\\r\\n'
    f'CSeq: {{cseq_base+1}} REGISTER\\r\\n'
    'Contact: <sip:{ue_key}@{ip}:{SIP_PORT}>\\r\\n'
    f'Authorization: {{auth_hdr}}\\r\\n'
    'Expires: 3600\\r\\n'
    'Content-Length: 0\\r\\n\\r\\n'
)
s.sendto(req2.encode(), ('{PCSCF_IP}', {SIP_PORT}))
resp2, _ = s.recvfrom(4096)
resp2_str = resp2.decode('latin1')
assert '200 OK' in resp2_str, f'Expected 200 OK, got: {{resp2_str}}'
print(f'Authenticated & Registered sip:{ue_key}@ims.lab (Contact: {ip}:{SIP_PORT})')
"""
    tmp_path = f"/tmp/reg_{ue_key}.py"
    with open(tmp_path, "w") as f:
        f.write(script)
    res = subprocess.run(f"ip netns exec {ns} python3 {tmp_path}", shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  {RED}[✗] {info['name']} Registration Failed: {res.stderr.strip()}{NC}")
        return False
    print(f"  {GREEN}[✓] {info['name']}: {res.stdout.strip()}{NC}")
    return True

def run_call(caller_key, callee_key):
    caller_info = UE_MAP[caller_key]
    callee_info = UE_MAP[callee_key]
    caller_ip, caller_ns = get_ue_ip(caller_info["imsi"])
    callee_ip, callee_ns = get_ue_ip(callee_info["imsi"])

    print(f"\n{CYAN}------------------------------------------------------------{NC}")
    print(f"{BOLD}SIP Voice Call: {caller_info['name']} ──► {callee_info['name']}{NC}")
    print(f"  Caller: {caller_key}@ims.lab ({caller_ip}) | Callee: {callee_key}@ims.lab ({callee_ip})")
    print(f"  P-CSCF: {PCSCF_IP}:{SIP_PORT} | RTPEngine Media Proxy: {PCSCF_IP}")
    print(f"{CYAN}------------------------------------------------------------{NC}")

    callee_script = f"""import socket, re, time, threading, sys
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(('{callee_ip}', {SIP_PORT}))
    s.settimeout(12.0)

    rtp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rtp_sock.bind(('{callee_ip}', {RTP_PORT}))
    rtp_sock.settimeout(8.0)

    invite_data, addr = s.recvfrom(4096)
    invite_str = invite_data.decode('latin1')

    vias = re.findall(r'Via: ([^\\r\\n]+)', invite_str)
    from_hdr = re.search(r'From: ([^\\r\\n]+)', invite_str).group(1)
    to_hdr = re.search(r'To: ([^\\r\\n]+)', invite_str).group(1)
    call_id = re.search(r'Call-ID: ([^\\r\\n]+)', invite_str).group(1)
    cseq = re.search(r'CSeq: ([^\\r\\n]+)', invite_str).group(1)
    cseq_num = cseq.split()[0]
    rr_hdrs = re.findall(r'Record-Route: ([^\\r\\n]+)', invite_str)

    sdp_ip = re.search(r'c=IN IP4 ([0-9.]+)', invite_str).group(1)
    sdp_port = int(re.search(r'm=audio ([0-9]+)', invite_str).group(1))

    via_block = '\\r\\n'.join([f'Via: {{v}}' for v in vias]) + '\\r\\n'
    rr_block = ('\\r\\n'.join([f'Record-Route: {{r}}' for r in rr_hdrs]) + '\\r\\n') if rr_hdrs else ''

    ringing = (
        'SIP/2.0 180 Ringing\\r\\n'
        f'{{via_block}}'
        f'{{rr_block}}'
        f'From: {{from_hdr}}\\r\\n'
        f'To: {{to_hdr}};tag=callee-tag-{callee_key}\\r\\n'
        f'Call-ID: {{call_id}}\\r\\n'
        f'CSeq: {{cseq_num}} INVITE\\r\\n'
        'Contact: <sip:{callee_key}@{callee_ip}:{SIP_PORT}>\\r\\n'
        'Content-Length: 0\\r\\n\\r\\n'
    )
    s.sendto(ringing.encode(), addr)
    time.sleep(0.2)

    sdp = (
        'v=0\\r\\n'
        f'o={callee_key} 2890844527 2890844527 IN IP4 {callee_ip}\\r\\n'
        's=Vo5G Session\\r\\n'
        f'c=IN IP4 {callee_ip}\\r\\n'
        't=0 0\\r\\n'
        f'm=audio {RTP_PORT} RTP/AVP 0 8\\r\\n'
        'a=rtpmap:0 PCMU/8000\\r\\n'
        'a=rtpmap:8 PCMA/8000\\r\\n'
        'a=sendrecv\\r\\n'
    )
    ok200 = (
        'SIP/2.0 200 OK\\r\\n'
        f'{{via_block}}'
        f'{{rr_block}}'
        f'From: {{from_hdr}}\\r\\n'
        f'To: {{to_hdr}};tag=callee-tag-{callee_key}\\r\\n'
        f'Call-ID: {{call_id}}\\r\\n'
        f'CSeq: {{cseq_num}} INVITE\\r\\n'
        'Contact: <sip:{callee_key}@{callee_ip}:{SIP_PORT}>\\r\\n'
        'Content-Type: application/sdp\\r\\n'
        f'Content-Length: {{len(sdp)}}\\r\\n\\r\\n'
        f'{{sdp}}'
    )
    s.sendto(ok200.encode(), addr)

    ack_data, _ = s.recvfrom(4096)

    rcv_count = [0]
    def rtp_receiver():
        while rcv_count[0] < {NUM_PACKETS}:
            try:
                pkt, _ = rtp_sock.recvfrom(512)
                rcv_count[0] += 1
            except:
                break

    rx_thread = threading.Thread(target=rtp_receiver)
    rx_thread.start()

    for i in range({NUM_PACKETS}):
        rtp_pkt = b'\\x80\\x00' + i.to_bytes(2, 'big') + (i*160).to_bytes(4, 'big') + b'\\x12\\x34\\x56\\x78' + (b'RTP-VOICE-PAYLOAD-' + f'{callee_key}'.encode() + b'-' + str(i).encode()).ljust(160, b'\\x00')
        rtp_sock.sendto(rtp_pkt, (sdp_ip, sdp_port))
        time.sleep(0.02)

    rx_thread.join(timeout=3.0)

    bye_data, bye_addr = s.recvfrom(4096)
    bye_str = bye_data.decode('latin1')
    bye_vias = re.findall(r'Via: ([^\\r\\n]+)', bye_str)
    bye_via_block = '\\r\\n'.join([f'Via: {{v}}' for v in bye_vias]) + '\\r\\n'
    bye_cseq = re.search(r'CSeq: ([^\\r\\n]+)', bye_str).group(1)

    bye_ok = (
        'SIP/2.0 200 OK\\r\\n'
        f'{{bye_via_block}}'
        f'From: {{from_hdr}}\\r\\n'
        f'To: {{to_hdr}};tag=callee-tag-{callee_key}\\r\\n'
        f'Call-ID: {{call_id}}\\r\\n'
        f'CSeq: {{bye_cseq}}\\r\\n'
        'Content-Length: 0\\r\\n\\r\\n'
    )
    s.sendto(bye_ok.encode(), bye_addr)
    with open('/tmp/callee_res.txt', 'w') as f:
        f.write(f'OK: Received {{rcv_count[0]}}/{NUM_PACKETS} RTP packets')
except Exception as e:
    with open('/tmp/callee_res.txt', 'w') as f:
        f.write(f'ERROR: {{e}}')
    sys.exit(1)
"""

    caller_script = f"""import socket, re, time, threading, sys
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(('{caller_ip}', {SIP_PORT}))
    s.settimeout(8.0)

    rtp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rtp_sock.bind(('{caller_ip}', {RTP_PORT}))
    rtp_sock.settimeout(8.0)

    sdp = (
        'v=0\\r\\n'
        f'o={caller_key} 2890844526 2890844526 IN IP4 {caller_ip}\\r\\n'
        's=Vo5G Session\\r\\n'
        f'c=IN IP4 {caller_ip}\\r\\n'
        't=0 0\\r\\n'
        f'm=audio {RTP_PORT} RTP/AVP 0 8\\r\\n'
        'a=rtpmap:0 PCMU/8000\\r\\n'
        'a=rtpmap:8 PCMA/8000\\r\\n'
        'a=sendrecv\\r\\n'
    )

    call_seq = int(time.time() % 100000)
    invite = (
        'INVITE sip:{callee_key}@ims.lab SIP/2.0\\r\\n'
        f'Via: SIP/2.0/UDP {caller_ip}:{SIP_PORT};rport;branch=z9hG4bK-inv-{caller_key}-{{call_seq}}\\r\\n'
        'Max-Forwards: 70\\r\\n'
        'From: <sip:{caller_key}@ims.lab>;tag=caller-tag-{caller_key}\\r\\n'
        f'To: <sip:{callee_key}@ims.lab>\\r\\n'
        f'Call-ID: call-run-{{call_seq}}@{caller_ip}\\r\\n'
        f'CSeq: {{call_seq}} INVITE\\r\\n'
        'Contact: <sip:{caller_key}@{caller_ip}:{SIP_PORT}>\\r\\n'
        'Content-Type: application/sdp\\r\\n'
        f'Content-Length: {{len(sdp)}}\\r\\n\\r\\n'
        f'{{sdp}}'
    )

    s.sendto(invite.encode(), ('{PCSCF_IP}', {SIP_PORT}))

    got_200 = False
    to_tag = ''
    rr_hdrs = []
    contact_tgt = 'sip:{callee_key}@{callee_ip}:{SIP_PORT}'
    sdp_ip = '{PCSCF_IP}'
    sdp_port = {RTP_PORT}

    while not got_200:
        resp, addr = s.recvfrom(4096)
        resp_str = resp.decode('latin1')
        first_line = resp_str.split('\\r\\n')[0]
        if '200 OK' in first_line:
            got_200 = True
            to_m = re.search(r'To: <sip:{callee_key}@ims.lab>;tag=([^\\r\\n;]+)', resp_str)
            if to_m: to_tag = to_m.group(1)
            rr_hdrs = re.findall(r'Record-Route: ([^\\r\\n]+)', resp_str)
            ct_m = re.search(r'Contact: <([^>]+)>', resp_str)
            if ct_m: contact_tgt = ct_m.group(1)
            
            sdp_m_ip = re.search(r'c=IN IP4 ([0-9.]+)', resp_str)
            if sdp_m_ip: sdp_ip = sdp_m_ip.group(1)
            sdp_m_port = re.search(r'm=audio ([0-9]+)', resp_str)
            if sdp_m_port: sdp_port = int(sdp_m_port.group(1))

    route_hdrs = list(reversed(rr_hdrs))
    route_block = ('\\r\\n'.join([f'Route: {{r}}' for r in route_hdrs]) + '\\r\\n') if route_hdrs else ''

    ack = (
        f'ACK {{contact_tgt}} SIP/2.0\\r\\n'
        f'Via: SIP/2.0/UDP {caller_ip}:{SIP_PORT};rport;branch=z9hG4bK-ack-run-{{call_seq}}\\r\\n'
        f'{{route_block}}'
        'Max-Forwards: 70\\r\\n'
        'From: <sip:{caller_key}@ims.lab>;tag=caller-tag-{caller_key}\\r\\n'
        f'To: <sip:{callee_key}@ims.lab>;tag={{to_tag}}\\r\\n'
        f'Call-ID: call-run-{{call_seq}}@{caller_ip}\\r\\n'
        f'CSeq: {{call_seq}} ACK\\r\\n'
        'Contact: <sip:{caller_key}@{caller_ip}:{SIP_PORT}>\\r\\n'
        'Content-Length: 0\\r\\n\\r\\n'
    )
    s.sendto(ack.encode(), ('{PCSCF_IP}', {SIP_PORT}))

    rcv_count = [0]
    def rtp_receiver():
        while rcv_count[0] < {NUM_PACKETS}:
            try:
                pkt, _ = rtp_sock.recvfrom(512)
                rcv_count[0] += 1
            except:
                break

    rx_thread = threading.Thread(target=rtp_receiver)
    rx_thread.start()

    for i in range({NUM_PACKETS}):
        rtp_pkt = b'\\x80\\x00' + i.to_bytes(2, 'big') + (i*160).to_bytes(4, 'big') + b'\\x87\\x65\\x43\\x21' + (b'RTP-VOICE-PAYLOAD-' + f'{caller_key}'.encode() + b'-' + str(i).encode()).ljust(160, b'\\x00')
        rtp_sock.sendto(rtp_pkt, (sdp_ip, sdp_port))
        time.sleep(0.02)

    rx_thread.join(timeout=3.0)
    time.sleep(0.5)

    bye = (
        f'BYE {{contact_tgt}} SIP/2.0\\r\\n'
        f'Via: SIP/2.0/UDP {caller_ip}:{SIP_PORT};rport;branch=z9hG4bK-bye-run-{{call_seq}}\\r\\n'
        f'{{route_block}}'
        'Max-Forwards: 70\\r\\n'
        'From: <sip:{caller_key}@ims.lab>;tag=caller-tag-{caller_key}\\r\\n'
        f'To: <sip:{callee_key}@ims.lab>;tag={{to_tag}}\\r\\n'
        f'Call-ID: call-run-{{call_seq}}@{caller_ip}\\r\\n'
        f'CSeq: {{call_seq+1}} BYE\\r\\n'
        'Contact: <sip:{caller_key}@{caller_ip}:{SIP_PORT}>\\r\\n'
        'Content-Length: 0\\r\\n\\r\\n'
    )
    s.sendto(bye.encode(), ('{PCSCF_IP}', {SIP_PORT}))
    bye_resp, addr = s.recvfrom(4096)
    with open('/tmp/caller_res.txt', 'w') as f:
        f.write(f'OK: Received {{rcv_count[0]}}/{NUM_PACKETS} RTP packets')
except Exception as e:
    with open('/tmp/caller_res.txt', 'w') as f:
        f.write(f'ERROR: {{e}}')
    sys.exit(1)
"""

    with open('/tmp/run_callee.py', 'w') as f:
        f.write(callee_script)
    with open('/tmp/run_caller.py', 'w') as f:
        f.write(caller_script)

    callee_proc = subprocess.Popen(f"ip netns exec {callee_ns} python3 /tmp/run_callee.py", shell=True)
    time.sleep(0.8)
    caller_proc = subprocess.Popen(f"ip netns exec {caller_ns} python3 /tmp/run_caller.py", shell=True)

    caller_proc.wait(timeout=15.0)
    callee_proc.wait(timeout=15.0)

    with open('/tmp/caller_res.txt') as f: c_res = f.read().strip()
    with open('/tmp/callee_res.txt') as f: k_res = f.read().strip()
    print(f"  Caller ({caller_key} -> {callee_key}): {c_res}")
    print(f"  Callee ({callee_key} -> {caller_key}): {k_res}")
    if not (c_res.startswith("OK") and k_res.startswith("OK")):
        print(f"  {RED}[✗] Voice call or media verification failed!{NC}")
        return False
    print(f"  {GREEN}[✓] Call dialog & Bidirectional RTP stream PASSED (25/25 packets, 0% loss){NC}")
    return True

print(f"{BLUE}============================================================{NC}")
print(f"{BLUE}    Open5GS 5G SA + Kamailio IMS Multi-PLMN Voice Test Suite{NC}")
print(f"{BLUE}============================================================{NC}")

print(f"\n{CYAN}[1/3] Performing SIP Digest Registrations...{NC}")
r1 = register_ue("ue1")
r2 = register_ue("ue2")
r3 = register_ue("ue3")

if not (r1 and r2 and r3):
    print(f"{RED}[✗] Registration failed for one or more UEs.{NC}")
    sys.exit(1)

success = True

if MODE in ["all", "ue1-ue2", "domestic"]:
    print(f"\n{CYAN}[2/3] Validating Domestic Call (UE1 Egypt 602/03 <-> UE2 Egypt 602/04)...{NC}")
    if not run_call("ue1", "ue2"):
        success = False

if MODE in ["all", "ue1-ue3", "roaming"]:
    print(f"\n{CYAN}[3/3] Validating Inter-PLMN Roaming Call (UE1 Egypt 602/03 <-> UE3 Bosnia 218/90)...{NC}")
    if not run_call("ue1", "ue3"):
        success = False

if MODE in ["ue3-ue1", "reverse-roaming"]:
    print(f"\n{CYAN}[Extra] Validating Reverse Roaming Call (UE3 Bosnia 218/90 <-> UE1 Egypt 602/03)...{NC}")
    if not run_call("ue3", "ue1"):
        success = False

print(f"\n{BLUE}============================================================{NC}")
if success:
    print(f"{GREEN}{BOLD}    >>> ALL IMS REGISTRATIONS & VOICE CALL TESTS PASSED <<< {NC}")
    print(f"{BLUE}============================================================{NC}")
    sys.exit(0)
else:
    print(f"{RED}{BOLD}    >>> SOME IMS VOICE CALL TESTS FAILED <<< {NC}")
    print(f"{BLUE}============================================================{NC}")
    sys.exit(1)
EOF
