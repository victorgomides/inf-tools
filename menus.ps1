<#
.SYNOPSIS
    Menu central para instalar, atualizar e diagnosticar os principais softwares.
.DESCRIPTION
    Usa identificadores estaveis e consulta as fontes no momento da execucao.
    Nao fixa versoes de PowerShell, Chrome, Git, Node.js, VS Code, Visual Studio,
    Power BI ou ferramentas de IA.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu','Instalar','Atualizar','Diagnosticar')]
    [string]$Acao = 'Menu',

    [ValidateSet('PowerShell7','Chrome','Git','NodeJS','VSCode','VisualStudio','PowerBI','Claude','Codex','OpenCode')]
    [string[]]$Pacotes,

    [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSCommandPath
$script:IaScript = Join-Path $script:Root 'ia-install.ps1'
$script:UpdaterScript = Join-Path $script:Root 'atualiza_softwares.ps1'
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Version = '1.0.0'
$script:NonInteractive = $Silent.IsPresent -or [Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or (-not [Environment]::UserInteractive)

$script:Catalog = [ordered]@{
    PowerShell7 = [PSCustomObject]@{ Name='PowerShell 7'; Id='Microsoft.PowerShell'; Source='winget'; Scope='user'; Admin=$false }
    Chrome      = [PSCustomObject]@{ Name='Google Chrome'; Id='Google.Chrome'; Source='winget'; Scope='user'; Admin=$false }
    Git         = [PSCustomObject]@{ Name='Git for Windows'; Id='Git.Git'; Source='winget'; Scope='user'; Admin=$false }
    NodeJS      = [PSCustomObject]@{ Name='Node.js LTS'; Id='OpenJS.NodeJS.LTS'; Source='winget'; Scope='user'; Admin=$false }
    VSCode      = [PSCustomObject]@{ Name='Visual Studio Code'; Id='Microsoft.VisualStudioCode'; Source='winget'; Scope='user'; Admin=$false }
    VisualStudio= [PSCustomObject]@{ Name='Visual Studio Community'; Id='Microsoft.VisualStudio.2022.Community'; Source='winget'; Scope=''; Admin=$true }
    PowerBI     = [PSCustomObject]@{ Name='Power BI Desktop'; Id='Microsoft.PowerBI'; Source='winget'; Scope=''; Admin=$true }
    Claude      = [PSCustomObject]@{ Name='Claude (CLI + Desktop)'; Id=''; Source='ia'; Scope='user'; Admin=$false }
    Codex       = [PSCustomObject]@{ Name='Codex (CLI + Desktop)'; Id=''; Source='ia'; Scope='user'; Admin=$false }
    OpenCode    = [PSCustomObject]@{ Name='OpenCode (CLI + Desktop)'; Id=''; Source='ia'; Scope='user'; Admin=$false }
}

function Write-Title {
    param([string]$Text)
    if (-not $script:NonInteractive) {
        try { Clear-Host } catch { }
    }
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ("  Infinity - Gerenciador de Softwares  v{0}" -f $script:Version) -ForegroundColor White
    Write-Host ("  {0}" -f $Text) -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Write-Ok   { param([string]$Text) Write-Host ("  [OK] {0}" -f $Text) -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host ("  [!]  {0}" -f $Text) -ForegroundColor Yellow }
function Write-Fail { param([string]$Text) Write-Host ("  [X]  {0}" -f $Text) -ForegroundColor Red; [void]$script:Failures.Add($Text) }
function Write-Step { param([string]$Text) Write-Host ("  [>]  {0}" -f $Text) -ForegroundColor Cyan }

function Test-WingetAvailable {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    try {
        $null = & $cmd.Source --version 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory=$true)][string]$Id, [string]$Source='winget')
    if (-not (Test-WingetAvailable)) { return $false }
    try {
        $args = @('list','--id',$Id,'--exact','--accept-source-agreements','--disable-interactivity')
        $output = & winget @args 2>&1 | Out-String
        $exactExitCode = $LASTEXITCODE
        if ($exactExitCode -eq 0 -and $output -match [regex]::Escape($Id) -and $output -notmatch '(?i)(Nenhum pacote|No installed package|No package found)') {
            return $true
        }

        # Alguns pacotes MSIX/EXE sao correlacionados pelo WinGet somente por nome
        # (por exemplo PowerShell MSIX e canais Beta do Chrome).
        $lookupName = switch -Regex ($Id) {
            '^Microsoft\.PowerShell$' { 'PowerShell'; break }
            '^Google\.Chrome' { 'Chrome'; break }
            '^Microsoft\.VisualStudioCode$' { 'Visual Studio Code'; break }
            '^Microsoft\.VisualStudio\.2022\.Community$' { 'Visual Studio Community'; break }
            '^Microsoft\.PowerBI$' { 'Power BI'; break }
            default { '' }
        }
        if ($lookupName) {
            $byName = & winget list --name $lookupName --accept-source-agreements --disable-interactivity 2>&1 | Out-String
            $nameExitCode = $LASTEXITCODE
            if ($nameExitCode -eq 0 -and $byName -match [regex]::Escape(($Id -replace '\.EXE$','')) -and
                $byName -notmatch '(?i)(Nenhum pacote|No installed package|No package found)') {
                return $true
            }
        }
        return $false
    } catch { return $false }
}

function Resolve-WingetUpgradePackage {
    param([Parameter(Mandatory=$true)]$Package)
    if ($Package.Id -ne 'Google.Chrome') { return $Package }

    # Mantem o canal que ja esta instalado, sem trocar Beta/Dev por Stable.
    foreach ($id in @('Google.Chrome','Google.Chrome.Beta.EXE','Google.Chrome.Beta','Google.Chrome.Dev.EXE','Google.Chrome.Dev','Google.Chrome.Canary','Google.Chrome.EXE')) {
        try {
            $out = & winget list --id $id --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-String
            $listExitCode = $LASTEXITCODE
            if ($listExitCode -eq 0 -and $out -match [regex]::Escape($id) -and $out -notmatch '(?i)(Nenhum pacote|No installed package|No package found)') {
                return [PSCustomObject]@{ Name=$Package.Name; Id=$id; Source=$Package.Source; Scope=$Package.Scope; Admin=$Package.Admin }
            }
        } catch { }
    }
    return $Package
}

function Invoke-WingetAction {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('install','upgrade')][string]$Mode,
        [Parameter(Mandatory=$true)]$Package
    )

    if (-not (Test-WingetAvailable)) {
        Write-Fail "WinGet indisponivel; nao foi possivel processar $($Package.Name)."
        return $false
    }

    $args = @($Mode,'--id',$Package.Id,'--exact','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity')
    if ($Package.Source) { $args += @('--source',$Package.Source) }
    if ($Package.Scope) { $args += @('--scope',$Package.Scope) }
    if ($Mode -eq 'upgrade') { $args += '--include-unknown' }

    $verb = if ($Mode -eq 'install') { 'Instalando' } else { 'Atualizando' }
    Write-Step "$verb $($Package.Name) pela fonte atual..."
    & winget @args 2>&1 | Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } | ForEach-Object { if ($_){ Write-Host "       $_" } }
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "$($Package.Name): WinGet encerrou com codigo $LASTEXITCODE."
        return $false
    }
    Write-Ok "$($Package.Name) processado com sucesso."
    return $true
}

