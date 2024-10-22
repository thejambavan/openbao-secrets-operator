#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

set -e

cat <<EOF | kubectl -n bao exec -i bao-0 -- sh -e
bao secrets disable kvv2/
bao secrets enable -path=kvv2 kv-v2
bao kv put kvv2/secret username="db-readonly-username" password="db-secret-password"

bao secrets disable kvv1/
bao secrets enable -path=kvv1 -version=1 kv
bao kv put kvv1/secret username="v1-user" password="v1-password"

bao secrets disable pki
bao secrets enable pki
bao write pki/root/generate/internal \
    common_name=example.com \
    ttl=768h
bao write pki/config/urls \
    issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
    crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"
bao write pki/roles/default \
    allowed_domains=example.com \
    allowed_domains=localhost \
    allow_subdomains=true \
    max_ttl=72h

cat <<EOT > /tmp/policy.hcl
path "kvv2/*" {
  capabilities = ["read"]
}
path "kvv1/*" {
  capabilities = ["read"]
}
path "pki/*" {
  capabilities = ["read", "create", "update"]
}
EOT
bao policy write demo /tmp/policy.hcl

# setup the necessary auth backend
bao auth disable kubernetes
bao auth enable kubernetes
bao write auth/kubernetes/config \
    kubernetes_host=https://kubernetes.default.svc
bao write auth/kubernetes/role/demo \
    bound_service_account_names=default \
    bound_service_account_namespaces=tenant-1,tenant-2 \
    policies=demo \
    ttl=1h
EOF

for ns in tenant-{1,2} ; do
    kubectl delete namespace --wait --timeout=30s "${ns}" &> /dev/null || true
    kubectl create namespace "${ns}"
done
