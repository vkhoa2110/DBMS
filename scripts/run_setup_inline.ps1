param(
    [string]$Server = "localhost",
    [string]$Database = "CustomerAIDemo",
    [switch]$SqlAuth,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"

function Invoke-SqlFile {
    param([string]$InputFile)

    $args = @("-S", $Server, "-b", "-i", $InputFile, "-v", "DemoDatabase=$Database")
    $args += @("-f", "i:65001,o:65001")

    if ($SqlAuth) {
        $args += @("-U", $User, "-P", $Password)
    }
    else {
        $args += "-E"
    }

    Write-Host "Running $InputFile"
    & sqlcmd @args

    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed for $InputFile with exit code $LASTEXITCODE."
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot

Invoke-SqlFile -InputFile (Join-Path $repoRoot "sql\00_setup_database.sql")
Invoke-SqlFile -InputFile (Join-Path $repoRoot "sql\01_schema.sql")
Invoke-SqlFile -InputFile (Join-Path $repoRoot "sql\03_seed_inline_sample.sql")

Write-Host "Inline sample database is ready."
Write-Host "Next: register the embedding model, generate embeddings, create vector index, and run demo queries."
