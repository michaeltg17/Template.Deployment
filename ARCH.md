# Template.Deployment

Deployment of the template project in **two clouds: AWS and Azure**, managed end to end with **Terraform** and **Kubernetes manifests**. The two clouds are deliberately symmetric: each has its own Terraform (infra), bootstrap (cluster post-provisioning), and a thin k8s overlay; everything the app actually runs as (deployments, services, config, secrets, migrations, ingress shape) lives **once** in `common/k8s/`. No domain in dev: the app is served plain-HTTP on the load balancer's DNS name (cost; this is a template).

**Terraform owns the infrastructure** (network, cluster, database, load balancer, IAM incl. the controller roles and the GitHub OIDC identities). **Kubernetes owns the workloads.** The load balancer is a cloud resource but it is created and managed by the controller in-cluster from the Ingress (AWS: load-balancer-controller + ALB; Azure: AGIC + App Gateway), so route changes are just manifest changes.

## Diagrams

### AWS (EKS + ALB + RDS)

```
                              INTERNET
                                  │
                                  │ HTTP :80
                                  ▼
                     ┌────────────────────────────┐
                     │           ALB              │
                     │      Internet-facing       │
                     │Managed by AWS LB Controller│
                     └────────────┬───────────────┘
                                  │
                           ┌──────▼────────┐
                           │  EKS Ingress  │
                           │  ingress.yaml │
                           └───────┬───────┘
                                  │
                     ┌────────────┴────────────┐
                     │                         │
               /api/*│                         │ /
                     ▼                         ▼
           ┌────────────────┐        ┌────────────────┐
           │  API Service   │        │ Next.js Service│
           └───────┬────────┘        └───────┬────────┘
                   │                         │
                   ▼                         ▼
           ┌────────────────┐        ┌────────────────┐
           │    API Pods    │        │  Next.js Pods  │
           └───────┬────────┘        └────────────────┘
                   │
                   │ PostgreSQL :5432
                   ▼
           ┌──────────────────────────────┐
           │       RDS PostgreSQL         │
           │          Multi-AZ            │
           │          Private             │
           └──────────────────────────────┘
```

### Azure (AKS + App Gateway + PostgreSQL Flexible)

```
                              INTERNET
                                  │
                                  │ HTTP :80
                                  ▼
                     ┌────────────────────────────┐
                     │        App Gateway         │
                     │        Standard_v2         │
                     │      Managed by AGIC       │
                     └────────────┬───────────────┘
                                  │
                           ┌──────▼─────────┐
                           │  AKS Ingress   │
                           │  ingress.yaml  │
                           └───────┬────────┘
                                  │
                     ┌────────────┴────────────┐
                     │                         │
               /api/*│                         │ /
                     ▼                         ▼
           ┌────────────────┐        ┌────────────────┐
           │   API Service  │        │  React Service │
           └───────┬────────┘        └───────┬────────┘
                   │                         │
                   ▼                         ▼
           ┌────────────────┐        ┌────────────────┐
           │    API Pods    │        │   React Pods   │
           └───────┬────────┘        └────────────────┘
                   │
                   │ PostgreSQL :5432
                   ▼
           ┌──────────────────────────────┐
           │  PostgreSQL Flexible Server  │
           │       B_Standard_B1ms        │
           │      Private (VNet + DNS)    │
           └──────────────────────────────┘
```

## Repo layout

