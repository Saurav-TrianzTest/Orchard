# Orchard CMS Deployment Guide

This document describes how to deploy Orchard CMS 1.x as a containerized application on AWS Elastic Kubernetes Service (EKS).

## Prerequisites and System Requirements

### Required Tools

- **Docker Desktop** (Windows) or **Docker Engine** (Linux) — version 20.10 or later
- **.NET Framework 4.8 SDK** — for building the application (Windows only)
- **Visual Studio 2022** with .NET Framework 4.8 development tools (optional, for IDE builds)
- **AWS CLI** — version 2.x, configured with IAM credentials
- **kubectl** — version 1.24 or later
- **eksctl** — for EKS cluster management (optional, if not using AWS CLI directly)

### Target Platform

- **AWS EKS** with Windows node groups (Windows Server 2019 LTSC)
- **Amazon ECR** for container image registry
- **Windows containers** — Orchard CMS 1.x is a .NET Framework 4.8 application that requires Windows containers

### System Requirements

- Minimum 4 GB RAM for build, 8 GB recommended
- 20 GB free disk space for build artifacts and Docker images
- Network access to NuGet package sources and AWS services

## Local Setup with Docker Compose

1. Ensure Docker is running.
2. Create a `.env` file in the project root (optional, for local development):

```bash
# .env file
ORCHARD_BASE_URL=http://localhost
DB_HOST=localhost
MACHINEKEY_VALIDATION=AutoGenerate,IsolateApps
MACHINEKEY_DECRYPTION=AutoGenerate,IsolateApps
```

3. Build and run locally:

```bash
docker-compose build
docker-compose up -d
```

4. Access the application at `http://localhost`.
5. The health check endpoint is available at `http://localhost/health`.

## Building and Pushing the Docker Image

### Using the Shell Script (Linux/macOS)

```bash
./scripts/build-push.sh
```

The script will:
1. Ask for the target platform (AWS ECR or Docker Hub)
2. Ask for the image tag (defaults to `latest`)
3. For AWS ECR: ask for AWS region and account ID, log in to ECR, create the repository if needed
4. Build the Docker image using `docker build -f Dockerfile -t <registry>/<repo>:<tag> .`
5. Push the image to the selected registry

### Using the Batch Script (Windows)

```cmd
scripts\build-push.bat
```

The script follows the same flow as the shell script.

### Image Naming

The image name is derived from the project name (`Orchard`):
- Lowercased: `orchard`
- Non-alphanumeric characters replaced with hyphens
- No leading or trailing hyphens

## AWS EKS Deployment

### 1. Prerequisites

- AWS CLI installed and configured with appropriate IAM permissions
- kubectl installed and configured
- eksctl installed (optional, for cluster creation)

### 2. EKS Cluster Setup

If you don't have an EKS cluster with Windows node groups:

```bash
# Create an EKS cluster
eksctl create cluster --name orchard-cluster --region us-east-1 --version 1.27

# Add a Windows node group
eksctl create nodegroup --name orchard-windows --cluster orchard-cluster --region us-east-1 \
    --node-type t3.large --nodes 2 --nodes-max 4 \
    --node-ami-family WindowsServer2019
```

### 3. kubectl Configuration

```bash
aws eks update-kubeconfig --region us-east-1 --name orchard-cluster
```

Verify connectivity:

```bash
kubectl cluster-info
```

### 4. Deploy the Application

Run the deployment script:

```bash
./scripts/deploy-image.sh
```

The script will:
1. Ask for AWS region and EKS cluster name
2. Configure kubectl for the target cluster
3. Ask for the image URI (full path with registry and tag)
4. Ask for environment variable values (ORCHARD_BASE_URL, DB_HOST)
5. Ask for secret values (MACHINEKEY_VALIDATION, MACHINEKEY_DECRYPTION)
6. Apply the namespace, secret, deployment, service, and ingress manifests
7. Wait for the deployment rollout to complete
8. Display the pod, service, and ingress status
9. Show the application URL

### 5. Manual Deployment Steps

If you prefer to deploy manually:

```bash
# 1. Apply the namespace
kubectl apply -f kubernetes/namespace.yaml

# 2. Create the secret (replace values with actual secrets)
kubectl create secret generic orchard-secrets -n orchard \
    --from-literal=machinekey-validation="<your-validation-key>" \
    --from-literal=machinekey-decryption="<your-decryption-key>"

# 3. Apply the deployment (replace placeholders)
sed 's|{{IMAGE_URI}}|<your-ecr-image-uri>|g' kubernetes/deployment.yaml | \
    sed 's|{{ORCHARD_BASE_URL}}|<your-base-url>|g' | \
    sed 's|{{DB_HOST}}|<your-db-host>|g' | \
    kubectl apply -f -

# 4. Apply the service
kubectl apply -f kubernetes/service.yaml

# 5. Apply the ingress
kubectl apply -f kubernetes/ingress.yaml

# 6. Wait for rollout
kubectl rollout status deployment/orchard -n orchard
```

