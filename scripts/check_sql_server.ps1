param(
    [string]$Server = ".\SQLEXPRESS",
    [switch]$SqlAuth,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"

$args = @(
    "-S", $Server,
    "-b",
    "-W",
    "-s", "|",
    "-Q",
    @"
SELECT
    CAST(@@SERVERNAME AS NVARCHAR(128)) AS server_name,
    CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(40)) AS product_version,
    CAST(SERVERPROPERTY('ProductMajorVersion') AS NVARCHAR(10)) AS major_version,
    CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) AS edition;
"@
)

if ($SqlAuth) {
    $args += @("-U", $User, "-P", $Password)
}
else {
    $args += "-E"
}

& sqlcmd @args

if ($LASTEXITCODE -ne 0) {
    throw "Could not connect to SQL Server '$Server'. Check the instance name and service status."
}

Write-Host ""
Write-Host "Native VECTOR / VECTOR_SEARCH requires SQL Server 2025 Preview or Azure SQL with vector support."
Write-Host "Your local SQL Server 2022 Express instances can connect, but they will not run the vector scripts."
