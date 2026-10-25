# Dumps the n8n PostgreSQL database to backups/n8n-<timestamp>.dump
# The dump does NOT contain N8N_ENCRYPTION_KEY: keep that key backed up separately.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot)

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$file = "backups/n8n-$stamp.dump"
New-Item -ItemType Directory -Force backups | Out-Null

# Dump inside the container then copy it out: piping binary through PowerShell would corrupt it.
docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -f /tmp/n8n.dump'
if ($LASTEXITCODE -ne 0) { throw "pg_dump failed" }
docker compose cp postgres:/tmp/n8n.dump $file
if ($LASTEXITCODE -ne 0) { throw "copy out of the container failed" }
docker compose exec -T postgres rm /tmp/n8n.dump

$size = (Get-Item $file).Length
Write-Host "Backup written: $file ($size bytes)"
