#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="demo"
NAMESPACE="demo"
RELEASE="demo"
IMAGE_NAME="demo-service"
IMAGE_TAG="latest"

echo "==> Checking kind cluster '${CLUSTER_NAME}'..."
if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --name "${CLUSTER_NAME}" --wait 60s
else
  echo "    Cluster already exists, reusing."
fi

echo "==> Setting kubectl context..."
kubectl cluster-info --context "kind-${CLUSTER_NAME}" > /dev/null

echo "==> Installing ingress-nginx..."
if ! kubectl get ns ingress-nginx &>/dev/null; then
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/kind/deploy.yaml
  echo "    Waiting for ingress-nginx to be ready..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s
else
  echo "    ingress-nginx already installed."
fi

echo "==> Building docker image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" service/

echo "==> Loading image into kind cluster..."
kind load docker-image "${IMAGE_NAME}:${IMAGE_TAG}" --name "${CLUSTER_NAME}"

echo "==> Creating namespace '${NAMESPACE}' if needed..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing/upgrading helm release '${RELEASE}'..."
helm upgrade --install "${RELEASE}" chart/ \
  --namespace "${NAMESPACE}" \
  --set image.repository="${IMAGE_NAME}" \
  --set image.tag="${IMAGE_TAG}" \
  --wait --timeout 120s

echo "==> Done. Verifying pods..."
kubectl get pods -n "${NAMESPACE}"
