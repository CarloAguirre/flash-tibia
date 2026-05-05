# Canary 15 Web Stack

This branch keeps the working 8.60 stack protected on `working-860` and prepares a separate Canary/client 15 stack.

## Ports

- 8.60 web: `http://localhost:8080/`
- Canary 15 web: `http://localhost:8081/`
- Canary game WebSocket proxy: `7272`
- Canary status/login TCP proxy: `7271`
- Canary DB host port: `3307`
- Canary login HTTP debug port: `8090`

## Local Files

`canary-main/docker/.env` is ignored by git and contains the local Docker settings used by Canary `start.sh`.

The client 15 assets must exist at `otclient/data/things/1500/` before building the WASM client. They are ignored by git because they are large and generated from `tibia-client-15.00.249ccc/assets`.

## Build The Client 15 Web Artifacts

From the workspace root:

```powershell
New-Item -ItemType Directory -Force otclient\data\things\1500 | Out-Null
Copy-Item tibia-client-15.00.249ccc\assets\* otclient\data\things\1500\ -Recurse -Force
Copy-Item tibia-client-15.00.249ccc\assets.json.sha256 otclient\data\things\1500\assets.json.sha256 -Force

docker build -t otclient-web15 -f otclient\Dockerfile.browser otclient
$container = docker create otclient-web15
docker cp "${container}:/otclient-web/." web15\public
docker rm $container
Move-Item web15\public\otclient.html web15\public\index.html -Force
```

## Start Canary 15

The local Canary Dockerfile builds vcpkg dependencies from source, so the first build can be slow but does not require a GitHub token.

```powershell
docker compose -f docker-compose.canary.yml build canary
docker compose -f docker-compose.canary.yml up -d canary-db canary-login canary canary-proxy web15
```

Test account from Canary seed data:

- Email: `@test1`
- Password: `test`

For friends outside your machine, set `CANARY_PUBLIC_HOST` to your public hostname/IP before starting the stack so the login server advertises the right game address.
