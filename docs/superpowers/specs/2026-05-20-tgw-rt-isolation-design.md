# Design: Isolamento Spoke-to-Spoke com 3 TGW Route Tables

**Data:** 2026-05-20

---

## Contexto

A rede hub/spoke possui um único TGW route table (`hub-tgw-rt-main`) compartilhado por todos os attachments (hub, dev, prod). Isso permite tráfego east-west entre spokes, o que não é desejado.

**Requisito:** Hub acessa dev e prod; dev e prod não podem se acessar mutuamente.

---

## Arquitetura

Três TGW route tables, uma por attachment:

| Route Table | Associada a | Rotas |
|---|---|---|
| `hub-tgw-rt-hub` | Hub attachment | `10.10.0.0/16` → dev, `10.11.0.0/16` → prod |
| `hub-tgw-rt-dev` | Dev attachment | `10.0.0.0/16` → hub, `0.0.0.0/0` → hub |
| `hub-tgw-rt-prod` | Prod attachment | `10.0.0.0/16` → hub, `0.0.0.0/0` → hub |

### Por que funciona

O TGW usa a route table **associada ao attachment de origem** para determinar o destino do tráfego.

- Dev → `10.11.0.0/16` (prod): usa `hub-tgw-rt-dev` → rota inexistente → pacote descartado ✅
- Prod → `10.10.0.0/16` (dev): usa `hub-tgw-rt-prod` → rota inexistente → descartado ✅
- Hub → `10.10.0.0/16` (dev): usa `hub-tgw-rt-hub` → rota existe → chega ao dev ✅
- Hub → `10.11.0.0/16` (prod): usa `hub-tgw-rt-hub` → rota existe → chega ao prod ✅
- Dev → `0.0.0.0/0` (internet): usa `hub-tgw-rt-dev` → hub → NAT GW ✅
- Prod → `0.0.0.0/0` (internet): usa `hub-tgw-rt-prod` → hub → NAT GW ✅

---

## Mudanças em `accounts/hub/tgw.tf`

### Remover (não são mais necessárias)

- `aws_ec2_transit_gateway_route.to_hub_vpc` — rota `10.0.0.0/16 → hub attachment` na hub RT. Era necessária apenas para tráfego de spokes rumo ao hub via RT compartilhada. Com RTs separadas, essa rota fica nas spoke RTs.
- `aws_ec2_transit_gateway_route.default_to_hub` — rota `0.0.0.0/0 → hub attachment` na hub RT. Mesmo raciocínio.

### Atualizar

- Tag de `aws_ec2_transit_gateway_route_table.main`: `"hub-tgw-rt-main"` → `"hub-tgw-rt-hub"` (renomear para refletir a nova responsabilidade)

### Adicionar (incondicionais)

- `aws_ec2_transit_gateway_route_table.dev` — nova RT dev com tag `"hub-tgw-rt-dev"`
- `aws_ec2_transit_gateway_route.dev_to_hub` — `10.0.0.0/16 → hub attachment` na dev RT
- `aws_ec2_transit_gateway_route.dev_default` — `0.0.0.0/0 → hub attachment` na dev RT
- `aws_ec2_transit_gateway_route_table.prod` — nova RT prod com tag `"hub-tgw-rt-prod"`
- `aws_ec2_transit_gateway_route.prod_to_hub` — `10.0.0.0/16 → hub attachment` na prod RT
- `aws_ec2_transit_gateway_route.prod_default` — `0.0.0.0/0 → hub attachment` na prod RT

### Atualizar (fase 2 gateada)

- `aws_ec2_transit_gateway_route_table_association.dev[0]`: mudar `transit_gateway_route_table_id` de `main.id` para `dev.id`
- `aws_ec2_transit_gateway_route_table_association.prod[0]`: mudar de `main.id` para `prod.id`

As rotas hub→spoke (`to_dev_vpc`, `to_prod_vpc`) **permanecem na hub RT** — sem mudança.

---

## Sem Mudanças

- `accounts/dev/` — routing do lado dos spokes não muda
- `accounts/prod/` — idem
- `accounts/hub/routes.tf` — rotas públicas para dev/prod continuam necessárias (retorno via NAT GW)
- `accounts/hub/ram.tf`, `variables.tf`, `terraform.tfvars` — sem mudança

---

## Sequência de Execução

1. Atualizar `accounts/hub/tgw.tf` com as mudanças descritas
2. `terraform plan` — verificar: ~8 to add, 2 to destroy, 1 to change (tag)
3. `terraform apply`
4. Verificar as três route tables no console AWS ou via CLI

---

## Validação

```bash
# Hub RT — deve ter rotas para dev e prod
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <hub-rt-id> \
  --filters "Name=state,Values=active" --profile ct8-hub

# Dev RT — deve ter apenas 10.0.0.0/16 e 0.0.0.0/0, sem 10.11.0.0/16
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <dev-rt-id> \
  --filters "Name=state,Values=active" --profile ct8-hub

# Prod RT — deve ter apenas 10.0.0.0/16 e 0.0.0.0/0, sem 10.10.0.0/16
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <prod-rt-id> \
  --filters "Name=state,Values=active" --profile ct8-hub
```