```
common/
  k8s/
    namespace.yaml
    secrets.yaml          template -> rendered by deploy.sh
    migrations-job.yaml   one-shot dbup runner, re-run on upgrades
    api.yaml              deployment + service (TemplateApi__* env vars, HTTP probes)
    react.yaml            configmap (API_URL) + deployment + service
    environments/
      dev.env.example         copy to dev.env: IMAGE_API_URL, RDS_ENDPOINT, DB_USER, tags
      dev.secrets.env.example copy to dev.secrets.env: DB_PASSWORD, IMAGE_API_KEY
    deploy.sh               <env> <cloud> -> renders + applies common/* + <cloud>/k8s/*
  ci.sh                   the CI checks (terraform fmt/validate, shellcheck, kubeconform)
  ci-docker.sh            builds the CI tools image, runs ci.sh on the working tree
  Dockerfile.ci           tools image (terraform, shellcheck, python3, kubeconform)
aws/
  terraform/
    bootstrap/           the remote state itself: S3 bucket (state + lockfile of all
                         envs), versioning, public access block, SSE
    modules/
      vpc/               VPC, 3 public + 3 private subnets, IGW, 1 NAT
      eks/               cluster, node group, addons, SGs, aws-auth,
                         ALB-controller IRSA role, GitHub OIDC role
      rds/               PostgreSQL instance, subnet group, SG
    environments/
      dev/               module wiring + per-env values (tfvars, gitignored),
                         state in S3 at dev/terraform.tfstate
  bootstrap/
    setup-eks.sh         kubeconfig + wait nodes + helm install ALB controller
    teardown.sh          k8s cleanup -> terraform destroy -> verify
  k8s/
    ingress.yaml         ALB ingress: /api -> api, / -> react (+ ALB healthcheck path)
azure/
  terraform/
    bootstrap/           the remote state itself: resource group + storage account
                         (container, key per env), used as the backend
    modules/
      vnet/              VNet, App Gateway /24 (delegated), nodes /24, PG /24 (delegated), NSGs
      aks/               cluster (system + user node pool), CD user-assigned MI +
                         federated credential, AGIC identity is bootstrapped
      postgresql/        private DNS zone + vnet link, Flexible Server (B_Standard_B1ms)
      appgateway/        public PIP + App Gateway Standard_v2 (AGIC-managed)
    environments/
      dev/               module wiring + per-env values (tfvars, gitignored),
                         state in the storage account at dev/terraform.tfstate
  bootstrap/
    setup-aks.sh         az aks get-credentials + wait nodes + helm install AGIC
                         (+ create the AGIC service principal)
    teardown.sh          k8s cleanup -> terraform destroy -> verify
  k8s/
    ingress.yaml         AGIC ingress: /api -> api, / -> react
.github/workflows/
  ci.yml                fmt + validate + shellcheck + kubeconform (on push); tag + release on main
  cd-aws.yml            "Deploy (AWS)" workflow (OIDC -> render env -> deploy.sh <env> aws)
  cd-azure.yml          "Deploy (Azure)" workflow (federated MI -> render env -> deploy.sh <env> azure)
```

## Run CI locally

The same checks that run in GitHub Actions also run in a docker container, so no local tooling is needed:

```sh
bash common/ci-docker.sh
```

Builds the `template-deployment-ci` tools image once (terraform, shellcheck, python3, kubeconform), then runs `common/ci.sh` against the current working tree (mounted, so uncommitted changes count). It formats/validates **both** clouds' Terraform, shellchecks every shell script, parses all k8s + workflow YAML, and kubeconforms every manifest.

## Shared k8s + deploy.sh

`common/k8s/` holds the cloud-agnostic manifests. `deploy.sh <env> <cloud>`:

1. Renders the common manifests + the `<cloud>/k8s/` overlay into a temp dir, replacing `__RDS_ENDPOINT__`, `__DB_USER__`, `__DB_PASSWORD__`, `__IMAGE_API_URL__`, `__IMAGE_API_KEY__`.
2. Applies in order: namespace -> secrets -> migrations job (waits) -> api -> react -> the cloud's ingress.
3. Prints the load balancer URL (ALB `load-balancer-ingress-controller` annotation on AWS; App Gateway `fqdn` output on Azure).

The two clouds differ only in the ingress (ALB annotations vs. the AGIC `IngressClass`), which is why the ingress lives in `<cloud>/k8s/` rather than `common/k8s/`.

---

## AWS

### Prerequisites

- AWS account + `aws` CLI credentials (or `terraform.tfvars` with `aws_profile`), plus `kubectl`
- Terraform >= 1.5 (CI uses a pinned docker image, no local install needed)
- the three images pushed to ghcr.io: `template-api`, `template-react`, `template-db-migrations` (public, no registry secret needed)
- the React app reads `API_URL` from an env var at runtime (no per-env builds)

### Deploy (dev)

