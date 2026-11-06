# Answers

## Q1. Migrating ~40 Ingress objects from ingress-nginx (EOL) to Kubernetes Gateway API with no downtime

### Approach

- **Phase 1 — Prepare:** Install Gateway API CRDs and a supported controller (e.g., Envoy Gateway or the nginx Gateway API implementation) alongside the existing ingress-nginx. Both run in parallel, no traffic shift yet. Validate the new controller is healthy in a staging environment first.

- **Phase 2 — Translate and test:** Convert each Ingress manifest to the equivalent Gateway + HTTPRoute resources. Automate this with a tool like `ingress2gateway` where possible, then review diffs manually — annotation-based behaviors (rate limiting, rewrites, auth snippets) rarely translate 1:1 and are the main breakage risk. Deploy the HTTPRoutes pointing at the same backend Services, but behind a separate Gateway listener (e.g., on a different port or internal-only LB) so they can be tested without affecting production traffic.

- **Phase 3 — Incremental cutover:** Migrate traffic one route at a time (or in small batches). Update external DNS / load-balancer targets to point at the new Gateway. Keep the old Ingress objects live as a fallback — if something breaks, DNS can flip back. Monitor error rates and latency at each step.

- **Phase 4 — Cleanup:** Once all routes are confirmed on the Gateway API and the old controller sees zero traffic, remove the Ingress objects and decommission ingress-nginx.

### What I expect to break

- Custom nginx annotations (snippets, `server-snippet`, `configuration-snippet`) have no Gateway API equivalent and need to be re-implemented as Gateway policies or EnvoyFilter-style extensions.
- TLS termination config may behave differently — cert-manager integration, wildcard certs, and redirect rules need explicit testing.
- Any tooling that reads or writes Ingress objects (CI/CD pipelines, IaC, monitoring dashboards) needs updating.
- Backend services using `externalTrafficPolicy: Local` may see client IP changes if the new controller routes differently.
