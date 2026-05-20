# TGW Route Table Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolar tráfego spoke-to-spoke criando três TGW route tables independentes (hub, dev, prod) para que hub acesse ambos os spokes mas spokes não se alcancem mutuamente.

**Architecture:** Substituir a única `hub-tgw-rt-main` por três RTs: `hub-tgw-rt-hub` (associada ao hub attachment, com rotas para spokes), `hub-tgw-rt-dev` (associada ao dev attachment, rotas só para hub), `hub-tgw-rt-prod` (idem para prod). O TGW usa a RT do attachment de origem para decidir o destino — sem rota spoke→spoke na RT dos spokes = tráfego descartado.

**Tech Stack:** Terraform >= 1.10, provider AWS ~> 5.0, arquivo `accounts/hub/tgw.tf`.

---

## Mapa de Arquivos

**Modificar:**
- `accounts/hub/tgw.tf` — única mudança: nova estrutura de route tables

**Sem mudanças:**
- `accounts/hub/routes.tf`, `ram.tf`, `variables.tf`, `terraform.tfvars`
- `accounts/dev/`, `accounts/prod/` — configuração do lado dos spokes não muda

---

### Task 1: Reescrever `accounts/hub/tgw.tf` com 3 route tables

**Files:**
- Modify: `accounts/hub/tgw.tf`

- [ ] **Step 1: Substituir o conteúdo completo de `accounts/hub/tgw.tf`**

O arquivo atual tem uma única RT compartilhada (`hub-tgw-rt-main`). Substitua o conteúdo completo pelo seguinte:

```hcl
resource "aws_ec2_transit_gateway" "this" {
  description                     = "Hub Transit Gateway"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "enable"
  dns_support                     = "enable"

  tags = { Name = "hub-tgw" }
}

# Hub route table — associada ao hub attachment; contém rotas para os spokes
resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = { Name = "hub-tgw-rt-hub" }
}

# Dev route table — associada ao dev attachment; rotas apenas para o hub (sem rota para prod)
resource "aws_ec2_transit_gateway_route_table" "dev" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = { Name = "hub-tgw-rt-dev" }
}

resource "aws_ec2_transit_gateway_route" "dev_to_hub" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
  destination_cidr_block         = "10.0.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

resource "aws_ec2_transit_gateway_route" "dev_default" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

# Prod route table — associada ao prod attachment; rotas apenas para o hub (sem rota para dev)
resource "aws_ec2_transit_gateway_route_table" "prod" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = { Name = "hub-tgw-rt-prod" }
}

resource "aws_ec2_transit_gateway_route" "prod_to_hub" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
  destination_cidr_block         = "10.0.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

resource "aws_ec2_transit_gateway_route" "prod_default" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
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

# Phase 2: added after accounts/dev is applied
# Route table association MUST be done by hub (TGW owner) not by spoke account
data "terraform_remote_state" "dev" {
  count   = var.dev_tgw_attachment_done ? 1 : 0
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "dev/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "dev" {
  count                          = var.dev_tgw_attachment_done ? 1 : 0
  transit_gateway_attachment_id  = data.terraform_remote_state.dev[0].outputs.tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
}

resource "aws_ec2_transit_gateway_route" "to_dev_vpc" {
  count                          = var.dev_tgw_attachment_done ? 1 : 0
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  destination_cidr_block         = "10.10.0.0/16"
  transit_gateway_attachment_id  = data.terraform_remote_state.dev[0].outputs.tgw_attachment_id
}

# Phase 2: added after accounts/prod is applied
# Route table association MUST be done by hub (TGW owner) not by spoke account
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
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route" "to_prod_vpc" {
  count                          = var.prod_tgw_attachment_done ? 1 : 0
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  destination_cidr_block         = "10.11.0.0/16"
  transit_gateway_attachment_id  = data.terraform_remote_state.prod[0].outputs.tgw_attachment_id
}
```

**Resumo das mudanças em relação ao arquivo atual:**
- Tag de `main` RT: `"hub-tgw-rt-main"` → `"hub-tgw-rt-hub"`
- **Removidos:** `aws_ec2_transit_gateway_route.to_hub_vpc` e `aws_ec2_transit_gateway_route.default_to_hub` (eram spoke→hub na RT hub; agora ficam nas RTs de dev e prod)
- **Adicionados:** `aws_ec2_transit_gateway_route_table.dev`, `.prod` e suas rotas (`dev_to_hub`, `dev_default`, `prod_to_hub`, `prod_default`)
- **Associações dev/prod:** `transit_gateway_route_table_id` mudou de `main.id` para `dev.id`/`prod.id`

- [ ] **Step 2: Validar HCL**

```bash
cd /Users/fernando/Work/estudos/aws-network/accounts/hub
terraform validate
```

