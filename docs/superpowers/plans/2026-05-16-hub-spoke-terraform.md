# Hub/Spoke Network POC — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar infraestrutura hub/spoke na AWS com Transit Gateway, NAT Gateway centralizado e egresso de internet pelo hub, gerenciada como IaC em Terraform.

**Architecture:** Monorepo com módulos compartilhados (`modules/vpc`, `modules/tgw-spoke`). Hub account é dona do Transit Gateway, compartilhado com Dev via AWS RAM. Egresso internet do spoke: workload → TGW → hub TGW subnet → NAT GW → IGW → internet. Apply em duas fases: hub primeiro, depois dev, depois hub novamente para adicionar rota estática do spoke no TGW route table.

**Tech Stack:** Terraform >= 1.10, AWS Provider ~> 5.0, Transit Gateway, RAM, NAT Gateway, VPC Flow Logs (CloudWatch)

---

## Pré-requisitos (executar manualmente antes de qualquer task)

Criar `TerraformExecutionRole` em cada conta. Substitua `<HUB_ACCOUNT_ID>` e `<DEV_ACCOUNT_ID>` pelos valores reais.

### Hub Account
```bash
aws iam create-role \
  --role-name TerraformExecutionRole \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::<HUB_ACCOUNT_ID>:root"},"Action":"sts:AssumeRole"}]
  }' \
  --profile hub-admin

aws iam attach-role-policy \
  --role-name TerraformExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile hub-admin
```

### Dev Account
```bash
aws iam create-role \
  --role-name TerraformExecutionRole \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::<HUB_ACCOUNT_ID>:root"},"Action":"sts:AssumeRole"}]
  }' \
  --profile dev-admin

aws iam attach-role-policy \
  --role-name TerraformExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile dev-admin
```

> Trust policy da role Dev permite o root da conta Hub assumir ela. O operador usa credenciais da conta Hub (profile `hub-admin`) em todos os applies — o provider do dev usa `assume_role` chain via Hub→Dev.

---

## Estrutura de Arquivos

```
aws-network/
├── .gitignore
├── .terraform-version
├── bootstrap/
│   ├── main.tf
│   ├── outputs.tf
│   └── variables.tf
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   └── tgw-spoke/
│       ├── main.tf
│       ├── outputs.tf
│       └── variables.tf
└── accounts/
    ├── hub/
    │   ├── backend.hcl.example
    │   ├── backend.tf
    │   ├── main.tf
    │   ├── nat.tf
    │   ├── outputs.tf
    │   ├── providers.tf
    │   ├── ram.tf
    │   ├── routes.tf
    │   ├── terraform.tfvars.example
    │   ├── tgw.tf
    │   └── variables.tf
    └── dev/
        ├── backend.hcl.example
        ├── backend.tf
        ├── main.tf
        ├── outputs.tf
        ├── providers.tf
        ├── routes.tf
        ├── terraform.tfvars.example
        ├── tgw-attachment.tf
        └── variables.tf
```

---

## Apply Order

1. `bootstrap/` — cria S3 + DynamoDB (state local, sem backend remoto)
2. `accounts/hub/` com `dev_tgw_attachment_done = false` — cria TGW, NAT, RAM share
3. `accounts/dev/` — cria VPC, TGW attachment
4. `accounts/hub/` com `dev_tgw_attachment_done = true` — adiciona rota 10.10.0.0/16 → dev no TGW

---

## Task 1: Arquivos base do repositório

**Files:**
- Create: `.terraform-version`
- Modify: `.gitignore`

- [ ] **Step 1: Criar `.terraform-version`**

```
1.10.0
```

- [ ] **Step 2: Atualizar `.gitignore`**

Adicionar ao `.gitignore` existente:

```gitignore
# Terraform
.terraform/
*.tfstate
*.tfstate.backup
.terraform.lock.hcl
terraform.tfvars
backend.hcl
*.tfplan

# Superpowers
.superpowers/
```

- [ ] **Step 3: Commit**

```bash
git add .terraform-version .gitignore
git commit -m "chore: add terraform version pin and gitignore rules"
```

---

## Task 2: Bootstrap — S3 + DynamoDB

