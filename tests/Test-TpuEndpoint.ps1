# Sends the three test prompts to the deployed TPU model and prints each response.
# Run from the repository root:
#   .\tests\Test-TpuEndpoint.ps1 -ProjectId your-project-id

param(
  [Parameter(Mandatory = $true)] [string]$ProjectId,
  [string]$Region = "us-east1",
  [string]$EndpointId = "aisecurity-tpu-endpoint"
)

$tests = @(
  @{ Name = "1. Normal prompt";      File = "tpu-test-1-normal.json" },
  @{ Name = "2. Prompt injection";   File = "tpu-test-2-injection.json" },
  @{ Name = "3. Sensitive data";     File = "tpu-test-3-sensitive.json" }
)

foreach ($t in $tests) {
  $path = Join-Path $PSScriptRoot $t.File
  Write-Host ""
  Write-Host "=== $($t.Name) ===" -ForegroundColor Cyan
  gcloud ai endpoints predict $EndpointId --region=$Region --project=$ProjectId --json-request=$path
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Request failed: $($t.Name)" -ForegroundColor Red
  }
}
