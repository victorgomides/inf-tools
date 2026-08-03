<#
.SYNOPSIS
    Diagnostica, instala e atualiza os principais softwares da Infinity.
.DESCRIPTION
    Ponto de entrada independente para o Infinity Hub. Baixa temporariamente
    o gerenciador vigente do mesmo repositorio, valida o PowerShell recebido,
    executa o fluxo interativo e remove a copia temporaria ao finalizar.

    Nao instala nem mantem este script na maquina.
.NOTES
    Versao: 1.0.0
    Compatibilidade: Windows PowerShell 5.1 e PowerShell 7+
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:ExitCode = 0
$repository = 'victorgomides/inf-tools'
$branch = 'main'
$engineName = 'atualiza_softwares.ps1'
$engineUri = "https://raw.githubusercontent.com/$repository/$branch/$engineName"
$runtimeRoot = Join-Path $env:TEMP 'InfinityHubScripts'
$enginePath = Join-Path $runtimeRoot ("software-manager-{0}.ps1" -f $PID)

function Write-EntryStatus {
    param([string]$Text, [ValidateSet('Info','Ok','Error')][string]$Type = 'Info')
    $color = switch ($Type) { 'Ok' {'Green'}; 'Error' {'Red'}; default {'Cyan'} }
    $prefix = switch ($Type) { 'Ok' {'[OK]'}; 'Error' {'[X]'}; default {'[>]'} }
    Write-Host ("  {0} {1}" -f $prefix,$Text) -ForegroundColor $color
}

function Test-DownloadedEngine {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt 10000) { return $false }
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count) { return $false }
    $required = @('Invoke-SoftwareManager','Get-SoftwareCatalog','Infinity - Gerenciador de Softwares')
    $content = Get-Content -LiteralPath $Path -Raw
    foreach ($marker in $required) { if ($content -notmatch [regex]::Escape($marker)) { return $false } }
    return $true
}

try {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    if (-not (Test-Path -LiteralPath $runtimeRoot)) {
        New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
    }

    Write-Host ''
    Write-Host '  I N F I N I T Y   S O F T W A R E S' -ForegroundColor White
    Write-Host '  Instalacao, atualizacao e diagnostico' -ForegroundColor DarkCyan
    Write-Host ''
    Write-EntryStatus 'Obtendo o gerenciador atualizado do repositorio...'

    Invoke-WebRequest -Uri $engineUri -OutFile $enginePath -UseBasicParsing -TimeoutSec 60
    if (-not (Test-DownloadedEngine -Path $enginePath)) {
        throw 'O gerenciador baixado nao passou na validacao de integridade e sintaxe.'
    }
    Write-EntryStatus 'Gerenciador validado.' Ok

    $shell = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $shell) { $shell = Get-Command powershell.exe -ErrorAction Stop | Select-Object -First 1 }
    & $shell.Source -NoLogo -NoProfile -File $enginePath
    $script:ExitCode = $LASTEXITCODE
    if ($script:ExitCode -ne 0) { throw "O gerenciador encerrou com codigo $script:ExitCode." }
}
catch {
    Write-EntryStatus $_.Exception.Message Error
    $script:ExitCode = 1
}
finally {
    if (Test-Path -LiteralPath $enginePath) {
        Remove-Item -LiteralPath $enginePath -Force -ErrorAction SilentlyContinue
    }
}

exit $script:ExitCode
