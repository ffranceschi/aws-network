# Prod Spoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar conta prod (`745416886900`) como segundo spoke da rede hub/spoke, com VPC `10.11.0.0/16` conectada ao TGW centralizado no hub.

**Architecture:** Espelha o spoke dev existente — VPC sem IGW, TGW attachment em subnets `/28`, workload em subnets `/24`, egresso internet via NAT GW do hub. O hub precisa de re-apply em duas fases: antes do prod apply (RAM share + rota pública) e após (TGW RT association + rota TGW).

**Tech Stack:** Terraform >= 1.10, provider AWS ~> 5.0, módulos locais `modules/vpc` e `modules/tgw-spoke`.

---

## Mapa de Arquivos

**Criar:**
- `accounts/prod/providers.tf`
- `accounts/prod/variables.tf`
- `accounts/prod/backend.tf`
- `accounts/prod/backend.hcl`
- `accounts/prod/backend.hcl.example`
- `accounts/prod/terraform.tfvars`
- `accounts/prod/terraform.tfvars.example`
- `accounts/prod/main.tf`
- `accounts/prod/tgw-attachment.tf`
- `accounts/prod/routes.tf`
- `accounts/prod/outputs.tf`

**Modificar:**
- `accounts/hub/variables.tf` — adicionar `prod_account_id` e `prod_tgw_attachment_done`
- `accounts/hub/ram.tf` — adicionar `aws_ram_principal_association.prod`
- `accounts/hub/routes.tf` — adicionar `aws_route.public_to_prod`
- `accounts/hub/tgw.tf` — adicionar data source + TGW RT association + rota TGW para prod (fase 2)
- `accounts/hub/terraform.tfvars` — adicionar variáveis prod

---

### Task 1: Pré-requisito — TerraformExecutionRole na conta prod

**Contexto:** O Terraform precisa de uma role na conta prod com trust policy permitindo que o root da conta hub (`225119180422`) a assuma. Sem isso, o `assume_role` no provider vai falhar.

- [ ] **Step 1: Criar a role na conta prod**

Execute no terminal (precisa de credenciais válidas para a conta prod via profile `ct8-prod`):

```bash
aws iam create-role \
  --role-name TerraformExecutionRole \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{
      "Effect":"Allow",
      "Principal":{"AWS":"arn:aws:iam::225119180422:root"},
      "Action":"sts:AssumeRole"
    }]
  }' \
  --profile ct8-prod
```

Resultado esperado: JSON com `RoleName: "TerraformExecutionRole"` e `Arn` contendo `745416886900`.

- [ ] **Step 2: Anexar política AdministratorAccess**

```bash
aws iam attach-role-policy \
  --role-name TerraformExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile ct8-prod
```

Resultado esperado: sem output (sucesso silencioso).

- [ ] **Step 3: Verificar que ct8-hub consegue assumir a role**

```bash
aws sts assume-role \
  --role-arn "arn:aws:iam::745416886900:role/TerraformExecutionRole" \
  --role-session-name test \
  --profile ct8-hub \
  --query 'AssumedRoleUser.Arn' \
  --output text
```

Resultado esperado: `arn:aws:sts::745416886900:assumed-role/TerraformExecutionRole/test`

---

### Task 2: Atualizar hub — variáveis e RAM share para prod

**Files:**
- Modify: `accounts/hub/variables.tf`
- Modify: `accounts/hub/ram.tf`
- Modify: `accounts/hub/terraform.tfvars`

- [ ] **Step 1: Adicionar variáveis prod em `accounts/hub/variables.tf`**

Adicionar ao final do arquivo (após o bloco `dev_tgw_attachment_done`):

```hcl
variable "prod_account_id" {
  type        = string
  description = "AWS Account ID of the prod spoke account"
}

variable "prod_tgw_attachment_done" {
  type        = bool
  default     = false
  description = "Set to true after accounts/prod is applied to add TGW route and association for prod spoke"
}
```

- [ ] **Step 2: Adicionar RAM principal association para prod em `accounts/hub/ram.tf`**

Adicionar ao final do arquivo (após o bloco `aws_ram_principal_association.dev`):

```hcl
resource "aws_ram_principal_association" "prod" {
  principal          = var.prod_account_id
  resource_share_arn = aws_ram_resource_share.tgw.arn
}
```

- [ ] **Step 3: Adicionar variáveis prod em `accounts/hub/terraform.tfvars`**

Adicionar ao final do arquivo:

```
prod_account_id          = "745416886900"
prod_tgw_attachment_done = false
```