**Files:**
- Create: `bootstrap/main.tf`
- Create: `bootstrap/variables.tf`
- Create: `bootstrap/outputs.tf`

- [ ] **Step 1: Criar `bootstrap/variables.tf`**

```hcl
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "aws-network-poc"
}

variable "owner" {
  type = string
}
```

- [ ] **Step 2: Criar `bootstrap/main.tf`**

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
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  bucket_suffix = data.aws_caller_identity.current.account_id
  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
    Owner     = var.owner
  }
}

resource "aws_s3_bucket" "state" {
  bucket = "${var.project_name}-tfstate-${local.bucket_suffix}"

  tags = merge(local.common_tags, { Name = "${var.project_name}-tfstate" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.state_logs.id
  target_prefix = "state-access-logs/"
}

resource "aws_s3_bucket" "state_logs" {
  bucket = "${var.project_name}-tfstate-logs-${local.bucket_suffix}"

  tags = merge(local.common_tags, { Name = "${var.project_name}-tfstate-logs" })
}

resource "aws_s3_bucket_public_access_block" "state_logs" {
  bucket                  = aws_s3_bucket.state_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = "${var.project_name}-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-tflock" })
}
```

- [ ] **Step 3: Criar `bootstrap/outputs.tf`**

```hcl
output "state_bucket_name" {
  value = aws_s3_bucket.state.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.lock.name
}
```

- [ ] **Step 4: Criar `bootstrap/terraform.tfvars`** (não comitar — está no .gitignore)

```hcl
aws_region   = "us-east-1"
project_name = "aws-network-poc"
owner        = "fernando"
```

- [ ] **Step 5: Validar e aplicar bootstrap**

```bash
cd bootstrap
terraform init
terraform fmt -check
terraform validate
# Esperado: Success! The configuration is valid.
terraform plan -out=bootstrap.tfplan
# Revisar: deve mostrar S3 buckets (2) + DynamoDB (1) a criar
terraform apply bootstrap.tfplan
```

Anotar o output:
```
state_bucket_name = "aws-network-poc-tfstate-<ACCOUNT_ID>"
lock_table_name   = "aws-network-poc-tflock"
```

- [ ] **Step 6: Commit**

```bash
cd ..
git add bootstrap/
git commit -m "feat: add terraform bootstrap (S3 state + DynamoDB lock)"
```

---

## Task 3: Módulo VPC

**Files:**
- Create: `modules/vpc/variables.tf`
- Create: `modules/vpc/main.tf`
- Create: `modules/vpc/outputs.tf`

- [ ] **Step 1: Criar `modules/vpc/variables.tf`**

```hcl
variable "vpc_cidr" {
  type = string
}

variable "environment" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = []
}

variable "tgw_subnet_cidrs" {
  type = list(string)
}

variable "workload_subnet_cidrs" {
  type    = list(string)
  default = []
}

variable "enable_igw" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

- [ ] **Step 2: Criar `modules/vpc/main.tf`**

```hcl
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.environment}-vpc" })
}

resource "aws_internet_gateway" "this" {
  count  = var.enable_igw ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.environment}-igw" })
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.environment}-public-${substr(var.azs[count.index], -1, 1)}"
    Tier = "public"
  })
}

resource "aws_subnet" "tgw" {
  count             = length(var.tgw_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.tgw_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.environment}-tgw-${substr(var.azs[count.index], -1, 1)}"
    Tier = "tgw-attachment"
  })
}

resource "aws_subnet" "workload" {
  count             = length(var.workload_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.workload_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.environment}-workload-${substr(var.azs[count.index], -1, 1)}"
    Tier = "workload"
  })
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc-flow-logs/${var.environment}"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_iam_role" "flow_log" {
  name = "${var.environment}-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_log" {
  name = "${var.environment}-vpc-flow-log-policy"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn

  tags = merge(var.tags, { Name = "${var.environment}-vpc-flow-log" })
}
```

- [ ] **Step 3: Criar `modules/vpc/outputs.tf`**

```hcl
output "vpc_id" {
  value = aws_vpc.this.id
}

output "igw_id" {
  value = length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : null
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "tgw_subnet_ids" {
  value = aws_subnet.tgw[*].id
}

output "workload_subnet_ids" {
  value = aws_subnet.workload[*].id
}
```

