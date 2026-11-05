#!/bin/bash
set -e

# Build and push script for Orchard CMS Docker image to AWS ECR
# Usage: ./scripts/build-push.sh

# Project name (used for image name)
PROJECT_NAME="Orchard"

# Sanitize the project name: lowercase, replace non-alphanumeric with hyphen, trim leading/trailing hyphens
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "=== Orchard CMS Docker Build and Push ==="
echo ""

# Ask for target platform
echo "Select target platform:"
echo "  1. AWS ECR"
echo "  2. Docker Hub"
read -p "Enter choice (1 or 2): " PLATFORM_CHOICE

# Ask for image tag
read -p "Enter image tag (or press Enter for 'latest'): " IMAGE_TAG
if [ -z "$IMAGE_TAG" ]; then
    IMAGE_TAG="latest"
fi

# Sanitize tag
IMAGE_TAG=$(echo "$IMAGE_TAG" | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')

if [ "$PLATFORM_CHOICE" = "1" ]; then
    # AWS ECR
    read -p "Enter AWS region (e.g., us-east-1): " AWS_REGION
    read -p "Enter AWS account ID: " AWS_ACCOUNT_ID
    read -p "Enter ECR repository name (or press Enter for '$IMAGE_NAME'): " ECR_REPO
    if [ -z "$ECR_REPO" ]; then
        ECR_REPO="$IMAGE_NAME"
    fi

    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

    echo ""
    echo "=== Building and pushing to AWS ECR ==="
    echo "Registry: $REGISTRY_URL"
    echo "Repository: $ECR_REPO"
    echo "Image: $FULL_IMAGE_NAME"
    echo ""

    # Login to ECR
    echo "Logging in to AWS ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"

    # Create repository if it doesn't exist
    echo "Checking if ECR repository exists..."
    aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
        aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"

    # Build the Docker image
    echo "Building Docker image..."
    docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

    # Push the image
    echo "Pushing Docker image..."
    docker push "$FULL_IMAGE_NAME"

    echo ""
    echo "=== Build and push complete ==="
    echo "Image: $FULL_IMAGE_NAME"

elif [ "$PLATFORM_CHOICE" = "2" ]; then
    # Docker Hub
    read -p "Enter Docker Hub username: " DOCKER_USERNAME
    read -s -p "Enter Docker Hub password: " DOCKER_PASSWORD
    echo ""
    read -p "Enter repository name (or press Enter for '$IMAGE_NAME'): " DOCKER_REPO
    if [ -z "$DOCKER_REPO" ]; then
        DOCKER_REPO="$IMAGE_NAME"
    fi

    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${DOCKER_REPO}:${IMAGE_TAG}"

    echo ""
    echo "=== Building and pushing to Docker Hub ==="
    echo "Repository: $FULL_IMAGE_NAME"
    echo ""

    # Login to Docker Hub
    echo "Logging in to Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin

    # Build the Docker image
    echo "Building Docker image..."
    docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

    # Push the image
    echo "Pushing Docker image..."
    docker push "$FULL_IMAGE_NAME"

    echo ""
    echo "=== Build and push complete ==="
    echo "Image: $FULL_IMAGE_NAME"

else
    echo "Invalid choice. Exiting."
    exit 1
fi
