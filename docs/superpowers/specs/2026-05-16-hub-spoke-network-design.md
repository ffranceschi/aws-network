# Design: Hub/Spoke Network POC — AWS

**Data:** 2026-05-16  
**Escopo:** Hub Account + Spoke Dev Account  
**Stack:** Terraform (monorepo com módulos compartilhados)

---

## 1. Visão Geral

POC de arquitetura de rede hub/spoke na AWS usando Transit Gateway. O spoke dev tem egresso centralizado para internet via NAT Gateway na conta hub. Toda a infraestrutura é gerenciada como IaC em Terraform, seguindo boas práticas de segurança.

---

## 2. Contas e CIDRs

| Conta       | VPC CIDR       | Papel                                    |
|-------------|----------------|------------------------------------------|
| Hub         | 10.0.0.0/16    | TGW owner, NAT Gateway, egresso internet |
| Spoke Dev   | 10.10.0.0/16   | Workloads de desenvolvimento             |

Região: a definir em variável (`aws_region`). Default: `us-east-1`.  
AZs: 2 por conta.

---

## 3. Topologia de Rede

### Hub Account — VPC 10.0.0.0/16

| Subnet          | CIDR           | AZ  | Função                        |
|-----------------|----------------|-----|-------------------------------|
| public-a        | 10.0.0.0/24    | a   | NAT Gateway + IGW             |
| public-b        | 10.0.1.0/24    | b   | Redundância pública           |
| tgw-attach-a    | 10.0.2.0/28    | a   | ENI do Transit Gateway        |
| tgw-attach-b    | 10.0.3.0/28    | b   | ENI do Transit Gateway        |

Recursos: Internet Gateway, NAT Gateway (1 instância na AZ-a com EIP), Transit Gateway (owner).

### Spoke Dev Account — VPC 10.10.0.0/16

| Subnet          | CIDR           | AZ  | Função                        |
|-----------------|----------------|-----|-------------------------------|
| workload-a      | 10.10.0.0/24   | a   | Recursos de desenvolvimento   |
| workload-b      | 10.10.1.0/24   | b   | Recursos de desenvolvimento   |
| tgw-attach-a    | 10.10.2.0/28   | a   | ENI do Transit Gateway        |
| tgw-attach-b    | 10.10.3.0/28   | b   | ENI do Transit Gateway        |

Sem Internet Gateway próprio. Todo egresso passa pelo TGW → Hub.

---

## 4. Tabelas de Roteamento

### Hub — rt-public (subnets public-a, public-b)

| Destino       | Target      | Motivo                                      |
|---------------|-------------|---------------------------------------------|
| 10.0.0.0/16   | local       | Tráfego local da VPC                        |
| 10.10.0.0/16  | TGW         | Retorno de pacotes para o spoke dev         |
| 0.0.0.0/0     | IGW         | Egresso internet das subnets públicas       |

### Hub — rt-tgw-attachment (subnets tgw-attach-a, tgw-attach-b)

| Destino       | Target      | Motivo                                      |
|---------------|-------------|---------------------------------------------|
| 10.0.0.0/16   | local       | Tráfego local da VPC                        |
| 0.0.0.0/0     | NAT GW      | Encaminha tráfego do spoke para internet    |

### Spoke Dev — rt-workload (subnets workload-a, workload-b)

| Destino       | Target      | Motivo                                      |
|---------------|-------------|---------------------------------------------|
| 10.10.0.0/16  | local       | Tráfego local da VPC                        |
| 10.0.0.0/16   | TGW         | Acesso à rede do hub                        |
| 0.0.0.0/0     | TGW         | Egresso internet via hub (centralizado)     |

### Spoke Dev — rt-tgw-attachment (subnets tgw-attach-a, tgw-attach-b)

| Destino       | Target      | Motivo                                      |
|---------------|-------------|---------------------------------------------|
| 10.10.0.0/16  | local       | Apenas local — TGW gerencia o roteamento    |

### Transit Gateway — tgw-rt-main

| Destino       | Target          | Motivo                                      |
|---------------|-----------------|---------------------------------------------|
| 10.0.0.0/16   | hub-attachment  | Rota para VPC do hub                        |
| 10.10.0.0/16  | dev-attachment  | Rota para VPC do spoke dev                  |
| 0.0.0.0/0     | hub-attachment  | Egresso internet centralizado pelo hub      |

TGW configurado com `default_route_table_association = disable` e `default_route_table_propagation = disable` — route tables explícitas.

---

## 5. Fluxo de Tráfego (Egresso Internet do Spoke Dev)

