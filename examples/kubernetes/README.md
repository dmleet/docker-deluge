# Kubernetes example manifests

Reference Kustomize overlay for running this image as a multi-replica
StatefulSet with `readOnlyRootFilesystem: true`, per-pod BitTorrent listen
ports, and per-pod LoadBalancer Services.

These manifests are **examples**, not a packaged Helm chart. Copy them into
your own cluster config and adjust storage classes, NFS server addresses,
LoadBalancer IPs, replica counts, and image tags to match your environment.

## Layout

| File | Purpose |
|---|---|
| `namespace.yaml` | The `deluge` namespace. |
| `statefulset.yaml` | StatefulSet with read-only root FS, `fsGroup: 1000`, NFS downloads mount, tmpfs `/tmp`, and `POD_NAME` downward API. |
| `service.yaml` | One LoadBalancer Service per pod (so each replica gets its own externally-reachable BitTorrent listen port). |
| `config/deluge.env` | Env-var config consumed via `envFrom` (configMap). Tuned for `readOnlyRootFilesystem`. |
| `config/ltconfig.conf` | libtorrent tuning profile applied by the bundled ltConfig plugin. |
| `kustomization.yaml` | Wires `deluge-config` and `deluge-env` ConfigMaps from `config/`. |

## Bootstrap (one-time)

The manifests rely on two pre-existing Secrets that you create out-of-band so
nothing sensitive is checked into git.

### 1. Daemon `auth` file

Deluge authenticates daemon clients (the web UI, Thin Client, etc.) against
a plaintext `auth` file with the format `username:password:level` per line.
See the [Deluge authentication docs](https://deluge-torrent.org/userguide/authentication/).

```sh
cat > auth <<'EOF'
localclient:changeme:10
EOF

kubectl create secret generic deluge-auth \
  --from-file=auth \
  --namespace=deluge
```

This Secret is mounted read-only at `/home/deluge/.config/deluge/auth` via
`subPath`. Deluge cannot add daemon users at runtime through the UI in this
setup — manage the Secret directly.

### 2. Web UI password

```sh
kubectl create secret generic deluge-web-password \
  --from-literal=DELUGE_WEB_PASSWORD='your_password_here' \
  --namespace=deluge
```

`inject_web_config.py` reads `DELUGE_WEB_PASSWORD` on each container start and
hashes it (salted SHA-1, Deluge's native format) into `web.conf` if it differs.

## Apply

```sh
kubectl apply -k .
```

## Customize before applying

- **Image tag** (`statefulset.yaml`): pin to a Deluge version or to a snapshot
  tag like `2.2.0-<sha>` if you want immutable rollouts.
- **`storageClassName`** (`statefulset.yaml`, `volumeClaimTemplates`): defaults
  to `longhorn`. Replace with your cluster's storage class. The PVC is
  intentionally small (300Mi) — only Deluge's config / state lives here, not
  downloads.
- **Downloads volume** (`statefulset.yaml`, `volumes.downloads`): shown as NFS
  pointing at `nas.example.com:/export/downloads`. Replace with whatever
  backs your downloads (PVC, hostPath, CephFS, etc.).
- **LoadBalancer IPs** (`service.yaml`): MetalLB annotations with placeholder
  addresses. Adjust the annotation key for your LB controller or change the
  Service `type` to `NodePort` / `ClusterIP` if you front it with an ingress.
- **Replica count** (`statefulset.yaml`, `spec.replicas`): three by default;
  adjust along with the number of per-pod Services in `service.yaml`.
- **Per-pod listen ports** (`service.yaml`): each Service exposes
  `61534 + pod_index`. If you change the replica count, add or remove
  Services accordingly.

## Why the manifests look the way they do

A few non-obvious choices the image's runtime contract requires:

- **`fsGroup: 1000` + `runAsUser: 1000`** — the image's `deluge` user is
  baked at uid/gid 1000. Without `fsGroup` the mounted PVC isn't writable.
- **`/tmp` as tmpfs emptyDir** — Deluge's `Config.save()` writes to
  `/tmp/<file>.<rand>` before `mv`, and `PYTHON_EGG_CACHE=/tmp` redirects
  plugin egg extraction here. Both are mandatory under `readOnlyRootFilesystem`.
- **`POD_NAME` via downward API** — consumed by `inject_core_config.py` to
  pick the per-pod BitTorrent listen port.
- **`DELUGE_CONF_CORE_RANDOM_PORT=FALSE`** — Deluge's default is `true`,
  which would override the assigned listen port. Without setting this to
  false, the per-pod port wiring is silently inert.
- **One LB Service per pod** — peers need to reach a specific replica on a
  specific port. A single fronting Service would round-robin and break
  peer connectivity.
- **`subPath` mounts for `auth` and `ltconfig.conf`** — both are
  managed-in-git config; mounting via `subPath` keeps them as single files
  alongside the PVC contents and prevents Deluge from rewriting them.
- **`fsGroupChangePolicy: OnRootMismatch`** — skips a recursive chown of
  the PVC on every pod start once it's correctly owned.

## Verifying after apply

```sh
# Pods Running and Ready
kubectl -n deluge get pods -l app.kubernetes.io/name=deluge

# Per-pod listen port was actually assigned
kubectl -n deluge logs deluge-0 | grep "Assigned listen port"
# → INFO:root:Assigned listen port 61534 for pod deluge-0

# Web UI reachable through the per-pod LoadBalancer
kubectl -n deluge get svc

# Plugin sync produced exactly one plugins/ dir, no nesting
kubectl -n deluge exec deluge-0 -- ls /home/deluge/.config/deluge/plugins
```
