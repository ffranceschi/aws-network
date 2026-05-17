# Runbook — Hub/Spoke Network POC

Passo a passo completo para provisionar a infraestrutura de rede hub/spoke na AWS.

---

## Contas e Profiles

| Conta  | Account ID     | AWS Profile   |
|--------|----------------|---------------|
| Hub    | 225119180422   | `ct8-hub`     |
| Dev    | 686633026087   | `ct8-develop` |

---

## Credenciais — Regra Geral

> **Importante:** O Terraform S3 backend não resolve credenciais SSO diretamente via profile. Antes de qualquer comando `terraform`, exporte as credenciais temporárias como variáveis de ambiente usando o script auxiliar.

```bash
# Na raiz do projeto — use "source" (não "./") para exportar as vars no shell atual
source scripts/tf-env.sh ct8-hub
```

O script faz login SSO e exporta `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` no shell atual. Repita sempre que as credenciais expirarem (~8h).

**Por que `ct8-hub` para tudo?**
- O bucket S3 de state está na conta hub → precisa de credenciais hub
- A `TerraformExecutionRole` da conta dev tem trust policy que permite o root da conta hub assumir → `ct8-hub` pode fazer o `assume_role` para a conta dev
- Resultado: um único profile para gerenciar ambas as contas via Terraform

---

## Pré-requisitos (executar uma única vez)

### 1. Criar `TerraformExecutionRole` na conta Hub

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
  --profile ct8-hub

aws iam attach-role-policy \
  --role-name TerraformExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile ct8-hub
```

### 2. Criar `TerraformExecutionRole` na conta Dev

> A trust policy usa o root da conta **hub** — isso permite que o Terraform autenticado com `ct8-hub` assuma essa role na conta dev.

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
  --profile ct8-develop

aws iam attach-role-policy \
  --role-name TerraformExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile ct8-develop
```

### 3. Criar `SSMInstanceProfile` na conta Dev (para testes)

Necessário para conectar via SSM Session Manager sem abrir portas SSH.

```bash
aws iam create-role \
  --role-name SSMInstanceRole \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{
      "Effect":"Allow",
      "Principal":{"Service":"ec2.amazonaws.com"},
      "Action":"sts:AssumeRole"
    }]
  }' \
  --profile ct8-develop

aws iam attach-role-policy \
  --role-name SSMInstanceRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  --profile ct8-develop

aws iam create-instance-profile \
  --instance-profile-name SSMInstanceProfile \
  --profile ct8-develop

aws iam add-role-to-instance-profile \
  --instance-profile-name SSMInstanceProfile \
  --role-name SSMInstanceRole \
  --profile ct8-develop
```

---

## Fase 0 — Bootstrap (S3 state bucket)

> Executa **uma única vez** na conta hub. Cria o bucket S3 para estado remoto do Terraform. O locking é feito nativamente via `use_lockfile = true` (Terraform >= 1.10 — sem DynamoDB necessário).

```bash
# Exportar credenciais
source scripts/tf-env.sh ct8-hub

cd bootstrap
```

O arquivo `terraform.tfvars` deve conter:
```hcl
aws_region   = "us-east-1"
project_name = "aws-network-poc"
owner        = "fernando"
profile      = "ct8-hub"
```

```bash
terraform init

terraform plan
# Revisar: deve mostrar 2 S3 buckets a criar (state + logs)

terraform apply
```

**Anotar o output:**
```
state_bucket_name = "aws-network-poc-tfstate-225119180422"
```

---

## Fase 1 — Hub Account

```bash
# Exportar credenciais (se ainda não fez)
source scripts/tf-env.sh ct8-hub

cd accounts/hub
```

### Criar `backend.hcl`

```bash
cat > backend.hcl << 'EOF'
bucket  = "aws-network-poc-tfstate-225119180422"
region  = "us-east-1"
profile = "ct8-hub"
EOF
```

### Criar `terraform.tfvars`

```bash
cat > terraform.tfvars << 'EOF'
aws_region              = "us-east-1"
hub_account_id          = "225119180422"
dev_account_id          = "686633026087"
owner                   = "fernando"
state_bucket            = "aws-network-poc-tfstate-225119180422"
dev_tgw_attachment_done = false
profile                 = "ct8-hub"
EOF
```

### Inicializar e aplicar

```bash
terraform init -backend-config=backend.hcl

terraform plan
# Revisar: VPC (10.0.0.0/16), subnets, IGW, TGW, NAT GW, route tables, RAM share

terraform apply
```

**Verificar outputs:**
```bash
terraform output
# Deve mostrar: vpc_id, tgw_id, tgw_route_table_id, nat_gateway_id
```

---

## Fase 2 — Dev Account

```bash
# Credenciais já exportadas como ct8-hub — válido para a conta dev também
cd accounts/dev
```

### Criar `backend.hcl`

> Usa `ct8-hub` porque o bucket S3 está na conta hub.

```bash
cat > backend.hcl << 'EOF'
bucket  = "aws-network-poc-tfstate-225119180422"
region  = "us-east-1"
profile = "ct8-hub"
EOF
```

### Criar `terraform.tfvars`

```bash
cat > terraform.tfvars << 'EOF'
aws_region     = "us-east-1"
dev_account_id = "686633026087"
owner          = "fernando"
state_bucket   = "aws-network-poc-tfstate-225119180422"
profile        = "ct8-hub"
EOF
```

