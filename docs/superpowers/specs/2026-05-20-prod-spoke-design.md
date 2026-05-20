# Design: Spoke Prod — Conta AWS 745416886900

**Data:** 2026-05-20

---

## Contexto

Projeto hub/spoke com Transit Gateway (TGW) centralizado na conta hub (`225119180422`). O spoke dev (`686633026087`, CIDR `10.10.0.0/16`) já está provisionado. Este spec descreve a adição de um segundo spoke para produção.

---

## Parâmetros

| Atributo          | Valor              |
|-------------------|--------------------|
| Account ID        | `745416886900`     |
| Environment       | `prod`             |
| VPC CIDR          | `10.11.0.0/16`     |
| TGW subnets       | `10.11.2.0/28`, `10.11.3.0/28` |
| Workload subnets  | `10.11.0.0/24`, `10.11.1.0/24` |
| Profile base      | `ct8-hub`          |
| State key         | `prod/terraform.tfstate` |
| State bucket      | `aws-network-poc-tfstate-225119180422` |

---

## Arquitetura

Segue o padrão existente do spoke dev:
- VPC sem IGW (egresso via NAT GW do hub)
- TGW attachment em subnets dedicadas (`/28`)
- Workload subnets em subnets separadas (`/24`)
- Route table workload: rota específica para hub (`10.0.0.0/16`) + rota default (`0.0.0.0/0`) via TGW
- Route table TGW attachment: local only
- NACL nas subnets TGW attachment: allow `10.0.0.0/8` inbound + TCP ephemeral + all egress
- `TerraformExecutionRole` com trust policy no root da conta hub

---

## Mudanças

### `accounts/prod/` (novo)

Arquivos espelhados de `accounts/dev` com substituições prod:

| Arquivo            | Mudanças principais |
|--------------------|---------------------|
| `providers.tf`     | `assume_role` para `745416886900`, env tag `prod` |
| `variables.tf`     | `prod_account_id` em vez de `dev_account_id` |
| `backend.tf`       | `key = "prod/terraform.tfstate"` |
| `backend.hcl`      | Mesmo bucket + profile `ct8-hub` |
| `terraform.tfvars` | `prod_account_id = "745416886900"`, profile `ct8-hub` |
| `main.tf`          | VPC `10.11.0.0/16`, environment `prod`, subnets prod |
| `tgw-attachment.tf`| `environment = "prod"` |
| `routes.tf`        | Prefixo `prod-` em todos os recursos |
| `outputs.tf`       | Idêntico ao dev |

### `accounts/hub/` (atualizado)

| Arquivo            | Mudanças |
|--------------------|----------|
| `variables.tf`     | `+prod_account_id`, `+prod_tgw_attachment_done` |
| `ram.tf`           | `+aws_ram_principal_association.prod` |
| `routes.tf`        | `+aws_route.public_to_prod` (`10.11.0.0/16 → TGW`, incondicional) |
| `tgw.tf`           | Fase 2: `+data.terraform_remote_state.prod`, `+route_table_association.prod`, `+route.to_prod_vpc` |
| `terraform.tfvars` | `+prod_account_id = "745416886900"`, `+prod_tgw_attachment_done = false` |

---

## Sequência de Execução

1. **Pré-requisito:** Criar `TerraformExecutionRole` na conta prod (`745416886900`) com trust no root da hub (`225119180422`), usando profile `ct8-prod`
2. **Hub fase 1.5:** Re-apply de `accounts/hub` → adiciona RAM share para prod + rota pública
3. **Prod fase 1:** Apply de `accounts/prod` → cria VPC + TGW attachment
4. **Hub fase 2:** Setar `prod_tgw_attachment_done = true` + re-apply → associa attachment no TGW RT e adiciona rota `10.11.0.0/16`

---

## Sem Mudanças Necessárias

- `accounts/dev/` — rota default (`0.0.0.0/0` via TGW) já cobre tráfego dev→prod via TGW
- `bootstrap/` — bucket S3 compartilhado, sem alteração
