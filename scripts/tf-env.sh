#!/usr/bin/env bash
# Exporta credenciais SSO temporárias para variáveis de ambiente.
# Uso: source scripts/tf-env.sh [profile]
# Exemplo: source scripts/tf-env.sh ct8-hub

PROFILE="${1:-ct8-hub}"

echo "Fazendo login SSO com profile: $PROFILE"
aws sso login --profile "$PROFILE"

echo "Exportando credenciais temporárias..."
eval "$(aws configure export-credentials --profile "$PROFILE" --format env)"

echo "Credenciais ativas:"
aws sts get-caller-identity
