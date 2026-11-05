@echo off
setlocal enabledelayedexpansion

REM Deploy Orchard CMS image to AWS EKS
REM Usage: scripts\deploy-image.bat

echo === Orchard CMS Deployment to AWS EKS ===
echo.

REM Ask for AWS details
set /p AWS_REGION="Enter AWS region (e.g., us-east-1): "
set /p CLUSTER_NAME="Enter EKS cluster name: "
set /p IMAGE_URI="Enter image URI (full path with registry and tag): "

REM Ask for environment variables
echo.
echo Enter values for environment variables (press Enter to skip):
set /p ORCHARD_BASE_URL="Enter value for ORCHARD_BASE_URL (or press Enter to skip): "
set /p DB_HOST="Enter value for DB_HOST (or press Enter to skip): "

REM Ask for secrets (without echoing)
echo.
echo Enter values for secrets (will not be echoed):
set /p MACHINEKEY_VALIDATION="Enter MACHINEKEY_VALIDATION: "
echo.
set /p MACHINEKEY_DECRYPTION="Enter MACHINEKEY_DECRYPTION: "
echo.

REM Configure kubectl for the EKS cluster
echo.
echo === Configuring kubectl for EKS cluster ===
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (echo Failed to configure kubectl & exit /b 1)

REM Verify cluster connectivity
echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (echo kubectl cluster-info failed & exit /b 1)

REM Apply namespace
echo.
echo === Applying namespace ===
kubectl apply -f kubernetes/namespace.yaml
if !ERRORLEVEL! neq 0 (echo Failed to apply namespace & exit /b 1)

REM Create Secret for sensitive values
echo.
echo === Creating Kubernetes Secret ===
kubectl create secret generic orchard-secrets -n orchard --from-literal=machinekey-validation="!MACHINEKEY_VALIDATION!" --from-literal=machinekey-decryption="!MACHINEKEY_DECRYPTION!" --dry-run=client -o yaml | kubectl apply -f -
if !ERRORLEVEL! neq 0 (echo Failed to create secret & exit /b 1)

REM Replace placeholders in deployment.yaml
echo.
echo === Applying deployment ===
powershell -Command "(Get-Content kubernetes/deployment.yaml) -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content kubernetes/deployment.yaml"
powershell -Command "(Get-Content kubernetes/deployment.yaml) -replace '{{ORCHARD_BASE_URL}}', '!ORCHARD_BASE_URL!' | Set-Content kubernetes/deployment.yaml"
powershell -Command "(Get-Content kubernetes/deployment.yaml) -replace '{{DB_HOST}}', '!DB_HOST!' | Set-Content kubernetes/deployment.yaml"

kubectl apply -f kubernetes/deployment.yaml
if !ERRORLEVEL! neq 0 (echo Failed to apply deployment & exit /b 1)

REM Apply service
echo.
echo === Applying service ===
kubectl apply -f kubernetes/service.yaml
if !ERRORLEVEL! neq 0 (echo Failed to apply service & exit /b 1)

REM Apply ingress
echo.
echo === Applying ingress ===
kubectl apply -f kubernetes/ingress.yaml
if !ERRORLEVEL! neq 0 (echo Failed to apply ingress & exit /b 1)

REM Wait for deployment rollout
echo.
echo === Waiting for deployment rollout ===
kubectl rollout status deployment/orchard -n orchard
if !ERRORLEVEL! neq 0 (echo Rollout failed & exit /b 1)

REM Show pod, service, and ingress status
echo.
echo === Deployment status ===
kubectl get pods,svc,ingress -n orchard

REM Show application URL
echo.
echo === Application URL ===
echo Your Orchard application should be accessible at: http://orchard.example.com
echo.

REM Rollback instructions
echo === Rollback instructions ===
echo If the deployment fails, you can rollback with:
echo   kubectl rollout undo deployment/orchard -n orchard
echo.

echo === Deployment complete ===

endlocal
