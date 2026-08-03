
param(
    [string]$WorkDir = "C:\ProgramData\InfinityUpdater",
    [ValidateSet("2022", "2026", "All")]
    [string]$Year    = "All",
    [ValidateSet("Community", "Professional", "Enterprise", "BuildTools")]
    [string]$Edition = "Community",
    [switch]$Force,
    [switch]$SkipVSCode,
    [switch]$SkipVisualStudio,
    [switch]$DetectOnly,
    [switch]$InternalEngine,
    [switch]$UnifiedController
)

$ErrorActionPreference = "Stop"
$SCRIPT_VERSION       = '3.1.3'
$script:ExitCode       = 0
$script:NonInteractive = $false
$script:ThisScriptPath = $PSCommandPath
if (-not $script:ThisScriptPath) { $script:ThisScriptPath = $MyInvocation.MyCommand.Path }
$EmbeddedPowerBIGzipBase64 = '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'

try {
    $script:NonInteractive = [Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or (-not [Environment]::UserInteractive)
}
catch {
    $script:NonInteractive = $false
}

$script:SymOk     = 'OK'
$script:SymFail   = 'X'
$script:SymWarn   = '!'
$script:SymStep   = '>'
$script:SymInfo   = 'i'
function Test-IsElevated {
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-IsAdminUser {
    try {
        $groups = & whoami.exe /groups /fo csv /nh 2>$null
        return ($groups -match 'S-1-5-32-544')
    }
    catch {
        return $false
    }
}

function Quote-Argument {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Join-ArgumentList {
    param([string[]]$Arguments)
    return ($Arguments | ForEach-Object {
        if ($_ -match '\s|"' ) { Quote-Argument $_ } else { $_ }
    }) -join ' '
}

function Initialize-ConsoleUi {
    param(
        [string]$Title = 'atualiza_visualstudio',
        [int]$Width = 140,
        [int]$Height = 42
    )

    if ($script:NonInteractive) { return }

    try {
        $raw = $Host.UI.RawUI
        $raw.WindowTitle = $Title
        $raw.BackgroundColor = 'Black'
        $raw.ForegroundColor = 'White'
        [Console]::BackgroundColor = 'Black'
        [Console]::ForegroundColor = 'White'

        $buffer = $raw.BufferSize
        if ($buffer.Width -lt $Width) { $buffer.Width = $Width }
        if ($buffer.Height -lt 3000) { $buffer.Height = 3000 }
        $raw.BufferSize = $buffer

        $max = $raw.MaxWindowSize
        $targetWidth = [Math]::Min($Width, $max.Width)
        $targetHeight = [Math]::Min($Height, $max.Height)
        $window = $raw.WindowSize
        if ($window.Width -lt $targetWidth) { $window.Width = $targetWidth }
        if ($window.Height -lt $targetHeight) { $window.Height = $targetHeight }
        $raw.WindowSize = $window
        Clear-Host
    } catch { }
}

function Request-Elevation {
    if ($script:NonInteractive) {
        throw 'Sessao nao interativa sem elevacao. No Agendador de Tarefas, habilite "Executar com privilegios mais altos".'
    }

    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.PSCommandPath }
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
    if (-not $scriptPath) { throw 'Nao foi possivel localizar o caminho do script para elevar.' }

    $argList = @(
        '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $scriptPath,
        '-WorkDir', $WorkDir,
        '-Year', $Year,
        '-Edition', $Edition
    )
    if ($Force) { $argList += '-Force' }
    if ($SkipVSCode) { $argList += '-SkipVSCode' }
    if ($SkipVisualStudio) { $argList += '-SkipVisualStudio' }
    if ($DetectOnly) { $argList += '-DetectOnly' }
    if ($InternalEngine) { $argList += '-InternalEngine' }
    if ($UnifiedController) { $argList += '-UnifiedController' }

    $shellPath = Get-PreferredPowerShellPath
    $argumentString = Join-ArgumentList -Arguments $argList
    $terminalPath = $null
    try { $terminalPath = (Get-Command wt.exe -ErrorAction Stop).Source } catch { }
    if (-not $terminalPath -and $env:LOCALAPPDATA) {
        $terminalCandidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
        if (Test-Path -LiteralPath $terminalCandidate) { $terminalPath = $terminalCandidate }
    }

    Initialize-ConsoleUi -Title 'atualiza_visualstudio'
    Write-Host ''
    if (Test-IsAdminUser) {
        Write-Host ("  {0} Sua conta e administradora, mas esta sessao nao esta elevada." -f $script:SymWarn) -ForegroundColor Yellow
    }
    else {
        Write-Host ("  {0} Este script requer uma sessao elevada." -f $script:SymWarn) -ForegroundColor Yellow
    }
    Write-Host ("  {0} Solicitando elevacao via UAC..." -f $script:SymStep) -ForegroundColor Cyan

    if ($terminalPath) {
        $terminalArgs = @(
            '-w', '-1', '--size', '140,42',
            'new-tab', '--title', 'Infinity - Softwares', '--suppressApplicationTitle',
            '--', $shellPath
        ) + $argList
        Start-Process -FilePath $terminalPath -Verb RunAs -ArgumentList (Join-ArgumentList -Arguments $terminalArgs) -ErrorAction Stop | Out-Null
    }
    else {
        Start-Process -FilePath $shellPath -Verb RunAs -ArgumentList $argumentString -ErrorAction Stop | Out-Null
    }
    exit 0
}

function Get-UnifiedInstalledEditions {
    $map = [ordered]@{
        Community    = 'Microsoft.VisualStudio.Product.Community'
        Professional = 'Microsoft.VisualStudio.Product.Professional'
        Enterprise   = 'Microsoft.VisualStudio.Product.Enterprise'
        BuildTools   = 'Microsoft.VisualStudio.Product.BuildTools'
    }
    $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
    $found = @()
    if (-not (Test-Path -LiteralPath $vswhere)) { return $found }
    foreach ($entry in $map.GetEnumerator()) {
        try {
            $json = & $vswhere -products $entry.Value -all -format json 2>$null
            if (-not $json) { continue }
            $items = @(($json | ConvertFrom-Json) | Where-Object { $_ -and $_.installationPath })
            if ($items.Count -gt 0) {
                $found += [pscustomobject]@{ Edition = [string]$entry.Key; Instances = $items.Count }
            }
        } catch { }
    }
    return $found
}

function Get-PreferredPowerShellPath {
    $pwsh = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pwsh -and $pwsh.Source) { return $pwsh.Source }
    return (Get-Command powershell.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
}

function Test-UnifiedVSCodeInstalled {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $app = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '^Microsoft Visual Studio Code' -and $_.DisplayName -notmatch 'Insiders' } |
        Select-Object -First 1
    return $null -ne $app
}

function Test-UnifiedPowerBIInstalled {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $app = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Power BI Desktop' -and $_.DisplayName -notmatch 'Report Server' } |
        Select-Object -First 1
    return $null -ne $app
}

function Write-UnifiedStatus {
    param([string]$Label, [string]$Message, [ValidateSet('Info','Ok','Warn','Error')][string]$Level = 'Info')
    $color = switch ($Level) { 'Ok'{'Green'} 'Warn'{'Yellow'} 'Error'{'Red'} default{'Cyan'} }
    $prefix = switch ($Level) { 'Ok'{'OK'} 'Warn'{'AVISO'} 'Error'{'ERRO'} default{'>'} }
    Write-Host ('  {0,-7} {1,-18} {2}' -f $prefix, $Label, $Message) -ForegroundColor $color
}

function Write-UnifiedSection {
    param([string]$Title)
    Write-Host ''
    Write-Host ('  {0}' -f $Title.ToUpperInvariant()) -ForegroundColor DarkCyan
    Write-Host ('  {0}' -f ('-' * [Math]::Min(42, [Math]::Max(18, $Title.Length + 4)))) -ForegroundColor DarkGray
}

function Write-UnifiedSoftwareResult {
    param(
        [string]$Status,
        [string]$InstalledVersion,
        [string]$LatestVersion
    )
    Write-UnifiedStatus 'Status' $Status Ok
    if ($InstalledVersion) {
        Write-Host ('  {0,-7} {1,-18} {2}' -f '', 'Versao instalada', $InstalledVersion) -ForegroundColor Gray
    }
    if ($LatestVersion) {
        Write-Host ('  {0,-7} {1,-18} {2}' -f '', 'Mais recente', $LatestVersion) -ForegroundColor Gray
    }
}

function Clear-UnifiedTempDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    $rootFull = [IO.Path]::GetFullPath($WorkDir).TrimEnd('\')
    $targetFull = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $targetFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Limpeza recusada para ${Label}: o caminho '$targetFull' esta fora de '$rootFull'."
    }

    [void](New-Item -ItemType Directory -Path $targetFull -Force)
    $items = @(Get-ChildItem -LiteralPath $targetFull -Force -ErrorAction Stop)
    foreach ($item in $items) {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
    }

    $remaining = @(Get-ChildItem -LiteralPath $targetFull -Force -ErrorAction Stop)
    if ($remaining.Count -gt 0) {
        $names = ($remaining | Select-Object -ExpandProperty Name) -join ', '
        throw "A pasta temporaria de $Label nao ficou vazia. Itens restantes: $names"
    }
}

