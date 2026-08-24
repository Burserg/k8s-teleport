#!/usr/bin/env bash
#
# Issue a Kubernetes client certificate through the CSR API and assemble a
# kubeconfig for it.
#
#   ./make-user.sh alice app-devs
#
# Run as an admin. Produces ./out/<user>/<user>.kubeconfig. Do not commit these.
#
# Kubernetes has no User object. The identity lives entirely in the
# certificate: CN becomes the username, O becomes the group. The cluster
# learns of the user through a Role or RoleBinding.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  make-user.sh [options] <username> <group> [api-server-url]
  make-user.sh -u <username> -g <group> [options]

Issue a short-lived client certificate via the Kubernetes CSR API and write
a ready-to-use kubeconfig for that identity.

Arguments (positional form, kept for the Makefile):
  <username>            Certificate CN — becomes the Kubernetes username.
  <group>               Certificate O — becomes the Kubernetes group; RBAC
                        bindings in this lab target the group, not the user.
  [api-server-url]      API server for the generated kubeconfig.
                        Default: the server of your current kubectl context.

Options (override positionals if both are given):
  -u, --user NAME       Username (CN).
  -g, --group NAME      Group (O).
  -s, --server URL      API server URL for the kubeconfig.
  -t, --tls-server-name NAME
                        TLS server name for the kubeconfig. Use the control
                        plane's certificate SAN when URL is an SSH tunnel.
  -e, --expiration SEC  Requested certificate lifetime in seconds.
                        Default: 86400 (24h), or $EXPIRATION_SECONDS if set.
                        This is a REQUEST; the signer may cap it.
  -n, --namespace NS    Default namespace in the kubeconfig context.
                        Default: cheesecake.
  -o, --out-dir DIR     Where to write key/cert/kubeconfig.
                        Default: ./out/<user> next to this script.
  -h, --help            Show this help and exit.

Examples:
  ./make-user.sh alice app-devs
  ./make-user.sh -u bob -g app-devs -e 3600
  ./make-user.sh --user carol --group platform-admins \
      --server https://ctrl-01.lab.local:6443 --namespace gateway-infra

Notes:
  - Run with admin credentials: approving a CSR mints a cluster identity.
  - Kubernetes has no certificate revocation; the short lifetime is the
    mitigation for a leaked credential.
  - The private key never leaves this machine. In a real workflow the user
    generates the key and sends only the CSR.
EOF
}

die() {
  echo "ERROR: $*" >&2
  echo >&2
  usage >&2
  exit 1
}

USER_NAME=""
GROUP=""
API_SERVER=""
TLS_SERVER_NAME="${TLS_SERVER_NAME:-}"
NAMESPACE="cheesecake"
OUT=""

# Short lived. Requests 24 hours. Leaked certificate is valid until it expires.
# the only real revocation is rotating the cluster CA, not ideal.
EXPIRATION_SECONDS="${EXPIRATION_SECONDS:-86400}"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user)       USER_NAME="${2:?$1 requires a value}"; shift 2 ;;
    -g|--group)      GROUP="${2:?$1 requires a value}"; shift 2 ;;
    -s|--server)     API_SERVER="${2:?$1 requires a value}"; shift 2 ;;
    -t|--tls-server-name) TLS_SERVER_NAME="${2:?$1 requires a value}"; shift 2 ;;
    -e|--expiration) EXPIRATION_SECONDS="${2:?$1 requires a value}"; shift 2 ;;
    -n|--namespace)  NAMESPACE="${2:?$1 requires a value}"; shift 2 ;;
    -o|--out-dir)    OUT="${2:?$1 requires a value}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    --)              shift; POSITIONAL+=("$@"); break ;;
    -*)              die "unknown option: $1" ;;
    *)               POSITIONAL+=("$1"); shift ;;
  esac
done

