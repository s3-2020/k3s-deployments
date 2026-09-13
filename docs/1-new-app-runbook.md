# 01 - Adding a New Application (runbook + template)

Every user-managed app lives in this repo (`k3s-deployments`), in its own
namespace under `apps/<name>/`, is composed by `apps/kustomization.yaml`, and
is reached at `<name>.kung.dk` through the shared Traefik gateway. Flux in the
cluster syncs `./apps` from this repo via the `deployments` Kustomization in
the `k3s-gitops` root repo. **Never** place files here as live manifests until
you are ready to deploy — Flux reconciles anything referenced from
`apps/kustomization.yaml`.

## Checklist

1. Create `apps/<name>/` with the files below (copy the templates).
2. Add the directory to `apps/kustomization.yaml`.
3. Commit + push to **this** repo; Flux applies within ~10m (or
   `flux reconcile kustomization deployments`).
4. Create the explicit UDM DNS record `<name>.kung.dk A 10.22.50.60`
   (no wildcards — see
   [08-dns-pki-tls.md](https://github.com/s3-2020/k3s-gitops/blob/main/docs/08-dns-pki-tls.md)).
5. Validate (bottom of this file).

## Template

### `apps/<name>/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <name>
```

### `apps/<name>/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <name>
  namespace: <name>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <name>
  template:
    metadata:
      labels:
        app: <name>
    spec:
      containers:
        - name: <name>
          image: <registry>/<image>:<tag>   # pin a tag or digest, never :latest
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              memory: 512Mi
```

### `apps/<name>/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <name>
  namespace: <name>
spec:
  selector:
    app: <name>
  ports:
    - port: 80
      targetPort: 8080
```

### `apps/<name>/httproute.yaml`

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <name>
  namespace: <name>
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: traefik-gateway
      namespace: kube-system
  hostnames:
    - <name>.kung.dk
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: <name>
          port: 80
```

HTTPS works automatically: the gateway's `websecure` listener serves the
internal `*.kung.dk` wildcard cert — clients need the internal CA trusted
([08-dns-pki-tls.md](https://github.com/s3-2020/k3s-gitops/blob/main/docs/08-dns-pki-tls.md)).

### `apps/<name>/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - httproute.yaml
```

## Optional pieces

### Persistent storage (TrueNAS iSCSI)

Use for anything that must survive pod/node loss. RWO — one pod at a time.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <name>-data
  namespace: <name>
spec:
  storageClassName: truenas-iscsi
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

Mount in the container:

```yaml
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: <name>-data
      containers:
        - name: <name>
          volumeMounts:
            - name: data
              mountPath: /data
```

Notes: `Retain` reclaim policy (see
[09-storage-truenas-csi.md](https://github.com/s3-2020/k3s-gitops/blob/main/docs/09-storage-truenas-csi.md));
`local-path` is **not** safe for real state.

### Secrets

**Do not commit plaintext secret values.** Pattern since 2026-09-13: write
the Secret manifest under `secrets/` in this repo and SOPS-encrypt it:

```bash
# create secrets/<name>.sops.yaml (Secret manifest, stringData), then:
sops --encrypt --in-place secrets/<name>.sops.yaml
# add the file to secrets/kustomization.yaml, commit, push
```

Flux's dedicated `secrets` Kustomization decrypts it via the cluster-held
age key and applies it; the app then references the Secret by name:

```yaml
          envFrom:
            - secretRef:
                name: <name>-credentials
```

Key custody and cold-start order:
[11-security.md](https://github.com/s3-2020/k3s-gitops/blob/main/docs/11-security.md).

### More replicas

Deployments scale freely; storage-bound apps on `truenas-iscsi` are RWO, so
either keep 1 replica or split state. Traefik reaches pods on any node via
the eBPF datapath — no affinity concerns.

## Validation

```bash
# local render before pushing (no cluster change), from this repo's root
kubectl kustomize apps | grep -A2 "name: <name>"

# after push
flux reconcile kustomization deployments
kubectl -n <name> get deploy,svc,httproute,pods
kubectl -n <name> describe httproute <name>    # Accepted=True ResolvedRefs=True

# through the gateway (before/without DNS)
curl -sI --resolve <name>.kung.dk:80:10.22.50.60 http://<name>.kung.dk
# after the UDM DNS record exists:
nslookup <name>.kung.dk 10.22.50.62
```

## House rules

- Namespace per app, names equal to the directory/app name.
- Pin image tags (Flux image automation can be added later).
- All resources stay private by default; public exposure is an explicit,
  separate decision
  ([11-security.md](https://github.com/s3-2020/k3s-gitops/blob/main/docs/11-security.md)).
- No changes via `kubectl edit` on Git-managed objects — Flux reverts them.
- Update
  [00-current-state.md](https://github.com/s3-2020/k3s-gitops/blob/main/docs/00-current-state.md)
  inventory and the
  [07-traefik-gateway-api.md](https://github.com/s3-2020/k3s-gitops/blob/main/docs/07-traefik-gateway-api.md)
  HTTPRoute table (both in `k3s-gitops`) when adding an app.
