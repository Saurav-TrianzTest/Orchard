#!/bin/bash
set -e
set -o pipefail

# Deploy Orchard CMS image to AWS EKS
# Usage: ./scripts/deploy-image.sh

echo "=== Orchard CMS Deployment to AWS EKS ==="
echo ""

# Ask for AWS details
read -p "Enter AWS region (e.g., us-east-1): " AWS_REGION
read -p "Enter EKS cluster name: " CLUSTER_NAME
read -p "Enter image URI (full path with registry and tag): " IMAGE_URI

# Ask for environment variables
echo ""
echo "Enter values for environment variables (press Enter to skip):"
read -p "Enter value for ORCHARD_BASE_URL (or press Enter to skip): " ORCHARD_BASE_URL
read -p "Enter value for DB_HOST (or press Enter to skip): " DB_HOST

# Ask for secrets (without echoing)
echo ""
echo "Enter values for secrets (will not be echoed):"
read -s -p "Enter MACHINEKEY_VALIDATION: " MACHINEKEY_VALIDATION
echo ""
read -s -p "Enter MACHINEKEY_DECRYPTION: " MACHINEKEY_DECRYPTION
echo ""

# Configure kubectl for the EKS cluster
echo ""
echo "=== Configuring kubectl for EKS cluster ==="
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
if [ $? -ne 0 ]; then
    echo "Failed to configure kubectl. Exiting."
    exit 1
fi

# Verify cluster connectivity
echo "Verifying cluster connectivity..."
kubectl cluster-info || exit 1

# Apply namespace
echo ""
echo "=== Applying namespace ==="
kubectl apply -f kubernetes/namespace.yaml

# Create Secret for sensitive values
echo ""
echo "=== Creating Kubernetes Secret ==="
kubectl create secret generic orchard-secrets -n orchard \
    --from-literal=machinekey-validation="$MACHINEKEY_VALIDATION" \
    --from-literal=machinekey-decryption="$MACHINEKEY_DECRYPTION" \
    --dry-run=client -o yaml | kubectl apply -f -

# Replace placeholders in deployment.yaml
echo ""
echo "=== Applying deployment ==="
sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" kubernetes/deployment.yaml
sed -i.bak "s|{{ORCHARD_BASE_URL}}|$ORCHARD_BASE_URL|g" kubernetes/deployment.yaml
sed -i.bak "s|{{DB_HOST}}|$DB_HOST|g" kubernetes/deployment.yaml
rm -f kubernetes/deployment.yaml.bak

kubectl apply -f kubernetes/deployment.yaml

# Apply service
echo ""
echo "=== Applying service ==="
kubectl apply -f kubernetes/service.yaml

# Apply ingress
echo ""
echo "=== Applying ingress ==="
kubectl apply -f kubernetes/ingress.yaml

# Wait for deployment rollout
echo ""
echo "=== Waiting for deployment rollout ==="
kubectl rollout status deployment/orchard -n orchard

# Show pod, service, and ingress status
echo ""
echo "=== Deployment status ==="
kubectl get pods,svc,ingress -n orchard

# Show application URL
echo ""
echo "=== Application URL ==="
echo "Your Orchard application should be accessible at: http://orchard.example.com"
echo ""

# Rollback instructions
echo "=== Rollback instructions ==="
echo "If the deployment fails, you can rollback with:"
echo "  kubectl rollout undo deployment/orchard -n orchard"
echo ""

echo "=== Deployment complete ==="
