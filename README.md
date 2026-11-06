# DevOps Take-Home - Enterprise Bot

## Prerequisites

- Docker
- kind
- kubectl
- helm

## How to run

```bash
# Deploy everything (idempotent - safe to run multiple times)
./setup.sh

# Verify the service is working
kubectl get pods -n demo
curl -H "Host: demo.local" http://localhost/
curl -H "Host: demo.local" http://localhost/healthz
```

If the ingress isn't reachable on localhost, port-forward instead:

```bash
kubectl port-forward -n demo svc/demo 8080:8080
curl http://localhost:8080/
curl http://localhost:8080/healthz
```

## Running the debug lab (Part 4)

```bash
cd lab
./scenario.sh up        # install broken chart
# investigate and fix lab/broken-chart/
./scenario.sh up        # re-apply fixes
./scenario.sh verify    # check - all green means done
```

## Resource requests and limits - rationale

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 50m | 200m |
| Memory | 64Mi | 128Mi |

- **50m CPU request**: the service is a lightweight HTTP server with no compute-heavy work. 50m gives it scheduling priority without reserving resources it won't use.
- **200m CPU limit**: allows brief bursts during startup or under load without letting a runaway process starve neighbors.
- **64Mi memory request / 128Mi limit**: Python's stdlib HTTP server has a small footprint. 64Mi covers steady-state; 128Mi gives headroom for connection spikes without risking OOM under normal conditions.

These are deliberately conservative - right for a take-home, not for production load testing.

## What I deliberately skipped (and the risk)

- **No TLS on the Ingress** - traffic between client and cluster is unencrypted. In production, cert-manager + a ClusterIssuer would terminate TLS at the Ingress.
- **No network policies** - any pod can talk to any pod. A production setup should restrict traffic to only what's needed.
- **No pod disruption budgets** - rolling updates could take all replicas down simultaneously. PDBs would prevent that.
- **No horizontal pod autoscaler** - fixed at 2 replicas. HPA with CPU/memory targets would handle variable load.
- **No image scanning in CI** - the Dockerfile is not scanned for vulnerabilities before deploy.
- **No secrets management** - env vars are in a ConfigMap, not a Secret. Fine for APP_NAME/VERSION, but any real credentials should use Secrets or an external vault.

## What I would change for production

- Add TLS termination with cert-manager
- Set up HPA and PDB
- Add network policies to restrict pod-to-pod traffic
- Use a private container registry with image scanning
- Add Prometheus annotations/ServiceMonitor for observability
- Run the image as a distroless base for smaller attack surface
- Add CI/CD pipeline with lint, build, scan, deploy stages
- Pin the ingress-nginx version in setup.sh to a known-good release

## How I used AI

I used Claude (Claude Code CLI) to help with:
- Generating the initial Python HTTP service and Dockerfile boilerplate
- Scaffolding the Helm chart templates
- Reviewing the broken chart to identify defects from code analysis
- Drafting the Gateway API migration answer

I used Claude Code CLI to assist with code generation, debugging, and writing. I reviewed all outputs, directed the approach, and made manual adjustments.
