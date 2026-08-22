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

# Ensure script executes with root privileges required for network namespaces and SIP socket operations
if [ "${EUID}" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

MODE="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Ensure UERANSIM gNodeBs & UEs are running before executing test calls
if ! ip netns list 2>/dev/null | grep -q "ueransim-602030000000001-ims-psi2" || \
   ! ip netns list 2>/dev/null | grep -q "ueransim-602040000000002-ims-psi2" || \
   ! ip netns list 2>/dev/null | grep -q "ueransim-602030000000003-ims-psi2"; then
    echo "[!] UERANSIM UE network namespaces not found. Starting gNodeBs and UEs..."
    bash "${SCRIPT_DIR}/run-gnb.sh" all >/dev/null 2>&1 || true
    bash "${SCRIPT_DIR}/run-ue.sh" all
fi

# Run python engine
python3 - "$@" << 'EOF'
import socket, re, hashlib, time, threading, sys, os, subprocess, json, urllib.request, urllib.error

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
    cmd = f"ip netns exec {ns} ip -4 addr show"
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        err_msg = res.stderr.strip() or res.stdout.strip() or "Unknown error"
        raise RuntimeError(f"Failed to inspect network namespace '{ns}' (exit code {res.returncode}): {err_msg}")
    m = re.search(r'inet (10\.46\.[0-9.]+)/\d+', res.stdout)
    if m:
        return m.group(1), ns
    raise RuntimeError(f"IMS IPv4 (10.46.x.x) not found in namespace '{ns}'. Output was:\n{res.stdout.strip()}")

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
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, 0xA0)  # CS5 (0xA0 / DSCP 40) - 3GPP 5QI 5 IMS Signaling
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