- [ ] **Step 4: Validar HCL do hub**

```bash
cd /Users/fernando/Work/estudos/aws-network/accounts/hub
terraform validate
```

Resultado esperado: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
cd /Users/fernando/Work/estudos/aws-network
git add accounts/hub/variables.tf accounts/hub/ram.tf accounts/hub/terraform.tfvars
git commit -m "feat(hub): add prod spoke variables and RAM share"
```

---

### Task 3: Atualizar hub — rota pública e TGW fase 2 para prod

**Files:**
- Modify: `accounts/hub/routes.tf`
- Modify: `accounts/hub/tgw.tf`

- [ ] **Step 1: Adicionar rota pública para prod em `accounts/hub/routes.tf`**

Adicionar após o bloco `aws_route.public_to_dev` (por volta da linha 22):

```hcl
resource "aws_route" "public_to_prod" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "10.11.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}
```

- [ ] **Step 2: Adicionar fase 2 para prod em `accounts/hub/tgw.tf`**

Adicionar ao final do arquivo (após os blocos `aws_ec2_transit_gateway_route.to_dev_vpc`):

```hcl
data "terraform_remote_state" "prod" {
  count   = var.prod_tgw_attachment_done ? 1 : 0
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "prod/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "prod" {
  count                          = var.prod_tgw_attachment_done ? 1 : 0
  transit_gateway_attachment_id  = data.terraform_remote_state.prod[0].outputs.tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

resource "aws_ec2_transit_gateway_route" "to_prod_vpc" {
  count                          = var.prod_tgw_attachment_done ? 1 : 0
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  destination_cidr_block         = "10.11.0.0/16"
  transit_gateway_attachment_id  = data.terraform_remote_state.prod[0].outputs.tgw_attachment_id
}
```

- [ ] **Step 3: Validar HCL do hub**

```bash
cd /Users/fernando/Work/estudos/aws-network/accounts/hub
terraform validate
```

Resultado esperado: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
cd /Users/fernando/Work/estudos/aws-network
git add accounts/hub/routes.tf accounts/hub/tgw.tf
git commit -m "feat(hub): add prod spoke public route and TGW phase-2 resources"
```

---

### Task 4: Criar diretório accounts/prod — providers, variables, backend

**Files:**
- Create: `accounts/prod/providers.tf`
- Create: `accounts/prod/variables.tf`
- Create: `accounts/prod/backend.tf`
- Create: `accounts/prod/backend.hcl`
- Create: `accounts/prod/backend.hcl.example`

- [ ] **Step 1: Criar `accounts/prod/providers.tf`**

```hcl
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.profile

  assume_role {
    role_arn = "arn:aws:iam::${var.prod_account_id}:role/TerraformExecutionRole"
  }

  default_tags {
    tags = {
      Project     = "aws-network-poc"
      ManagedBy   = "terraform"
      Environment = "prod"
      Owner       = var.owner
    }
  }
}
```

- [ ] **Step 2: Criar `accounts/prod/variables.tf`**

```hcl
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources"
}

variable "prod_account_id" {
  type        = string
  description = "AWS Account ID of the prod spoke account"
}

variable "owner" {
  type        = string
  description = "Owner tag applied to all resources"
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket name for Terraform remote state (same bucket as hub, different key)"
}

variable "profile" {
  type        = string
  default     = null
  description = "AWS CLI profile usado como credencial base para o assume_role. Use ct8-hub pois a trust policy da role prod permite o root da conta hub."
}
```

- [ ] **Step 3: Criar `accounts/prod/backend.tf`**

```hcl
terraform {
  backend "s3" {
    key          = "prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
```

- [ ] **Step 4: Criar `accounts/prod/backend.hcl`**

```hcl
bucket  = "aws-network-poc-tfstate-225119180422"
region  = "us-east-1"
profile = "ct8-hub"
```

- [ ] **Step 5: Criar `accounts/prod/backend.hcl.example`**

```hcl
bucket  = "aws-network-poc-tfstate-<HUB_ACCOUNT_ID>"
region  = "us-east-1"
profile = "<AWS_CLI_PROFILE_HUB>"  # backend está na conta hub mesmo para a conta prod
```

- [ ] **Step 6: Commit**

```bash
cd /Users/fernando/Work/estudos/aws-network
git add accounts/prod/providers.tf accounts/prod/variables.tf accounts/prod/backend.tf accounts/prod/backend.hcl accounts/prod/backend.hcl.example
git commit -m "feat(prod): add provider, variables, and backend config"
```

---

### Task 5: Criar accounts/prod — tfvars, VPC, TGW attachment, routes, outputs

**Files:**
- Create: `accounts/prod/terraform.tfvars`
- Create: `accounts/prod/terraform.tfvars.example`
- Create: `accounts/prod/main.tf`
- Create: `accounts/prod/tgw-attachment.tf`
- Create: `accounts/prod/routes.tf`
- Create: `accounts/prod/outputs.tf`

- [ ] **Step 1: Criar `accounts/prod/terraform.tfvars`**

```hcl
aws_region      = "us-east-1"
prod_account_id = "745416886900"
owner           = "fernando"
state_bucket    = "aws-network-poc-tfstate-225119180422"
profile         = "ct8-hub"
```

- [ ] **Step 2: Criar `accounts/prod/terraform.tfvars.example`**

```hcl
aws_region      = "us-east-1"
prod_account_id = "<PROD_ACCOUNT_ID>"
owner           = "<OWNER>"
state_bucket    = "aws-network-poc-tfstate-<HUB_ACCOUNT_ID>"
profile         = "<AWS_CLI_PROFILE_HUB>"  # usa ct8-hub: trust policy da role prod permite hub account root
```

- [ ] **Step 3: Criar `accounts/prod/main.tf`**

```hcl
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr    = "10.11.0.0/16"
  environment = "prod"
  azs         = ["${var.aws_region}a", "${var.aws_region}b"]

  tgw_subnet_cidrs      = ["10.11.2.0/28", "10.11.3.0/28"]
  workload_subnet_cidrs = ["10.11.0.0/24", "10.11.1.0/24"]

  enable_igw = false
}
```

- [ ] **Step 4: Criar `accounts/prod/tgw-attachment.tf`**

```hcl
data "terraform_remote_state" "hub" {
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "hub/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

module "tgw_spoke" {
  source = "../../modules/tgw-spoke"

  transit_gateway_id = data.terraform_remote_state.hub.outputs.tgw_id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.tgw_subnet_ids
  environment        = "prod"
}
```

- [ ] **Step 5: Criar `accounts/prod/routes.tf`**

```hcl
# rt-workload: workload-a and workload-b subnets
resource "aws_route_table" "workload" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = "prod-rt-workload" }
}

resource "aws_route" "workload_to_hub" {
  route_table_id         = aws_route_table.workload.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = data.terraform_remote_state.hub.outputs.tgw_id

  depends_on = [module.tgw_spoke]
}

resource "aws_route" "workload_default" {
  route_table_id         = aws_route_table.workload.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = data.terraform_remote_state.hub.outputs.tgw_id

  depends_on = [module.tgw_spoke]
}

resource "aws_route_table_association" "workload" {
  count          = length(module.vpc.workload_subnet_ids)
  subnet_id      = module.vpc.workload_subnet_ids[count.index]
  route_table_id = aws_route_table.workload.id
}

# rt-tgw-attachment: local only — TGW manages routing at this boundary
resource "aws_route_table" "tgw_attachment" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = "prod-rt-tgw-attachment" }
}

resource "aws_route_table_association" "tgw_attachment" {
  count          = length(module.vpc.tgw_subnet_ids)
  subnet_id      = module.vpc.tgw_subnet_ids[count.index]
  route_table_id = aws_route_table.tgw_attachment.id
}

# NACL on TGW attachment subnets (stateless extra layer)
resource "aws_network_acl" "tgw_attachment" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.tgw_subnet_ids

  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "10.0.0.0/8"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "prod-nacl-tgw-attachment" }
}
```

- [ ] **Step 6: Criar `accounts/prod/outputs.tf`**

```hcl
output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "Prod VPC ID"
}

output "tgw_attachment_id" {
  value       = module.tgw_spoke.attachment_id
  description = "TGW attachment ID — read by hub account in phase 2 to add route table association and static route"
}

output "workload_subnet_ids" {
  value       = module.vpc.workload_subnet_ids
  description = "Workload subnet IDs — use for deploying resources"
}
```

- [ ] **Step 7: Commit**

```bash
cd /Users/fernando/Work/estudos/aws-network
git add accounts/prod/
git commit -m "feat(prod): add prod spoke VPC, TGW attachment, routes, and outputs"
```

---

### Task 6: Apply hub fase 1.5 (RAM share + rota pública para prod)

**Contexto:** Re-apply do hub com `prod_tgw_attachment_done = false` (valor atual). Isso adiciona o RAM share e a rota pública para `10.11.0.0/16` sem tentar ler o state prod (que ainda não existe).

- [ ] **Step 1: Exportar credenciais**

```bash
source /Users/fernando/Work/estudos/aws-network/scripts/tf-env.sh ct8-hub
```

- [ ] **Step 2: Plan do hub**

```bash
cd /Users/fernando/Work/estudos/aws-network/accounts/hub
terraform plan
```

Resultado esperado: `2 to add` — `aws_ram_principal_association.prod` e `aws_route.public_to_prod`.

- [ ] **Step 3: Apply do hub**

```bash
terraform apply
```

Resultado esperado: `Apply complete! Resources: 2 added, 0 changed, 0 destroyed.`

---

### Task 7: Init e apply de accounts/prod

**Contexto:** Inicializar o diretório prod e provisionar a VPC e o TGW attachment. O hub já compartilhou o TGW via RAM, então o attachment será aceito automaticamente (`auto_accept_shared_attachments = enable` no TGW).

- [ ] **Step 1: Inicializar o diretório prod**

```bash
cd /Users/fernando/Work/estudos/aws-network/accounts/prod
terraform init -backend-config=backend.hcl
```

Resultado esperado: `Terraform has been successfully initialized!`

- [ ] **Step 2: Plan do prod**

```bash
terraform plan
```

Resultado esperado: `14 to add` (ou similar) — VPC, subnets, route tables, NACLs, TGW attachment.

- [ ] **Step 3: Apply do prod**

```bash
terraform apply
```

Resultado esperado: `Apply complete! Resources: N added, 0 changed, 0 destroyed.`

- [ ] **Step 4: Verificar outputs**

```bash
terraform output
```

Resultado esperado:
```
tgw_attachment_id = "tgw-attach-XXXXXXXXXXXXXXXXX"
vpc_id            = "vpc-XXXXXXXXXXXXXXXXX"
workload_subnet_ids = [
  "subnet-XXXXXXXXXXXXXXXXX",
  "subnet-XXXXXXXXXXXXXXXXX",
]
```

---

### Task 8: Hub fase 2 — associar attachment prod no TGW RT

**Contexto:** Com o TGW attachment prod criado, o hub precisa associá-lo ao route table do TGW e adicionar a rota `10.11.0.0/16`. Isso é feito setando `prod_tgw_attachment_done = true`.

- [ ] **Step 1: Atualizar terraform.tfvars do hub**

Em `accounts/hub/terraform.tfvars`, alterar:

```
prod_tgw_attachment_done = true
```

- [ ] **Step 2: Plan do hub**

```bash
cd /Users/fernando/Work/estudos/aws-network/accounts/hub
terraform plan
```

Resultado esperado: `2 to add` — `aws_ec2_transit_gateway_route_table_association.prod[0]` e `aws_ec2_transit_gateway_route.to_prod_vpc[0]`.

- [ ] **Step 3: Apply do hub**

```bash
terraform apply
```

Resultado esperado: `Apply complete! Resources: 2 added, 0 changed, 0 destroyed.`

- [ ] **Step 4: Verificar rotas no TGW**

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $(terraform output -raw tgw_route_table_id) \
  --filters "Name=state,Values=active" \
  --profile ct8-hub \
  --query 'Routes[*].{Dest:DestinationCidrBlock,State:State}' \
  --output table
```

Resultado esperado:
```
| Dest          | State  |
|---------------|--------|
| 0.0.0.0/0     | active |
| 10.0.0.0/16   | active |
| 10.10.0.0/16  | active |
| 10.11.0.0/16  | active |
```

- [ ] **Step 5: Commit do tfvars atualizado**

```bash
cd /Users/fernando/Work/estudos/aws-network
git add accounts/hub/terraform.tfvars
git commit -m "feat(hub): enable prod spoke TGW phase 2"
```

---

### Task 9: Commit do spec e plano

- [ ] **Step 1: Commit dos documentos**

```bash
cd /Users/fernando/Work/estudos/aws-network
git add docs/superpowers/
git commit -m "docs: add prod spoke design spec and implementation plan"
```

---

## Notas de Rollback

Para desfazer:

```bash
# 1. Hub: desabilitar fase 2 prod
sed -i '' 's/prod_tgw_attachment_done = true/prod_tgw_attachment_done = false/' accounts/hub/terraform.tfvars
cd accounts/hub && terraform apply

# 2. Destruir spoke prod
cd ../prod && terraform destroy

# 3. Hub: remover RAM share e rota (requer remover vars prod do tfvars e ram.tf/routes.tf/tgw.tf)
```
