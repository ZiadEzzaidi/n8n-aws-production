# Restores a dump made by backup.ps1 into the running postgres service.
# n8n is stopped during the restore so nothing writes to the database meanwhile.
param([Parameter(Mandatory)][string]$BackupFile)
$ErrorActionPreference = "Stop"
$BackupFile = (Resolve-Path $BackupFile).Path
Set-Location (Split-Path $PSScriptRoot)

docker compose stop n8n
docker compose cp $BackupFile postgres:/tmp/restore.dump
if ($LASTEXITCODE -ne 0) { throw "copy into the container failed" }

docker compose exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner /tmp/restore.dump'
$restoreExit = $LASTEXITCODE
docker compose exec -T postgres rm /tmp/restore.dump
if ($restoreExit -ne 0) { throw "pg_restore failed (exit code $restoreExit)" }

docker compose start n8n
Write-Host "Restored $BackupFile. n8n is starting again."