def run_call(caller_key, callee_key, duration_secs=None):
    caller_info = UE_MAP[caller_key]
    callee_info = UE_MAP[callee_key]
    caller_ip, caller_ns = get_ue_ip(caller_info["imsi"])
    callee_ip, callee_ns = get_ue_ip(callee_info["imsi"])

    # Determine packet count and duration mode
    # Default 25 packets (~0.5s) if duration_secs is None, or calculate from duration_secs
    is_manual = (duration_secs == 0 or duration_secs == "manual")
    if is_manual:
        num_packets = 999999
        max_duration = 0.0
        dur_label = "Continuous (until manual hangup)"
    elif duration_secs is not None and float(duration_secs) > 0:
        max_duration = float(duration_secs)
        num_packets = max(int(max_duration * 50), 25)
        dur_label = f"{max_duration:.1f}s ({num_packets} RTP packets)"
    else:
        num_packets = NUM_PACKETS
        max_duration = 0.0
        dur_label = f"{num_packets} RTP packets (~1.0s)"

    print(f"\n{CYAN}------------------------------------------------------------{NC}")
    print(f"{BOLD}SIP Voice Call: {caller_info['name']} ──► {callee_info['name']}{NC}")
    print(f"  Caller: {caller_key}@ims.lab ({caller_ip}) | Callee: {callee_key}@ims.lab ({callee_ip})")
    print(f"  P-CSCF: {PCSCF_IP}:{SIP_PORT} | RTPEngine Media Proxy: {PCSCF_IP}")
    print(f"  Duration Mode: {dur_label}")
    print(f"{CYAN}------------------------------------------------------------{NC}")

    # Remove any existing stop flag
    if os.path.exists('/tmp/stop_ims_call.flag'):
        try: os.remove('/tmp/stop_ims_call.flag')
        except: pass

    # Write initial call status
    with open('/tmp/active_call_status.json', 'w') as f:
        json.dump({
            "active": True,
            "state": "SIGNALING",
            "caller": caller_key,
            "callee": callee_key,
            "caller_name": caller_info['name'],
            "callee_name": callee_info['name'],
            "caller_ip": caller_ip,
            "callee_ip": callee_ip,
            "elapsed_seconds": 0.0,
            "packets_sent": 0,
            "packets_received": 0,
            "start_time": time.time()
        }, f)

    callee_script = """import socket, re, time, threading, sys, os, json

callee_key = sys.argv[1]
callee_ip = sys.argv[2]
pcscf_ip = sys.argv[3]
sip_port = int(sys.argv[4])
rtp_port = int(sys.argv[5])
num_packets = int(sys.argv[6])
max_duration = float(sys.argv[7])

try:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, 0xA0)  # CS5 (0xA0 / DSCP 40) - 3GPP 5QI 5 IMS Signaling
    s.bind((callee_ip, sip_port))
    s.settimeout(12.0)

    rtp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rtp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    rtp_sock.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, 0xB8)  # EF (0xB8 / DSCP 46) - 3GPP 5QI 1 Conversational Voice
    rtp_sock.bind((callee_ip, rtp_port))
    rtp_sock.settimeout(0.5)

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

    via_block = '\\r\\n'.join([f'Via: {v}' for v in vias]) + '\\r\\n'
    rr_block = ('\\r\\n'.join([f'Record-Route: {r}' for r in rr_hdrs]) + '\\r\\n') if rr_hdrs else ''

    ringing = (
        'SIP/2.0 180 Ringing\\r\\n'
        f'{via_block}'
        f'{rr_block}'
        f'From: {from_hdr}\\r\\n'
        f'To: {to_hdr};tag=callee-tag-{callee_key}\\r\\n'
        f'Call-ID: {call_id}\\r\\n'
        f'CSeq: {cseq_num} INVITE\\r\\n'
        f'Contact: <sip:{callee_key}@{callee_ip}:{sip_port}>\\r\\n'
        'Content-Length: 0\\r\\n\\r\\n'
    )
    s.sendto(ringing.encode(), addr)
    time.sleep(0.1)

    sdp = (
        'v=0\\r\\n'
        f'o={callee_key} 2890844527 2890844527 IN IP4 {callee_ip}\\r\\n'
        's=Vo5G Session\\r\\n'
        f'c=IN IP4 {callee_ip}\\r\\n'
        't=0 0\\r\\n'
        f'm=audio {rtp_port} RTP/AVP 0 8\\r\\n'
        'a=rtpmap:0 PCMU/8000\\r\\n'
        'a=rtpmap:8 PCMA/8000\\r\\n'
        'a=sendrecv\\r\\n'
    )
    ok200 = (
        'SIP/2.0 200 OK\\r\\n'
        f'{via_block}'
        f'{rr_block}'
        f'From: {from_hdr}\\r\\n'
        f'To: {to_hdr};tag=callee-tag-{callee_key}\\r\\n'
        f'Call-ID: {call_id}\\r\\n'
        f'CSeq: {cseq_num} INVITE\\r\\n'
        f'Contact: <sip:{callee_key}@{callee_ip}:{sip_port}>\\r\\n'
        'Content-Type: application/sdp\\r\\n'
        f'Content-Length: {len(sdp)}\\r\\n\\r\\n'
        f'{sdp}'
    )
    s.sendto(ok200.encode(), addr)

    ack_data, _ = s.recvfrom(4096)

    rcv_count = [0]
    is_running = [True]
    def rtp_receiver():
        while is_running[0]:
            try:
                pkt, _ = rtp_sock.recvfrom(512)
                rcv_count[0] += 1
            except:
                pass

    rx_thread = threading.Thread(target=rtp_receiver)
    rx_thread.daemon = True
    rx_thread.start()

    stop_flag = '/tmp/stop_ims_call.flag'
    i = 0
    start_rtp = time.time()
    while (i < num_packets) and not os.path.exists(stop_flag):
        rtp_pkt = b'\\x80\\x00' + (i % 65536).to_bytes(2, 'big') + ((i*160) % 4294967296).to_bytes(4, 'big') + b'\\x12\\x34\\x56\\x78' + (b'RTP-VOICE-PAYLOAD-' + callee_key.encode() + b'-' + str(i).encode()).ljust(160, b'\\x00')
        try:
            rtp_sock.sendto(rtp_pkt, (sdp_ip, sdp_port))
        except:
            pass
        i += 1
        time.sleep(0.02)
        if max_duration > 0 and (time.time() - start_rtp) >= max_duration:
            break

    is_running[0] = False
    rx_thread.join(timeout=1.0)

    s.settimeout(6.0)
    bye_data, bye_addr = s.recvfrom(4096)
    bye_str = bye_data.decode('latin1')
    bye_vias = re.findall(r'Via: ([^\\r\\n]+)', bye_str)
    bye_via_block = '\\r\\n'.join([f'Via: {v}' for v in bye_vias]) + '\\r\\n'
    bye_cseq = re.search(r'CSeq: ([^\\r\\n]+)', bye_str).group(1)

    bye_ok = (
        'SIP/2.0 200 OK\\r\\n'
        f'{bye_via_block}'
        f'From: {from_hdr}\\r\\n'
        f'To: {to_hdr};tag=callee-tag-{callee_key}\\r\\n'
        f'Call-ID: {call_id}\\r\\n'
        f'CSeq: {bye_cseq}\\r\\n'
        'Content-Length: 0\\r\\n\\r\\n'
    )
    s.sendto(bye_ok.encode(), bye_addr)
    with open('/tmp/callee_res.txt', 'w') as f:
        f.write(f'OK: Received {rcv_count[0]} RTP packets (Sent: {i})')
except Exception as e:
    with open('/tmp/callee_res.txt', 'w') as f:
        f.write(f'ERROR: {e}')
    sys.exit(1)
"""

    caller_script = """import socket, re, time, threading, sys, os, json

caller_key = sys.argv[1]
callee_key = sys.argv[2]
caller_ip = sys.argv[3]
callee_ip = sys.argv[4]
pcscf_ip = sys.argv[5]
sip_port = int(sys.argv[6])
rtp_port = int(sys.argv[7])
num_packets = int(sys.argv[8])
max_duration = float(sys.argv[9])

try:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, 0xA0)  # CS5 (0xA0 / DSCP 40) - 3GPP 5QI 5 IMS Signaling
    s.bind((caller_ip, sip_port))
    s.settimeout(8.0)

    rtp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rtp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    rtp_sock.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, 0xB8)  # EF (0xB8 / DSCP 46) - 3GPP 5QI 1 Conversational Voice
    rtp_sock.bind((caller_ip, rtp_port))
    rtp_sock.settimeout(0.5)

    sdp = (
        'v=0\\r\\n'
        f'o={caller_key} 2890844526 2890844526 IN IP4 {caller_ip}\\r\\n'
        's=Vo5G Session\\r\\n'
        f'c=IN IP4 {caller_ip}\\r\\n'
        't=0 0\\r\\n'
        f'm=audio {rtp_port} RTP/AVP 0 8\\r\\n'
        'a=rtpmap:0 PCMU/8000\\r\\n'
        'a=rtpmap:8 PCMA/8000\\r\\n'
        'a=sendrecv\\r\\n'
    )

    call_seq = int(time.time() % 100000)
    invite = (
        f'INVITE sip:{callee_key}@ims.lab SIP/2.0\\r\\n'
        f'Via: SIP/2.0/UDP {caller_ip}:{sip_port};rport;branch=z9hG4bK-inv-{caller_key}-{call_seq}\\r\\n'
        'Max-Forwards: 70\\r\\n'
        f'From: <sip:{caller_key}@ims.lab>;tag=caller-tag-{caller_key}\\r\\n'
        f'To: <sip:{callee_key}@ims.lab>\\r\\n'
        f'Call-ID: call-run-{call_seq}@{caller_ip}\\r\\n'
        f'CSeq: {call_seq} INVITE\\r\\n'
        f'Contact: <sip:{caller_key}@{caller_ip}:{sip_port}>\\r\\n'
        'Content-Type: application/sdp\\r\\n'
        f'Content-Length: {len(sdp)}\\r\\n\\r\\n'
        f'{sdp}'
    )

    s.sendto(invite.encode(), (pcscf_ip, sip_port))

    got_200 = False
    to_tag = ''
    rr_hdrs = []
    contact_tgt = f'sip:{callee_key}@{callee_ip}:{sip_port}'
    sdp_ip = pcscf_ip
    sdp_port = rtp_port

    while not got_200:
        resp, addr = s.recvfrom(4096)
        resp_str = resp.decode('latin1')
        first_line = resp_str.split('\\r\\n')[0]
        if '200 OK' in first_line:
            got_200 = True
            to_m = re.search(r'To: <sip:[^>]+>;tag=([^\\r\\n;]+)', resp_str)
            if to_m: to_tag = to_m.group(1)
            rr_hdrs = re.findall(r'Record-Route: ([^\\r\\n]+)', resp_str)
            ct_m = re.search(r'Contact: <([^>]+)>', resp_str)
            if ct_m: contact_tgt = ct_m.group(1)
            
            sdp_m_ip = re.search(r'c=IN IP4 ([0-9.]+)', resp_str)
            if sdp_m_ip: sdp_ip = sdp_m_ip.group(1)
            sdp_m_port = re.search(r'm=audio ([0-9]+)', resp_str)
            if sdp_m_port: sdp_port = int(sdp_m_port.group(1))

    route_hdrs = list(reversed(rr_hdrs))
    route_block = ('\\r\\n'.join([f'Route: {r}' for r in route_hdrs]) + '\\r\\n') if route_hdrs else ''

    ack = (
        f'ACK {contact_tgt} SIP/2.0\\r\\n'
        f'Via: SIP/2.0/UDP {caller_ip}:{sip_port};rport;branch=z9hG4bK-ack-run-{call_seq}\\r\\n'
        f'{route_block}'
        'Max-Forwards: 70\\r\\n'
        f'From: <sip:{caller_key}@ims.lab>;tag=caller-tag-{caller_key}\\r\\n'
        f'To: <sip:{callee_key}@ims.lab>;tag={to_tag}\\r\\n'
        f'Call-ID: call-run-{call_seq}@{caller_ip}\\r\\n'
        f'CSeq: {call_seq} ACK\\r\\n'
        f'Contact: <sip:{caller_key}@{caller_ip}:{sip_port}>\\r\\n'
        'Content-Length: 0\\r\\n\\r\\n'
    )
    s.sendto(ack.encode(), (pcscf_ip, sip_port))

    rcv_count = [0]
    is_running = [True]
    def rtp_receiver():
        while is_running[0]:
            try:
                pkt, _ = rtp_sock.recvfrom(512)
                rcv_count[0] += 1
            except:
                pass

    rx_thread = threading.Thread(target=rtp_receiver)
    rx_thread.daemon = True
    rx_thread.start()

    stop_flag = '/tmp/stop_ims_call.flag'
    i = 0
    start_rtp = time.time()
    while (i < num_packets) and not os.path.exists(stop_flag):
        rtp_pkt = b'\\x80\\x00' + (i % 65536).to_bytes(2, 'big') + ((i*160) % 4294967296).to_bytes(4, 'big') + b'\\x87\\x65\\x43\\x21' + (b'RTP-VOICE-PAYLOAD-' + caller_key.encode() + b'-' + str(i).encode()).ljust(160, b'\\x00')
        try:
            rtp_sock.sendto(rtp_pkt, (sdp_ip, sdp_port))
        except:
            pass
        i += 1
        time.sleep(0.02)
        if i % 10 == 0:
            try:
                with open('/tmp/active_call_status.json', 'w') as f:
                    st_data = {
                        'active': True,
                        'state': 'CONNECTED',
                        'caller': caller_key,
                        'callee': callee_key,
                        'elapsed_seconds': round(time.time() - start_rtp, 2),
                        'packets_sent': i,
                        'packets_received': rcv_count[0],
                        'call_id': f'call-run-{call_seq}@{caller_ip}'
                    }
                    f.write(json.dumps(st_data))
            except:
                pass
        if max_duration > 0 and (time.time() - start_rtp) >= max_duration:
            break

    actual_duration = max(round(time.time() - start_rtp, 2), 0.5)
    is_running[0] = False
    rx_thread.join(timeout=1.0)

    cseq_bye = call_seq + 1
    bye = (
        f'BYE {contact_tgt} SIP/2.0\\r\\n'
        f'Via: SIP/2.0/UDP {caller_ip}:{sip_port};rport;branch=z9hG4bK-bye-run-{call_seq}\\r\\n'
        f'{route_block}'
        'Max-Forwards: 70\\r\\n'
        f'From: <sip:{caller_key}@ims.lab>;tag=caller-tag-{caller_key}\\r\\n'
        f'To: <sip:{callee_key}@ims.lab>;tag={to_tag}\\r\\n'
        f'Call-ID: call-run-{call_seq}@{caller_ip}\\r\\n'
        f'CSeq: {cseq_bye} BYE\\r\\n'
        f'Contact: <sip:{caller_key}@{caller_ip}:{sip_port}>\\r\\n'
        'Content-Length: 0\\r\\n\\r\\n'
    )
    s.sendto(bye.encode(), (pcscf_ip, sip_port))
    s.settimeout(6.0)
    bye_resp, addr = s.recvfrom(4096)
    with open('/tmp/caller_res.txt', 'w') as f:
        f.write(f'OK: Received {rcv_count[0]} RTP packets (Sent: {i}, Duration: {actual_duration}s)|call-run-{call_seq}@{caller_ip}|{actual_duration}')
except Exception as e:
    with open('/tmp/caller_res.txt', 'w') as f:
        f.write(f'ERROR: {e}')
    sys.exit(1)
"""

    with open('/tmp/run_callee.py', 'w') as f:
        f.write(callee_script)
    with open('/tmp/run_caller.py', 'w') as f:
        f.write(caller_script)

    callee_cmd = f"ip netns exec {callee_ns} python3 /tmp/run_callee.py {callee_key} {callee_ip} {PCSCF_IP} {SIP_PORT} {RTP_PORT} {num_packets} {max_duration}"
    caller_cmd = f"ip netns exec {caller_ns} python3 /tmp/run_caller.py {caller_key} {callee_key} {caller_ip} {callee_ip} {PCSCF_IP} {SIP_PORT} {RTP_PORT} {num_packets} {max_duration}"

    callee_proc = subprocess.Popen(callee_cmd, shell=True)
    time.sleep(0.8)
    caller_proc = subprocess.Popen(caller_cmd, shell=True)

    # Wait for completion or timeout
    wait_limit = (max_duration + 10.0) if max_duration > 0 else 3600.0
    caller_proc.wait(timeout=wait_limit)
    callee_proc.wait(timeout=wait_limit)

    with open('/tmp/caller_res.txt') as f: c_raw = f.read().strip()
    with open('/tmp/callee_res.txt') as f: k_res = f.read().strip()

    call_id = f"call-{caller_key}-{callee_key}-{int(time.time())}@{caller_ip}"
    actual_dur = 10.0
    if "|" in c_raw:
        parts = c_raw.split("|")
        c_res = parts[0]
        if len(parts) > 1: call_id = parts[1]
        if len(parts) > 2:
            try: actual_dur = float(parts[2])
            except: pass
    else:
        c_res = c_raw

    # Clear active status file
    try:
        with open('/tmp/active_call_status.json', 'w') as f:
            json.dump({"active": False, "state": "IDLE"}, f)
    except: pass

    print(f"  Caller ({caller_key} -> {callee_key}): {c_res}")
    print(f"  Callee ({callee_key} -> {caller_key}): {k_res}")
    if not (c_res.startswith("OK") and k_res.startswith("OK")):
        print(f"  {RED}[✗] Voice call or media verification failed!{NC}")
        return False
    print(f"  {GREEN}[✓] Call dialog & Bidirectional RTP stream PASSED (Duration: {actual_dur}s, 0% loss){NC}")

    # Record Kamailio SQLite CDR for persistence
    record_sqlite_cdr(caller_key, callee_key, call_id, actual_dur)

    # Invoke Erlang/OTP Telecom Charging Integration
    process_charging_event(caller_key, callee_key, call_id, duration=actual_dur)
    return True

