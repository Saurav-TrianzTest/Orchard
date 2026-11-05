# Dockerfile for Orchard CMS 1.x (.NET Framework 4.8, ASP.NET MVC 5, IIS)
# Uses Windows containers with IIS for .NET Framework compatibility
# Multi-stage build: build stage compiles and stages the application, runtime stage serves it

# Build stage
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8-windowsservercore-ltsc2019 AS build
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

WORKDIR /app

# Copy solution and restore packages
COPY src/Orchard.sln .
COPY src/NuGet.config ./src/
COPY src/Orchard/Orchard.Framework.csproj ./src/Orchard/
COPY src/Orchard.Web/Orchard.Web.csproj ./src/Orchard.Web/
COPY src/Tools/Orchard/Orchard.csproj ./src/Tools/Orchard/
COPY src/Orchard.WarmupStarter/Orchard.WarmupStarter.csproj ./src/Orchard.WarmupStarter/

# Restore NuGet packages
RUN nuget restore src/Orchard.sln

# Copy all source files
COPY src/ ./src/

# Build and stage the web application using Orchard's build system
RUN msbuild Orchard.proj /t:Package-Stage /p:Configuration=Release /m

# Final runtime stage
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8-windowsservercore-ltsc2019 AS final
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Environment variables for the application
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ORCHARD_BASE_URL=http://localhost
ENV DB_HOST=localhost
ENV MACHINEKEY_VALIDATION=AutoGenerate,IsolateApps
ENV MACHINEKEY_DECRYPTION=AutoGenerate,IsolateApps

# Configure IIS to serve Orchard on port 80
RUN Remove-WebSite -Name 'Default Web Site'; \
    New-Website -Name 'Orchard' -Port 80 -PhysicalPath 'C:\inetpub\wwwroot' -ApplicationPool '.NET v4.5'

WORKDIR /inetpub/wwwroot

# Copy the staged Orchard web application
COPY --from=build /app/build/Stage/Orchard.Web/ ./

# Expose port 80 for HTTP
EXPOSE 80

# Container startup - start IIS and keep the container running
ENTRYPOINT ["powershell", "-Command", "Start-Service W3SVC; while ($true) { Start-Sleep -Seconds 3600 }"]
