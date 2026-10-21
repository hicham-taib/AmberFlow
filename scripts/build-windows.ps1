param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $root "apps/windows/Amberflow.Windows.sln"

dotnet restore $solution
dotnet build $solution --configuration $Configuration --no-restore
