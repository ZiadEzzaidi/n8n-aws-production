# Applies the current configuration (compose.yaml, Caddyfile, n8n version, settings) to the running
# server in place, through Systems Manager. No SSH, and the server and its data are not replaced.
param(
    [string]$AwsProfile = "default",
    [string]$Region = "eu-north-1",
    [string]$AwsCli = "aws"
)
$ErrorActionPreference = "Stop"
$infra = Join-Path (Split-Path $PSScriptRoot) "infra"

$instanceId = terraform "-chdir=$infra" output -raw instance_id
$scriptB64 = terraform "-chdir=$infra" output -raw configure_script_b64
if (-not $instanceId -or -not $scriptB64) { throw "Run terraform apply first: no instance_id/configure_script_b64 output" }

$paramsFile = Join-Path ([IO.Path]::GetTempPath()) "n8n-configure-params.json"
$commands = @("echo '$scriptB64' | base64 -d > /opt/configure.sh", "bash /opt/configure.sh")
[IO.File]::WriteAllText($paramsFile, (@{ commands = $commands } | ConvertTo-Json -Compress))

$commandId = & $AwsCli ssm send-command --instance-ids $instanceId --document-name AWS-RunShellScript `
    --comment "Apply n8n configuration" --parameters "file://$paramsFile" `
    --query Command.CommandId --output text --profile $AwsProfile --region $Region
Remove-Item $paramsFile
if (-not $commandId) { throw "send-command failed" }

& $AwsCli ssm wait command-executed --command-id $commandId --instance-id $instanceId --profile $AwsProfile --region $Region
& $AwsCli ssm get-command-invocation --command-id $commandId --instance-id $instanceId `
    --query "[Status,StandardOutputContent,StandardErrorContent]" --output text --profile $AwsProfile --region $Region