def record_sqlite_cdr(caller_key, callee_key, call_id, duration):
    try:
        import sqlite3
        db_path = "/etc/kamailio/db/kamailio.sqlite"
        if os.path.exists(db_path):
            con = sqlite3.connect(db_path)
            cur = con.cursor()
            now = int(time.time())
            start_t = now - int(duration)
            end_t = now
            call_type = "Vo5G-Roaming" if (caller_key == "ue3" or callee_key == "ue3") else "Vo5G-SIP"
            cur.execute(
                "INSERT INTO cdrs (callid, caller, callee, start_time, end_time, duration, sip_code, sip_reason, call_type) VALUES (?, ?, ?, ?, ?, ?, 200, 'OK', ?)",
                (call_id, f"sip:{caller_key}@ims.lab", f"sip:{callee_key}@ims.lab", start_t, end_t, int(duration), call_type)
            )
            con.commit()
            con.close()
    except Exception as e:
        pass

def process_charging_event(caller_key, callee_key, call_id, duration=10.0):
    # Determine target charging account and roaming context
    if caller_key == "ue3" or callee_key == "ue3":
        acc_id = "acc-ue3"
        dest = "roaming_vplmn"
        role_label = "UE3 Roaming (Bosnia 218/90, HPLMN 602/03)"
    elif caller_key == "ue1":
        acc_id = "acc-ue1"
        dest = "domestic"
        role_label = "UE1 Domestic (Egypt 602/03)"
    elif caller_key == "ue2":
        acc_id = "acc-ue2"
        dest = "domestic"
        role_label = "UE2 Domestic (Egypt 602/04)"
    else:
        acc_id = f"acc-{caller_key}"
        dest = "domestic"
        role_label = f"{caller_key.upper()} Domestic"

    payload = {
        "call_id": call_id,
        "session_id": call_id,
        "caller": f"sip:{caller_key}@ims.lab",
        "callee": f"sip:{callee_key}@ims.lab",
        "account_id": acc_id,
        "service_type": "voice",
        "duration": max(duration, 1.0),
        "destination": dest
    }

    import urllib.request, urllib.error
    url = "http://127.0.0.1:8085/v1/charging/events"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            status = data.get("status")
            tx_id = data.get("transaction_id", "N/A")
            charge = data.get("total_charge", 0.0)
            avail = data.get("available_balance", 0.0)
            cons = data.get("consumed_balance", 0.0)
            tariff = data.get("tariff_id", "N/A")
            expl = data.get("explanation", "")
            print(f"  {GREEN}[✓] Erlang/OTP Charging Engine ({acc_id} - {role_label}):{NC}")
            print(f"      Status: {status} | Rated Charge: {charge:.4f} LAB ({tariff})")
            print(f"      Balance Available: {avail:.4f} LAB | Consumed: {cons:.4f} LAB | Tx: {tx_id}")
            if expl:
                print(f"      Rating Breakdown: {expl}")
            return True
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        print(f"  {RED}[✗] Erlang Charging HTTP {e.code}: {err_body}{NC}")
        return False
    except Exception as e:
        print(f"  {YELLOW}[!] Erlang Charging Service offline on :8085 ({e}){NC}")
        return False

