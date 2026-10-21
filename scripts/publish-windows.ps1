param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "apps/windows/src/Amberflow.Windows/Amberflow.Windows.csproj"
$output = Join-Path $root "artifacts/windows/$Runtime"

dotnet publish $project `
    --configuration Release `
    --runtime $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    --output $output

Write-Host "Published Amberflow to $output"