1. **Bootstrap the remote state** (one-time, only on a fresh account):

   ```sh
   aws s3api create-bucket --bucket michaeltg17-template-terraform-state --region us-east-1
   cd aws/terraform/bootstrap
   terraform init
   terraform import aws_s3_bucket.state michaeltg17-template-terraform-state
   terraform apply
   ```

   Terraform can't store state in a bucket that doesn't exist yet, so the bucket is created with the one CLI command above and `terraform import` adopts it; from then on Terraform manages everything (versioning, public access block, encryption). All environments keep their state under their own key in this bucket (`dev/terraform.tfstate`, `qa/...`, `prod/...`); locking is S3-native (`use_lockfile`, a `<key>.tflock` object), no DynamoDB.

2. **Provision AWS** (takes ~15-20 min):

   ```sh
   cd aws/terraform/environments/dev
   cp terraform.tfvars.example terraform.tfvars   # set db_master_password
   terraform init
   terraform apply
   ```

   `db_master_password` in `terraform.tfvars` MUST equal `DB_PASSWORD` in `aws` secrets (below).

3. **Bootstrap the cluster** (kubeconfig + ALB load balancer controller):

   ```sh
   bash aws/bootstrap/setup-eks.sh dev
   ```

4. **Fill env values**:

   ```sh
   cp common/k8s/environments/dev.env.example common/k8s/environments/dev.env
   #    IMAGE_API_URL=<image api host>, RDS_ENDPOINT=(terraform output -raw rds_endpoint),
   #    DB_USER=(terraform output -raw db_user)
   cp common/k8s/environments/dev.secrets.env.example common/k8s/environments/dev.secrets.env
   #    fill DB_PASSWORD= (same as terraform.tfvars) and IMAGE_API_KEY=
   ```

5. **Deploy** (the cloud argument is what picks the ALB ingress overlay):

   ```sh
   cd common/k8s
   ./deploy.sh dev aws
   ```

   The script renders the placeholders, applies namespace -> secrets -> migrations job (against RDS) -> api -> react -> the ALB ingress, and prints the ALB URL once the controller publishes it on the Ingress status.

6. **Validate**:

   ```sh
   curl http://<ALB-DNS>/api/    # api through the ALB
   curl http://<ALB-DNS>/        # Next.js through the ALB
   ```

### Deploy a new build (manual CD)

The app repos (`Template.Api`, `Template.React`) build and push their ghcr images on their own CI (tagged `<sha7>` + `latest`). To deploy a new build you press a button — no tags to edit by hand:

1. Push to the app repo's `main` (its CI pushes the new `sha7` + `latest` images).
2. GitHub -> **Actions** -> **Deploy (AWS)** (`.github/workflows/cd-aws.yml`) -> choose `env` -> **Run workflow**.
3. The workflow assumes the env's OIDC role, resolves the `sha7` of the app repos' `main` HEAD (or a specific `sha7` from the optional `api_tag` / `react_tag` fields, to pin or roll back), resolves the RDS endpoint/user via the aws CLI, renders the env files, and runs `common/k8s/deploy.sh <env> aws` — which re-runs the migrations job and rolls the deployments.

Required per environment (repo settings -> Secrets & variables -> Actions):

| Type   | Name                  | Value                                                        |
| ------ | --------------------- | ------------------------------------------------------------ |
| Secret | `AWS_ROLE_ARN_DEV`    | `terraform output -raw cd_role_arn`                          |
| Secret | `DB_PASSWORD_DEV`     | RDS master password (must match `db_master_password` in tfvars) |
| Secret | `IMAGE_API_KEY_DEV`   | image API key for this env                                    |
| Var    | `IMAGE_API_URL_DEV`   | image API base URL for this env (e.g. the dev image-api host) |

Only `dev` is provisioned in this repo so far; `qa`/`prod` (offered by the workflow) follow the same pattern: add an `aws/terraform/environments/<env>` plus the per-env secrets/vars above.

No kubeconfig secret: kubectl authenticates through the OIDC role (`aws eks update-kubeconfig` mints short-lived tokens per request).

### Destroy everything (after validation)

```sh
bash aws/bootstrap/teardown.sh dev
```