### 6. Verify the Deployment

```bash
# Check pods
kubectl get pods -n orchard

# Check service
kubectl get svc -n orchard

# Check ingress
kubectl get ingress -n orchard

# Check health endpoint
kubectl exec -it <pod-name> -n orchard -- powershell -Command "Invoke-WebRequest http://localhost/health"
```

## Kubernetes Manifests

### namespace.yaml
Creates the `orchard` namespace for resource isolation.

### deployment.yaml
Defines the Orchard deployment with:
- 2 replicas for high availability
- Container port 80 for HTTP
- Environment variables for configuration (ORCHARD_BASE_URL, DB_HOST)
- Secret references for machineKey values
- Resource requests (250m CPU, 512Mi memory) and limits (500m CPU, 1Gi memory)
- Liveness and readiness probes on the `/health` endpoint
- EmptyDir volume for App_Data persistence within the pod

### service.yaml
Defines a ClusterIP service exposing port 80, routing to the container port 80.

### ingress.yaml
Defines an AWS ALB ingress with internet-facing scheme, routing traffic from `orchard.example.com` to the service.

## Configuration Management

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ORCHARD_BASE_URL` | Base URL for the Orchard application | `http://localhost` |
| `DB_HOST` | Database server host name | `localhost` |
| `MACHINEKEY_VALIDATION` | Machine key validation value | `AutoGenerate,IsolateApps` |
| `MACHINEKEY_DECRYPTION` | Machine key decryption value | `AutoGenerate,IsolateApps` |
| `ASPNETCORE_ENVIRONMENT` | ASP.NET environment | `Production` |

### Secrets

Sensitive values (machineKey) are stored in a Kubernetes Secret named `orchard-secrets` in the `orchard` namespace. The secret is created during deployment using `kubectl create secret generic`.

### Configuration Files

- `Web.config` — Main IIS configuration file (app settings, connection strings, HTTP modules/handlers)
- `Web.Release.config` — Release configuration transforms (machineKey externalization)
- `Config/HostComponents.config` — Autofac component registrations
- `Config/log4net.config` — Log4net logging configuration

## Security Considerations and Best Practices

### Container Security

1. **Windows Container Base Image**: The Dockerfile uses `mcr.microsoft.com/dotnet/framework/aspnet:4.8-windowsservercore-ltsc2019` as the base image, which includes only the .NET Framework runtime and IIS.

2. **No Package Manager**: The runtime stage does not install any additional packages (no chocolatey, no apt-get).

3. **Non-root User**: On Windows containers, IIS runs under the `ApplicationPoolIdentity` by default, which is a restricted service account.

4. **HTTPS**: The application should be configured with HTTPS termination at the load balancer (AWS ALB). The ingress is configured with `alb.ingress.kubernetes.io/scheme: internet-facing`.

5. **Security Headers**: Configure IIS to add security headers (X-Frame-Options, X-Content-Type-Options, etc.) in the Web.config.

6. **Authentication and Authorization**: Orchard CMS uses forms authentication configured in Web.config. Ensure the machineKey is properly externalized for consistent authentication across replicas.

7. **CORS**: Configure CORS policies in Web.config if the application serves API endpoints consumed by external frontends.

8. **Data Protection**: The machineKey is externalized via Kubernetes Secrets to ensure consistent encryption/decryption across all pod replicas.

### Kubernetes Security

1. **Secrets Management**: Sensitive values are stored in Kubernetes Secrets, never in plain text in the deployment manifests.

2. **Resource Limits**: CPU and memory limits are set to prevent resource exhaustion.

3. **Readiness and Liveness Probes**: The `/health` endpoint is used for both probes to ensure the application is healthy before receiving traffic.

4. **Namespace Isolation**: The application runs in its own namespace (`orchard`) for resource isolation.

### AWS Security

1. **IAM Roles for Service Accounts (IRSA)**: If the application needs access to AWS services (S3, RDS), use IRSA to grant pod-level IAM permissions.

2. **ECR Image Scanning**: Enable ECR image scanning to detect vulnerabilities in the container image.

3. **Network Policies**: Consider applying Kubernetes Network Policies to restrict pod-to-pod communication.

## .NET Notes

### Runtime Settings

- **Target Framework**: .NET Framework 4.8
- **Web Server**: IIS (Internet Information Services)
- **Garbage Collector**: Server GC is enabled in Web.config (`<gcServer enabled="true"/>`)
- **Kestrel**: Not applicable — Orchard CMS 1.x uses IIS as the web server

### Garbage Collector Tuning