function Convert-UnifiedActivityLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    $text = $Line -replace '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\]\s*', ''
    $text = $text -replace '^\[(?:VS [0-9]{4} [^\]]+|VS Code)\]\s*', ''

    switch -Regex ($text) {
        '^Consultando catalogo oficial'                  { return 'Consultando versao mais recente' }
        '^Consultando versao disponivel'                 { return 'Consultando versao mais recente' }
        '^Verificando atualizacao via winget'            { return 'Consultando VS Code no winget' }
        '^Consultando servico oficial do VS Code'        { return 'Consultando servico oficial do VS Code' }
        '^Versao disponivel(?: no canal)?'               { return 'Comparando versoes' }
        '^Download:\s*'                                  { return $text }
        '^Power BI: [0-9.]+%'                             { return ($text -replace '^Power BI:\s*', 'Baixando - ') }
        '^Power BI: iniciando download'                  { return 'Iniciando download' }
        '^Power BI: tamanho aproximado'                  { return $text }
        '^Baixando (?:componentes de )?atualizacao'      { return 'Baixando atualizacao' }
        '^Assinatura digital'                            { return 'Validando assinatura digital' }
        '^Preparando instalador'                         { return 'Preparando instalador' }
        '^Aplicando atualizacao'                         { return 'Aplicando atualizacao' }
        '^Aguardando (?:o registro|confirmacao)'         { return 'Validando versao instalada' }
        '^Versao (?:apos atualizacao|instalada apos)'    { return 'Confirmando resultado' }
        '^Atualizacao confirmada'                        { return 'Atualizacao confirmada' }
        '^Instalador finalizado'                         { return 'Finalizando instalacao' }
        '^(?:Sem atualizacao disponivel|Nenhuma atualizacao disponivel|Power BI Desktop ja esta atualizado)' { return 'Confirmando versao instalada' }
    }
    return $null
}

function Expand-UnifiedPowerBIEngine {
    param([string]$RootDir)
    $compressed = [Convert]::FromBase64String($EmbeddedPowerBIGzipBase64)
    $input = New-Object IO.MemoryStream(, $compressed)
    $gzip = New-Object IO.Compression.GZipStream($input, [IO.Compression.CompressionMode]::Decompress)
    $output = New-Object IO.MemoryStream
    try { $gzip.CopyTo($output); $bytes = $output.ToArray() }
    finally { $gzip.Dispose(); $input.Dispose(); $output.Dispose() }
    $runtimeDir = Join-Path $RootDir 'Runtime'
    [void](New-Item -ItemType Directory -Path $runtimeDir -Force)
    $path = Join-Path $runtimeDir ('Infinity-PowerBI-{0}-{1}.ps1' -f $PID, ([guid]::NewGuid().ToString('N').Substring(0,8)))
    [IO.File]::WriteAllBytes($path, $bytes)
    return $path
}

function Invoke-UnifiedHiddenEngine {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments,
        [string]$Label,
        [string]$LogRoot,
        [int[]]$SuccessExitCodes = @(0)
    )
    $logDir = Join-Path $LogRoot 'Logs'
    [void](New-Item -ItemType Directory -Path $logDir -Force)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeLabel = $Label -replace '[^a-zA-Z0-9_-]', '-'
    $stdout = Join-Path $logDir "Engine-$safeLabel-$stamp.stdout.log"
    $stderr = Join-Path $logDir "Engine-$safeLabel-$stamp.stderr.log"
    $shell = Get-PreferredPowerShellPath
    $processArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$ScriptPath) + $Arguments
    Write-Host ''
    Write-Host ('  {0}' -f $Label.ToUpperInvariant()) -ForegroundColor White
    Write-UnifiedStatus 'Status' 'Verificando atualizacoes...'
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $shell
        $psi.Arguments = Join-ArgumentList $processArgs
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()
        $stdoutLines = New-Object 'System.Collections.Generic.List[string]'
        $stderrLines = New-Object 'System.Collections.Generic.List[string]'
        $stdoutTask = $proc.StandardOutput.ReadLineAsync()
        $stderrTask = $proc.StandardError.ReadLineAsync()
        $stdoutClosed = $false
        $stderrClosed = $false
        $utf8NoBom = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($stdout, '', $utf8NoBom)
        [IO.File]::WriteAllText($stderr, '', $utf8NoBom)
        $started = Get-Date
        $inlineWidth = 120
        $spinnerFrames = @(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F)
        $spinnerIndex = 0
        $activityDetail = 'Inicializando mecanismo'
        if (-not $script:NonInteractive) {
            try { $inlineWidth = [Math]::Max(1, $Host.UI.RawUI.WindowSize.Width - 1) } catch { }
        }
        while (-not $proc.HasExited -or -not $stdoutClosed -or -not $stderrClosed) {
            while (-not $stdoutClosed -and $stdoutTask.IsCompleted) {
                $line = $stdoutTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $stdoutClosed = $true
                }
                else {
                    [void]$stdoutLines.Add($line)
                    [IO.File]::AppendAllText($stdout, $line + [Environment]::NewLine, $utf8NoBom)
                    $newDetail = Convert-UnifiedActivityLine $line
                    if ($newDetail) { $activityDetail = $newDetail }
                    $stdoutTask = $proc.StandardOutput.ReadLineAsync()
                }
            }
            while (-not $stderrClosed -and $stderrTask.IsCompleted) {
                $line = $stderrTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $stderrClosed = $true
                }
                else {
                    [void]$stderrLines.Add($line)
                    [IO.File]::AppendAllText($stderr, $line + [Environment]::NewLine, $utf8NoBom)
                    $stderrTask = $proc.StandardError.ReadLineAsync()
                }
            }
            if (-not $script:NonInteractive) {
                $elapsed = (Get-Date) - $started
                $spinner = [char]$spinnerFrames[$spinnerIndex % $spinnerFrames.Count]
                $spinnerIndex++
                $inlineStatus = ('    {0} {1} | {2:hh\:mm\:ss}' -f $spinner, $activityDetail, $elapsed)
                if ($inlineStatus.Length -gt $inlineWidth) {
                    $inlineStatus = $inlineStatus.Substring(0, $inlineWidth)
                }
                Write-Host ("`r" + $inlineStatus.PadRight($inlineWidth)) -NoNewline -ForegroundColor Yellow
            }
            Start-Sleep -Milliseconds 150
            $proc.Refresh()
        }
        $proc.WaitForExit()
        $stdoutText = $stdoutLines -join [Environment]::NewLine
        $stderrText = $stderrLines -join [Environment]::NewLine
        $exitCode = [int]$proc.ExitCode
        if (-not $script:NonInteractive) {
            Write-Host ("`r" + (' ' * $inlineWidth) + "`r") -NoNewline
        }
        if ($SuccessExitCodes -notcontains $exitCode) {
            Write-UnifiedStatus 'Status' ("Falha na atualizacao (ExitCode {0})." -f $exitCode) Error
            Write-Host ('  {0,-7} {1,-18} {2}' -f '', 'Log tecnico', $stdout) -ForegroundColor DarkGray
            return $false
        }
        if ((Test-Path $stderr) -and (Get-Item $stderr).Length -eq 0) {
            Remove-Item $stderr -Force -ErrorAction SilentlyContinue
        }
        $alreadyCurrent = $stdoutText -match '(?im)(sem atualizacao disponivel|nenhuma atualizacao disponivel|ja esta atualizado)'
        $installedVersion = $null
        $latestVersion = $null

        if ($stdoutText -match '(?im)Versao instalada apos execucao:\s*([0-9]+(?:\.[0-9]+)+)') {
            $installedVersion = $Matches[1]
        }
        elseif ($stdoutText -match '(?im)Versao apos atualizacao:\s*([0-9]+(?:\.[0-9]+)+)') {
            $installedVersion = $Matches[1]
        }
        elseif ($stdoutText -match '(?im)Atualizacao confirmada:\s*[0-9]+(?:\.[0-9]+)+\s*->\s*([0-9]+(?:\.[0-9]+)+)') {
            $installedVersion = $Matches[1]
        }
        elseif ($stdoutText -match '(?im)(?:Sem atualizacao disponivel|ja esta atualizado)\.[^\r\n]*Instalado:\s*([0-9]+(?:\.[0-9]+)+)') {
            $installedVersion = $Matches[1]
        }
        elseif ($stdoutText -match '(?im)\[VS Code\]\s*Instalado:\s*([0-9]+(?:\.[0-9]+)+)') {
            $installedVersion = $Matches[1]
        }

        if ($stdoutText -match '(?im)Versao disponivel no canal:\s*([0-9]+(?:\.[0-9]+)+)') {
            $latestVersion = $Matches[1]
        }
        elseif ($stdoutText -match '(?im)Versao disponivel:\s*([0-9]+(?:\.[0-9]+)+)') {
            $latestVersion = $Matches[1]
        }
        elseif ($stdoutText -match '(?im)ja esta atualizado\.[^\r\n]*(?:Disponivel|Instalador):\s*([0-9]+(?:\.[0-9]+)+)') {
            $latestVersion = $Matches[1]
        }
        elseif ($alreadyCurrent -and $installedVersion) {
            $latestVersion = $installedVersion
        }

        if ($alreadyCurrent) {
            Write-UnifiedSoftwareResult -Status 'Ja estava atualizado.' -InstalledVersion $installedVersion -LatestVersion $latestVersion
        }
        else {
            Write-UnifiedSoftwareResult -Status 'Atualizacao concluida.' -InstalledVersion $installedVersion -LatestVersion $latestVersion
        }
        return $true
    } catch {
        Write-UnifiedStatus $Label $_.Exception.Message Error
        return $false
    }
}

