param(
    [string]$Server = "localhost",
    [string]$Database = "CustomerAIDemo",
    [string]$CsvPath = "D:\DSA\Demo_DBMS\data\customer_feedback.csv",
    [switch]$SqlAuth,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"

function Invoke-SqlFile {
    param(
        [string]$InputFile,
        [string[]]$Variables = @()
    )

    $args = @("-S", $Server, "-b", "-f", "i:65001,o:65001", "-i", $InputFile)

    if ($SqlAuth) {
        $args += @("-U", $User, "-P", $Password)
    }
    else {
        $args += "-E"
    }

    foreach ($variable in $Variables) {
        $args += @("-v", $variable)
    }

    Write-Host "Running $InputFile"
    & sqlcmd @args

    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed for $InputFile with exit code $LASTEXITCODE."
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$absoluteCsv = (Resolve-Path -LiteralPath $CsvPath).Path

Invoke-SqlFile -InputFile (Join-Path $repoRoot "sql\00_setup_database.sql") -Variables @("DemoDatabase=$Database")
Invoke-SqlFile -InputFile (Join-Path $repoRoot "sql\01_schema.sql") -Variables @("DemoDatabase=$Database")
Invoke-SqlFile -InputFile (Join-Path $repoRoot "sql\03_import_csv.sql") -Variables @("DemoDatabase=$Database", "CsvPath=$absoluteCsv")

Write-Host "Database and seed data are ready."
Write-Host "Next: run sql\02_register_external_model_ollama.sql, sql\04_generate_embeddings.sql, sql\05_create_vector_index.sql."