- [ ] **Step 4: Validar módulo**

```bash
cd modules/vpc
terraform fmt -check
# Esperado: sem output (formato OK)
# terraform validate não funciona direto em módulos sem root, pulamos
cd ../..
```

- [ ] **Step 5: Commit**

```bash
git add modules/vpc/
git commit -m "feat: add reusable vpc terraform module with flow logs"
```

---

## Task 4: Módulo TGW-Spoke

**Files:**
- Create: `modules/tgw-spoke/variables.tf`
- Create: `modules/tgw-spoke/main.tf`
- Create: `modules/tgw-spoke/outputs.tf`

- [ ] **Step 1: Criar `modules/tgw-spoke/variables.tf`**

```hcl
variable "transit_gateway_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

- [ ] **Step 2: Criar `modules/tgw-spoke/main.tf`**

> **Nota:** A associação do attachment ao route table do TGW é feita pelo hub (Task 16), não aqui. Isso é necessário porque a API `AssociateTransitGatewayRouteTable` precisa ser chamada com credenciais do TGW owner (hub), não do spoke.

```hcl
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, { Name = "${var.environment}-tgw-attachment" })
}
```

- [ ] **Step 3: Criar `modules/tgw-spoke/outputs.tf`**

```hcl
output "attachment_id" {
  value = aws_ec2_transit_gateway_vpc_attachment.this.id
}
```

- [ ] **Step 4: Commit**

```bash
git add modules/tgw-spoke/
git commit -m "feat: add tgw-spoke module for transit gateway attachment"
```

---

## Task 5: Hub — Providers, Backend e Variables

**Files:**
- Create: `accounts/hub/providers.tf`
- Create: `accounts/hub/backend.tf`
- Create: `accounts/hub/backend.hcl.example`
- Create: `accounts/hub/variables.tf`
- Create: `accounts/hub/terraform.tfvars.example`

- [ ] **Step 1: Criar `accounts/hub/providers.tf`**

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
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::${var.hub_account_id}:role/TerraformExecutionRole"
  }

  default_tags {
    tags = {
      Project     = "aws-network-poc"
      ManagedBy   = "terraform"
      Environment = "hub"
      Owner       = var.owner
    }
  }
}
```

- [ ] **Step 2: Criar `accounts/hub/backend.tf`**

```hcl
terraform {
  backend "s3" {
    key     = "hub/terraform.tfstate"
    encrypt = true
  }
}
```

- [ ] **Step 3: Criar `accounts/hub/backend.hcl.example`**

```hcl
bucket         = "aws-network-poc-tfstate-<HUB_ACCOUNT_ID>"
dynamodb_table = "aws-network-poc-tflock"
region         = "us-east-1"
```

- [ ] **Step 4: Copiar como `backend.hcl` e preencher com valores reais do bootstrap**

```bash
cp accounts/hub/backend.hcl.example accounts/hub/backend.hcl
# Editar accounts/hub/backend.hcl com os valores reais do output do bootstrap
```

- [ ] **Step 5: Criar `accounts/hub/variables.tf`**

```hcl
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "hub_account_id" {
  type = string
}

variable "dev_account_id" {
  type = string
}

variable "owner" {
  type = string
}

variable "state_bucket" {
  type = string
}

variable "lock_table" {
  type = string
}

variable "dev_tgw_attachment_done" {
  type    = bool
  default = false
  description = "Setar true após accounts/dev ser aplicado para adicionar rota TGW do spoke"
}
```

- [ ] **Step 6: Criar `accounts/hub/terraform.tfvars.example`**

```hcl
aws_region              = "us-east-1"
hub_account_id          = "<HUB_ACCOUNT_ID>"
dev_account_id          = "<DEV_ACCOUNT_ID>"
owner                   = "fernando"
state_bucket            = "aws-network-poc-tfstate-<HUB_ACCOUNT_ID>"
lock_table              = "aws-network-poc-tflock"
dev_tgw_attachment_done = false
```

- [ ] **Step 7: Criar `terraform.tfvars` com valores reais (não comitar)**