The script does the k8s-side cleanup **before** `terraform destroy`: it deletes the `app` namespace (the Ingress finalizer makes the ALB controller delete the public ALB), waits for the ALB and its ENIs/EIPs to leave AWS, removes the controller's `k8s-*` security groups, uninstalls the controller, runs `terraform destroy`, and verifies nothing is left.

**Do not run `terraform destroy` directly** while the cluster is up: the ALB is controller-created and not in the Terraform state, so destroying the cluster first orphans the ALB, whose ENIs/EIPs then block the public subnets, the internet gateway and the VPC (the script's self-healing path recovers from exactly that, but the VPC/subnets stay broken until the orphan is removed).

If the script is unavailable, the manual equivalent (cluster still up):

```sh
kubectl delete ns app          # wait for it to disappear (Ingress finalized -> ALB deleted)
aws elbv2 describe-load-balancers   # wait until the k8s-app-app-* ALB is gone
cd aws/terraform/environments/dev && terraform destroy
```

`terraform destroy` removes everything this config created (EKS, RDS, VPC, NAT, IAM). Nothing persists: the RDS snapshot is skipped and the dev DB is disposable (the migrations job rebuilds the schema on next deploy). Verify: `aws ec2 describe-instances --filters "tag:Project=template"` and `aws eks list-clusters` return nothing for this project.

The remote state itself (the S3 bucket from `aws/terraform/bootstrap`) is **not** touched by `teardown.sh`: it outlives the environment so state history (versioned) is kept, and so a re-deploy goes straight to `terraform apply`.

Re-deploying later is: `terraform apply` -> `aws/bootstrap/setup-eks.sh` -> `common/k8s/deploy.sh dev aws`.

### Known limitations (AWS, by design, for this phase)

- Plain HTTP, no domain/cert: the ALB listens on :80 only. When a domain exists, add an ACM cert + `listen-ports` HTTPS + a redirect (Ingress annotations).
- Single NAT gateway in one AZ (cheapest): an AZ outage affects new image pulls, not running pods. Add one NAT per AZ for full HA.
- The app connects to RDS as the master user (dev). Create a dedicated app user (and IAM auth) before prod.
- The RDS connection uses `SSL Mode=Require` with `Trust Server Certificate=true`: traffic is encrypted but the RDS CA is not pinned, so the server's identity is not verified (a MITM could present a fake cert). For prod, pin the RDS CA certificate and use `SSL Mode=Verify-Full`.
- CI/CD never runs `terraform` (only `common/k8s/deploy.sh`). If that changes (e.g. a pipeline applies prod), the pipeline role needs S3 access to the env's state key + lockfile in `michaeltg17-template-terraform-state` (see the [S3 backend docs](https://developer.hashicorp.com/terraform/language/backend/s3#permissions-required) for the exact statements).
- `worker_min_size` defaults to 1: set it to 3 (one per AZ) when the app needs real HA.

---

## Azure

### Prerequisites

- Azure account + `az` CLI (`az login`), plus `kubectl`
- The app repo's GitHub OIDC provider is already trusted (the `main`/`dev` branches mint tokens; the federated credential is created by Terraform)
- Terraform >= 1.5 (CI uses a pinned docker image, no local install needed)
- the three images pushed to ghcr.io: `template-api`, `template-react`, `template-db-migrations` (public)
- the React app reads `API_URL` from an env var at runtime (no per-env builds)

### Deploy (dev)

1. **Bootstrap the remote state** (one-time, only on a fresh account):

   ```sh
   cd azure/terraform/bootstrap
   terraform init
   terraform apply          # creates the state resource group + storage account + container
   ```

   The state storage account (`michaeltg17azstate`) and its `terraform` container live in `template-az-state`. All environments keep their state under their own key (`dev/terraform.tfstate`, `qa/...`, `prod/...`); locking is storage-account-native. This is the only thing you create manually; everything else is Terraform.

2. **Provision Azure** (takes ~15-25 min):

   ```sh
   cd azure/terraform/environments/dev
   cp terraform.tfvars.example terraform.tfvars   # set pg_password
   terraform init
   terraform apply
   ```

   `pg_password` in `terraform.tfvars` MUST equal `DB_PASSWORD` in the Azure secrets (below).

3. **Bootstrap the cluster** (kubeconfig + wait nodes + AGIC + the AGIC service principal):

   ```sh
   bash azure/bootstrap/setup-aks.sh dev
   ```

   `setup-aks.sh` reads the cluster/App Gateway/PG outputs, fetches the kubeconfig, waits for nodes, creates the AGIC service principal (via the az CLI — recent azurerm versions can't create service principals in Terraform), and installs the `ingress-azure` chart pointing at the App Gateway.

4. **Fill env values**:

   ```sh
   cp common/k8s/environments/dev.env.example common/k8s/environments/dev.env
   #    IMAGE_API_URL=<image api host>, RDS_ENDPOINT=(the PG server FQDN; terraform output -raw postgresql_fqdn),
   #    DB_USER=(terraform output -raw postgresql_db_user)   # just the login, not login@fqdn
   cp common/k8s/environments/dev.secrets.env.example common/k8s/environments/dev.secrets.env
   #    fill DB_PASSWORD= (same as terraform.tfvars) and IMAGE_API_KEY=
   ```

5. **Deploy**:

   ```sh
   cd common/k8s
   ./deploy.sh dev azure
   ```

   The script renders the placeholders, applies namespace -> secrets -> migrations job (against PostgreSQL) -> api -> react -> the AGIC ingress, and prints the App Gateway URL.

6. **Validate**:

   ```sh
   curl http://<APP-GATEWAY-DNS>/api/    # api through the App Gateway
   curl http://<APP-GATEWAY-DNS>/        # React through the App Gateway
   ```

### Deploy a new build (manual CD)

GitHub -> **Actions** -> **Deploy (Azure)** (`.github/workflows/cd-azure.yml`) -> choose `env` -> **Run workflow**. The workflow authenticates with a **user-assigned managed identity** (created by Terraform) whose federated credential trusts this repo's `main`/`dev` branches, resolves the `sha7` of the app repos' `main` HEAD (or a specific `sha7` from `api_tag` / `react_tag`), resolves the PostgreSQL FQDN + user via the az CLI, renders the env files, and runs `common/k8s/deploy.sh <env> azure`.

Required per environment (repo settings -> Secrets & variables -> Actions):

| Type   | Name                     | Value                                                        |
| ------ | ------------------------ | ------------------------------------------------------------ |
| Secret | `AZURE_TENANT_ID_DEV`    | tenant id (the one Terraform provisions into, or `terraform output -raw cd_tenant_id`) |
| Secret | `AZURE_SUBSCRIPTION_ID_DEV` | subscription id                                              |
| Secret | `AZURE_CLIENT_ID_DEV`    | `terraform output -raw cd_client_id` (the user-assigned MI client id) |
| Secret | `DB_PASSWORD_DEV`        | PG server password (must match `pg_password` in tfvars)      |
| Secret | `IMAGE_API_KEY_DEV`      | image API key for this env                                    |
| Var    | `IMAGE_API_URL_DEV`      | image API base URL for this env                               |

The identity needs `Reader` on the env resource group + `AKS RBAC Reader` on the cluster (both applied by Terraform via `azure_ad`/`azurerm`). No kubeconfig secret: kubectl authenticates through the cluster's Azure AD.

### Destroy everything (after validation)

```sh
bash azure/bootstrap/teardown.sh dev
```

The script deletes the `app` namespace, uninstalls AGIC, runs `terraform destroy`, and verifies the resource group is empty.

### Known limitations (Azure, by design, for this phase)

- Plain HTTP, no domain/cert: the App Gateway listens on :80 only. When a domain exists, add a certificate + an HTTPS listener/Ingress TLS.
- Single-region, single-node-pool (cheapest). For HA: more nodes / multiple zones.
- The app connects to PostgreSQL as the admin user (dev). Create a dedicated app user before prod.
- AGIC (App Gateway Ingress Controller) creates the actual routing rules from the Ingress; the Terraform App Gateway is a minimal shell (a placeholder listener + pool) that AGIC overwrites at runtime.
- CI/CD never runs `terraform` (only `common/k8s/deploy.sh`). The AGIC service principal is created by `setup-aks.sh` (az CLI), not by Terraform, because recent azurerm versions removed `azurerm_application`/`azurerm_service_principal` from the provider.