function Invoke-UnifiedController {
    Initialize-ConsoleUi -Title 'Infinity - Atualizacao de softwares'
    Write-Host ''
    Write-Host '  I N F I N I T Y   U P D A T E' -ForegroundColor White
    Write-Host ("  Deteccao automatica | v{0}" -f $SCRIPT_VERSION) -ForegroundColor DarkCyan
    Write-Host ''
    $editions = @(Get-UnifiedInstalledEditions)
    $vsCodeInstalled = Test-UnifiedVSCodeInstalled
    $powerBIInstalled = Test-UnifiedPowerBIInstalled
    Write-UnifiedSection 'Softwares detectados'
    if ($editions.Count) {
        foreach ($item in $editions) { Write-UnifiedStatus 'Visual Studio' "$($item.Edition) ($($item.Instances) instancia(s))" Ok }
    } else { Write-UnifiedStatus 'Visual Studio' 'Nao instalado.' }
    if ($vsCodeInstalled) { Write-UnifiedStatus 'VS Code' 'Instalado' Ok } else { Write-UnifiedStatus 'VS Code' 'Nao instalado.' }
    if ($powerBIInstalled) { Write-UnifiedStatus 'Power BI' 'Desktop instalado' Ok } else { Write-UnifiedStatus 'Power BI' 'Nao instalado.' }
    if ($DetectOnly) {
        Write-UnifiedSection 'Resultado'
        Write-UnifiedStatus 'Conclusao' 'Deteccao concluida; nenhuma atualizacao foi executada.' Ok
        return 0
    }
    $mutex = $null
    $acquired = $false
    $cleanupAuthorized = $false
    $powerRuntime = $null
    $visualDir = Join-Path $WorkDir 'Atualizacao\VisualStudio'
    $powerDir = Join-Path $WorkDir 'Atualizacao\PowerBI'
    $visualTempDir = Join-Path $visualDir 'Temp'
    $powerTempDir = Join-Path $powerDir 'Temp'
    $runtimeDir = Join-Path $WorkDir 'Runtime'
    try {
        $created = $false
        $mutex = New-Object Threading.Mutex($false, 'Global\InfinityAtualizarSoftwares', [ref]$created)
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { Write-UnifiedStatus 'Execucao' 'Ja existe outra atualizacao em andamento.' Warn; return 3 }

        $activeUpdaterProcesses = @()
        try {
            $activeUpdaterProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
                $_.ProcessId -ne $PID -and (
                    ($_.Name -in @('setup.exe', 'vs_installer.exe', 'PBIDesktopSetup_x64.exe')) -or
                    ($_.CommandLine -match '(?i)atualiza_softwares\.ps1.+-InternalEngine') -or
                    ($_.CommandLine -match '(?i)Infinity-PowerBI-[^\s]+\.ps1')
                )
            })
        } catch { }
        if ($activeUpdaterProcesses.Count -gt 0) {
            $processNames = ($activeUpdaterProcesses | Select-Object -ExpandProperty Name -Unique) -join ', '
            Write-UnifiedStatus 'Execucao' ("Existe uma atualizacao anterior em andamento ($processNames). Aguarde a conclusao e tente novamente.") Warn
            return 3
        }

        $cleanupAuthorized = $true
        Clear-UnifiedTempDirectory -Path $visualTempDir -Label 'Visual Studio e VS Code'
        Clear-UnifiedTempDirectory -Path $powerTempDir -Label 'Power BI'
        Clear-UnifiedTempDirectory -Path $runtimeDir -Label 'mecanismo temporario'

        Write-UnifiedSection 'Processamento'
        $failed = $false
        foreach ($item in $editions) {
            $args = @('-InternalEngine','-WorkDir',$visualDir,'-Year',$Year,'-Edition',$item.Edition,'-SkipVSCode')
            if ($Force) { $args += '-Force' }
            if (-not (Invoke-UnifiedHiddenEngine $script:ThisScriptPath $args "VS $($item.Edition)" $WorkDir)) { $failed = $true }
        }
        if ($vsCodeInstalled -and -not $SkipVSCode) {
            $args = @('-InternalEngine','-WorkDir',$visualDir,'-Year',$Year,'-Edition','Community','-SkipVisualStudio')
            if ($Force) { $args += '-Force' }
            if (-not (Invoke-UnifiedHiddenEngine $script:ThisScriptPath $args 'VS Code' $WorkDir)) { $failed = $true }
        }
        if ($powerBIInstalled) {
            $powerRuntime = Expand-UnifiedPowerBIEngine $WorkDir
            $args = @('-WorkDir',$powerDir)
            if ($Force) { $args += '-Force' }
            if (-not (Invoke-UnifiedHiddenEngine $powerRuntime $args 'Power BI' $WorkDir -SuccessExitCodes @(0, 2))) { $failed = $true }
        }
        if ($editions.Count -eq 0 -and (-not $vsCodeInstalled -or $SkipVSCode) -and -not $powerBIInstalled) {
            Write-UnifiedSection 'Resultado'
            Write-UnifiedStatus 'Conclusao' 'Nenhum software compativel instalado.' Ok
        } elseif ($failed) {
            Write-UnifiedSection 'Resultado'
            Write-UnifiedStatus 'Conclusao' 'Uma ou mais atualizacoes falharam.' Error
            return 1
        } else {
            Write-UnifiedSection 'Resultado'
            Write-UnifiedStatus 'Conclusao' 'Todos os softwares detectados foram processados.' Ok
        }
        return 0
    } finally {
        $cleanupError = $null
        if ($powerRuntime -and (Test-Path $powerRuntime)) { Remove-Item $powerRuntime -Force -ErrorAction SilentlyContinue }
        if ($cleanupAuthorized) {
            try {
                Clear-UnifiedTempDirectory -Path $visualTempDir -Label 'Visual Studio e VS Code'
                Clear-UnifiedTempDirectory -Path $powerTempDir -Label 'Power BI'
                Clear-UnifiedTempDirectory -Path $runtimeDir -Label 'mecanismo temporario'
            }
            catch { $cleanupError = $_ }
        }
        if ($acquired -and $mutex) { try { $mutex.ReleaseMutex() } catch { } }
        if ($mutex) { try { $mutex.Dispose() } catch { } }
        if ($cleanupError) { throw $cleanupError }
    }
}

function Get-SoftwareCatalog {
    return @(
        [pscustomobject]@{ Key='PowerShell7'; Name='PowerShell 7'; Ids=@('Microsoft.PowerShell','Microsoft.PowerShell.MSIX'); Command='pwsh.exe'; Ia=$null; Scope='user' }
        [pscustomobject]@{ Key='Chrome'; Name='Google Chrome'; Ids=@('Google.Chrome','Google.Chrome.EXE','Google.Chrome.Beta.EXE','Google.Chrome.Beta','Google.Chrome.Dev.EXE'); Command=''; Ia=$null; Scope='user' }
        [pscustomobject]@{ Key='Git'; Name='Git for Windows'; Ids=@('Git.Git'); Command='git.exe'; Ia='Git'; Scope='user' }
        [pscustomobject]@{ Key='NodeJS'; Name='Node.js LTS'; Ids=@('OpenJS.NodeJS.LTS'); Command='node.exe'; Ia=$null; Scope='user' }
        [pscustomobject]@{ Key='VSCode'; Name='Visual Studio Code'; Ids=@('Microsoft.VisualStudioCode'); Command='code.cmd'; Ia=$null; Scope='user' }
        [pscustomobject]@{ Key='VisualStudio'; Name='Visual Studio Community'; Ids=@('Microsoft.VisualStudio.2022.Community'); Command=''; Ia=$null; Scope='' }
        [pscustomobject]@{ Key='PowerBI'; Name='Power BI Desktop'; Ids=@('Microsoft.PowerBI'); Command=''; Ia=$null; Scope='' }
        [pscustomobject]@{ Key='Claude'; Name='Claude'; Ids=@(); Command='claude.cmd'; Ia='ClaudeCLI,ClaudeDesk'; Scope='user' }
        [pscustomobject]@{ Key='Codex'; Name='Codex'; Ids=@(); Command='codex.cmd'; Ia='CodexCLI,CodexDesk'; Scope='user' }
        [pscustomobject]@{ Key='OpenCode'; Name='OpenCode'; Ids=@(); Command='opencode.cmd'; Ia='OpenCode,OpenDesk'; Scope='user' }
    )
}