```bash
cp accounts/hub/terraform.tfvars.example accounts/hub/terraform.tfvars
# Editar com os valores reais
```

- [ ] **Step 8: Commit dos arquivos versionados**

```bash
git add accounts/hub/providers.tf accounts/hub/backend.tf \
        accounts/hub/backend.hcl.example accounts/hub/variables.tf \
        accounts/hub/terraform.tfvars.example
git commit -m "feat: add hub account terraform providers and backend config"
```

---

## Task 6: Hub — VPC

**Files:**
- Create: `accounts/hub/main.tf`

- [ ] **Step 1: Criar `accounts/hub/main.tf`**

```hcl
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr    = "10.0.0.0/16"
  environment = "hub"
  azs         = ["${var.aws_region}a", "${var.aws_region}b"]

  public_subnet_cidrs = ["10.0.0.0/24", "10.0.1.0/24"]
  tgw_subnet_cidrs    = ["10.0.2.0/28", "10.0.3.0/28"]

  enable_igw = true

  tags = {
    Environment = "hub"
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add accounts/hub/main.tf
git commit -m "feat: add hub vpc configuration using vpc module"
```

---

## Task 7: Hub — Transit Gateway

**Files:**
- Create: `accounts/hub/tgw.tf`

- [ ] **Step 1: Criar `accounts/hub/tgw.tf`**

```hcl
resource "aws_ec2_transit_gateway" "this" {
  description                     = "Hub Transit Gateway"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "enable"
  dns_support                     = "enable"

  tags = { Name = "hub-tgw" }
}

resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = { Name = "hub-tgw-rt-main" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.tgw_subnet_ids

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "hub-tgw-attachment" }
}

resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

resource "aws_ec2_transit_gateway_route" "to_hub_vpc" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  destination_cidr_block         = "10.0.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

resource "aws_ec2_transit_gateway_route" "default_to_hub" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

# Fase 2: adicionado após accounts/dev ser aplicado
# A associação do attachment ao route table DEVE ser feita pelo hub (TGW owner)
data "terraform_remote_state" "dev" {
  count   = var.dev_tgw_attachment_done ? 1 : 0
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = "dev/terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = var.lock_table
    encrypt        = true
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "dev" {
  count                          = var.dev_tgw_attachment_done ? 1 : 0
  transit_gateway_attachment_id  = data.terraform_remote_state.dev[0].outputs.tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

resource "aws_ec2_transit_gateway_route" "to_dev_vpc" {
  count                          = var.dev_tgw_attachment_done ? 1 : 0
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  destination_cidr_block         = "10.10.0.0/16"
  transit_gateway_attachment_id  = data.terraform_remote_state.dev[0].outputs.tgw_attachment_id
}
```

- [ ] **Step 2: Commit**

```bash
git add accounts/hub/tgw.tf
git commit -m "feat: add hub transit gateway with route table and phase-2 spoke route"
```

---

## Task 8: Hub — NAT Gateway

**Files:**
- Create: `accounts/hub/nat.tf`

- [ ] **Step 1: Criar `accounts/hub/nat.tf`**

```hcl
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "hub-nat-eip" }

  depends_on = [module.vpc]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = module.vpc.public_subnet_ids[0]

  tags = { Name = "hub-nat-gw" }

  depends_on = [module.vpc]
}
```

- [ ] **Step 2: Commit**

```bash
git add accounts/hub/nat.tf
git commit -m "feat: add hub nat gateway (single az, poc cost optimization)"
```

---

## Task 9: Hub — Route Tables

**Files:**
- Create: `accounts/hub/routes.tf`

- [ ] **Step 1: Criar `accounts/hub/routes.tf`**

```hcl
# rt-public: subnets public-a e public-b
resource "aws_route_table" "public" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = "hub-rt-public" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = module.vpc.igw_id
}

resource "aws_route" "public_to_dev" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "10.10.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route_table_association" "public" {
  count          = length(module.vpc.public_subnet_ids)
  subnet_id      = module.vpc.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public.id
}

# rt-tgw-attachment: subnets tgw-a e tgw-b do hub
resource "aws_route_table" "tgw_attachment" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = "hub-rt-tgw-attachment" }
}

resource "aws_route" "tgw_attachment_default" {
  route_table_id         = aws_route_table.tgw_attachment.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "tgw_attachment" {
  count          = length(module.vpc.tgw_subnet_ids)
  subnet_id      = module.vpc.tgw_subnet_ids[count.index]
  route_table_id = aws_route_table.tgw_attachment.id
}

# NACLs nas subnets TGW attachment (camada stateless extra)
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

  tags = { Name = "hub-nacl-tgw-attachment" }
}
```