The .NET Framework garbage collector is configured for server mode in the Web.config:

```xml
<runtime>
  <gcServer enabled="true"/>
</runtime>
```

For containerized deployments, consider setting the following environment variables:
- `COMPLUS_gcServer=1` — Enable server GC
- `COMPLUS_gcConcurrent=1` — Enable concurrent GC
- `COMPLUS_GCHeapHardLimit` — Set maximum GC heap size

### Monitoring

- **Log4net**: The application uses log4net for logging, configured via `Config/log4net.config`. Logs are written to the `App_Data/Logs` directory.
- **Application Insights**: Not currently integrated. Consider adding Application Insights SDK for .NET Framework for production monitoring.
- **Health Endpoint**: A `/health` endpoint has been added that returns JSON status `{"status": "healthy", "timestamp": "..."}`.

### HTTPS Redirection

HTTPS termination should be handled by the AWS ALB ingress controller. The application itself runs on HTTP port 80 inside the container. Configure the ALB to redirect HTTP to HTTPS:

```yaml
alb.ingress.kubernetes.io/ssl-redirect: "443"
```

### Security Headers

Add the following to the Web.config `<system.webServer>` section for security headers:

```xml
<system.webServer>
  <httpProtocol>
    <customHeaders>
      <add name="X-Frame-Options" value="SAMEORIGIN" />
      <add name="X-Content-Type-Options" value="nosniff" />
      <add name="X-XSS-Protection" value="1; mode=block" />
    </customHeaders>
  </httpProtocol>
</system.webServer>
```

### Authentication and Authorization

Orchard CMS uses forms authentication configured in Web.config:

```xml
<system.web>
  <authentication mode="Forms">
    <forms loginUrl="~/Users/Account/AccessDenied" timeout="2880"/>
  </authentication>
</system.web>
```

The machineKey must be consistent across all pod replicas for authentication to work correctly. This is achieved by externalizing the machineKey via Kubernetes Secrets.

### CORS

If the application serves API endpoints consumed by external frontends, configure CORS in Web.config:

```xml
<system.webServer>
  <httpProtocol>
    <customHeaders>
      <add name="Access-Control-Allow-Origin" value="*" />
    </customHeaders>
  </httpProtocol>
</system.webServer>
```

### Data Protection

The `System.Web` data protection system relies on the machineKey for encrypting and decrypting authentication tickets, ViewState, and other protected data. In a multi-replica deployment, all pods must use the same machineKey values, which is achieved through Kubernetes Secrets.

## Troubleshooting

### Pod Failures

```bash
# Check pod logs
kubectl logs <pod-name> -n orchard

# Describe pod for events
kubectl describe pod <pod-name> -n orchard

# Check if the pod is running
kubectl get pods -n orchard
```

### Service Issues

```bash
# Check service details
kubectl describe svc orchard-service -n orchard

# Test connectivity from within a pod
kubectl exec -it <pod-name> -n orchard -- powershell -Command "Invoke-WebRequest http://orchard-service/health"
```

### Ingress Problems

```bash
# Check ingress status
kubectl describe ingress orchard-ingress -n orchard

# Check ALB logs in AWS CloudWatch
aws logs tail /aws/eks/ingress/orchard --follow
```

### Build Issues

If the Docker build fails:
1. Ensure you have sufficient disk space
2. Check that all NuGet packages can be restored
3. Verify the .NET Framework 4.8 SDK is available in the build stage

### Common Issues

- **Port conflicts**: Ensure port 80 is not already in use
- **DNS resolution**: Verify the ingress host name resolves correctly
- **Secret not found**: Ensure the Kubernetes Secret is created before deploying the application

## Scaling and Management

### Horizontal Pod Autoscaler (HPA)

To enable auto-scaling:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: orchard-hpa
  namespace: orchard
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: orchard
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

Apply with:

```bash
kubectl apply -f kubernetes/hpa.yaml
```

### Rolling Updates

To update the application:

```bash
# Update the image
kubectl set image deployment/orchard orchard=<new-image-uri> -n orchard

# Or use the deployment script with a new image tag
./scripts/deploy-image.sh
```

### Rollbacks

To rollback to a previous deployment:

```bash
# Rollback to the previous revision
kubectl rollout undo deployment/orchard -n orchard

# Rollback to a specific revision
kubectl rollout history deployment/orchard -n orchard
kubectl rollout undo deployment/orchard --to-revision=<revision> -n orchard
```

### Resource Adjustments

To adjust resource limits:

```bash
kubectl patch deployment orchard -n orchard -p '{"spec":{"template":{"spec":{"containers":[{"name":"orchard","resources":{"requests":{"cpu":"500m","memory":"1Gi"},"limits":{"cpu":"1000m","memory":"2Gi"}}}]}}}}'
```
