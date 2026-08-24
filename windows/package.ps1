param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeIdentifier,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $PSScriptRoot "DSHDesktop.Windows.csproj"
$PublishDirectory = Join-Path $ProjectRoot ".build/windows/$RuntimeIdentifier"
$DistDirectory = Join-Path $ProjectRoot ".build/dist-windows"
$ArchiveName = "DSH-Desktop-Windows-$RuntimeIdentifier-$Version.zip"
$Archive = Join-Path $DistDirectory $ArchiveName

New-Item -ItemType Directory -Force -Path $PublishDirectory, $DistDirectory | Out-Null

dotnet publish $Project `
    --configuration $Configuration `
    --runtime $RuntimeIdentifier `
    --self-contained true `
    --output $PublishDirectory `
    -p:Version=$Version `
    -p:DebugSymbols=false

Copy-Item (Join-Path $PSScriptRoot "README.md") (Join-Path $PublishDirectory "README.txt") -Force

if (Test-Path $Archive) {
    Remove-Item $Archive -Force
}
Compress-Archive -Path (Join-Path $PublishDirectory "*") -DestinationPath $Archive -CompressionLevel Optimal

$Digest = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
"$Digest  $ArchiveName" | Set-Content -Encoding ascii "$Archive.sha256"

Write-Host "Created $Archive"
Write-Host "SHA-256 $Digest"