function Get-InstalledWingetId {
    param([string[]]$Ids)
    if ($script:WingetListText) {
        foreach ($id in $Ids) {
            if ($script:WingetListText -match [regex]::Escape($id)) { return $id }
        }
        return $null
    }
    foreach ($id in $Ids) {
        try {
            $text = & winget.exe list --id $id --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0 -and $text -match [regex]::Escape($id) -and $text -notmatch '(?i)nenhum pacote|no installed package|no package found') { return $id }
        } catch { }
    }
    return $null
}

function Test-SoftwareInstalled {
    param($Item)
    if ($Item.Key -eq 'VisualStudio') { return (@(Get-UnifiedInstalledEditions).Count -gt 0) }
    if ($Item.Key -eq 'PowerBI') { return (Test-UnifiedPowerBIInstalled) }
    if ($Item.Key -eq 'Chrome') {
        foreach ($path in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) {
            if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $true }
        }
    }
    if ($Item.Command -and (Get-Command $Item.Command -ErrorAction SilentlyContinue)) { return $true }
    return [bool](Get-InstalledWingetId -Ids $Item.Ids)
}

function Get-SoftwareState {
    param($Item)
    $installed = Test-SoftwareInstalled $Item
    $id = if ($Item.Ids.Count) { Get-InstalledWingetId -Ids $Item.Ids } else { $null }
    $update = $false
    if ($installed -and $id) {
        $update = ($script:WingetUpgradeText -and $script:WingetUpgradeText -match [regex]::Escape($id))
    }
    elseif ($installed -and $Item.Ia -and $Item.Command) {
        try {
            $package = switch ($Item.Key) { 'Claude' {'@anthropic-ai/claude-code'}; 'Codex' {'@openai/codex'}; 'OpenCode' {'opencode-ai'} }
            $currentText = & $Item.Command --version 2>$null | Select-Object -First 1
            $current = [regex]::Match([string]$currentText,'\d+(\.\d+){1,3}').Value
            $latest = (Invoke-RestMethod -Uri ("https://registry.npmjs.org/{0}/latest" -f $package) -TimeoutSec 20).version
            if ($current -and $latest) { $update = ([version]$latest -gt [version]$current) }
        } catch { $update = $false }
    }
    [pscustomobject]@{ Item=$Item; Installed=$installed; UpdateAvailable=$update; InstalledId=$id }
}

function Get-TemporaryIaEngine {
    $target = Join-Path $env:TEMP 'InfinityHubScripts\ia-install.ps1'
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $uri = 'https://raw.githubusercontent.com/victorgomides/inf-tools/main/ia-install.ps1'
    Invoke-WebRequest -Uri $uri -OutFile $target -UseBasicParsing -TimeoutSec 60
    $tokens=$null; $errors=$null
    [Management.Automation.Language.Parser]::ParseFile($target,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -or -not (Select-String -LiteralPath $target -Pattern 'ClaudeCLI' -Quiet)) { throw 'O motor de IA baixado nao passou na validacao.' }
    return $target
}

function Invoke-SoftwareAction {
    param($State)
    $item = $State.Item
    if ($item.Ia) {
        $engine = Get-TemporaryIaEngine
        $shell = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
        & $shell -NoLogo -NoProfile -File $engine -PacotesCsv $item.Ia -Silent 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { return $false }
        $env:Path = (@([Environment]::GetEnvironmentVariable('Path','Machine'),[Environment]::GetEnvironmentVariable('Path','User')) | Where-Object { $_ }) -join ';'
        $command = Get-Command $item.Command -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $command) { Write-UnifiedStatus $item.Name 'Instalador terminou, mas o comando nao foi encontrado no PATH.' Error; return $false }
        try { $version = & $command.Source --version 2>&1 | Select-Object -First 1; return ($LASTEXITCODE -eq 0 -and $version) } catch { return $false }
    }
    $id = if ($State.InstalledId) { $State.InstalledId } else { $item.Ids[0] }
    $operation = if ($State.Installed) { 'upgrade' } else { 'install' }
    $args = @($operation,'--id',$id,'--exact','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity')
    if ($operation -eq 'install' -and $item.Scope) { $args += @('--scope',$item.Scope) }
    if ($operation -eq 'upgrade') { $args += '--include-unknown' }
    & winget.exe @args 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -and $operation -eq 'install' -and $item.Scope) {
        Write-UnifiedStatus $item.Name 'Instalacao por usuario indisponivel; tentando o escopo suportado pelo pacote.' Warn
        $args = @($operation,'--id',$id,'--exact','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity')
        & winget.exe @args 2>&1 | ForEach-Object { Write-Host $_ }
    }
    if ($LASTEXITCODE -ne 0) { return $false }
    $env:Path = (@([Environment]::GetEnvironmentVariable('Path','Machine'),[Environment]::GetEnvironmentVariable('Path','User')) | Where-Object { $_ }) -join ';'
    if ($item.Command) {
        $knownPaths = switch ($item.Key) {
            'Git' { @("$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe") }
            'NodeJS' { @("$env:ProgramFiles\nodejs\node.exe", "$env:LOCALAPPDATA\Programs\nodejs\node.exe") }
            'PowerShell7' { @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe") }
            'VSCode' { @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd", "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd") }
            default { @() }
        }
        $command = Get-Command $item.Command -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $command) {
            $candidate = $knownPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
            if ($candidate) {
                $binDir = Split-Path -Parent $candidate
                $currentUserPath = [Environment]::GetEnvironmentVariable('Path','User')
                if (-not (($currentUserPath -split ';') -contains $binDir)) {
                    [Environment]::SetEnvironmentVariable('Path',((@($currentUserPath,$binDir) | Where-Object { $_ }) -join ';'),'User')
                }
                $env:Path = "$binDir;$env:Path"
                $command = [pscustomobject]@{ Source=$candidate }
            }
        }
        if (-not $command) { Write-UnifiedStatus $item.Name 'Pacote registrado, mas executavel nao localizado.' Error; return $false }
        try { $version = & $command.Source --version 2>&1 | Select-Object -First 1; if ($LASTEXITCODE -ne 0 -or -not $version) { return $false } } catch { return $false }
    }
    return (Test-SoftwareInstalled $item)
}

