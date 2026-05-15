param(
    [string]$Server = ".\SQLEXPRESS",
    [string]$Database = "CustomerAIDemo2022",
    [switch]$SqlAuth,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$inputFile = Join-Path $repoRoot "sql\compat_2022_helpdesk_demo.sql"

$args = @(
    "-S", $Server,
    "-b",
    "-f", "i:65001,o:65001",
    "-i", $inputFile,
    "-v", "DemoDatabase=$Database"
)

if ($SqlAuth) {
    $args += @("-U", $User, "-P", $Password)
}
else {
    $args += "-E"
}

Write-Host "Running SQL Server 2022-compatible fallback demo on $Server / $Database"
& sqlcmd @args

if ($LASTEXITCODE -ne 0) {
    throw "sqlcmd failed for $inputFile with exit code $LASTEXITCODE."
}

Write-Host ""
Write-Host "Fallback demo completed."
Write-Host "Use this for local rehearsal. For the real Native Vector Search message, run the SQL Server 2025 scripts on a 17.x/Azure SQL instance."