- [ ] **Step 2: Commit**

```bash
git add accounts/hub/routes.tf
git commit -m "feat: add hub route tables (public + tgw-attachment) and nacls"
```

---

## Task 10: Hub — RAM Share e Outputs

**Files:**
- Create: `accounts/hub/ram.tf`
- Create: `accounts/hub/outputs.tf`

- [ ] **Step 1: Criar `accounts/hub/ram.tf`**

```hcl
resource "aws_ram_resource_share" "tgw" {
  name                      = "hub-tgw-share"
  allow_external_principals = false

  tags = { Name = "hub-tgw-share" }
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

resource "aws_ram_principal_association" "dev" {
  principal          = "arn:aws:iam::${var.dev_account_id}:root"
  resource_share_arn = aws_ram_resource_share.tgw.arn
}
```

- [ ] **Step 2: Criar `accounts/hub/outputs.tf`**

```hcl
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "tgw_id" {
  value = aws_ec2_transit_gateway.this.id
}

output "tgw_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.main.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.this.id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "tgw_subnet_ids" {
  value = module.vpc.tgw_subnet_ids
}
```

- [ ] **Step 3: Commit**

```bash
git add accounts/hub/ram.tf accounts/hub/outputs.tf
git commit -m "feat: add hub ram share for tgw and outputs"
```

---

## Task 11: Hub Phase 1 — Validar e Aplicar

- [ ] **Step 1: Inicializar backend**

```bash
cd accounts/hub
terraform init -backend-config=backend.hcl
# Esperado: Terraform initialized successfully
```

- [ ] **Step 2: Formatar e validar**

```bash
terraform fmt -check -recursive ../../
terraform validate
# Esperado: Success! The configuration is valid.
```

- [ ] **Step 3: Plan**

```bash
terraform plan -out=hub-phase1.tfplan
```

Verificar no output que serão criados (aproximadamente):
- 1 VPC + 4 subnets + 1 IGW
- 1 Transit Gateway + 1 TGW route table + 1 TGW attachment (hub)
- 1 EIP + 1 NAT Gateway
- 2 Route tables + associações + rotas
- 1 NACL
- 1 RAM resource share
- CloudWatch Log Group + IAM role (flow logs)

- [ ] **Step 4: Apply**

```bash
terraform apply hub-phase1.tfplan
```

- [ ] **Step 5: Verificar outputs**

```bash
terraform output
```

Confirmar que `tgw_id` e `tgw_route_table_id` têm valores.

---

## Task 12: Dev — Providers, Backend e Variables

**Files:**
- Create: `accounts/dev/providers.tf`
- Create: `accounts/dev/backend.tf`
- Create: `accounts/dev/backend.hcl.example`
- Create: `accounts/dev/variables.tf`
- Create: `accounts/dev/terraform.tfvars.example`

- [ ] **Step 1: Criar `accounts/dev/providers.tf`**

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
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::${var.dev_account_id}:role/TerraformExecutionRole"
  }

  default_tags {
    tags = {
      Project     = "aws-network-poc"
      ManagedBy   = "terraform"
      Environment = "dev"
      Owner       = var.owner
    }
  }
}
```

- [ ] **Step 2: Criar `accounts/dev/backend.tf`**

```hcl
terraform {
  backend "s3" {
    key     = "dev/terraform.tfstate"
    encrypt = true
  }
}
```

- [ ] **Step 3: Criar `accounts/dev/backend.hcl.example`**

```hcl
bucket         = "aws-network-poc-tfstate-<HUB_ACCOUNT_ID>"
dynamodb_table = "aws-network-poc-tflock"
region         = "us-east-1"
```

- [ ] **Step 4: Copiar como `backend.hcl` e preencher**

```bash
cp accounts/dev/backend.hcl.example accounts/dev/backend.hcl
# Editar com os valores reais (mesmo bucket do hub — contas diferentes, keys diferentes)
```

- [ ] **Step 5: Criar `accounts/dev/variables.tf`**

```hcl
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "hub_account_id" {
  type = string
}

