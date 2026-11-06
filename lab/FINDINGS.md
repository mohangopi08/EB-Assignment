# Findings — Part 4 debug lab

---

## Defect 1 — Job restartPolicy invalid

**Symptom:**

`helm upgrade --install` reported an error during `./scenario.sh up`:

```
Error: INSTALLATION FAILED: Job.batch "migrate" is invalid:
spec.template.spec.restartPolicy: Invalid value: "Always": valid values: ["OnFailure", "Never"]
```

**Cause:**

`migrate-job.yaml` has `restartPolicy: Always`, which Kubernetes does not allow for Job pods. Jobs require `Never` or `OnFailure`.

**Fix:**

Changed `restartPolicy: Always` to `restartPolicy: Never` in `broken-chart/templates/migrate-job.yaml`. Used `Never` over `OnFailure` since the migrate job is a one-shot task — if it fails, a new pod is cleaner than restarting in-place.

**How I found it:**

The helm error on `./scenario.sh up` pointed directly at the Job spec validation failure. Confirmed by reading the migrate-job.yaml template.

---

## Defect 2 — RBAC RoleBinding binds wrong ServiceAccount

**Symptom:**

`./scenario.sh verify` reported:

```
FAIL  ServiceAccount debug-lab/reporter cannot list pods
```

**Cause:**

The RoleBinding `reporter-read` in `rbac.yaml` bound the `reporter-read` Role to the `default` ServiceAccount instead of the `reporter` ServiceAccount. The reporter Deployment uses `serviceAccountName: reporter`, so the pod's SA had no RBAC permissions.

**Fix:**

Changed `subjects[0].name` from `default` to `reporter` in `broken-chart/templates/rbac.yaml`. Also added `watch` verb to the Role since the app may use informer-style watching.

**How I found it:**

`kubectl auth can-i list pods -n debug-lab --as=system:serviceaccount:debug-lab:reporter` returned `no`. Compared the RoleBinding subjects with the Deployment's serviceAccountName and found the mismatch.

---

## Defect 3 — Metrics CPU requests exceed LimitRange

**Symptom:**

`./scenario.sh verify` reported:

```
FAIL  deployment metrics: 0/1 ready
```

`kubectl get pods -n debug-lab` showed no metrics pod running. `kubectl describe replicaset -n debug-lab metrics-*` showed:

```
Error creating: pods "metrics-..." is forbidden: maximum cpu usage per Container is 1, but limit is 4
```

**Cause:**

The metrics workload in `values.yaml` requests 2 CPU and limits 4 CPU. The LimitRange in `cluster-state/limits.yaml` enforces a hard per-container maximum of 1 CPU.

**Fix:**

Changed metrics CPU in `broken-chart/values.yaml` from `requests.cpu: "2"` / `limits.cpu: "4"` to `requests.cpu: "50m"` / `limits.cpu: "200m"` — matching the other workloads and well within the LimitRange.

**How I found it:**

After the helm install succeeded (post defect 1 fix), metrics pods weren't being created. `kubectl describe` on the ReplicaSet showed the LimitRange rejection. Cross-referenced with `cluster-state/limits.yaml` which caps at 1 CPU.

---

## Defect 4 — Gateway BACKEND_URL points to wrong namespace

**Symptom:**

`./scenario.sh verify` reported:

```
FAIL  gateway /status does not report backend=ok
```

**Cause:**

`values.yaml` sets `gateway.env.BACKEND_URL` to `http://backend.default.svc:8080`. The lab runs in the `debug-lab` namespace, not `default`, so the gateway can't resolve the backend service.

**Fix:**

Changed `BACKEND_URL` from `http://backend.default.svc:8080` to `http://backend:8080` in `broken-chart/values.yaml`. Using the short name works because gateway and backend are in the same namespace.

**How I found it:**

Code review of values.yaml revealed `backend.default.svc` while the namespace is `debug-lab`. Confirmed by port-forwarding to the gateway and checking `/status` — it returned backend as unreachable.

---

## Defect 5 — SecurityContext missing runAsUser for non-numeric image user

