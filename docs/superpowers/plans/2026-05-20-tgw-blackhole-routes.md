# TGW Blackhole Routes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar rotas blackhole explícitas nas spoke TGW route tables para que tentativas de acesso entre dev e prod sejam descartadas com intenção documentada.

**Architecture:** Dois novos recursos `aws_ec2_transit_gateway_route` com `blackhole = true` em `accounts/hub/tgw.tf`: um na `hub-tgw-rt-dev` bloqueando `10.11.0.0/16` (prod), outro na `hub-tgw-rt-prod` bloqueando `10.10.0.0/16` (dev). Nenhuma attachment é referenciada — `blackhole = true` cria uma rota do tipo blackhole na AWS.

**Tech Stack:** Terraform >= 1.10, provider AWS ~> 5.0.

---

## Mapa de Arquivos

**Modificar:**
- `accounts/hub/tgw.tf` — adicionar 2 recursos blackhole ao final do arquivo

---

### Task 1: Adicionar blackhole routes em `accounts/hub/tgw.tf`

**Files:**
- Modify: `accounts/hub/tgw.tf`

- [ ] **Step 1: Ler o final atual do arquivo para encontrar o ponto de inserção**

```bash
tail -10 /Users/fernando/Work/estudos/aws-network/accounts/hub/tgw.tf
```

O arquivo termina com o bloco `aws_ec2_transit_gateway_route.to_prod_vpc`. As novas rotas vão depois.

- [ ] **Step 2: Adicionar as rotas blackhole ao final de `accounts/hub/tgw.tf`**

Adicionar exatamente este conteúdo após a última linha do arquivo:

```hcl

# Blackhole routes — spoke-to-spoke traffic is explicitly dropped
resource "aws_ec2_transit_gateway_route" "dev_blackhole_prod" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
  destination_cidr_block         = "10.11.0.0/16"
  blackhole                      = true
}

resource "aws_ec2_transit_gateway_route" "prod_blackhole_dev" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
  destination_cidr_block         = "10.10.0.0/16"
  blackhole                      = true
}
```

- [ ] **Step 3: Validar HCL**

```bash
cd /Users/fernando/Work/estudos/aws-network/accounts/hub
terraform validate
```

Resultado esperado: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
cd /Users/fernando/Work/estudos/aws-network
git add accounts/hub/tgw.tf
git commit -m "feat(hub): add explicit blackhole routes to block spoke-to-spoke traffic"
```

---

### Task 2: Aplicar e verificar

- [ ] **Step 1: Credenciais**

```bash
source /Users/fernando/Work/estudos/aws-network/scripts/tf-env.sh ct8-hub
```

Se falhar por SSO expirado, use `AWS_PROFILE=ct8-hub` diretamente nos comandos seguintes.

- [ ] **Step 2: Plan**

```bash
cd /Users/fernando/Work/estudos/aws-network/accounts/hub
terraform plan
```

Resultado esperado: exatamente `2 to add, 0 to change, 0 to destroy`. Se aparecer qualquer destroy, **NÃO aplique** — reporte o output completo.

- [ ] **Step 3: Apply**

```bash
terraform apply -auto-approve
```

Resultado esperado: `Apply complete! Resources: 2 added, 0 changed, 0 destroyed.`

- [ ] **Step 4: Capturar IDs das spoke RTs**

```bash
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

echo "Dev RT: $DEV_RT"
echo "Prod RT: $PROD_RT"
```

- [ ] **Step 5: Verificar blackhole na dev RT**

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $DEV_RT \
  --filters "Name=state,Values=blackhole" \
  --profile ct8-hub \
  --query 'Routes[*].{Dest:DestinationCidrBlock,Type:Type,State:State}' \
  --output table
```

Resultado esperado:
```
| Dest          | State     | Type   |
|---------------|-----------|--------|
| 10.11.0.0/16  | blackhole | static |
```

- [ ] **Step 6: Verificar blackhole na prod RT**

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $PROD_RT \
  --filters "Name=state,Values=blackhole" \
  --profile ct8-hub \
  --query 'Routes[*].{Dest:DestinationCidrBlock,Type:Type,State:State}' \
  --output table
```

Resultado esperado:
```
| Dest          | State     | Type   |
|---------------|-----------|--------|
| 10.10.0.0/16  | blackhole | static |
```

- [ ] **Step 7: Commit do plano**

```bash
cd /Users/fernando/Work/estudos/aws-network
git add docs/superpowers/plans/2026-05-20-tgw-blackhole-routes.md
git commit -m "docs: add TGW blackhole routes implementation plan"
```