variable "dev_account_id" {
  type = string
}

variable "owner" {
  type = string
}

variable "state_bucket" {
  type = string
}

variable "lock_table" {
  type = string
}
```

- [ ] **Step 6: Criar `accounts/dev/terraform.tfvars.example`**

```hcl
aws_region     = "us-east-1"
hub_account_id = "<HUB_ACCOUNT_ID>"
dev_account_id = "<DEV_ACCOUNT_ID>"
owner          = "fernando"
state_bucket   = "aws-network-poc-tfstate-<HUB_ACCOUNT_ID>"
lock_table     = "aws-network-poc-tflock"
```

- [ ] **Step 7: Criar `terraform.tfvars` com valores reais (não comitar)**

```bash
cp accounts/dev/terraform.tfvars.example accounts/dev/terraform.tfvars
# Editar com os valores reais
```

- [ ] **Step 8: Commit dos arquivos versionados**

```bash
cd ../..
git add accounts/dev/providers.tf accounts/dev/backend.tf \
        accounts/dev/backend.hcl.example accounts/dev/variables.tf \
        accounts/dev/terraform.tfvars.example
git commit -m "feat: add dev account terraform providers and backend config"
```

---

## Task 13: Dev — VPC

**Files:**
- Create: `accounts/dev/main.tf`

- [ ] **Step 1: Criar `accounts/dev/main.tf`**

```hcl
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr    = "10.10.0.0/16"
  environment = "dev"
  azs         = ["${var.aws_region}a", "${var.aws_region}b"]

  tgw_subnet_cidrs      = ["10.10.2.0/28", "10.10.3.0/28"]
  workload_subnet_cidrs = ["10.10.0.0/24", "10.10.1.0/24"]

  enable_igw = false

  tags = {
    Environment = "dev"
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add accounts/dev/main.tf
git commit -m "feat: add dev vpc configuration (no igw, egress via hub)"
```

---

## Task 14: Dev — TGW Attachment e Routes

**Files:**
- Create: `accounts/dev/tgw-attachment.tf`
- Create: `accounts/dev/routes.tf`
- Create: `accounts/dev/outputs.tf`

- [ ] **Step 1: Criar `accounts/dev/tgw-attachment.tf`**

```hcl
data "terraform_remote_state" "hub" {
  backend = "s3"
  config = {
    bucket         = var.state_bucket
    key            = "hub/terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = var.lock_table
    encrypt        = true
  }
}

module "tgw_spoke" {
  source = "../../modules/tgw-spoke"

  transit_gateway_id = data.terraform_remote_state.hub.outputs.tgw_id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.tgw_subnet_ids
  environment        = "dev"

  tags = { Environment = "dev" }
}
```

- [ ] **Step 2: Criar `accounts/dev/routes.tf`**

```hcl
# rt-workload: subnets workload-a e workload-b
resource "aws_route_table" "workload" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = "dev-rt-workload" }
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

# rt-tgw-attachment: apenas local (TGW gerencia o roteamento)
resource "aws_route_table" "tgw_attachment" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = "dev-rt-tgw-attachment" }
}

resource "aws_route_table_association" "tgw_attachment" {
  count          = length(module.vpc.tgw_subnet_ids)
  subnet_id      = module.vpc.tgw_subnet_ids[count.index]
  route_table_id = aws_route_table.tgw_attachment.id
}

# NACLs nas subnets TGW attachment
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

  tags = { Name = "dev-nacl-tgw-attachment" }
}
```

- [ ] **Step 3: Criar `accounts/dev/outputs.tf`**

```hcl
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "tgw_attachment_id" {
  value = module.tgw_spoke.attachment_id
}

