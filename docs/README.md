# Eurofins DevOps Take-Home: HelloWorld IIS Pipeline

[![CI](https://github.com/nunoermidapacheco/eurofins-devops-take-home/actions/workflows/ci.yml/badge.svg)](https://github.com/nunoermidapacheco/eurofins-devops-take-home/actions/workflows/ci.yml)

A small end-to-end delivery pipeline for a .NET web application: build and package with CI, deploy to IIS on Windows, monitor with a Windows service, and optionally run as a Docker container.

## Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Where to find each step](#where-to-find-each-step)
- [Architecture](#architecture)
- [Quick start](#quick-start)
- [Step 1: Build and CI](#step-1-build-and-ci)
- [Step 2: IIS deployment](#step-2-iis-deployment)
- [Step 3: HelloWorldMonitor](#step-3-helloworldmonitor)
- [Step 4: Windows service deployment](#step-4-windows-service-deployment)
- [Steps 5 and 6: Docker](#steps-5-and-6-docker)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)

## Overview

| Component | What it does |
|---|---|
| **HelloWorld** | Minimal ASP.NET Core app that returns `Hello World!` on `/` |
| **HelloWorldMonitor** | .NET Worker Service that checks the IIS site every 60 seconds and logs the HTTP result |
| **CI pipeline** | GitHub Actions: builds, publishes, zips, containerizes and pushes the image |
| **Deployment scripts** | PowerShell scripts for IIS, the Windows service and Docker |

**Tech stack:** C#, .NET 10, ASP.NET Core, IIS, PowerShell, GitHub Actions, Docker / Docker Hub.

## Requirements

- **Windows** with administrator rights. This can be a physical machine or a virtual one; macOS and Linux users need a Windows VM to follow the IIS and service steps. (For example **UTM** on a Mac).
- **.NET 10 SDK** to build the monitor, and the **.NET 10 Hosting Bundle** to run the app in IIS
- **Docker** (any OS), only for the container steps. The deploy script is PowerShell, so on macOS or Linux install PowerShell 7 or run the three `docker` commands by hand.

## Where to find each step

| Step | What | Where |
|---|---|---|
| 1. Build | Web app, CI pipeline, zip package | `HelloWorld/`, `.github/workflows/ci.yml` |
| 2. IIS deployment | Site, HTTPS binding, app pool, local group and user | `scripts/Deploy-HelloWorld.ps1` |
| 3. Log status | Windows service that checks the site every 60 seconds | `HelloWorldMonitor/` |
| 4. Service deployment | Install script (auto-start, run as user, recovery) | `scripts/Install-HelloWorldMonitor.ps1` |
| 5. Docker image | Dockerfile and CI push to Docker Hub | `HelloWorld/Dockerfile`, `.github/workflows/ci.yml` |
| 6. Docker deployment | Pull and run the container | `scripts/Deploy-HelloWorld-Docker.ps1` |

## Architecture

See [architecture.md](architecture.md) for the project architecture.

## Quick start

To reproduce the whole setup on a Windows machine, in this order (run from the repository root, in an elevated PowerShell):

- **Step 1:** download the `HelloWorld` artifact from the CI run and extract it to `C:\Eurofins\HelloWorld`
- **Step 2:** run `scripts\Deploy-HelloWorld.ps1` to configure IIS
- **Step 3:** run `dotnet publish HelloWorldMonitor -c Release -r win-x64 --self-contained false -o C:\Eurofins\HelloWorldMonitor` to build the monitor
- **Step 4:** run `scripts\Install-HelloWorldMonitor.ps1` to install the service
- **Steps 5 and 6 (optional):** run `scripts\Deploy-HelloWorld-Docker.ps1` for the container

Each step is described in detail in its own section below.

## Step 1: Build and CI

`.github/workflows/ci.yml` is a GitHub Actions workflow that automatically builds the HelloWorld app, packages it as a zip for IIS, and publishes it as a Docker image, so every commit to `main` produces a deployable result without any manual steps.

It runs on every push to `main`, in the following stages:

| # | Stage | What it does |
|---|---|---|
| 1 | Checkout and setup | Fetches the code and installs the .NET 10 SDK |
| 2 | Restore and build | `dotnet restore` and `dotnet build` |
| 3 | Publish | `dotnet publish` outputs the deployable files to `./publish` |
| 4 | Package | Zips the output as `HelloWorld.zip` and uploads it as a build artifact |
| 5 | Docker build | Builds the image from `HelloWorld/Dockerfile` |
| 6 | Smoke test | Starts the container and checks that `http://localhost:8080` responds |
| 7 | Docker Hub push | Logs in, tags the image and pushes `nunopacheco/helloworld` as `latest` and with the short commit SHA |

**Docker Hub credentials:** the login uses the `DOCKERHUB_TOKEN` repository secret (*Settings > Secrets and variables > Actions*), so no credentials are stored in the code.

**Getting the package:** open the workflow run in the GitHub *Actions* tab and download the `HelloWorld` artifact at the bottom of the page. Extract it into the IIS folder in Step 2.

## Step 2: IIS deployment

`scripts/Deploy-HelloWorld.ps1` configures IIS on a Windows machine from scratch: it creates the user, group, application pool, web site, HTTPS binding and application, so the deployment is repeatable instead of clicked together by hand.

It is idempotent: each resource is checked before it is created, so the script can be re-run safely.

### Prerequisites

- Windows with IIS installed, including *IIS Management Scripts and Tools* (provides the `WebAdministration` module)
- The **.NET 10 Hosting Bundle**, so IIS can run ASP.NET Core applications
- An elevated PowerShell session (Run as Administrator)
- The published application extracted to `C:\Eurofins\HelloWorld` (the `HelloWorld` artifact from the CI run is a zip file). The script configures IIS but does not copy the files.

### What the script creates

| Resource | Name / value |
|---|---|
| Local user | `HelloWorldUser` |
| Local group | `HelloWorldGroup` (contains `HelloWorldUser`) |
| Application pool | `HelloWorldPool`, running as `.\HelloWorldUser` |
| Web site | `HelloWorld`, path `C:\Eurofins\HelloWorld`, HTTP on port `8080`, host header `localhost` |
| HTTPS binding | Port `443`, host header `localhost`, self-signed certificate `CN=localhost` |
| IIS log folder | `C:\Eurofins\IISLogs` |
| IIS application | `/HelloWorld` under the site, bound to `HelloWorldPool` |

### Running it

```powershell
.\scripts\Deploy-HelloWorld.ps1
```

### Checking the result

The application answers at:

- `http://localhost:8080/HelloWorld/`
- `https://localhost/HelloWorld/` (the browser warns about the self-signed certificate)

The site root (`http://localhost:8080/` and `https://localhost/`) is not used. It returns `HTTP 500.35`, because ASP.NET Core does not allow two apps in the same pool and the root points to the same folder as the application.

## Step 3: HelloWorldMonitor

`HelloWorldMonitor/` is a .NET Worker Service that watches the IIS deployment: it checks the site every 60 seconds, records the result in a log file, and stops itself if the site is not healthy.

### Behaviour

1. Sends an HTTP `GET` to `http://localhost:8080/HelloWorld/` every 60 seconds
2. Appends the result to `status.log`, in the same folder as the executable
3. If the status code is anything other than `200`, the service exits with code `1`

Each log line has the format `date | status code | message`:

```
29/09/2026 12:30:00 | 200 | OK
```

If the site cannot be reached at all (for example IIS is stopped), the line shows code `0` with the error message, and the service stops as well.

### Running it locally

For development, run it from the terminal or your editor. It writes to the console as well as to the log file. The site from Step 2 must be running, otherwise the monitor logs code `0` and stops:

```powershell
dotnet run --project HelloWorldMonitor
```

### Building it for the server

```powershell
dotnet publish HelloWorldMonitor -c Release -r win-x64 --self-contained false -o C:\Eurofins\HelloWorldMonitor
```

This produces `HelloWorldMonitor.exe` in `C:\Eurofins\HelloWorldMonitor`, which is the path the install script in Step 4 points to. The `-r win-x64` option makes sure a Windows executable is generated.

Building requires the **.NET 10 SDK** on the same machine. Running the resulting service only needs the .NET runtime, which the Hosting Bundle from Step 2 already includes.

## Step 4: Windows service deployment

`scripts/Install-HelloWorldMonitor.ps1` registers HelloWorldMonitor as a Windows service that starts automatically with the machine, runs under a dedicated user, and recovers by itself after a failure.

### Prerequisites

- An elevated PowerShell session (Run as Administrator)
- `HelloWorldMonitor.exe` published to `C:\Eurofins\HelloWorldMonitor` (see Step 3)
- The local user `HelloWorldUser`, which is created by the IIS deployment script (Step 2)
- The *Log on as a service* right for `HelloWorldUser` (*Local Security Policy > Local Policies > User Rights Assignment > Log on as a service*)
- Write permission for `HelloWorldUser` on `C:\Eurofins\HelloWorldMonitor`, so the service can create `status.log`

### What the script configures

| Setting | Value |
|---|---|
| Service name | `HelloWorldMonitor` |
| Executable | `C:\Eurofins\HelloWorldMonitor\HelloWorldMonitor.exe` |
| Runs as | `.\HelloWorldUser` |
| Startup type | Automatic |
| Recovery | Restart the service after 300 seconds (`restart/300000`, in milliseconds) |
| Recovery counter | Reset after 24 hours (`reset= 86400`) |
| Failure flag | Enabled, so an exit with a non-zero code counts as a failure |

The failure flag makes Windows count a non-zero exit code as a failure. The monitor exits with code `1` when the site does not return `200`, so Windows restarts it after 300 seconds.

### Running it

```powershell
.\scripts\Install-HelloWorldMonitor.ps1
```

The script creates the service, sets the recovery options and starts it.

### Checking the result

```powershell
Get-Service HelloWorldMonitor
sc.exe qc HelloWorldMonitor
sc.exe qfailure HelloWorldMonitor
Get-Content C:\Eurofins\HelloWorldMonitor\status.log -Tail 5
```

- `Get-Service` shows whether the service is running
- `sc.exe qc` shows the startup type and the user it runs as
- `sc.exe qfailure` shows the recovery settings
- `Get-Content ... -Tail 5` shows the last five log lines

### Testing the recovery

Use two PowerShell windows (both as administrator): one to watch the log, one to run commands.

**Terminal 1:** follow the log live (press `Ctrl+C` to stop watching):

```powershell
Get-Content C:\Eurofins\HelloWorldMonitor\status.log -Tail 5 -Wait
```

**Terminal 2:** run the test:

1. Stop the IIS site: `Stop-Website -Name HelloWorld`
2. Within 60 seconds, Terminal 1 shows a failed check (code `0` or not `200`) and the service stops. Confirm with `Get-Service HelloWorldMonitor`, which shows `Stopped`.
3. Start the site again before the 300 seconds are over: `Start-Website -Name HelloWorld`
4. Windows restarts the service after 300 seconds. `Get-Service HelloWorldMonitor` shows `Running` again, and Terminal 1 shows a new line with `200`.

## Steps 5 and 6: Docker

The same application can also run as a container: the CI pipeline builds a Docker image and publishes it to Docker Hub, and `scripts/Deploy-HelloWorld-Docker.ps1` pulls it and starts it on any machine with Docker, with no IIS setup needed.

### The image

`HelloWorld/Dockerfile` uses a multi-stage build:

| Stage | Base image | Purpose |
|---|---|---|
| build | `mcr.microsoft.com/dotnet/sdk:10.0` | Compiles and publishes the app |
| final | `mcr.microsoft.com/dotnet/aspnet:10.0` | Runs the published app (smaller, no SDK) |

The container listens on port `8080` internally (`ASPNETCORE_HTTP_PORTS=8080`). The CI pipeline pushes the result to Docker Hub as `nunopacheco/helloworld:latest`, and also tags it with the short commit SHA.

### Prerequisites

- Docker installed and running (Docker Desktop or Docker Engine)
- Docker set to run **Linux containers** (the default in Docker Desktop)
- Internet access to Docker Hub, to pull the image

### Running it

```powershell
.\scripts\Deploy-HelloWorld-Docker.ps1
```

The script does three things:

1. Removes any existing `helloworld` container, so it can be re-run safely
2. Pulls the latest image from Docker Hub
3. Starts a new container in the background, mapping port `9090` on the host to port `8080` in the container

### Checking the result

The application answers at `http://localhost:9090/`. Unlike IIS, there is no `/HelloWorld` path here.

```powershell
docker ps
Invoke-WebRequest http://localhost:9090/ -UseBasicParsing
docker logs helloworld
```

- `docker ps` shows that the `helloworld` container is running
- `Invoke-WebRequest` should return `200` and `Hello World!`
- `docker logs` shows the application output

> **Ports:** the container is published on host port `9090` so it doesn't clash with the IIS site on `8080`. Both can run on the same machine at the same time.

## Troubleshooting

Common problems, their likely causes and the locations of the logs are listed in [troubleshooting.md](troubleshooting.md)

## Known limitations

This project is a time-boxed spike, so some choices are deliberate shortcuts. They are listed here with what a production version would do instead.

| Limitation | Why it matters | Production approach |
|---|---|---|
| **Credentials are hard-coded** in the IIS and service scripts | Anyone with repository access can read the `HelloWorldUser` password | Prompt for the password, or read it from a secret store |
| **Self-signed HTTPS certificate** | Browsers show a warning, and the certificate is not trusted | Use a certificate from a trusted authority |
| **CI does not deploy** | The pipeline produces the zip and the image, but copying the zip to IIS is manual | Add a release stage or a self-hosted runner that deploys after a successful build |
| **No automated tests in CI** | The pipeline only checks that the app builds and that the container answers | Add a `dotnet test` stage before packaging |
| **Some prerequisites are manual** | The *Log on as a service* right and the folder permissions for `HelloWorldUser` are not set by the scripts | Grant them in the scripts, or through Group Policy |
| **`HelloWorldGroup` has no permissions assigned** | The group exists and contains the user, but no resource uses it yet | Grant the group NTFS rights on the site and log folders |
| **The monitor stops on the first failure** | A single transient error stops the service, and it stays down for 300 seconds | Require several consecutive failures before stopping (the brief asks for immediate stop, so this is as specified) |
| **The monitor is built by hand** | `dotnet publish` is run manually, while the web app is built by CI | Add a second job to the workflow that publishes the monitor as an artifact |