Resultado esperado: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
cd /Users/fernando/Work/estudos/aws-network
git add accounts/hub/tgw.tf
git commit -m "feat(hub): isolate spoke-to-spoke traffic with 3 TGW route tables"
```

---

### Task 2: Aplicar mudanças no hub

**Contexto:** Terraform vai:
- Adicionar: 2 novas RTs + 4 novas rotas nas spoke RTs = 6 recursos
- Destruir: `to_hub_vpc` e `default_to_hub` = 2 recursos
- Substituir (destroy+create): associações dev[0] e prod[0] (mudança de RT força recriação) = 2 recursos
- Modificar in-place: tag da RT `main` = 1 recurso

As associações são destruídas antes de recriadas (comportamento padrão do Terraform). Há uma janela breve onde os spokes ficam sem associação — aceitável em ambiente de estudo.

- [ ] **Step 1: Exportar credenciais**

```bash
source /Users/fernando/Work/estudos/aws-network/scripts/tf-env.sh ct8-hub
```

Se o script falhar por SSO expirado, use `AWS_PROFILE=ct8-hub` diretamente (o perfil SSO lida com refresh automaticamente).

- [ ] **Step 2: Plan**

```bash
cd /Users/fernando/Work/estudos/aws-network/accounts/hub
terraform plan
```

Resultado esperado: `6 to add, 2 to destroy, 1 to change` (mais 2 replace das associações = total ~11 ações). Verifique:
- Nenhum destroy de recursos além de `to_hub_vpc`, `default_to_hub`, e as associações old (que serão recriadas)
- Nenhum destroy de VPCs, attachments, NAT GW, ou RAM resources

Se o plan mostrar destroys inesperados, **NÃO aplique** — reporte o output completo.

- [ ] **Step 3: Apply**

```bash
terraform apply -auto-approve
```

Resultado esperado: `Apply complete! Resources: 6 added, 1 changed, 4 destroyed.` (os destroys incluem os 2 recursos removidos + 2 associações antigas que são recriadas).

---

### Task 3: Verificar isolamento de roteamento

- [ ] **Step 1: Capturar IDs das 3 route tables**

```bash
cd /Users/fernando/Work/estudos/aws-network/accounts/hub
HUB_RT=$(terraform output -raw tgw_route_table_id)
DEV_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=hub-tgw-rt-dev" \
  --profile ct8-hub \
  --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
  --output text)
PROD_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=hub-tgw-rt-prod" \
  --profile ct8-hub \
  --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
  --output text)
echo "Hub RT: $HUB_RT"
echo "Dev RT: $DEV_RT"
echo "Prod RT: $PROD_RT"
```

Resultado esperado: três IDs distintos no formato `tgw-rtb-XXXXXXXXXXXXXXXXX`.

- [ ] **Step 2: Verificar hub RT — deve ver dev e prod**

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $HUB_RT \
  --filters "Name=state,Values=active" \
  --profile ct8-hub \
  --query 'Routes[*].{Dest:DestinationCidrBlock,State:State}' \
  --output table
```

Resultado esperado:
```
| Dest          | State  |
|---------------|--------|
| 10.10.0.0/16  | active |
| 10.11.0.0/16  | active |
```

**Não deve conter** `0.0.0.0/0` nem `10.0.0.0/16` (essas rotas foram removidas da hub RT).

- [ ] **Step 3: Verificar dev RT — deve ver apenas hub, sem prod**

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $DEV_RT \
  --filters "Name=state,Values=active" \
  --profile ct8-hub \
  --query 'Routes[*].{Dest:DestinationCidrBlock,State:State}' \
  --output table
```

Resultado esperado:
```
| Dest         | State  |
|--------------|--------|
| 0.0.0.0/0    | active |
| 10.0.0.0/16  | active |
```

**Não deve conter** `10.11.0.0/16` (prod). Se aparecer, o isolamento falhou.

- [ ] **Step 4: Verificar prod RT — deve ver apenas hub, sem dev**

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $PROD_RT \
  --filters "Name=state,Values=active" \
  --profile ct8-hub \
  --query 'Routes[*].{Dest:DestinationCidrBlock,State:State}' \
  --output table
```

Resultado esperado:
```
| Dest         | State  |
|--------------|--------|
| 0.0.0.0/0    | active |
| 10.0.0.0/16  | active |
```

**Não deve conter** `10.10.0.0/16` (dev). Se aparecer, o isolamento falhou.

- [ ] **Step 5: Commit do spec e plano**

```bash
cd /Users/fernando/Work/estudos/aws-network
git add docs/superpowers/
git commit -m "docs: add TGW RT isolation plan"
```

---

## Notas de Rollback

Para desfazer (restaurar RT única compartilhada):

```bash
# Reverter tgw.tf para o conteúdo anterior
git checkout HEAD~2 -- accounts/hub/tgw.tf
cd accounts/hub
terraform plan   # verificar antes de aplicar
terraform apply
```