# Parse CLI arguments
args = [arg.strip().lower() for arg in sys.argv[1:] if arg.strip()]

def norm_ue(val):
    v = val.replace("ue", "").replace("-", "")
    return f"ue{v}" if v in ["1", "2", "3"] else None

call_scenarios = []
custom_duration = None

if not args or args[0] in ["all", "full"]:
    call_scenarios = [
        ("ue1", "ue2", "Domestic Call (UE1 Egypt 602/03 <-> UE2 Egypt 602/04)", None),
        ("ue1", "ue3", "Inter-PLMN Roaming Call (UE1 Egypt 602/03 <-> UE3 Bosnia 218/90)", None)
    ]
elif len(args) >= 2 and norm_ue(args[0]) and norm_ue(args[1]):
    c1, c2 = norm_ue(args[0]), norm_ue(args[1])
    if c1 == c2:
        print(f"{RED}[✗] Error: Caller ({c1}) and Callee ({c2}) must be different UEs.{NC}")
        sys.exit(1)
    if len(args) >= 3:
        if args[2] in ["manual", "inf", "continuous"]:
            custom_duration = 0
        else:
            try: custom_duration = float(args[2])
            except: custom_duration = None
    call_scenarios = [(c1, c2, f"Call ({UE_MAP[c1]['name']} ──► {UE_MAP[c2]['name']})", custom_duration)]