function Invoke-SoftwareManager {
    Initialize-ConsoleUi -Title 'Infinity - Gerenciador de Softwares'
    Write-Host ''
    Write-Host '  Infinity - Gerenciador de Softwares' -ForegroundColor White
    Write-Host ("  Diagnostico e acoes | v{0}" -f $SCRIPT_VERSION) -ForegroundColor DarkCyan
    Write-Host ''
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'WinGet nao esta disponivel neste computador.' }
    Write-UnifiedStatus 'Diagnostico' 'Consultando aplicativos instalados e atualizacoes...'
    $script:WingetListText = (& winget.exe list --accept-source-agreements --disable-interactivity 2>&1 | Out-String)
    $script:WingetUpgradeText = (& winget.exe upgrade --accept-source-agreements --disable-interactivity 2>&1 | Out-String)
    $states = @(Get-SoftwareCatalog | ForEach-Object { Get-SoftwareState $_ })
    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($state in $states) {
        if (-not $state.Installed) { $label='Nao instalado'; $color='Yellow'; [void]$actions.Add($state) }
        elseif ($state.UpdateAvailable) { $label='Atualizacao disponivel'; $color='Cyan'; [void]$actions.Add($state) }
        else { $label='Atualizado'; $color='Green' }
        Write-Host ("  {0,-28} {1}" -f $state.Item.Name,$label) -ForegroundColor $color
    }
    Write-Host ''
    if (-not $actions.Count) {
        Write-UnifiedStatus 'Conclusao' 'Todos os aplicativos estao instalados e atualizados.' Ok
        if (-not $script:NonInteractive) { Write-Host ''; $null = Read-Host '  Pressione ENTER para voltar ao Infinity Hub' }
        return
    }
    Write-Host '  ACOES DISPONIVEIS' -ForegroundColor White
    for ($i=0; $i -lt $actions.Count; $i++) {
        $verb = if ($actions[$i].Installed) { 'Atualizar' } else { 'Instalar' }
        Write-Host ("  [{0}] {1} {2}" -f ($i+1),$verb,$actions[$i].Item.Name)
    }
    Write-Host '  [A] Executar todas as acoes' -ForegroundColor Yellow
    Write-Host '  [0] Voltar'
    $answer = Read-Host '  Escolha numeros separados por virgula'
    if ($answer -eq '0' -or [string]::IsNullOrWhiteSpace($answer)) { return }
    $selected = if ($answer -match '^(?i)a$') { @($actions) } else {
        @($answer -split '[,; ]+' | ForEach-Object { $n=0; if ([int]::TryParse($_,[ref]$n) -and $n -ge 1 -and $n -le $actions.Count) { $actions[$n-1] } })
    }
    if (-not $selected.Count) {
        Write-UnifiedStatus 'Selecao' 'Nenhuma opcao valida foi informada.' Warn
        if (-not $script:NonInteractive) { Write-Host ''; $null = Read-Host '  Pressione ENTER para voltar ao Infinity Hub' }
        return
    }
    foreach ($state in $selected) {
        $verb = if ($state.Installed) { 'Atualizando' } else { 'Instalando' }
        Write-UnifiedStatus $state.Item.Name $verb
        if (Invoke-SoftwareAction $state) { Write-UnifiedStatus $state.Item.Name 'Concluido.' Ok }
        else { Write-UnifiedStatus $state.Item.Name 'Falha no processamento.' Error; $script:ExitCode=1 }
    }

    Write-Host ''
    Write-Host '  VALIDACAO FINAL' -ForegroundColor White
    Write-UnifiedStatus 'Diagnostico' 'Atualizando PATH e conferindo o estado final...'
    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = (@($machinePath,$userPath) | Where-Object { $_ }) -join ';'
    $script:WingetListText = (& winget.exe list --accept-source-agreements --disable-interactivity 2>&1 | Out-String)
    $script:WingetUpgradeText = (& winget.exe upgrade --accept-source-agreements --disable-interactivity 2>&1 | Out-String)
    $finalStates = @(Get-SoftwareCatalog | ForEach-Object { Get-SoftwareState $_ })
    $pendingCount = 0
    foreach ($final in $finalStates) {
        if (-not $final.Installed) { $label='Nao instalado'; $color='Yellow' }
        elseif ($final.UpdateAvailable) { $label='Atualizacao ainda disponivel'; $color='Yellow' }
        else { $label='Instalado e atualizado'; $color='Green' }
        if ($final.Item.Key -in @($selected | ForEach-Object { $_.Item.Key }) -and ($label -ne 'Instalado e atualizado')) { $pendingCount++ }
        Write-Host ("  {0,-28} {1}" -f $final.Item.Name,$label) -ForegroundColor $color
    }
    Write-Host ''
    if ($pendingCount -eq 0 -and $script:ExitCode -eq 0) {
        Write-UnifiedStatus 'Conclusao' 'Todas as acoes selecionadas foram validadas.' Ok
    } else {
        Write-UnifiedStatus 'Conclusao' ("Existem {0} acao(oes) selecionada(s) que exigem revisao." -f $pendingCount) Warn
        if ($pendingCount -gt 0) { $script:ExitCode = 1 }
    }
    if (-not $script:NonInteractive) { Write-Host ''; $null = Read-Host '  Pressione ENTER para voltar ao Infinity Hub' }
}

if (-not $InternalEngine -and -not $UnifiedController -and -not $DetectOnly) {
    try { Invoke-SoftwareManager }
    catch {
        Write-UnifiedStatus 'Execucao' $_.Exception.Message Error
        $script:ExitCode=1
        if (-not $script:NonInteractive) { Write-Host ''; $null = Read-Host '  Pressione ENTER para voltar ao Infinity Hub' }
    }
    exit $script:ExitCode
}

if (-not $DetectOnly -and -not (Test-IsElevated)) {
    try { Request-Elevation }
    catch {
        Write-Host ("  {0} Falha ao solicitar elevacao: {1}" -f $script:SymFail, $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}

if (-not $InternalEngine) {
    try { $script:ExitCode = Invoke-UnifiedController }
    catch { Write-UnifiedStatus 'Execucao' $_.Exception.Message Error; $script:ExitCode = 1 }
    exit $script:ExitCode
}

$TempDir = Join-Path $WorkDir "Temp"

[void](New-Item -ItemType Directory -Path $TempDir -Force)

# Mapeamento de edicoes: Product ID e sufixo do bootstrapper
$EditionMap = @{
    "Community"    = @{ ProductID = "Microsoft.VisualStudio.Product.Community";    Bootstrapper = "vs_community.exe"    }
    "Professional" = @{ ProductID = "Microsoft.VisualStudio.Product.Professional"; Bootstrapper = "vs_professional.exe" }
    "Enterprise"   = @{ ProductID = "Microsoft.VisualStudio.Product.Enterprise";   Bootstrapper = "vs_enterprise.exe"   }
    "BuildTools"   = @{ ProductID = "Microsoft.VisualStudio.Product.BuildTools";   Bootstrapper = "vs_buildtools.exe"   }
}

$SelectedEdition = $EditionMap[$Edition]
$ProductID       = $SelectedEdition.ProductID
$BootstrapperExe = $SelectedEdition.Bootstrapper

# Bootstrappers oficiais por canal/ano
# VS 2022 = canal 17 (Release) | VS 2026 = canal 18 (Stable)
$BootstrapperMap = @{
    "2022" = "https://aka.ms/vs/17/release/$BootstrapperExe"
    "2026" = "https://aka.ms/vs/18/Stable/$BootstrapperExe"
}

$ChannelManifestMap = @{
    "2022" = "https://aka.ms/vs/17/release/channel"
    "2026" = "https://aka.ms/vs/18/stable/channel"
}

# Funcoes auxiliares

function Write-UiLine {
    param(
        [string]$Label,
        [string]$Text,
        [string]$Color = 'Gray',
        [switch]$NewGroup
    )

    if ($script:NonInteractive) { return }
    if ($NewGroup -and $script:LastUiLabel) { Write-Host "" }
    $script:LastUiLabel = $Label
    Write-Host ("  {0,-20} {1}" -f $Label, $Text) -ForegroundColor $Color
}

function Write-Log {
    param([string]$Message)

    if ($script:NonInteractive) {
        $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        Write-Host $line
        return
    }

    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    if ($Message -match '^=====') { return }
    if ($Message -match '^(Parametros:|URL do instalador|Download parcial|Argumentos do instalador|ExitCode do instalador|VS Installer ExitCode|Bootstrapper temporario|Arquivo temporario antigo|Log antigo removido|Atualiza Visual Studio|Versao do bootstrapper baixado)') { return }
    if ($Message -match '^\[VS \d{4} .+\] Nao encontrado neste computador\. Pulando\.$') { return }

    $label = 'Status'
    $text = $Message
    $color = 'Gray'

    if ($text -match '^\[(VS \d{4} [^\]]+)\]\s*(.*)$') {
        $label = $matches[1]
        $text = $matches[2]
    }
    elseif ($text -match '^\[VS Code\]\s*(.*)$') {
        $label = 'VS Code'
        $text = $matches[1]
    }

    if ($text -match '^Encontrado: Visual Studio (.+?) \| Versao: ([^|]+) \| Caminho:') {
        $label = 'Visual Studio'
        $text = "$($matches[1]) instalado ($($matches[2].Trim()))"
    }
    elseif ($text -match '^Visual Studio (.+?) instalado: (.+)$') {
        $label = 'Visual Studio'
        $text = "$($matches[1]) instalado ($($matches[2]))"
    }
    elseif ($text -match '^Instalado: (.+)$') {
        $text = "Instalado $($matches[1])"
    }
    elseif ($text -match '^Consultando catalogo oficial do canal') {
        $text = 'Consultando atualizacao disponivel'
    }
    elseif ($text -match '^Versao disponivel no canal: (.+)$') {
        $text = "Disponivel $($matches[1])"
    }
    elseif ($text -match '^Sem atualizacao disponivel\. Instalado: (.+?) \| Canal: (.+)\.$') {
        $text = "OK Sem atualizacao (instalado $($matches[1]))"
    }
    elseif ($text -match '^Atualizacao disponivel\. Instalado: (.+?) \| Canal: (.+)\.$') {
        $text = "Atualizacao disponivel ($($matches[1]) -> $($matches[2]))"
    }
    elseif ($text -match '^Baixando componentes de atualizacao') {
        $text = 'Baixando componentes'
    }
    elseif ($text -match '^Preparando instalador') {
        $text = 'Preparando instalador'
    }
    elseif ($text -match '^Aplicando atualizacao') {
        $text = 'Aplicando atualizacao'
    }
    elseif ($text -match '^Instalador finalizado com sucesso') {
        $text = 'OK Instalador finalizado'
    }
    elseif ($text -match '^Versao instalada apos execucao: (.+)$') {
        $text = "Versao final $($matches[1])"
    }
    elseif ($text -match '^Nenhuma alteracao necessaria\. Versao atual: (.+)\.$') {
        $text = "OK Nenhuma alteracao necessaria ($($matches[1]))"
    }
    elseif ($text -match '^Atualizacao confirmada: (.+?) -> (.+)\.$') {
        $text = "OK Atualizado ($($matches[1]) -> $($matches[2]))"
    }
    elseif ($text -match '^Verificacao ignorada por parametro') {
        $text = 'Verificacao ignorada por parametro'
    }
    elseif ($text -match '^Nao instalado\. Pulando\.$') {
        $text = 'Nao instalado'
    }
    elseif ($text -match '^Verificando atualizacao via winget') {
        $text = 'Consultando atualizacao via winget'
    }
    elseif ($text -match '^Nenhuma atualizacao disponivel') {
        $text = 'OK Nenhuma atualizacao disponivel'
    }
    elseif ($text -match '^Atualizacao disponivel\. Aplicando') {
        $text = 'Atualizacao disponivel. Aplicando'
    }
    elseif ($text -match '^Upgrade finalizado, mas a versao registrada permaneceu (.+)\.$') {
        $text = "OK Upgrade finalizado; versao registrada permaneceu $($matches[1])"
    }
    elseif ($text -match '^Upgrade finalizado\. Nao foi possivel confirmar versao no registro\.$') {
        $text = 'AVISO Upgrade finalizado; versao nao confirmada no registro'
    }
    elseif ($text -match '^OK Verificacao concluida\.$') {
        $label = 'Resultado'
        $text = 'OK Verificacao concluida'
    }
    elseif ($text -match '^ERRO\s+(.+)$') {
        $label = 'Resultado'
        $text = "ERRO $($matches[1])"
    }

    if ($text -match '^(ERRO|.* ERRO:|.* FALHA|Falha|O instalador retornou|X )') {
        $color = 'Red'
        $text = $text -replace '^(ERRO GERAL|ERRO):\s*', 'ERRO ' -replace '^Falha:\s*', 'ERRO '
    }
    elseif ($text -match '^(AVISO|.*AVISO:)') {
        $color = 'Yellow'
        $text = $text -replace '^AVISO:\s*', 'AVISO '
    }
    elseif ($text -match '^(OK|.*concluido|.*sucesso|.*Sem atualizacao|.*Nenhuma atualizacao|.*Nenhuma alteracao)') {
        $color = 'Green'
    }
    else {
        $color = 'Cyan'
    }

    $newGroup = ($label -ne $script:LastUiLabel)
    Write-UiLine -Label $label -Text $text -Color $color -NewGroup:$newGroup
}
function Show-Banner {
    Write-Host ""
    Write-Host "  U P D A T E" -ForegroundColor White
    Write-Host ("  Visual Studio e VS Code | v{0}" -f $SCRIPT_VERSION) -ForegroundColor DarkCyan
    Write-Host ""
}


function Invoke-SilentProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$ArgumentList
    )

    $captureDir = Join-Path $TempDir 'ProcessOutput'
    [void](New-Item -ItemType Directory -Path $captureDir -Force)

    $stamp = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'), ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $stdoutPath = Join-Path $captureDir "$stamp.stdout.log"
    $stderrPath = Join-Path $captureDir "$stamp.stderr.log"

    $proc = Start-Process `
        -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -Wait `
        -PassThru `
        -ErrorAction Stop

    $outputLines = @()
    if (Test-Path -LiteralPath $stderrPath) {
        $outputLines += Get-Content -LiteralPath $stderrPath -Tail 20 -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $stdoutPath) {
        $outputLines += Get-Content -LiteralPath $stdoutPath -Tail 20 -ErrorAction SilentlyContinue
    }

    $succeeded = $proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010
    if ($succeeded) {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }

    return [PSCustomObject]@{
        ExitCode  = $proc.ExitCode
        Output    = ($outputLines -join ' | ').Trim()
        OutputDir = $captureDir
    }
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$ArgumentList
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $ArgumentList
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    return [PSCustomObject]@{
        ExitCode = $proc.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
        Output   = (($stdout, $stderr) -join "`n").Trim()
    }
}

