# Runbook — Hub/Spoke Network POC

Passo a passo completo para provisionar a infraestrutura de rede hub/spoke na AWS.

---

## Contas e Profiles

| Conta  | Account ID     | AWS Profile   |
|--------|----------------|---------------|
| Hub    | 225119180422   | `ct8-hub`     |
| Dev    | 686633026087   | `ct8-develop` |

---

## Pré-requisitos

### 1. Login SSO (necessário antes de qualquer apply)

```bash
aws sso login --profile ct8-hub
aws sso login --profile ct8-develop
```

> Repita sempre que as credenciais expirarem (normalmente a cada 8h).

### 2. Verificar acesso às contas

```bash
aws sts get-caller-identity --profile ct8-hub
aws sts get-caller-identity --profile ct8-develop
```

Cada comando deve retornar o `Account` correspondente sem erro.

### 3. Criar `TerraformExecutionRole` em cada conta

Execute uma única vez. Substitua os account IDs nos comandos abaixo.

**Conta Hub (225119180422):**
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

**Conta Dev (686633026087):**
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

---

## Fase 0 — Bootstrap (S3 + DynamoDB)

> Executa **uma única vez** na conta hub. Cria o bucket de state e a tabela de lock.

```bash
cd bootstrap
```

O arquivo `terraform.tfvars` já está configurado:
```hcl
aws_region   = "us-east-1"
project_name = "aws-network-poc"
owner        = "fernando"
profile      = "ct8-hub"
```

```bash
terraform init

terraform plan
# Revisar: deve mostrar 2 S3 buckets + 1 DynamoDB a criar

terraform apply
```

**Anotar os outputs:**
```
state_bucket_name = "aws-network-poc-tfstate-225119180422"
lock_table_name   = "aws-network-poc-tflock"
```

---

## Fase 1 — Hub Account

```bash
cd ../accounts/hub
```

### Criar `backend.hcl`

```bash
cat > backend.hcl << 'EOF'
bucket         = "aws-network-poc-tfstate-225119180422"
dynamodb_table = "aws-network-poc-tflock"
region         = "us-east-1"
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
lock_table              = "aws-network-poc-tflock"
dev_tgw_attachment_done = false
EOF
```

### Inicializar e aplicar

```bash
terraform init -backend-config=backend.hcl

terraform plan
# Revisar: VPC, subnets, IGW, TGW, NAT GW, route tables, RAM share

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
cd ../dev
```

### Criar `backend.hcl`

```bash
cat > backend.hcl << 'EOF'
bucket         = "aws-network-poc-tfstate-225119180422"
dynamodb_table = "aws-network-poc-tflock"
region         = "us-east-1"
EOF
```

### Criar `terraform.tfvars`

```bash
cat > terraform.tfvars << 'EOF'
aws_region     = "us-east-1"
dev_account_id = "686633026087"
owner          = "fernando"
state_bucket   = "aws-network-poc-tfstate-225119180422"
lock_table     = "aws-network-poc-tflock"
EOF
```

### Inicializar e aplicar

```bash
terraform init -backend-config=backend.hcl

terraform plan
# Revisar: VPC, subnets (sem IGW), TGW attachment, route tables

terraform apply
```

**Verificar outputs:**
```bash
terraform output
# Deve mostrar: vpc_id, tgw_attachment_id, workload_subnet_ids
```

---

## Fase 3 — Hub Phase 2 (rota TGW para Dev)

> Após o apply do dev, o hub precisa associar o attachment do spoke ao route table do TGW e adicionar a rota estática.

```bash
cd ../hub
```

### Atualizar `terraform.tfvars`

Mudar a linha `dev_tgw_attachment_done`:

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

> Valida que o egresso de internet do spoke passa pelo NAT Gateway do hub.

### Criar instância de teste na conta dev

```bash
# Subnet ID de workload
DEV_SUBNET=$(cd ../dev && terraform output -json workload_subnet_ids | jq -r '.[0]')
DEV_VPC=$(cd ../dev && terraform output -raw vpc_id)

# Security group sem regras inbound (SSM não precisa de inbound)
SG_ID=$(aws ec2 create-security-group \
  --group-name "test-connectivity" \
  --description "Teste temporario de conectividade" \
  --vpc-id $DEV_VPC \
  --profile ct8-develop \
  --query 'GroupId' --output text)

# Lançar instância com SSM
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.micro \
  --subnet-id $DEV_SUBNET \
  --iam-instance-profile Name=SSMInstanceProfile \
  --security-group-ids $SG_ID \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-connectivity}]' \
  --profile ct8-develop \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance: $INSTANCE_ID"
```

> **Pré-requisito:** O `SSMInstanceProfile` precisa existir na conta dev com a policy `AmazonSSMManagedInstanceCore`. Criar via console se não existir.

### Conectar via SSM e testar

```bash
aws ssm start-session --target $INSTANCE_ID --profile ct8-develop
```

Dentro da instância:
```bash
# IP deve ser o EIP do NAT Gateway do hub, não um IP da conta dev
curl -s https://checkip.amazonaws.com

# Confirmar o IP do NAT Gateway do hub
aws ec2 describe-nat-gateways \
  --profile ct8-hub \
  --query 'NatGateways[0].NatGatewayAddresses[0].PublicIp' \
  --output text
```

Os dois IPs devem ser iguais.

### Limpar instância de teste

```bash
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --profile ct8-develop
aws ec2 delete-security-group --group-id $SG_ID --profile ct8-develop
```

---

## Destruir a infraestrutura (quando quiser limpar)

Execute na **ordem inversa**:

```bash
# 1. Dev
cd accounts/dev && terraform destroy

# 2. Hub (phase 2 primeiro — remover rotas do dev)
cd ../hub
sed -i '' 's/dev_tgw_attachment_done = true/dev_tgw_attachment_done = false/' terraform.tfvars
terraform apply   # remove a rota e associação do dev
terraform destroy # destrói o resto

# 3. Bootstrap (por último — state bucket tem prevent_destroy)
cd ../../bootstrap
# Remover prevent_destroy manualmente antes, ou:
terraform destroy -target=aws_dynamodb_table.lock
# O bucket S3 precisará ser esvaziado manualmente antes do destroy
aws s3 rm s3://aws-network-poc-tfstate-225119180422 --recursive --profile ct8-hub
terraform destroy
```
