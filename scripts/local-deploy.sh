# scripts/local-deploy.sh
#!/bin/bash
set -e

# Function to check command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "$1 is required but not installed. Please install it first."
        exit 1
    fi
}

# Check required commands
check_command docker
check_command kind
check_command kubectl
check_command helm

# Create Kind cluster with metallb support
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: keycloak-local
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF

# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

# Configure MetalLB
docker network inspect -f '{{.IPAM.Config}}' kind

# Get the network CIDR and calculate a range for MetalLB
DOCKER_SUBNET=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' | cut -d'.' -f1,2)
METALLB_START="${DOCKER_SUBNET}.255.200"
METALLB_END="${DOCKER_SUBNET}.255.250"

cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example
  namespace: metallb-system
spec:
  addresses:
  - ${METALLB_START}-${METALLB_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF

# Add Helm repositories
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Create namespaces
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -

# Install NGINX Ingress
echo "Installing NGINX Ingress..."
helm upgrade --install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --values ../kubernetes/nginx-ingress/values.yaml \
    --wait

# Install cert-manager
echo "Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --values ../kubernetes/cert-manager/values.yaml \
    --set installCRDs=true \
    --wait

# Create self-signed cluster issuer for local testing
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

# Start local PostgreSQL
docker run -d \
  --name keycloak-postgres \
  -e POSTGRES_DB=keycloak \
  -e POSTGRES_USER=keycloak \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  postgres:13

# Create secrets for Keycloak
kubectl create secret generic keycloak-db-secret \
    --namespace keycloak \
    --from-literal=username=keycloak \
    --from-literal=password=password \
    --from-literal=host=host.docker.internal \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic keycloak-admin-secret \
    --namespace keycloak \
    --from-literal=admin-password=admin123 \
    --dry-run=client -o yaml | kubectl apply -f -

# Install Keycloak
echo "Installing Keycloak..."
helm upgrade --install keycloak bitnami/keycloak \
    --namespace keycloak \
    --set auth.adminUser=admin \
    --set auth.existingSecret=keycloak-admin-secret \
    --set postgresql.enabled=false \
    --set externalDatabase.host=host.docker.internal \
    --set externalDatabase.port=5432 \
    --set externalDatabase.user=keycloak \
    --set externalDatabase.password=password \
    --set externalDatabase.database=keycloak \
    --wait

# Create local ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  namespace: keycloak
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: selfsigned-issuer
spec:
  tls:
  - hosts:
    - keycloak.local
    secretName: keycloak-tls
  rules:
  - host: keycloak.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keycloak
            port:
              number: 8080
EOF

# Add local DNS entry
echo "127.0.0.1 keycloak.local" | sudo tee -a /etc/hosts

# Get LoadBalancer IP
echo "Waiting for ingress IP..."
INGRESS_IP=""
while [ -z "$INGRESS_IP" ]; do
    INGRESS_IP=$(kubectl get service -n ingress-nginx nginx-ingress-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [ -z "$INGRESS_IP" ]; then
        echo "Waiting for ingress IP..."
        sleep 10
    fi
done

echo "================================================================"
echo "Local deployment completed successfully!"
echo "Access Keycloak at: https://keycloak.local"
echo "Admin username: admin"
echo "Admin password: admin123"
echo "Note: You'll need to accept the self-signed certificate in your browser"
echo "================================================================"