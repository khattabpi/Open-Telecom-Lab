#!/usr/bin/env bash
#
# start-lab.sh — bring up the Open5GS-on-kind lab for local UERANSIM.
#
# Steps:
#   1. Stop any native Open5GS systemd services (they conflict on ports/SCTP).
#   2. Ensure the kind control-plane container is running and pinned to a
#      stable IP on the kind docker network (so gNB/UE configs stay valid).
#   3. Wait for every pod in the open5gs namespace to be Running.
#   4. Print status when the core is ready.
#
set -euo pipefail

# --- Config -----------------------------------------------------------------
CLUSTER_NAME="open5gs-cluster"
NODE_CONTAINER="${CLUSTER_NAME}-control-plane"
KIND_NETWORK="kind"
NODE_IP="172.19.0.2"
NAMESPACE="open5gs"
POD_WAIT_TIMEOUT="180s"

log()  { printf '\033[1;34m[start-lab]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[start-lab]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[start-lab]\033[0m %s\n' "$*" >&2; }

# --- 1. Stop native Open5GS systemd services -------------------------------
stop_native_open5gs() {
  log "Stopping native Open5GS systemd services (open5gs-*) ..."
  # List installed open5gs units; stop any that are active.
  local units
  units=$(systemctl list-units 'open5gs-*' --all --no-legend 2>/dev/null | awk '{print $1}') || true
  if [[ -z "${units}" ]]; then
    log "No native open5gs-* units found; nothing to stop."
    return 0
  fi
  # sudo only if not already root.
  local SUDO=""
  [[ "${EUID}" -ne 0 ]] && SUDO="sudo"
  ${SUDO} systemctl stop 'open5gs-*' 2>/dev/null || true
  log "Native Open5GS services stopped."
}

# --- 2. Ensure kind node is running and pinned to NODE_IP -------------------
ensure_node_ip() {
  local current_ip
  current_ip=$(docker inspect -f \
    "{{ (index .NetworkSettings.Networks \"${KIND_NETWORK}\").IPAddress }}" \
    "${NODE_CONTAINER}" 2>/dev/null || echo "")

  if [[ "${current_ip}" == "${NODE_IP}" ]]; then
    log "Node ${NODE_CONTAINER} already on ${KIND_NETWORK} at ${NODE_IP}."
    return 0
  fi

  warn "Node IP is '${current_ip:-none}', expected ${NODE_IP}. Re-pinning ..."
  docker network disconnect "${KIND_NETWORK}" "${NODE_CONTAINER}" 2>/dev/null || true
  docker network connect --ip "${NODE_IP}" "${KIND_NETWORK}" "${NODE_CONTAINER}"
  log "Reconnected ${NODE_CONTAINER} to ${KIND_NETWORK} with --ip ${NODE_IP}."
}

start_node() {
  if ! docker inspect "${NODE_CONTAINER}" >/dev/null 2>&1; then
    err "Container ${NODE_CONTAINER} does not exist. Create the cluster first:"
    err "  kind create cluster --config k8s/kind-config.yaml"
    exit 1
  fi

  local state
  state=$(docker inspect -f '{{.State.Running}}' "${NODE_CONTAINER}" 2>/dev/null || echo "false")

  if [[ "${state}" == "true" ]]; then
    log "Container ${NODE_CONTAINER} is running."
    ensure_node_ip
  else
    warn "Container ${NODE_CONTAINER} is not running."
    # If it is stopped with the wrong network config, fix the network while
    # stopped, then start. docker network (dis)connect works on stopped
    # containers, so re-pin first for a clean start.
    ensure_node_ip
    log "Starting ${NODE_CONTAINER} ..."
    docker start "${NODE_CONTAINER}" >/dev/null
    # Give kubelet/apiserver a moment to come back after a cold start.
    log "Waiting for Kubernetes API to respond ..."
    local i
    for i in $(seq 1 30); do
      if kubectl get --raw='/readyz' >/dev/null 2>&1; then
        log "Kubernetes API is ready."
        break
      fi
      sleep 2
    done
  fi
}

# --- 3. Wait for pods -------------------------------------------------------
wait_for_pods() {
  log "Waiting for pods in namespace '${NAMESPACE}' to be Ready (timeout ${POD_WAIT_TIMEOUT}) ..."
  if ! kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
    err "Namespace '${NAMESPACE}' not found. Apply manifests first (kubectl apply -f k8s/)."
    exit 1
  fi
  # Wait for all pods to reach Ready. --all matches every pod in the ns.
  if kubectl wait --for=condition=Ready pods --all \
      -n "${NAMESPACE}" --timeout="${POD_WAIT_TIMEOUT}"; then
    log "All pods are Ready."
  else
    warn "Not all pods became Ready within ${POD_WAIT_TIMEOUT}. Current state:"
    kubectl get pods -n "${NAMESPACE}" -o wide || true
    exit 1
  fi
}

# --- 4. Status --------------------------------------------------------------
print_status() {
  echo
  log "=== Lab is ready ==="
  kubectl get pods -n "${NAMESPACE}" -o wide
  echo
  log "Node IP (AMF/UPF reachable here): ${NODE_IP}"
  log "AMF NGAP (SCTP): ${NODE_IP}:38412"
  log "Next: run the gNB and UE from the host, e.g."
  echo "    ./UERANSIM/build/nr-gnb -c ./UERANSIM/config/open5gs-gnb.yaml"
  echo "    sudo ./UERANSIM/build/nr-ue  -c ./UERANSIM/config/open5gs-ue.yaml"
}

main() {
  stop_native_open5gs
  start_node
  wait_for_pods
  print_status
}

main "$@"