function Get-IaInstallPackages {
    param([string[]]$Names, [switch]$OnlyInstalled)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($name in $Names) {
        $defs = switch ($name) {
            'Claude' {
                @([PSCustomObject]@{Ia='ClaudeCLI'; Cmd='claude'; DesktopId=''}, [PSCustomObject]@{Ia='ClaudeDesk'; Cmd=''; DesktopId='Anthropic.Claude'})
            }
            'Codex' {
                @([PSCustomObject]@{Ia='CodexCLI'; Cmd='codex'; DesktopId=''}, [PSCustomObject]@{Ia='CodexDesk'; Cmd=''; DesktopId='9PLM9XGG6VKS'})
            }
            'OpenCode' {
                @([PSCustomObject]@{Ia='OpenCode'; Cmd='opencode'; DesktopId=''}, [PSCustomObject]@{Ia='OpenDesk'; Cmd=''; DesktopId='SST.OpenCodeDesktop'})
            }
            default { @() }
        }
        foreach ($def in $defs) {
            $installed = $true
            if ($OnlyInstalled) {
                if ($def.Cmd) { $installed = [bool](Get-Command $def.Cmd -ErrorAction SilentlyContinue) }
                elseif ($def.DesktopId -eq '9PLM9XGG6VKS') { $installed = Test-WingetPackageInstalled -Id $def.DesktopId -Source 'msstore' }
                else { $installed = Test-WingetPackageInstalled -Id $def.DesktopId }
            }
            if ($installed) { [void]$result.Add($def.Ia) }
        }
    }
    return @($result | Select-Object -Unique)
}