```
workload (dev)
  → 0.0.0.0/0 via rt-workload → TGW attachment (dev)
  → TGW rt-main: 0.0.0.0/0 → hub-attachment
  → Hub: tgw-attach subnet → rt-tgw-attachment: 0.0.0.0/0 → NAT GW
  → NAT GW → IGW → Internet
```

---

## 6. Transit Gateway — Compartilhamento entre Contas

- TGW criado e proprietário na conta **hub**
- Compartilhado com a conta **dev** via **AWS Resource Access Manager (RAM)**
- A conta dev aceita o compartilhamento RAM e cria o TGW attachment
- `auto_accept_shared_attachments = enable` no TGW simplifica o processo

---

## 7. Estrutura do Repositório Terraform

```
aws-network/
├── bootstrap/                  # Aplicar PRIMEIRO
│   ├── main.tf                 # S3 bucket (state) + DynamoDB (lock)
│   ├── outputs.tf
│   └── variables.tf
│
├── modules/
│   ├── vpc/                    # Módulo VPC reutilizável
│   │   ├── main.tf             # VPC, subnets, IGW (condicional), tags
│   │   ├── outputs.tf
│   │   └── variables.tf
│   └── tgw-spoke/             # Módulo para spoke se conectar ao TGW
│       ├── main.tf             # TGW attachment + route table do attachment
│       ├── outputs.tf
│       └── variables.tf
│
└── accounts/
    ├── hub/
    │   ├── providers.tf        # AWS provider + assume_role (hub)
    │   ├── backend.tf          # S3 key=hub/terraform.tfstate
    │   ├── main.tf             # Instancia módulo vpc (com IGW=true)
    │   ├── tgw.tf              # Transit Gateway + route table TGW
    │   ├── nat.tf              # EIP + NAT Gateway
    │   ├── routes.tf           # rt-public e rt-tgw-attachment
    │   ├── ram.tf              # RAM share do TGW para conta dev
    │   ├── outputs.tf          # tgw_id, vpc_id, subnet IDs
    │   └── variables.tf
    └── dev/
        ├── providers.tf        # AWS provider + assume_role (dev)
        ├── backend.tf          # S3 key=dev/terraform.tfstate
        ├── main.tf             # Instancia módulo vpc (com IGW=false)
        ├── tgw-attachment.tf   # Instancia módulo tgw-spoke
        ├── routes.tf           # rt-workload
        ├── outputs.tf
        └── variables.tf
```

### Ordem de Apply

1. `bootstrap/` → cria S3 bucket + DynamoDB
2. `accounts/hub/` → cria VPC, TGW, NAT, RAM share
3. `accounts/dev/` → cria VPC, aceita RAM, cria TGW attachment

---

## 8. Comunicação Entre Contas no Terraform

`accounts/dev` descobre o TGW ID via `terraform_remote_state` lendo o state do hub no S3:

```hcl
data "terraform_remote_state" "hub" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "hub/terraform.tfstate"
    region = var.aws_region
  }
}
```

A IAM Role da conta dev precisa de permissão `s3:GetObject` no bucket de state do hub.

---

## 9. Segurança

### IAM Cross-Account

- Cada conta tem uma `TerraformExecutionRole` com least privilege
- Providers Terraform usam `assume_role` — sem access keys em código
- Trust policy da role dev permite apenas a conta hub (ou pipeline CI/CD)

### Backend S3 + DynamoDB

- Versionamento habilitado no bucket de state
- Criptografia SSE-KMS com chave gerenciada
- Block Public Access habilitado em todas as dimensões
- Access logging em bucket separado (`terraform-state-logs-XXXX`)
- DynamoDB com criptografia at-rest para o lock de estado

### Rede

- Security Groups com default deny — apenas regras explícitas de allow
- VPC Flow Logs habilitado nas duas contas (destino: CloudWatch Logs)
- NACLs nas subnets TGW attachment — camada stateless adicional
- Spoke dev sem Internet Gateway — egresso exclusivamente via hub

### Tags Obrigatórias

```hcl
default_tags = {
  Project     = "aws-network-poc"
  ManagedBy   = "terraform"
  Environment = "hub" | "dev"
  Owner       = var.owner
}
```

---

## 10. Decisões em Aberto

- **Região AWS:** será variável (`us-east-1` como default)
- **Account IDs:** passados via variáveis, nunca hardcoded
- **NAT Gateway:** 1 instância para POC (custo); migrar para 1 por AZ em produção
- **Network Firewall:** não incluso nesta fase — ponto de extensão natural
- **Spoke Prod:** não incluso nesta fase — adicionar seguindo o mesmo padrão do módulo `tgw-spoke`