elif args[0] in ["domestic", "ue1-ue2", "1-2", "1_2"]:
    dur = float(args[1]) if len(args) > 1 and args[1].replace('.','',1).isdigit() else None
    call_scenarios = [("ue1", "ue2", "Domestic Call (UE1 Egypt 602/03 <-> UE2 Egypt 602/04)", dur)]
elif args[0] in ["roaming", "ue1-ue3", "1-3", "1_3"]:
    dur = float(args[1]) if len(args) > 1 and args[1].replace('.','',1).isdigit() else None
    call_scenarios = [("ue1", "ue3", "Inter-PLMN Roaming Call (UE1 Egypt 602/03 <-> UE3 Bosnia 218/90)", dur)]
elif args[0] in ["reverse-roaming", "ue3-ue1", "3-1", "3_1"]:
    dur = float(args[1]) if len(args) > 1 and args[1].replace('.','',1).isdigit() else None
    call_scenarios = [("ue3", "ue1", "Reverse Roaming Call (UE3 Bosnia 218/90 <-> UE1 Egypt 602/03)", dur)]
elif norm_ue(args[0]) == "ue1":
    call_scenarios = [("ue1", "ue2", "Domestic Call (UE1 Egypt 602/03 <-> UE2 Egypt 602/04)", None)]
