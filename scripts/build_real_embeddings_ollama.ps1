param(
    [string]$Server = ".\SQLEXPRESS",
    [string]$Database = "CustomerAIDemo2022",
    [string]$Model = "bge-m3",
    [string]$OllamaUrl = "http://127.0.0.1:11434/api/embed",
    [int]$BatchSize = 8
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "tools\build_real_embeddings_ollama.py"

py -3 $scriptPath `
    --server $Server `
    --database $Database `
    --model $Model `
    --ollama-url $OllamaUrl `
    --batch-size $BatchSize

if ($LASTEXITCODE -ne 0) {
    throw "Real embedding build failed with exit code $LASTEXITCODE."
}

Write-Host ""
Write-Host "Real embeddings are ready."
Write-Host "Restart UI with:"
Write-Host '$env:HELPDESK_EMBEDDING_MODE="real"'
Write-Host '$env:HELPDESK_UI_PORT="8081"'
Write-Host 'py -3 .\ui\server.py'