function Remove-OldLogs {
    param([string]$Path, [int]$DaysToKeep = 60)

    if (-not (Test-Path $Path)) { return }

    $limit = (Get-Date).AddDays(-$DaysToKeep)
    Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq ".log" -and $_.LastWriteTime -lt $limit } |
        ForEach-Object {
            try {
                Remove-Item $_.FullName -Force -ErrorAction Stop
                Write-Log "Log antigo removido: $($_.FullName)"
            }
            catch {
                Write-Log "Falha ao remover log antigo: $($_.FullName) | $($_.Exception.Message)"
            }
        }
}

function Get-InstalledVSInstances {
    <#
        Usa vswhere.exe para descobrir instancias instaladas da edicao selecionada.
        Retorna lista de objetos com Year, Version e InstallPath.
    #>
    $result      = @()
    $vswherePath = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"

    if (-not (Test-Path $vswherePath)) {
        Write-Log "vswhere.exe nao encontrado. Nao e possivel detectar instancias instaladas."
        return $result
    }

    $instances = & $vswherePath -products $ProductID -all -format json 2>$null | ConvertFrom-Json

    foreach ($inst in $instances) {
        $rawVersion = $inst.installationVersion

        $major = try { ([version]$rawVersion).Major } catch { $null }
        $vsYear = switch ($major) {
            17      { "2022" }
            18      { "2026" }
            default { $null  }
        }

        if (-not $vsYear) {
            Write-Log "Instancia ignorada (versao principal nao reconhecida): $rawVersion"
            continue
        }

        try {
            $result += [PSCustomObject]@{
                Year        = $vsYear
                Version     = [version]$rawVersion
                InstallPath = $inst.installationPath
            }
            if ($script:NonInteractive) {
                Write-Log "Encontrado: Visual Studio $vsYear $Edition | Versao: $rawVersion | Caminho: $($inst.installationPath)"
            }
            else {
                Write-Log "Visual Studio $vsYear $Edition instalado: $rawVersion"
            }
        }
        catch {
            Write-Log "Nao foi possivel converter a versao '$rawVersion'. Instancia ignorada."
        }
    }

    return $result
}

function Get-VSInstanceVersionByPath {
    param([string]$InstallPath)

    $vswherePath = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswherePath)) { return $null }

    $instances = & $vswherePath -products $ProductID -all -format json 2>$null | ConvertFrom-Json
    foreach ($inst in $instances) {
        if ($inst.installationPath -eq $InstallPath) {
            try { return [version]$inst.installationVersion } catch { return $null }
        }
    }

    return $null
}

function Get-VSCodeInstallInfo {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $apps = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -match '^Microsoft Visual Studio Code' -and
            $_.DisplayName -notmatch 'Insiders'
        }

    if (-not $apps) { return $null }

    $app = $apps |
        Sort-Object {
            try { [version]$_.DisplayVersion } catch { [version]'0.0.0.0' }
        } -Descending |
        Select-Object -First 1

    $version = $null
    try {
        if ($app.DisplayVersion) { $version = [version]$app.DisplayVersion }
    }
    catch { }

    return [PSCustomObject]@{
        Name            = $app.DisplayName
        Version         = $version
        Raw             = $app.DisplayVersion
        InstallLocation = $app.InstallLocation
        Scope           = if ($app.DisplayName -match '\(User\)' -or $app.PSPath -match 'HKEY_CURRENT_USER') { 'User' } else { 'Machine' }
    }
}

function Invoke-VSCodeDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination
    )

    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [Threading.Timeout]::InfiniteTimeSpan
    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        $response = $client.GetAsync($Uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode()
        $totalBytes = $response.Content.Headers.ContentLength
        $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] (1024 * 1024)
        [long]$downloaded = 0
        $lastReport = [DateTime]::MinValue
        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $read)
            $downloaded += $read
            if (((Get-Date) - $lastReport).TotalSeconds -ge 2) {
                if ($totalBytes -and $totalBytes -gt 0) {
                    $percent = [Math]::Min(100, ($downloaded * 100.0 / $totalBytes))
                    Write-Log ("[VS Code] Download: {0:N1}% ({1:N1} MB de {2:N1} MB)." -f $percent, ($downloaded / 1MB), ($totalBytes / 1MB))
                }
                else {
                    Write-Log ("[VS Code] Download: {0:N1} MB recebidos." -f ($downloaded / 1MB))
                }
                $lastReport = Get-Date
            }
        }
        Write-Log ("[VS Code] Download concluido ({0:N1} MB)." -f ($downloaded / 1MB))
    }
    finally {
        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if ($response) { $response.Dispose() }
        $client.Dispose()
    }
}