# Positional form: <username> <group> [api-server-url]. Flags win when both
# are supplied.
[[ -z "${USER_NAME}" && ${#POSITIONAL[@]} -ge 1 ]] && USER_NAME="${POSITIONAL[0]}"
[[ -z "${GROUP}"     && ${#POSITIONAL[@]} -ge 2 ]] && GROUP="${POSITIONAL[1]}"
[[ -z "${API_SERVER}" && ${#POSITIONAL[@]} -ge 3 ]] && API_SERVER="${POSITIONAL[2]}"
[[ ${#POSITIONAL[@]} -gt 3 ]] && die "too many positional arguments"

[[ -n "${USER_NAME}" ]] || die "username is required (-u/--user or first positional)"
[[ -n "${GROUP}" ]]     || die "group is required (-g/--group or second positional)"
[[ "${EXPIRATION_SECONDS}" =~ ^[0-9]+$ ]] || die "--expiration must be an integer number of seconds"

if [[ -z "${API_SERVER}" ]]; then
  API_SERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
  [[ -n "${API_SERVER}" ]] || die "could not determine the API server from the current context; pass -s/--server"
fi

OUT="${OUT:-$(dirname "$0")/out/${USER_NAME}}"
mkdir -p "$OUT"
chmod 700 "$OUT"

echo "==> Generating a private key for ${USER_NAME}"
# The key never leaves this machine. In a real workflow the user generates it
# themselves and sends only the CSR, so the admin never possesses it.
openssl genrsa -out "${OUT}/${USER_NAME}.key" 2048
chmod 600 "${OUT}/${USER_NAME}.key"

echo "==> Generating a CSR with CN=${USER_NAME}, O=${GROUP}"
openssl req -new \
  -key "${OUT}/${USER_NAME}.key" \
  -out "${OUT}/${USER_NAME}.csr" \
  -subj "/CN=${USER_NAME}/O=${GROUP}"

echo "==> Submitting the CertificateSigningRequest"
# Delete any prior CSR with the same name.
kubectl delete csr "${USER_NAME}" --ignore-not-found >/dev/null

cat <<YAML | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER_NAME}
spec:
  request: $(base64 -w0 < "${OUT}/${USER_NAME}.csr")
  # This signer produces certificates the API server accepts for client auth.
  # kubernetes.io/kubelet-serving and /kube-apiserver-client-kubelet are for
  # node identities and will NOT work for a human user.
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: ${EXPIRATION_SECONDS}
  usages:
    - client auth
YAML

echo "==> Approving"
# Treat certificatesigningrequests/approval as an identity-issuing privilege.
kubectl certificate approve "${USER_NAME}"

echo "==> Waiting for the signed certificate"
for _ in $(seq 1 30); do
  CERT="$(kubectl get csr "${USER_NAME}" -o jsonpath='{.status.certificate}' 2>/dev/null || true)"
  [[ -n "${CERT}" ]] && break
  sleep 1
done

if [[ -z "${CERT:-}" ]]; then
  echo "ERROR: no certificate issued. Check: kubectl describe csr ${USER_NAME}" >&2
  echo "If the cluster uses an external signer, the CSR stays Pending until that signer acts." >&2
  exit 1
fi

echo "${CERT}" | base64 -d > "${OUT}/${USER_NAME}.crt"

echo "==> Assembling kubeconfig"
kubectl config view --raw --minify --flatten \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > "${OUT}/ca.crt"

KUBECONFIG_OUT="${OUT}/${USER_NAME}.kubeconfig"

TLS_SERVER_NAME_ARGS=()
if [[ -n "${TLS_SERVER_NAME}" ]]; then
  TLS_SERVER_NAME_ARGS=(--tls-server-name "${TLS_SERVER_NAME}")
fi

kubectl --kubeconfig="${KUBECONFIG_OUT}" config set-cluster lab \
  --server="${API_SERVER}" \
  --certificate-authority="${OUT}/ca.crt" \
  --embed-certs=true \
  "${TLS_SERVER_NAME_ARGS[@]}"

kubectl --kubeconfig="${KUBECONFIG_OUT}" config set-credentials "${USER_NAME}" \
  --client-certificate="${OUT}/${USER_NAME}.crt" \
  --client-key="${OUT}/${USER_NAME}.key" \
  --embed-certs=true

kubectl --kubeconfig="${KUBECONFIG_OUT}" config set-context "${USER_NAME}" \
  --cluster=lab \
  --user="${USER_NAME}" \
  --namespace="${NAMESPACE}"

kubectl --kubeconfig="${KUBECONFIG_OUT}" config use-context "${USER_NAME}"
chmod 600 "${KUBECONFIG_OUT}"

echo
echo "Wrote ${KUBECONFIG_OUT}"
echo "Valid for ${EXPIRATION_SECONDS}s. Verify with:"
echo
echo "  KUBECONFIG=${KUBECONFIG_OUT} kubectl auth whoami"
echo "  KUBECONFIG=${KUBECONFIG_OUT} kubectl auth can-i create deployments -n ${NAMESPACE}   # yes"
echo "  KUBECONFIG=${KUBECONFIG_OUT} kubectl auth can-i list nodes                          # no"
echo
