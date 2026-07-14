#Requires -Version 7
<#
.SYNOPSIS
  Resolve a Bitwarden Secrets Manager secret by key name and write its value to stdout.

.DESCRIPTION
  bws secret get requires a UUID. This helper looks up the key in `bws secret list`,
  then fetches by id. Intended for piping into env assignment — do not log the output.

.PARAMETER Key
  Secret name / key (becomes the env var name when using `bws run`).

.EXAMPLE
  $val = & .\Get-BwsSecret.ps1 -Key GITHUB_TOKEN
  [Environment]::SetEnvironmentVariable("GITHUB_PERSONAL_ACCESS_TOKEN", $val, "User")
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Key
)

$ErrorActionPreference = "Stop"

if (-not $env:BWS_ACCESS_TOKEN) {
    throw "BWS_ACCESS_TOKEN is not set. Configure the machine-account access token first."
}

if (-not (Get-Command bws -ErrorAction SilentlyContinue)) {
    throw "bws CLI not found on PATH."
}

$matches = bws secret list -o json | ConvertFrom-Json | Where-Object { $_.key -eq $Key }
$count = @($matches).Count
if ($count -eq 0) {
    throw "No BWS secret with key '$Key'."
}
if ($count -gt 1) {
    throw "Multiple BWS secrets named '$Key' ($count). Disambiguate in the vault or use UUID."
}

$secret = @($matches)[0]
$obj = bws secret get $secret.id -o json | ConvertFrom-Json
if (-not $obj.value) {
    throw "Secret '$Key' ($($secret.id)) has an empty value."
}

# stdout only — caller assigns; never Write-Host the value
Write-Output $obj.value
