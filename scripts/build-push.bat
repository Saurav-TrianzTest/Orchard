@echo off
setlocal enabledelayedexpansion

REM Build and push script for Orchard CMS Docker image
REM Usage: scripts\build-push.bat

REM Project name (used for image name)
set "PROJECT_NAME=Orchard"

REM Sanitize the project name: lowercase, replace non-alphanumeric with hyphen, trim leading/trailing hyphens
for /f "delims=" %%i in ('powershell -Command "('$PROJECT_NAME'.ToLower() -creplace '[^a-z0-9]+', '-').Trim('-')"') do set "IMAGE_NAME=%%i"

echo === Orchard CMS Docker Build and Push ===
echo.

REM Ask for target platform
echo Select target platform:
echo   1. AWS ECR
echo   2. Docker Hub
set /p PLATFORM_CHOICE="Enter choice (1 or 2): "

REM Ask for image tag
set /p IMAGE_TAG="Enter image tag (or press Enter for 'latest'): "
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"

REM Sanitize tag
for /f "delims=" %%i in ('powershell -Command "(!IMAGE_TAG! -creplace '[^a-z0-9.-]+', '-').Trim('-')"') do set "IMAGE_TAG=%%i"

if "!PLATFORM_CHOICE!"=="1" (
    REM AWS ECR
    set /p AWS_REGION="Enter AWS region (e.g., us-east-1): "
    set /p AWS_ACCOUNT_ID="Enter AWS account ID: "
    set /p ECR_REPO="Enter ECR repository name (or press Enter for !IMAGE_NAME!): "
    if "!ECR_REPO!"=="" set "ECR_REPO=!IMAGE_NAME!"

    set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
    set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

    echo.
    echo === Building and pushing to AWS ECR ===
    echo Registry: !REGISTRY_URL!
    echo Repository: !ECR_REPO!
    echo Image: !FULL_IMAGE_NAME!
    echo.

    REM Login to ECR
    echo Logging in to AWS ECR...
    aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
    if !ERRORLEVEL! neq 0 (echo ECR login failed & exit /b 1)

    REM Create repository if it doesn't exist
    echo Checking if ECR repository exists...
    aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        echo Creating ECR repository...
        aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    )

    REM Build the Docker image
    echo Building Docker image...
    docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
    if !ERRORLEVEL! neq 0 (echo Docker build failed & exit /b 1)

    REM Push the image
    echo Pushing Docker image...
    docker push !FULL_IMAGE_NAME!
    if !ERRORLEVEL! neq 0 (echo Docker push failed & exit /b 1)

    echo.
    echo === Build and push complete ===
    echo Image: !FULL_IMAGE_NAME!

) else if "!PLATFORM_CHOICE!"=="2" (
    REM Docker Hub
    set /p DOCKER_USERNAME="Enter Docker Hub username: "
    set /p DOCKER_PASSWORD="Enter Docker Hub password: "
    set /p DOCKER_REPO="Enter repository name (or press Enter for !IMAGE_NAME!): "
    if "!DOCKER_REPO!"=="" set "DOCKER_REPO=!IMAGE_NAME!"

    set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!DOCKER_REPO!:!IMAGE_TAG!"

    echo.
    echo === Building and pushing to Docker Hub ===
    echo Repository: !FULL_IMAGE_NAME!
    echo.

    REM Login to Docker Hub
    echo Logging in to Docker Hub...
    echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
    if !ERRORLEVEL! neq 0 (echo Docker login failed & exit /b 1)

    REM Build the Docker image
    echo Building Docker image...
    docker build -f Dockerfile -t !FULL_IMAGE_NAME! .
    if !ERRORLEVEL! neq 0 (echo Docker build failed & exit /b 1)

    REM Push the image
    echo Pushing Docker image...
    docker push !FULL_IMAGE_NAME!
    if !ERRORLEVEL! neq 0 (echo Docker push failed & exit /b 1)

    echo.
    echo === Build and push complete ===
    echo Image: !FULL_IMAGE_NAME!

) else (
    echo Invalid choice. Exiting.
    exit /b 1
)

endlocal
