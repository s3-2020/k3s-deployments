# k3s-deployments — application deployments

Application-layer GitOps repository for the home K3s cluster. Deployed
workloads live here; the platform that runs them lives in
[`s3-2020/k3s-gitops`](https://github.com/s3-2020/k3s-gitops).

| Repository | Contains |
|------------|----------|
| `k8s-gitops` | Cluster bootstrap, infrastructure (Traefik, Gateway, cert-manager, PKI, TrueNAS CSI, monitoring stack), platform docs |
| `k3s-deployments` (this repo) | Applications: Rancher, Hubble route, Grafana route, Flux UI route, and all future apps |

## How it reaches the cluster

Flux in the cluster syncs this repo through a `GitRepository` +
`Kustomization` defined in `k8s-gitops/clusters/home/` (path `./apps`,
branch `main`, deploy key read-only). Push here → Flux reconciles within
~10 minutes.

## Layout

```
apps/
├── kustomization.yaml   ← lists every app; add new apps here
├── rancher/             HelmRelease + HelmRepository + HTTPRoute
├── hubble/              HTTPRoute → kube-system/hubble-ui
├── grafana/             HTTPRoute → monitoring/kube-prometheus-stack-grafana
└── flux/                HTTPRoute → flux-system/flux-operator
```

Each future app: its own directory + namespace, added to
`apps/kustomization.yaml`. Full template and checklist:
[new-application runbook]([https://github.com/s3-2020/k3s-deployments/blob/main/docs/1-new-app-runbook.md])
— architecture and operations docs in the
[k8s-gitops docs folder](https://github.com/s3-2020/k3s-gitops/tree/main/docs).

## Rules

- Everything user-managed is declarative here or in k8s-gitops — no
  `kubectl edit` (Flux reverts).
- No secret values in Git; out-of-band Secrets referenced by name
  (SOPS + age planned).
- Namespaces are private by default; public exposure is an explicit
  decision.