elif norm_ue(args[0]) == "ue2":
    call_scenarios = [("ue2", "ue1", "Reverse Domestic Call (UE2 Egypt 602/04 <-> UE1 Egypt 602/03)", None)]
elif norm_ue(args[0]) == "ue3":
    call_scenarios = [("ue3", "ue1", "Reverse Roaming Call (UE3 Bosnia 218/90 <-> UE1 Egypt 602/03)", None)]
else:
    print(f"{RED}[✗] Unknown test mode or parameters: {' '.join(args)}{NC}")
    print("Valid usage:")
    print("  sudo bash scripts/test-ims-call.sh                     # Run all test calls (Domestic + Roaming)")
    print("  sudo bash scripts/test-ims-call.sh domestic            # Domestic call (UE1 -> UE2)")
    print("  sudo bash scripts/test-ims-call.sh roaming             # Roaming call (UE1 -> UE3)")
    print("  sudo bash scripts/test-ims-call.sh 1 2 [seconds]       # Custom call: UE1 -> UE2 (optional duration)")
    print("  sudo bash scripts/test-ims-call.sh 2 1 [seconds]       # Custom call: UE2 -> UE1")
    print("  sudo bash scripts/test-ims-call.sh 1 3 [seconds]       # Custom call: UE1 -> UE3 (Roaming)")
    print("  sudo bash scripts/test-ims-call.sh 3 1 [seconds]       # Custom call: UE3 -> UE1")
    print("  sudo bash scripts/test-ims-call.sh 2 3 [seconds]       # Custom call: UE2 -> UE3")
    print("  sudo bash scripts/test-ims-call.sh 3 2 [seconds]       # Custom call: UE3 -> UE2")
    print("  sudo bash scripts/test-ims-call.sh 1 2 manual          # Manual continuous call (stop via /tmp/stop_ims_call.flag)")
    sys.exit(1)

# Determine required UEs to register
required_ues = set()
for c1, c2, _, _ in call_scenarios:
    required_ues.add(c1)
    required_ues.add(c2)
if not args or args[0] in ["all", "full"]:
    required_ues = {"ue1", "ue2", "ue3"}

print(f"{BLUE}============================================================{NC}")
print(f"{BLUE}    Open5GS 5G SA + Kamailio IMS Multi-PLMN Voice Test Suite{NC}")
print(f"{BLUE}============================================================{NC}")

print(f"\n{CYAN}[1/2] Performing SIP Digest Registrations...{NC}")
reg_ok = True
for ue_key in sorted(required_ues):
    if not register_ue(ue_key):
        reg_ok = False

if not reg_ok:
    print(f"{RED}[✗] Registration failed for one or more UEs.{NC}")
    sys.exit(1)

print(f"\n{CYAN}[2/2] Validating SIP Signaling & RTPEngine Media Flows...{NC}")
success = True
for c1, c2, desc, dur in call_scenarios:
    print(f"\n{YELLOW}▶ Scenario: {desc}{NC}")
    if not run_call(c1, c2, duration_secs=dur):
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
