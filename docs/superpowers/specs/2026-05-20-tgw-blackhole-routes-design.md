# Design: Blackhole Routes nas Spoke TGW Route Tables

**Data:** 2026-05-20

---

## Contexto

As TGW route tables de dev e prod já isolam o tráfego spoke-to-spoke por ausência de rota (drop implícito). Este spec adiciona rotas blackhole explícitas para tornar o bloqueio visível, intencional e auditável.

---

## Requisito

Tentativas de acesso entre spokes devem resultar em blackhole explícito no TGW, visível via `search-transit-gateway-routes`.

---

## Design

Adicionar dois recursos em `accounts/hub/tgw.tf`:

| Recurso TF | RT | CIDR | Tipo |
|---|---|---|---|
| `dev_blackhole_prod` | `hub-tgw-rt-dev` | `10.11.0.0/16` | blackhole |
| `prod_blackhole_dev` | `hub-tgw-rt-prod` | `10.10.0.0/16` | blackhole |

```hcl
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

Em `aws_ec2_transit_gateway_route` com `blackhole = true`, o atributo `transit_gateway_attachment_id` é omitido — a AWS cria a rota do tipo `blackhole` sem attachment.

---

## Sem Mudanças

- `hub-tgw-rt-hub` — não recebe blackhole; hub precisa alcançar ambos os spokes
- `accounts/dev/`, `accounts/prod/` — nenhuma mudança nas spoke accounts
- Outros arquivos do hub — nenhuma mudança

---

## Resultado Esperado

```
hub-tgw-rt-dev:
  0.0.0.0/0    → hub attachment  (egresso internet)
  10.0.0.0/16  → hub attachment  (hub VPC)
  10.11.0.0/16 → blackhole       ← novo

hub-tgw-rt-prod:
  0.0.0.0/0    → hub attachment  (egresso internet)
  10.0.0.0/16  → hub attachment  (hub VPC)
  10.10.0.0/16 → blackhole       ← novo
```

## Validação

```bash
DEV_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=hub-tgw-rt-dev" \
  --profile ct8-hub \
  --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
  --output text)

aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $DEV_RT \
  --filters "Name=type,Values=static" \
  --profile ct8-hub \
  --query 'Routes[*].{Dest:DestinationCidrBlock,Type:Type,State:State}' \
  --output table
```

Resultado esperado: `10.11.0.0/16` com `Type=static` e `State=blackhole` na dev RT (e análogo para prod RT).