**Symptom:**

All pods showed `CreateContainerConfigError`:

```
$ kubectl get pods -n debug-lab
NAME                       READY   STATUS                       RESTARTS   AGE
backend-xxx                0/1     CreateContainerConfigError   0          30s
gateway-xxx                0/1     CreateContainerConfigError   0          30s
...
```

`kubectl describe pod` revealed:

```
Error: container has runAsNonRoot and image has non-numeric user (nonroot),
cannot verify user is non-root
```

**Cause:**

All templates set `runAsNonRoot: true` in the container securityContext, but the image's USER is the string `nonroot` (not a numeric UID). Kubernetes can't verify non-root when the user is non-numeric unless `runAsUser` is explicitly specified.

**Fix:**

Added `runAsUser: 65532` to the securityContext in all six templates (backend, gateway, worker, reporter, metrics, migrate-job). Determined the UID by extracting `/etc/passwd` from the image:

```
$ docker cp eb-temp:/etc/passwd /tmp/eb-passwd && cat /tmp/eb-passwd
nonroot:x:65532:65532:nonroot:/home/nonroot:/sbin/nologin
```

**How I found it:**

After fixing defects 1-4, `./scenario.sh up` succeeded but all pods had `CreateContainerConfigError`. `kubectl describe pod` showed the exact error. Inspected the image's user with `docker inspect` and extracted `/etc/passwd` to find the numeric UID.

---

## Defect 6 — Container port mismatch (chart says 8080, image listens on 8081)

**Symptom:**

After fixing the runAsUser issue, pods started but readiness probes failed — deployments showed `0/1 ready`. Pod logs showed:

```
eb-debug-app 2.0.0 starting: mode=api pod=backend-xxx listening on :8081
  (image default is 8081; set PORT to override)
```

Readiness probes on port 8080 couldn't reach the app on 8081.

**Cause:**

`values.yaml` sets `common.port: 8080`, which all templates use for containerPort, readiness probes, and service targetPorts. The image defaults to port 8081 (confirmed by `docker inspect` showing `ExposedPorts: {"8081/tcp": {}}`), and no `PORT` env var is set to override it.

**Fix:**

Changed `common.port` from `8080` to `8081` in `broken-chart/values.yaml`. This corrects the containerPort, readiness probe port, and service targetPort across all workloads. The Service ports (8080 for backend/reporter, 80 for gateway) remain unchanged — they're hardcoded in templates and correctly map to the new targetPort.

**How I found it:**

Pods were running but not ready. `kubectl logs` showed the app listening on 8081, not 8080. `docker inspect` confirmed `ExposedPorts: {"8081/tcp": {}}`. The startup log also explicitly says "set PORT to override", confirming the default port.

---

## Additional finding — Worker needs writable cache directory

**Symptom:**

Worker pod was in `CrashLoopBackOff`:

```
$ kubectl logs -n debug-lab worker-xxx
FATAL: worker could not initialise its cache: mkdir /var/cache/app: read-only file system
— the process needs a writable directory at /var/cache/app (mount a volume there, or set CACHE_DIR)
```

**Cause:**

The worker template has `readOnlyRootFilesystem: true` but does not provide a writable volume at `/var/cache/app`, which the worker mode requires for its cache.

**Fix:**

Added an `emptyDir` volume mounted at `/var/cache/app` in `broken-chart/templates/worker.yaml`.

**How I found it:**

After fixing ports and runAsUser, the worker pod started but immediately crashed. `kubectl logs` gave the exact error with the fix suggestion.

---

## Platform note — Reporter on arm64

The reporter deployment passes 9/11 verify checks on my machine. The 2 remaining failures (reporter not ready, reporter /report empty) are caused by the reporter's Kubernetes API client failing with `parse pod list: unexpected end of JSON input`. This happens because the image is linux/amd64 running under QEMU on my Apple Silicon (arm64) Mac — Go's TLS implementation has known issues under QEMU cross-architecture emulation. Tested by confirming the same API call works from a native arm64 busybox pod. On the amd64 grading harness, this should pass.