function Invoke-IaManager {
    param([string[]]$Names, [switch]$OnlyInstalled)
    if (-not (Test-Path -LiteralPath $script:IaScript -PathType Leaf)) {
        Write-Fail "Motor de IA ausente: $script:IaScript"
        return
    }
    $iaPackages = @(Get-IaInstallPackages -Names $Names -OnlyInstalled:$OnlyInstalled)
    if ($iaPackages.Count -eq 0) {
        Write-Warn 'Nenhuma ferramenta de IA selecionada esta instalada; nada para atualizar.'
        return
    }
    Write-Step ("Executando motor de IA para: {0}" -f ($iaPackages -join ', '))
    $shell = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { (Get-Command pwsh.exe).Source } else { (Get-Command powershell.exe).Source }
    $args = @('-NoLogo','-NoProfile','-File',$script:IaScript,'-Pacotes',($iaPackages -join ','),'-Silent')
    & $shell @args
    $iaExitCode = $LASTEXITCODE
    if ($iaExitCode -ne 0) { Write-Fail "Motor de IA encerrou com codigo $iaExitCode." }
    else { Write-Ok 'Ferramentas de IA processadas.' }
}

function Resolve-Names {
    param([string[]]$Requested)
    if ($Requested -and $Requested.Count -gt 0) { return @($Requested | Select-Object -Unique) }
    return @($script:Catalog.Keys)
}

function Invoke-InstallSelected {
    param([string[]]$Names)
    Write-Title 'Instalacao'
    $iaNames = @($Names | Where-Object { $_ -in @('Claude','Codex','OpenCode') })
    foreach ($name in $Names | Where-Object { $_ -notin @('Claude','Codex','OpenCode') }) {
        $package = $script:Catalog[$name]
        if (Test-WingetPackageInstalled -Id $package.Id -Source $package.Source) {
            Write-Ok "$($package.Name) ja esta instalado."
        } else {
            if ($package.Admin) { Write-Warn "$($package.Name) pode solicitar UAC por ser instalado no computador." }
            $null = Invoke-WingetAction -Mode install -Package $package
        }
    }
    if ($iaNames.Count -gt 0) { Invoke-IaManager -Names $iaNames }
}

function Test-UnifiedUpdaterRelevant {
    if (-not (Test-Path -LiteralPath $script:UpdaterScript -PathType Leaf)) { return $false }
    foreach ($id in @('Microsoft.VisualStudioCode','Microsoft.VisualStudio.2022.Community','Microsoft.PowerBI')) {
        if (Test-WingetPackageInstalled -Id $id) { return $true }
    }
    # O atualizador possui deteccao adicional para instalacoes fora do WinGet.
    return $true
}

function Invoke-UpdateInstalled {
    param([string[]]$Names)
    Write-Title 'Atualizacao dos softwares instalados'
    $unifiedNames = @($Names | Where-Object { $_ -in @('VSCode','VisualStudio','PowerBI') })
    foreach ($name in $Names | Where-Object { $_ -notin @('VSCode','VisualStudio','PowerBI','Claude','Codex','OpenCode') }) {
        $package = $script:Catalog[$name]
        if (Test-WingetPackageInstalled -Id $package.Id -Source $package.Source) {
            $upgradePackage = Resolve-WingetUpgradePackage -Package $package
            $null = Invoke-WingetAction -Mode upgrade -Package $upgradePackage
        } else { Write-Warn "$($package.Name) nao esta instalado; ignorado." }
    }

    if ($unifiedNames.Count -gt 0 -and (Test-UnifiedUpdaterRelevant)) {
        Write-Step 'Executando o atualizador unificado de VS Code, Visual Studio e Power BI...'
        $shell = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { (Get-Command pwsh.exe).Source } else { (Get-Command powershell.exe).Source }
        & $shell -NoLogo -NoProfile -File $script:UpdaterScript
        $updaterExitCode = $LASTEXITCODE
        if ($updaterExitCode -ne 0) { Write-Fail "Atualizador unificado encerrou com codigo $updaterExitCode." }
        else { Write-Ok 'Atualizador unificado concluido.' }
    }

    $iaNames = @($Names | Where-Object { $_ -in @('Claude','Codex','OpenCode') })
    if ($iaNames.Count -gt 0) { Invoke-IaManager -Names $iaNames -OnlyInstalled }
}