### Inicializar e aplicar

```bash
terraform init -backend-config=backend.hcl

terraform plan
# Revisar: VPC (10.10.0.0/16), subnets sem IGW, TGW attachment, route tables

terraform apply
```

**Verificar outputs:**
```bash
terraform output
# Deve mostrar: vpc_id, tgw_attachment_id, workload_subnet_ids
```

---

## Fase 3 — Hub Phase 2 (rota TGW para Dev)

> Após o apply do dev, o hub associa o attachment do spoke ao route table do TGW e adiciona a rota estática `10.10.0.0/16`.

```bash
cd accounts/hub
```

### Atualizar `terraform.tfvars`

```bash
sed -i '' 's/dev_tgw_attachment_done = false/dev_tgw_attachment_done = true/' terraform.tfvars
```

### Aplicar

```bash
terraform plan
# Verificar: deve mostrar 2 recursos novos:
#   + aws_ec2_transit_gateway_route_table_association.dev[0]
#   + aws_ec2_transit_gateway_route.to_dev_vpc[0]

terraform apply
```

### Verificar rotas no TGW

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
```

---

## Fase 4 — Verificação End-to-End

> Confirma que o egresso de internet do spoke passa pelo NAT Gateway do hub.

### Criar instância de teste na conta dev

```bash
# Pegar outputs da conta dev
DEV_SUBNET=$(cd accounts/dev && terraform output -json workload_subnet_ids | jq -r '.[0]')
DEV_VPC=$(cd accounts/dev && terraform output -raw vpc_id)

# Security group sem inbound (SSM não precisa de porta aberta)
SG_ID=$(aws ec2 create-security-group \
  --group-name "test-connectivity" \
  --description "Teste temporario de conectividade" \
  --vpc-id $DEV_VPC \
  --profile ct8-develop \
  --query 'GroupId' --output text)

# Aguardar IAM propagar antes de lançar
sleep 10

# Lançar instância
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.micro \
  --subnet-id $DEV_SUBNET \
  --iam-instance-profile Name=SSMInstanceProfile \
  --security-group-ids $SG_ID \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-connectivity}]' \
  --profile ct8-develop \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance ID: $INSTANCE_ID"
```

### Aguardar instância ficar disponível

```bash
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --profile ct8-develop
# Aguardar mais ~30s para o SSM agent inicializar
sleep 30
```

### Conectar via SSM e validar egresso

```bash
aws ssm start-session --target $INSTANCE_ID --profile ct8-develop
```

Dentro da instância:
```bash
# Deve retornar o IP público do NAT Gateway do hub
curl -s https://checkip.amazonaws.com
```

Fora da instância, confirmar o EIP do NAT Gateway:
```bash
aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --profile ct8-hub \
  --query 'NatGateways[0].NatGatewayAddresses[0].PublicIp' \
  --output text
```

Os dois IPs devem ser iguais — isso confirma que todo o egresso do spoke dev passa pelo NAT Gateway centralizado no hub.

> **Nota:** `ping` pode não funcionar pois ICMP de retorno é bloqueado pelo NACL das subnets TGW attachment (que só permitem TCP ephemeral de volta). O `curl` é o teste correto para validar o egresso.

### Limpar recursos de teste

```bash
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --profile ct8-develop
aws ec2 delete-security-group --group-id $SG_ID --profile ct8-develop
```

---

## Destruir a infraestrutura

Execute na **ordem inversa**:

```bash
source scripts/tf-env.sh ct8-hub

# 1. Dev
cd accounts/dev
terraform destroy

# 2. Hub — remover rotas do dev antes de destruir
cd ../hub
sed -i '' 's/dev_tgw_attachment_done = true/dev_tgw_attachment_done = false/' terraform.tfvars
terraform apply   # remove associação e rota do spoke dev
terraform destroy # destrói o restante

# 3. Bootstrap — esvaziar bucket antes (prevent_destroy bloqueia bucket não vazio)
cd ../../bootstrap
aws s3 rm s3://aws-network-poc-tfstate-225119180422 --recursive --profile ct8-hub
terraform destroy
```

---

## Troubleshooting

| Erro | Causa | Solução |
|------|-------|---------|
| `ExpiredToken` | Token STS expirou | `source scripts/tf-env.sh ct8-hub` |
| `No valid credential sources found` (backend) | S3 backend não lê SSO profile diretamente | `source scripts/tf-env.sh ct8-hub` antes do terraform |
| `No valid credential sources found` (provider) | Profile não configurado ou expirado | Adicionar `profile = "ct8-hub"` no `terraform.tfvars` |
| `CredentialRequiresARNError: profile default` | Profile `[default]` tem `source_profile` sem `role_arn` | Remover `source_profile` do `[default]` em `~/.aws/config` |
| `OperationNotPermittedException` no RAM | RAM org sharing não habilitado | `allow_external_principals = true` + account ID como principal |
| `InvalidParameterException: Principal ID is malformed` | ARN root como principal no RAM | Usar só o account ID (`var.dev_account_id`) como principal |
| `Value (SSMInstanceProfile) is invalid` | Instance profile não existe na conta dev | Criar `SSMInstanceProfile` conforme Pré-requisito #3 |