function Update-VSCodeFromOfficialService {
    param([Parameter(Mandatory)]$Installed)

    $label = 'VS Code'
    $installerPath = $null
    try {
        $architecture = if ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64' -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        $platform = if ($Installed.Scope -eq 'User') { "win32-$architecture-user" } else { "win32-$architecture" }
        $metadataUrl = "https://update.code.visualstudio.com/api/update/$platform/stable/latest"

        Write-Log "[$label] Consultando servico oficial do VS Code..."
        $metadata = Invoke-RestMethod -Uri $metadataUrl -UseBasicParsing -TimeoutSec 45 -ErrorAction Stop
        $latestRaw = if ($metadata.productVersion) { [string]$metadata.productVersion } else { [string]$metadata.name }
        if (-not $latestRaw -or -not $metadata.url) { throw 'O servico oficial nao retornou versao ou URL de download.' }
        try { $latestVersion = [version]$latestRaw } catch { throw "Versao invalida retornada pelo servico oficial: $latestRaw" }
        Write-Log "[$label] Versao disponivel: $latestRaw"

        if (-not $Force -and $Installed.Version -and $Installed.Version -ge $latestVersion) {
            Write-Log "[$label] Nenhuma atualizacao disponivel. Instalado: $($Installed.Raw) | Disponivel: $latestRaw."
            return $true
        }

        $installerPath = Join-Path $TempDir ("VSCodeSetup-{0}-{1}.exe" -f $architecture, $latestRaw)
        Write-Log "[$label] Baixando atualizacao pelo servico oficial..."
        Invoke-VSCodeDownload -Uri ([string]$metadata.url) -Destination $installerPath

        if ($metadata.sha256hash) {
            $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($actualHash -ine [string]$metadata.sha256hash) {
                throw "Hash SHA-256 divergente. Esperado: $($metadata.sha256hash) | Obtido: $actualHash"
            }
            Write-Log "[$label] Hash SHA-256 validado."
        }
        Assert-MicrosoftSignedFile -Path $installerPath
        Write-Log "[$label] Assinatura digital da Microsoft validada."

        Write-Log "[$label] Encerrando processos do VS Code em todas as sessoes..."
        Get-Process -Name 'Code' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        Write-Log "[$label] Aplicando atualizacao oficial..."
        $install = Invoke-SilentProcess -FilePath $installerPath -ArgumentList '/VERYSILENT /NORESTART /MERGETASKS=!runcode'
        if ($install.ExitCode -ne 0 -and $install.ExitCode -ne 3010) {
            throw "Falha no instalador oficial do VS Code. ExitCode: $($install.ExitCode). $($install.Output)"
        }

        Start-Sleep -Seconds 2
        $updated = Get-VSCodeInstallInfo
        if (-not $updated -or -not $updated.Raw) { throw 'Instalador finalizado, mas a versao nao foi encontrada no registro.' }
        if ($updated.Version -lt $latestVersion) {
            throw "A versao registrada apos a instalacao ($($updated.Raw)) e anterior a esperada ($latestRaw)."
        }
        Write-Log "[$label] Atualizacao confirmada: $($Installed.Raw) -> $($updated.Raw)."
        return $true
    }
    finally {
        if ($installerPath -and (Test-Path -LiteralPath $installerPath)) {
            Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Update-VSCode {
    $label = 'VS Code'

    try {
        if ($SkipVSCode) {
            Write-Log "[$label] Verificacao ignorada por parametro -SkipVSCode."
            return $true
        }

        $installed = Get-VSCodeInstallInfo
        if (-not $installed) {
            Write-Log "[$label] Nao instalado. Pulando."
            return $true
        }

        Write-Log "[$label] Instalado: $($installed.Raw)"

        $winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
        if (-not $winget) {
            Write-Log "[$label] winget nao encontrado. Usando o servico oficial do VS Code."
            return (Update-VSCodeFromOfficialService -Installed $installed)
        }

        Write-Log "[$label] Verificando atualizacao via winget..."
        $checkArgs = 'upgrade --id Microsoft.VisualStudioCode --exact --source winget --accept-source-agreements --disable-interactivity'
        $check = Invoke-CapturedProcess -FilePath $winget -ArgumentList $checkArgs

        $noUpgrade = $check.ExitCode -eq -1978335189 -or $check.Output -match '(?i)(nenhuma atualiza[cç][aã]o dispon[ií]vel|nenhuma vers[aã]o de pacote mais recente|no available upgrade|no newer package version|no applicable upgrade)'
        if ($noUpgrade) {
            Write-Log "[$label] Nenhuma atualizacao disponivel."
            return $true
        }

        if ($check.ExitCode -ne 0) {
            $details = if ($check.Output) { ($check.Output -split "`r?`n" | Select-Object -Last 3) -join ' | ' } else { 'sem detalhes do winget' }
            throw "Falha ao consultar atualizacao do VS Code. ExitCode: $($check.ExitCode). $details"
        }

        if ($check.Output -notmatch 'Microsoft\.VisualStudioCode') {
            Write-Log "[$label] Nenhuma atualizacao disponivel."
            return $true
        }

        Write-Log "[$label] Atualizacao disponivel. Aplicando..."
        $upgradeArgs = 'upgrade --id Microsoft.VisualStudioCode --exact --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity'
        $upgrade = Invoke-CapturedProcess -FilePath $winget -ArgumentList $upgradeArgs

        if ($upgrade.ExitCode -ne 0) {
            $details = if ($upgrade.Output) { ($upgrade.Output -split "`r?`n" | Select-Object -Last 3) -join ' | ' } else { 'sem detalhes do winget' }
            throw "Falha ao atualizar VS Code. ExitCode: $($upgrade.ExitCode). $details"
        }

        Start-Sleep -Seconds 2
        $updated = Get-VSCodeInstallInfo
        if ($updated -and $updated.Raw) {
            if ($installed.Version -and $updated.Version -and $updated.Version -gt $installed.Version) {
                Write-Log "[$label] Atualizacao confirmada: $($installed.Raw) -> $($updated.Raw)."
            }
            elseif ($updated.Raw -eq $installed.Raw) {
                Write-Log "[$label] Upgrade finalizado, mas a versao registrada permaneceu $($updated.Raw)."
            }
            else {
                Write-Log "[$label] Versao apos execucao: $($updated.Raw)."
            }
        }
        else {
            Write-Log "[$label] Upgrade finalizado. Nao foi possivel confirmar versao no registro."
        }

        return $true
    }
    catch {
        Write-Log "[$label] ERRO: $($_.Exception.Message)"
        return $false
    }
}

function Convert-WebContentToText {
    param([object]$Content)

    if ($Content -is [byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($Content)
    }

    return [string]$Content
}

function Assert-MicrosoftSignedFile {
    param([Parameter(Mandatory)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Assinatura digital invalida em '$Path'. Status: $($signature.Status)."
    }

    $subject = [string]$signature.SignerCertificate.Subject
    if ($subject -notmatch '(?i)Microsoft Corporation') {
        throw "O arquivo '$Path' nao foi assinado pela Microsoft Corporation. Assinante: $subject"
    }
}

function Get-VSChannelAvailableVersion {
    param(
        [Parameter(Mandatory)][string]$Year,
        [Parameter(Mandatory)][string]$ProductId,
        [Parameter(Mandatory)][string]$Label
    )

    $channelUrl = $ChannelManifestMap[$Year]
    if (-not $channelUrl) {
        Write-Log "[$Label] AVISO: Canal nao mapeado para VS $Year."
        return $null
    }

    try {
        Write-Log "[$Label] Consultando catalogo oficial do canal..."
        $response = Invoke-WebRequest -Uri $channelUrl -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 45
        $jsonText = Convert-WebContentToText -Content $response.Content
        $channel = $jsonText | ConvertFrom-Json

        $productItem = $channel.channelItems | Where-Object { $_.id -eq $ProductId } | Select-Object -First 1
        $rawVersion = $null
        if ($productItem -and $productItem.version) {
            $rawVersion = [string]$productItem.version
        }
        elseif ($channel.info -and $channel.info.buildVersion) {
            $rawVersion = [string]$channel.info.buildVersion
        }

        if (-not $rawVersion) {
            Write-Log "[$Label] AVISO: Catalogo nao trouxe versao disponivel."
            return $null
        }

        $match = [regex]::Match($rawVersion, '\d+\.\d+\.\d+\.\d+')
        if (-not $match.Success) {
            Write-Log "[$Label] AVISO: Versao do catalogo em formato inesperado: $rawVersion"
            return $null
        }

        $availableVersion = [version]$match.Value
        Write-Log "[$Label] Versao disponivel no canal: $availableVersion"
        return $availableVersion
    }
    catch {
        Write-Log "[$Label] AVISO: Falha ao consultar catalogo do canal: $($_.Exception.Message)"
        return $null
    }
}

function Stop-VisualStudio {
    param([string]$Label)

    $vsProcesses = @("devenv", "WDExpress", "VSIXInstaller")
    $found       = $false

    foreach ($procName in $vsProcesses) {
        $running = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($running) {
            Write-Log "[$Label] Encerrando processo '$procName'..."
            $running | Stop-Process -Force
            $found = $true
        }
    }

    if ($found) {
        Start-Sleep -Seconds 5
    }
}

function Wait-VSInstallerIdle {
    param([string]$Label, [int]$TimeoutMinutes = 30)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $processNames = @('setup','vs_installer','vs_installershell','VSIXInstaller')
    while ($true) {
        $running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $processNames -contains $_.Name -and $_.Id -ne $PID -and ($_.Name -eq 'VSIXInstaller' -or ($_.Path -and $_.Path -match 'Microsoft Visual Studio|VisualStudio|Installer'))
        }
        if (-not $running) { return $true }
        if ((Get-Date) -gt $deadline) {
            $names = ($running | Select-Object -ExpandProperty Name -Unique) -join ', '
            throw "Visual Studio Installer ainda esta em execucao/configuracao apos $TimeoutMinutes minuto(s): $names"
        }
        $names = ($running | Select-Object -ExpandProperty Name -Unique) -join ', '
        Write-Log "[$Label] Aguardando Visual Studio Installer finalizar configuracao em andamento: $names"
        Start-Sleep -Seconds 10
    }
}


function Update-VSInstance {
    param(
        [string]$Year,
        [version]$InstalledVersion,
        [string]$InstallPath
    )

    $label            = "VS $Year $Edition"
    $bootstrapperUrl  = $BootstrapperMap[$Year]
    $bootstrapperPath = Join-Path $TempDir ("vs_${Edition}_${Year}.exe")

    try {
        # 1. Verifica a versao disponivel no catalogo do canal antes de baixar/executar instalador.
        $availableVersion = Get-VSChannelAvailableVersion -Year $Year -ProductId $ProductID -Label $label

        if ($availableVersion) {
            if (-not $Force -and $InstalledVersion -and $availableVersion -le $InstalledVersion) {
                Write-Log "[$label] Sem atualizacao disponivel. Instalado: $InstalledVersion | Canal: $availableVersion."
                return $true
            }

            Write-Log "[$label] Atualizacao disponivel. Instalado: $InstalledVersion | Canal: $availableVersion."
        }
        else {
            if (-not $Force) {
                Write-Log "[$label] ERRO: Nao foi possivel confirmar atualizacao disponivel. Use -Force para forcar."
                return $false
            }

            Write-Log "[$label] AVISO: Verificacao indisponivel, mas -Force foi informado. Prosseguindo."
        }

        # 2. Baixa o bootstrapper completo apenas quando existe atualizacao ou -Force foi informado.
        if (Test-Path -LiteralPath $bootstrapperPath) {
            Remove-Item -LiteralPath $bootstrapperPath -Force -ErrorAction SilentlyContinue
            Write-Log "[$label] Bootstrapper temporario antigo removido."
        }

        Write-Log "[$label] Baixando componentes de atualizacao..."
        Invoke-WebRequest -Uri $bootstrapperUrl -OutFile $bootstrapperPath -UseBasicParsing
        Assert-MicrosoftSignedFile -Path $bootstrapperPath
        Write-Log "[$label] Assinatura digital da Microsoft validada."

        # 3. Registra a versao do bootstrapper baixado apenas como informacao.
        $item       = Get-Item $bootstrapperPath -ErrorAction Stop
        $rawVersion = $item.VersionInfo.ProductVersion
        if (-not $rawVersion) { $rawVersion = $item.VersionInfo.FileVersion }

        if ($rawVersion) {
            $m = [regex]::Match($rawVersion, '\d+\.\d+\.\d+\.\d+')
            if ($m.Success) {
                $downloadedVersion = [version]$m.Value
                Write-Log "[$label] Versao do bootstrapper baixado: $downloadedVersion"
            }
        }

        # 4. Fecha o VS se estiver aberto
        Stop-VisualStudio -Label $label

        # 5. Atualiza o VS Installer antes do produto
        $vsInstallerSetup = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
        if (Test-Path $vsInstallerSetup) {
            Write-Log "[$label] Preparando instalador..."
            $installerUpdateArgs = "update --quiet --norestart --installPath `"$InstallPath`""
            Wait-VSInstallerIdle -Label $label | Out-Null
            $procInst = Invoke-SilentProcess -FilePath $vsInstallerSetup -ArgumentList $installerUpdateArgs
            if ($procInst.ExitCode -ne 0 -and $procInst.ExitCode -ne 3010) { throw "Falha ao atualizar Visual Studio Installer. ExitCode: $($procInst.ExitCode)" }
            Wait-VSInstallerIdle -Label $label | Out-Null
            Write-Log "[$label] VS Installer ExitCode: $($procInst.ExitCode)"
        }

        # 6. Executa a atualizacao do produto
        $arguments  = "update --wait --quiet --norestart --installPath `"$InstallPath`""

        Write-Log "[$label] Aplicando atualizacao..."
        $proc = Invoke-SilentProcess -FilePath $bootstrapperPath -ArgumentList $arguments

        Write-Log "[$label] ExitCode do instalador: $($proc.ExitCode)"

        # 3010 = sucesso com reinicializacao pendente (comportamento normal do Windows Installer)
        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
            throw "Falha na instalacao. ExitCode: $($proc.ExitCode)."
        }

        if ($proc.ExitCode -eq 3010) {
            Write-Log "[$label] Atualizacao concluida. Reinicializacao pendente."
        }
        else {
            Write-Log "[$label] Instalador finalizado com sucesso."
        }

        Wait-VSInstallerIdle -Label $label | Out-Null
        Start-Sleep -Seconds 3

        $newVersion = Get-VSInstanceVersionByPath -InstallPath $InstallPath
        if (-not $newVersion) {
            throw "Instalador finalizou, mas nao foi possivel confirmar a versao instalada via vswhere."
        }

        Write-Log "[$label] Versao instalada apos execucao: $newVersion"

        if ($InstalledVersion -and $newVersion -lt $InstalledVersion) {
            throw "Versao instalada ficou menor que a anterior ($InstalledVersion -> $newVersion)."
        }

        if ($InstalledVersion -and $newVersion -eq $InstalledVersion) {
            Write-Log "[$label] Nenhuma alteracao necessaria. Versao atual: $newVersion."
        }
        else {
            Write-Log "[$label] Atualizacao confirmada: $InstalledVersion -> $newVersion."
        }

        return $true
    }
    catch {
        Write-Log "[$label] ERRO: $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path $bootstrapperPath) {
            Remove-Item $bootstrapperPath -Force -ErrorAction SilentlyContinue
            Write-Log "[$label] Bootstrapper temporario removido."
        }
    }
}

# Execucao principal

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Initialize-ConsoleUi -Title 'atualiza_visualstudio'
    Show-Banner
    Write-Log "===== Inicio da execucao ====="
    if ($script:NonInteractive) {
        Write-Log "Atualiza Visual Studio e VS Code | v$SCRIPT_VERSION"
        Write-Log "Parametros: Year=$Year | Edition=$Edition | Force=$Force | SkipVSCode=$SkipVSCode | SkipVisualStudio=$SkipVisualStudio"
    }


    $anyFailure = $false

    if ($SkipVisualStudio) {
        Write-Log "Visual Studio ignorado; executando somente a verificacao do VS Code."
    }
    else {
        $instances = Get-InstalledVSInstances
        if ($instances.Count -eq 0) {
            Write-Log "Nenhuma instancia do Visual Studio $Edition encontrada."
        }
        else {
        $yearsToProcess = if ($Year -eq "All") {
            @($instances | Select-Object -ExpandProperty Year -Unique | Sort-Object)
        }
        else {
            @($Year)
        }

        foreach ($vsYear in $yearsToProcess) {
            $instancesForYear = @($instances | Where-Object { $_.Year -eq $vsYear })

            if ($instancesForYear.Count -eq 0) {
                Write-Log "[VS $vsYear $Edition] Nao encontrado neste computador. Pulando."
                continue
            }

            foreach ($inst in $instancesForYear) {
                $success = Update-VSInstance `
                    -Year             $inst.Year `
                    -InstalledVersion $inst.Version `
                    -InstallPath      $inst.InstallPath

                if (-not $success) {
                    $anyFailure = $true
                }
            }
        }
        }
    }

    if (-not (Update-VSCode)) { $anyFailure = $true }

    if ($anyFailure) {
        $script:ExitCode = 1
        Write-Log "ERRO Uma ou mais atualizacoes falharam."
    }
    else {
        Write-Log "OK Verificacao concluida."
    }

    Write-Log "===== Fim da execucao ====="
}
catch {
    Write-Log "ERRO GERAL: $($_.Exception.Message)"
    Write-Log "===== Fim com erro ====="
    $script:ExitCode = 1
}

exit $script:ExitCode