function Invoke-Diagnostic {
    param([string[]]$Names)
    Write-Title 'Diagnostico'
    Write-Host ("  Usuario       : {0}\{1}" -f $env:USERDOMAIN,$env:USERNAME)
    Write-Host ("  PowerShell    : {0} ({1})" -f $PSVersionTable.PSVersion,$PSVersionTable.PSEdition)
    Write-Host ("  WinGet        : {0}" -f $(if(Test-WingetAvailable){'Disponivel'}else{'Indisponivel'}))
    Write-Host ("  PATH usuario  : {0} caracteres" -f ([string][Environment]::GetEnvironmentVariable('Path','User')).Length)
    Write-Host ''
    foreach ($name in $Names) {
        if ($name -in @('Claude','Codex','OpenCode')) { continue }
        $p = $script:Catalog[$name]
        $state = if(Test-WingetPackageInstalled -Id $p.Id -Source $p.Source){'Instalado'}else{'Nao detectado'}
        Write-Host ("  {0,-28} {1}" -f $p.Name,$state) -ForegroundColor $(if($state -eq 'Instalado'){'Green'}else{'DarkGray'})
    }
    foreach ($cmd in @('claude','codex','opencode')) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $version = try { (& $found.Source --version 2>$null | Select-Object -First 1) } catch { 'falha ao iniciar' }
            Write-Host ("  {0,-28} {1}" -f $cmd,$version) -ForegroundColor Green
        } else { Write-Host ("  {0,-28} Nao detectado" -f $cmd) -ForegroundColor DarkGray }
    }
    Write-Host ''
    if ($script:Failures.Count -eq 0) { Write-Ok 'Diagnostico concluido.' }
}

function Read-PackageSelection {
    Write-Title 'Selecionar softwares'
    $keys = @($script:Catalog.Keys)
    for ($i=0; $i -lt $keys.Count; $i++) {
        $p=$script:Catalog[$keys[$i]]
        $tag=if($p.Admin){'UAC'}else{'usuario'}
        Write-Host ("  [{0,2}] {1,-30} ({2})" -f ($i+1),$p.Name,$tag)
    }
    Write-Host '  [ A] Todos'
    Write-Host '  [ 0] Voltar'
    Write-Host ''
    $raw=Read-Host '  Informe numeros separados por virgula'
    if ($raw -match '^(?i)a$') { return $keys }
    if ($raw -eq '0') { return @() }
    $selected=New-Object System.Collections.Generic.List[string]
    foreach($part in $raw -split '[,; ]+') {
        $n=0
        if([int]::TryParse($part,[ref]$n) -and $n -ge 1 -and $n -le $keys.Count){ [void]$selected.Add($keys[$n-1]) }
    }
    return @($selected | Select-Object -Unique)
}

function Invoke-MainMenu {
    while($true) {
        Write-Title 'Menu principal'
        Write-Host '  [1] Instalar todos os softwares principais' -ForegroundColor Yellow
        Write-Host '  [2] Escolher softwares para instalar'
        Write-Host '  [3] Atualizar somente os softwares instalados' -ForegroundColor Green
        Write-Host '  [4] Diagnosticar instalacoes e comandos'
        Write-Host '  [5] Abrir o gerenciador detalhado das IAs'
        Write-Host '  [0] Sair'
        Write-Host ''
        $choice=Read-Host '  Opcao'
        switch($choice) {
            '1' { Invoke-InstallSelected -Names @($script:Catalog.Keys) }
            '2' { $names=Read-PackageSelection; if($names.Count){Invoke-InstallSelected -Names $names} }
            '3' { Invoke-UpdateInstalled -Names @($script:Catalog.Keys) }
            '4' { Invoke-Diagnostic -Names @($script:Catalog.Keys) }
            '5' {
                if(Test-Path -LiteralPath $script:IaScript){ & $script:IaScript }
                else { Write-Fail "Arquivo ausente: $script:IaScript" }
            }
            '0' { return }
            default { Write-Warn 'Opcao invalida.' }
        }
        if($choice -in @('1','2','3','4','5')) { Write-Host ''; $null=Read-Host '  Pressione ENTER para voltar' }
    }
}

$selectedNames = Resolve-Names -Requested $Pacotes
switch($Acao) {
    'Instalar'    { Invoke-InstallSelected -Names $selectedNames }
    'Atualizar'   { Invoke-UpdateInstalled -Names $selectedNames }
    'Diagnosticar'{ Invoke-Diagnostic -Names $selectedNames }
    default {
        if($Silent){ throw 'Use -Acao Instalar, Atualizar ou Diagnosticar com -Silent.' }
        Invoke-MainMenu
    }
}

if($script:Failures.Count -gt 0){ exit 1 }
exit 0