output "workload_subnet_ids" {
  value = module.vpc.workload_subnet_ids
}
```

- [ ] **Step 4: Commit**

```bash
git add accounts/dev/tgw-attachment.tf accounts/dev/routes.tf accounts/dev/outputs.tf
git commit -m "feat: add dev tgw attachment, routes and outputs"
```

---

## Task 15: Dev — Validar e Aplicar

- [ ] **Step 1: Inicializar backend**

```bash
cd accounts/dev
terraform init -backend-config=backend.hcl
# Esperado: Terraform initialized successfully
```

- [ ] **Step 2: Validar**

```bash
terraform fmt -check
terraform validate
# Esperado: Success! The configuration is valid.
```

- [ ] **Step 3: Plan**

```bash
terraform plan -out=dev-phase1.tfplan
```

Verificar no output que serão criados:
- 1 VPC + 4 subnets (sem IGW)
- 1 TGW attachment + associação ao route table do hub
- 2 Route tables (workload + tgw-attachment) + rotas + associações
- 1 NACL
- CloudWatch Log Group + IAM role (flow logs)

- [ ] **Step 4: Apply**

```bash
terraform apply dev-phase1.tfplan
```

- [ ] **Step 5: Verificar outputs**

```bash
terraform output
```

Confirmar que `tgw_attachment_id` tem valor. Anotar o ID.

---

## Task 16: Hub Phase 2 — Rota TGW para Dev

- [ ] **Step 1: Atualizar `terraform.tfvars` do hub**

Em `accounts/hub/terraform.tfvars`, alterar:
```hcl
dev_tgw_attachment_done = true
```

- [ ] **Step 2: Plan**

```bash
cd accounts/hub
terraform plan -out=hub-phase2.tfplan
```

Verificar no output que serão criados:
- `aws_ec2_transit_gateway_route_table_association.dev[0]` — associa o attachment do spoke dev ao route table do hub
- `aws_ec2_transit_gateway_route.to_dev_vpc[0]` — rota estática 10.10.0.0/16 → dev attachment

- [ ] **Step 3: Apply**

```bash
terraform apply hub-phase2.tfplan
```

- [ ] **Step 4: Verificar rota no TGW**

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $(terraform output -raw tgw_route_table_id) \
  --filters "Name=state,Values=active" \
  --profile hub-admin \
  --query 'Routes[*].{Dest:DestinationCidrBlock,State:State}' \
  --output table
```

Esperado:
```
| Dest           | State  |
|----------------|--------|
| 0.0.0.0/0      | active |
| 10.0.0.0/16    | active |
| 10.10.0.0/16   | active |
```

---

## Task 17: Verificação End-to-End

- [ ] **Step 1: Criar EC2 de teste no spoke dev (workload subnet)**

```bash
# Pegar subnet ID da conta dev
DEV_SUBNET=$(cd accounts/dev && terraform output -json workload_subnet_ids | jq -r '.[0]')

# Criar security group temporário de teste
aws ec2 create-security-group \
  --group-name "test-sg" \
  --description "Teste de conectividade" \
  --vpc-id $(cd accounts/dev && terraform output -raw vpc_id) \
  --profile dev-admin

# Lançar instância com SSM (sem SSH aberto, boas práticas)
aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.micro \
  --subnet-id $DEV_SUBNET \
  --iam-instance-profile Name=SSMInstanceProfile \
  --security-group-ids <SG_ID> \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-connectivity}]' \
  --profile dev-admin
```

> Nota: requer SSM Instance Profile criado na conta dev. Se não existir, criar via console antes deste step.

- [ ] **Step 2: Testar egresso via SSM Session Manager**

```bash
aws ssm start-session \
  --target <INSTANCE_ID> \
  --profile dev-admin
```

Dentro da instância:
```bash
curl -s https://checkip.amazonaws.com
# Deve retornar o IP do NAT Gateway do hub (não um IP da conta dev)

traceroute 8.8.8.8
# Deve mostrar o caminho passando pelo NAT GW do hub
```

- [ ] **Step 3: Terminar instância de teste**

```bash
aws ec2 terminate-instances --instance-ids <INSTANCE_ID> --profile dev-admin
```

- [ ] **Step 4: Commit final do plano de implementação**

```bash
cd /path/to/aws-network
git add docs/superpowers/plans/
git commit -m "docs: add hub-spoke terraform implementation plan"
```
