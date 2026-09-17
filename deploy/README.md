# deploy/ - rendered GitOps manifests (committed by CI, synced by ArgoCD)

This directory holds the **rendered** Kubernetes manifests that ArgoCD syncs into
each cluster. You do not edit anything here by hand: it is generated and
committed by the CD workflows (`Deploy (AWS)` / `Deploy (Azure)` in
`.github/workflows/`), and ArgoCD (installed by Terraform) watches it on `main`.

## Layout

```
deploy/
  <env>/
    aws/      # rendered from common/k8s + aws/k8s      (EKS: ESO owns secrets)
    azure/    # rendered from common/k8s + azure/k8s    (AKS: secrets baked in)
```

`<env>` is one of `dev`, `qa`, `prod`. A path only appears once the matching
CD workflow has run for that env + cloud (the first run creates it).

## How a manifest gets here

1. You run **Deploy (AWS)** / **Deploy (Azure)** (Actions tab), choosing the env
   and optionally pinning image tags.
2. The workflow resolves the live values (RDS/PG endpoint, image API URL, image
   tags) with the read-only CD identity, renders the manifests with
   `common/k8s/render.sh`, and commits them to `main` under `deploy/<env>/<cloud>/`.
3. ArgoCD detects the new commit and syncs the change into the cluster. The
   migrations Job runs first (it carries the `argocd.argoproj.io/hook: PreSync`
   annotation) and is deleted on success.

## Why committed (and not rendered in-cluster)

Committing the rendered output makes the exact set of manifests that were
applied to a cluster visible in git history - a per-env, per-cloud audit trail -
and lets ArgoCD show drift against a concrete, reviewable source. Secrets are
never committed: on AWS they are fetched at runtime by External Secrets
Operator, and on Azure the (non-prod) values are rendered from repo secrets at
CD time.
