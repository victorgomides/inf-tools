<#
.SYNOPSIS
    Instalador de ferramentas IA (Claude Code, Codex CLI, OpenCode, Desktops) para Windows.

.DESCRIPTION
    Script de instalacao/atualizacao/remocao das ferramentas de IA. Suporta:
      - Modo interativo (menu) e nao-interativo (via switches)
      - Instalacao por usuario, sem exigir privilegios administrativos
      - Maquina local, Servidor e Terminal Server
      - PowerShell 5.1+ (Desktop e Core)
      - Console UTF-8/VT com fallback ASCII
      - Proxy do sistema, retry automatico em downloads
      - Log estruturado via -LogPath

.PARAMETER Tudo
    Instala todas as ferramentas (CLI + Desktop). Equivale a opcao 1 do menu.

.PARAMETER CLI
    Instala somente as ferramentas CLI (Claude Code, Codex CLI, OpenCode).

.PARAMETER Desktop
    Instala somente os apps Desktop (Claude, ChatGPT/Codex, OpenCode).

.PARAMETER Pacotes
    Lista especifica de pacotes a instalar. Valores aceitos:
    Git, ClaudeCLI, CodexCLI, OpenCode, ClaudeDesk, CodexDesk, OpenDesk

.PARAMETER Silent
    Modo nao-interativo: sem prompts, sem ESPERAS, sem menu.
    Usa logging estruturado se -LogPath for fornecido.

.PARAMETER LogPath
    Caminho do arquivo de log (transcript). Se nao informado em modo Silent,
    grava em %TEMP%\ia-install_<timestamp>.log

.PARAMETER SkipDiagnostico
    Pula a etapa de diagnostico inicial (instala tudo sem checar versao atual).

.EXAMPLE
    .\ia-install.ps1
    Abre o menu interativo.

.EXAMPLE
    .\ia-install.ps1 -Tudo -Silent -LogPath "C:\Logs\ia.log"
    Instala todas as ferramentas em modo nao-interativo, gravando log.

.EXAMPLE
    .\ia-install.ps1 -Pacotes ClaudeCLI,CodexCLI -Silent
    Instala somente Claude Code e Codex CLI sem prompts.

.NOTES
    Versao: 2.11.3
    Compatibilidade: Windows 10 1809+/11, Server 2019+, PowerShell 5.1+
#>
[CmdletBinding(DefaultParameterSetName='Interactive', SupportsShouldProcess=$true)]
param(
    [Parameter(ParameterSetName='Tudo')]
    [switch]$Tudo,

    [Parameter(ParameterSetName='CLI')]
    [switch]$CLI,

    [Parameter(ParameterSetName='Desktop')]
    [switch]$Desktop,

    [Parameter(ParameterSetName='Pacotes')]
    [ValidateSet('Git','ClaudeCLI','CodexCLI','OpenCode','ClaudeDesk','CodexDesk','OpenDesk')]
    [string[]]$Pacotes,

    # Quando combinado com -Pacotes ou -Tudo/-CLI/-Desktop, remove em vez de instalar
    [switch]$Remover,

    [switch]$Silent,

    [string]$LogPath,

    [switch]$SkipDiagnostico
)

$ErrorActionPreference = "Continue"

# Modo nao-interativo? Detecta via switch ou ausencia de host interativo
$script:NonInteractive = $Silent.IsPresent -or
                         [Console]::IsInputRedirected -or
                         (-not [Environment]::UserInteractive)

# Inicia transcript se solicitado (ou auto em modo Silent)
$script:TranscriptStarted = $false
if ($LogPath -or ($Silent -and -not $LogPath)) {
    if (-not $LogPath) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $LogPath = Join-Path $env:TEMP "ia-install_$stamp.log"
    }
    try {
        $logDir = Split-Path -Parent $LogPath
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Start-Transcript -Path $LogPath -Append -ErrorAction Stop | Out-Null
        $script:TranscriptStarted = $true
    } catch { Write-Warning "Nao foi possivel iniciar transcript em $LogPath : $_" }
}

# ----------------------------------------------------------
# Versao e Historico de Atualizacoes
# ----------------------------------------------------------
$SCRIPT_VERSION = "2.11.3"
$SCRIPT_DATA    = "03/08/2026"
$CHANGELOG = @(
    [PSCustomObject]@{ Versao = "2.11.3"; Data = "03/08/2026"; Descricao = "Seguranca: remove -EncodedCommand dos testes de inicializacao para evitar alertas comportamentais do antivirus" }
    [PSCustomObject]@{ Versao = "2.11.2"; Data = "03/08/2026"; Descricao = "Auditoria: confirma os metodos oficiais atuais de Claude, Codex, OpenCode, Node.js e Git" }
    [PSCustomObject]@{ Versao = "2.11.2"; Data = "03/08/2026"; Descricao = "OpenCode Desktop: adiciona fallback pelo instalador oficial do GitHub quando o WinGet falhar" }
    [PSCustomObject]@{ Versao = "2.11.2"; Data = "03/08/2026"; Descricao = "Diagnostico: alerta sobre registros duplicados dos aplicativos Desktop no WinGet" }
    [PSCustomObject]@{ Versao = "2.11.1"; Data = "03/08/2026"; Descricao = "Diagnostico: detecta e repara PATH/PATHEXT, shims PowerShell, npm prefix/cache e permissoes do perfil" }
    [PSCustomObject]@{ Versao = "2.11.1"; Data = "03/08/2026"; Descricao = "Inicializacao: testa cada CLI em processo isolado e aponta conflitos entre instalacoes" }
    [PSCustomObject]@{ Versao = "2.11.1"; Data = "03/08/2026"; Descricao = "Claude Code: CLAUDE_CODE_GIT_BASH_PATH passa a apontar corretamente para o executavel bash.exe" }
    [PSCustomObject]@{ Versao = "2.11.0"; Data = "03/08/2026"; Descricao = "Usuario comum: instaladores, PATH, npm e WinGet passam a usar sempre o escopo do usuario" }
    [PSCustomObject]@{ Versao = "2.11.0"; Data = "03/08/2026"; Descricao = "Confiabilidade: valida codigos de saida e confirma cada instalacao antes de informar sucesso" }
    [PSCustomObject]@{ Versao = "2.11.0"; Data = "03/08/2026"; Descricao = "Claude Code: usa instalador nativo atual em processo isolado, inclusive no Windows Server" }
    [PSCustomObject]@{ Versao = "2.11.0"; Data = "03/08/2026"; Descricao = "Codex: remove instalacao preventiva do VC++ que exigia UAC; runtime fica como troubleshooting" }
    [PSCustomObject]@{ Versao = "2.10.9"; Data = "03/08/2026"; Descricao = "Claude Desktop: substitui ClaudeSetup.exe legado pelo MSIX oficial mais recente" }
    [PSCustomObject]@{ Versao = "2.10.9"; Data = "03/08/2026"; Descricao = "Claude Desktop: valida o codigo de saida do WinGet e usa fallback oficial por arquitetura" }
    [PSCustomObject]@{ Versao = "2.10.8"; Data = "06/05/2026"; Descricao = "Entrada: limpa buffer antes de confirmacoes" }
    [PSCustomObject]@{ Versao = "2.10.7"; Data = "06/05/2026"; Descricao = "Diagnostico: evita travamento no npm prefix e lista vazia" }
    [PSCustomObject]@{ Versao = "2.10.6"; Data = "06/05/2026"; Descricao = "VC++: baixa a versao mais recente e atualiza se a instalada estiver antiga" }
    [PSCustomObject]@{ Versao = "2.10.5"; Data = "06/05/2026"; Descricao = "VC++: corrige deteccao em registros sem DisplayName" },
    [PSCustomObject]@{ Versao = "2.10.0"; Data = "06/05/2026"; Descricao = "Codex: verifica e instala Visual C++ Redistributable x64 quando necessario" },
    [PSCustomObject]@{ Versao = "2.9.9"; Data = "29/04/2026"; Descricao = "UX: cabecalho compacto sem recuo no banner" },
    [PSCustomObject]@{ Versao = "2.9.8"; Data = "29/04/2026"; Descricao = "UX: alinha cabecalho compacto ao conceito final do remove-apps, com texto recuado e sem bordas" },
    [PSCustomObject]@{ Versao = "2.9.7"; Data = "29/04/2026"; Descricao = "UX: banner compacto sem borda e console preferencialmente maior (140x42)" },
    [PSCustomObject]@{ Versao = "2.9.6"; Data = "28/04/2026"; Descricao = "Fix: Install-NodeJS detecta admin e cai em portable .zip (LocalAppData) quando sem privilegio" },
    [PSCustomObject]@{ Versao = "2.9.6"; Data = "28/04/2026"; Descricao = "Fix: novo helper Test-IsAdmin + Install-NodeJSPortable (.zip oficial nodejs.org)" },
    [PSCustomObject]@{ Versao = "2.9.6"; Data = "28/04/2026"; Descricao = "Fix: tenta winget --scope user antes do .zip portable (mais limpo quando disponivel)" },
    [PSCustomObject]@{ Versao = "2.9.6"; Data = "28/04/2026"; Descricao = "Fix: Test-NpmDisponivel inclui LocalAppData\\nodejs e WinGet\\Packages user-scope" },
    [PSCustomObject]@{ Versao = "2.9.6"; Data = "28/04/2026"; Descricao = "Fix: detecta arquitetura ARM64/x64/x86 ao baixar Node.js portable" },
    [PSCustomObject]@{ Versao = "2.9.5"; Data = "24/04/2026"; Descricao = "Visual: bordas Unicode arredondadas (cantos suaves) com fallback ASCII" },
    [PSCustomObject]@{ Versao = "2.9.5"; Data = "24/04/2026"; Descricao = "Visual: spinner Braille (10 frames Unicode) padrao npm/cargo, mais suave em 80ms" },
    [PSCustomObject]@{ Versao = "2.9.5"; Data = "24/04/2026"; Descricao = "Visual: progress bar com blocos solidos e gradient (cheio/medio/leve/vazio)" },
    [PSCustomObject]@{ Versao = "2.9.5"; Data = "24/04/2026"; Descricao = "Visual: Show-Summary com badges coloridos [INSTALADO]/[ATUALIZADO]/[FALHOU]/[PULADO]" },
    [PSCustomObject]@{ Versao = "2.9.5"; Data = "24/04/2026"; Descricao = "Visual: tempo total formatado (Xm Ys) + status geral colorido (TUDO CERTO/FALHAS)" },
    [PSCustomObject]@{ Versao = "2.9.4"; Data = "24/04/2026"; Descricao = "Qualidade: testes Pester 5 em ia-install.Tests.ps1 cobrindo Repair-NpmRc e sintaxe" },
    [PSCustomObject]@{ Versao = "2.9.4"; Data = "24/04/2026"; Descricao = "Qualidade: PSScriptAnalyzerSettings.psd1 com regras compativeis PS 5.1/7.4" },
    [PSCustomObject]@{ Versao = "2.9.4"; Data = "24/04/2026"; Descricao = "Modernizacao: switch -Remover combinavel com -Tudo/-CLI/-Desktop/-Pacotes" },
    [PSCustomObject]@{ Versao = "2.9.4"; Data = "24/04/2026"; Descricao = "Modernizacao: catalogo de pacotes em `$script:PACKAGES (foundation para futura externalizacao)" },
    [PSCustomObject]@{ Versao = "2.9.3"; Data = "24/04/2026"; Descricao = "Modernizacao: param block + CmdletBinding, modo nao-interativo via -Silent, -Tudo, -CLI, -Desktop, -Pacotes" },
    [PSCustomObject]@{ Versao = "2.9.3"; Data = "24/04/2026"; Descricao = "Modernizacao: log estruturado via -LogPath (Start-Transcript automatico em modo Silent)" },
    [PSCustomObject]@{ Versao = "2.9.3"; Data = "24/04/2026"; Descricao = "Modernizacao: SupportsShouldProcess=true permite -WhatIf e -Confirm" },
    [PSCustomObject]@{ Versao = "2.9.3"; Data = "24/04/2026"; Descricao = "Modernizacao: comment-based help completo (.SYNOPSIS, .EXAMPLE, .PARAMETER)" },
    [PSCustomObject]@{ Versao = "2.9.3"; Data = "24/04/2026"; Descricao = "Modernizacao: verbos aprovados (Send-EnvChangeNotification, Wait-Readable) com aliases" },
    [PSCustomObject]@{ Versao = "2.9.2"; Data = "24/04/2026"; Descricao = "Hardening: pre-flight detecta PS, .NET, HttpClient, CIM/WMI, Console UTF-8/VT/redirect, Proxy" },
    [PSCustomObject]@{ Versao = "2.9.2"; Data = "24/04/2026"; Descricao = "Hardening: simbolos Unicode com fallback ASCII (+/X/!/>/i/*) em consoles sem UTF-8" },
    [PSCustomObject]@{ Versao = "2.9.2"; Data = "24/04/2026"; Descricao = "Hardening: [Console]::Write protegido contra saida redirecionada (logs, pipes)" },
    [PSCustomObject]@{ Versao = "2.9.2"; Data = "24/04/2026"; Descricao = "Hardening: download com retry+exponential backoff (2s/4s/8s) e proxy do sistema" },
    [PSCustomObject]@{ Versao = "2.9.2"; Data = "24/04/2026"; Descricao = "Hardening: HttpClient indisponivel cai direto em Invoke-WebRequest (compat .NET antigo)" },
    [PSCustomObject]@{ Versao = "2.9.1"; Data = "24/04/2026"; Descricao = "Fix: Codex CLI agora usa Invoke-NpmTool (passa --prefix/--cache explicitos, evita ENOENT)" },
    [PSCustomObject]@{ Versao = "2.9.1"; Data = "24/04/2026"; Descricao = "Fix: Repair-NpmRc detecta e corrige .npmrc com linhas concatenadas (prefix=X\npmcache=Y)" },
    [PSCustomObject]@{ Versao = "2.9.1"; Data = "24/04/2026"; Descricao = "Fix: .npmrc gravado via System.IO.File + UTF8 sem BOM + CRLF explicito" },
    [PSCustomObject]@{ Versao = "2.9.1"; Data = "24/04/2026"; Descricao = "Fix: Invoke-NpmInstallGlobal repara .npmrc do usuario efetivo antes do install" },
    [PSCustomObject]@{ Versao = "2.9.0"; Data = "24/04/2026"; Descricao = "Visual: dashboard com banner, fases numeradas, simbolos unicode e resumo final" },
    [PSCustomObject]@{ Versao = "2.9.0"; Data = "24/04/2026"; Descricao = "Visual: Show-Spinner para esperas longas, Write-Phase com contador N/Total" },
    [PSCustomObject]@{ Versao = "2.9.0"; Data = "24/04/2026"; Descricao = "Download: nova funcao Invoke-FastDownload via HttpClient (5-10x mais rapido)" },
    [PSCustomObject]@{ Versao = "2.9.0"; Data = "24/04/2026"; Descricao = "Download: barra de progresso visual com %, MB/s e ETA em tempo real" },
    [PSCustomObject]@{ Versao = "2.9.0"; Data = "24/04/2026"; Descricao = "Download: TLS 1.2/1.3 + ConnectionLimit 100 + buffer 1MB para throughput maximo" },
    [PSCustomObject]@{ Versao = "2.9.0"; Data = "24/04/2026"; Descricao = "Download: fallback automatico para Invoke-WebRequest se HttpClient falhar" },
    [PSCustomObject]@{ Versao = "2.8.1"; Data = "24/04/2026"; Descricao = "TS/UAC: PATH final grava direto em HKU do usuario real + Broadcast-EnvChange garantido" },
    [PSCustomObject]@{ Versao = "2.8.1"; Data = "24/04/2026"; Descricao = "TS/UAC: PATH inclui LocalAppData\Programs\Git\cmd para Git Bash user-scope" },
    [PSCustomObject]@{ Versao = "2.8.1"; Data = "24/04/2026"; Descricao = "Git Bash: varre varios locais e detecta instalacao em escopo do admin elevado (local errado em TS)" },
    [PSCustomObject]@{ Versao = "2.8.1"; Data = "24/04/2026"; Descricao = "Git Bash: quando em local errado, reinstala em %LOCALAPPDATA%\Programs\Git do usuario real via /CURRENTUSER" },
    [PSCustomObject]@{ Versao = "2.8.1"; Data = "24/04/2026"; Descricao = "Git Bash: nova instalacao em TS usa /CURRENTUSER para evitar exigir admin" },
    [PSCustomObject]@{ Versao = "2.8.0"; Data = "24/04/2026"; Descricao = "TS/UAC: detecta usuario interativo real (dono do explorer.exe) via WMI e registro" },
    [PSCustomObject]@{ Versao = "2.8.0"; Data = "24/04/2026"; Descricao = "TS/UAC: npm install -g --prefix forcado para APPDATA do usuario real, nao do admin elevado" },
    [PSCustomObject]@{ Versao = "2.8.0"; Data = "24/04/2026"; Descricao = "TS/UAC: PATH e env vars gravadas em HKU:\SID\Environment do usuario real" },
    [PSCustomObject]@{ Versao = "2.8.0"; Data = "24/04/2026"; Descricao = "TS/UAC: Test-Path agora usa perfil do usuario real em todas as checagens" },
    [PSCustomObject]@{ Versao = "2.8.0"; Data = "24/04/2026"; Descricao = "TS/UAC: notificacao de mudanca de ambiente via WM_SETTINGCHANGE apos gravar env vars" },
    [PSCustomObject]@{ Versao = "2.7.0"; Data = "24/04/2026"; Descricao = "Servidor: cache de tentativa de instalacao do Node.js (evita loop de 3 reinstalacoes)" },
    [PSCustomObject]@{ Versao = "2.7.0"; Data = "24/04/2026"; Descricao = "Servidor: deteccao de npm via Get-Command (substitui try/catch instavel em PS 5.1)" },
    [PSCustomObject]@{ Versao = "2.7.0"; Data = "24/04/2026"; Descricao = "Servidor: recarrega PATH de Machine+User apos MSI do Node.js" },
    [PSCustomObject]@{ Versao = "2.7.0"; Data = "24/04/2026"; Descricao = "Servidor: nao tenta criar diretorios protegidos como C:\Program Files\nodejs" },
    [PSCustomObject]@{ Versao = "2.7.0"; Data = "24/04/2026"; Descricao = "Servidor: deteccao de ProductType via CIM (fallback WMI) mais robusta" },
    [PSCustomObject]@{ Versao = "2.7.0"; Data = "24/04/2026"; Descricao = "Install-NodeJS: aguarda MSI, sonda npm por ate 15s antes de desistir" },
    [PSCustomObject]@{ Versao = "2.6.0"; Data = "09/04/2026"; Descricao = "Diagnostico executa apenas ferramentas com acao pendente, nao todas as selecionadas" },
    [PSCustomObject]@{ Versao = "2.5.0"; Data = "09/04/2026"; Descricao = "Remocao CLI: limpeza de variaveis de ambiente (CLAUDE_CODE_GIT_BASH_PATH etc)" },
    [PSCustomObject]@{ Versao = "2.5.0"; Data = "09/04/2026"; Descricao = "Remocao CLI: busca ampla por executavel em todos os locais conhecidos" },
    [PSCustomObject]@{ Versao = "2.5.0"; Data = "09/04/2026"; Descricao = "Remocao CLI: limpeza de entradas do PATH apos remocao" },
    [PSCustomObject]@{ Versao = "2.4.0"; Data = "09/04/2026"; Descricao = "Remocao melhorada: verifica resultado e tenta metodos alternativos" },
    [PSCustomObject]@{ Versao = "2.4.0"; Data = "09/04/2026"; Descricao = "Remocao Claude Code: 4 metodos (winget, npm, binario nativo, pasta npm)" },
    [PSCustomObject]@{ Versao = "2.4.0"; Data = "09/04/2026"; Descricao = "Remocao Claude Desktop: usa Update.exe nativo como primeiro metodo" },
    [PSCustomObject]@{ Versao = "2.3.0"; Data = "09/04/2026"; Descricao = "Diagnostico aplicado em todas as opcoes de instalacao" },
    [PSCustomObject]@{ Versao = "2.3.0"; Data = "09/04/2026"; Descricao = "Diagnostico refatorado como funcao reutilizavel Invoke-Diagnostico" },
    [PSCustomObject]@{ Versao = "2.2.2"; Data = "09/04/2026"; Descricao = "npm instalado sempre no perfil do usuario logado mesmo rodando como admin" },
    [PSCustomObject]@{ Versao = "2.2.1"; Data = "09/04/2026"; Descricao = "npm prefix forcado para perfil do usuario correto ao rodar como Administrador" },
    [PSCustomObject]@{ Versao = "2.2.0"; Data = "09/04/2026"; Descricao = "Opcao 1 Tudo: diagnostico completo antes de instalar/atualizar" },
    [PSCustomObject]@{ Versao = "2.2.0"; Data = "09/04/2026"; Descricao = "Diagnostico exibe status de cada ferramenta com versao atual e disponivel" },
    [PSCustomObject]@{ Versao = "2.1.2"; Data = "09/04/2026"; Descricao = "Deteccao Codex Desktop: triplo fallback via ID, lista geral e AppxPackage" },
    [PSCustomObject]@{ Versao = "2.1.1"; Data = "09/04/2026"; Descricao = "Corrigida deteccao de Codex Desktop e OpenCode Desktop ja instalados" },
    [PSCustomObject]@{ Versao = "2.1.0"; Data = "09/04/2026"; Descricao = "Corrigido bug C:\Program1: /DIR do Git Bash agora usa aspas para caminhos com espacos" },
    [PSCustomObject]@{ Versao = "2.1.0"; Data = "09/04/2026"; Descricao = "Melhorada deteccao do Git: busca em mais caminhos e no registro do Windows" },
    [PSCustomObject]@{ Versao = "2.1.0"; Data = "09/04/2026"; Descricao = "Auto-elevacao compativel com execucao via irm | iex (GitHub) e arquivo local" },
    [PSCustomObject]@{ Versao = "2.1.0"; Data = "09/04/2026"; Descricao = "Corrigido erro de sintaxe PS5: operador ?. substituido por compativel com PS5" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Menu principal com opcoes Instalar e Remover" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Adicionado OpenCode Desktop (SST.OpenCodeDesktop via winget)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Deteccao automatica de ambiente servidor (ProductType) para Claude Code" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Claude Code instalado via npm em servidores/VMs (evita crash do Bun sem AVX)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Node.js instalado com ALLUSERS=1 (disponivel para todos os usuarios)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "PATH corrigido: adiciona %APPDATA%\npm e %ProgramFiles%\nodejs automaticamente" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Deteccao de instalacao via winget list (mais confiavel que winget upgrade)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Mensagens de Desktop corrigidas: instrui pesquisar no Menu Iniciar" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Auto-elevacao: script se reinicia como Administrador se necessario" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Mensagem final diferenciada: CLI vs Desktop vs ambos" },
    [PSCustomObject]@{ Versao = "1.0.0"; Data = "07/04/2026"; Descricao = "Versao inicial: Claude Code, Codex CLI, OpenCode, Claude Desktop, Codex Desktop" },
    [PSCustomObject]@{ Versao = "1.0.0"; Data = "07/04/2026"; Descricao = "Instalacao silenciosa via winget com fallback por download direto" },
    [PSCustomObject]@{ Versao = "1.0.0"; Data = "07/04/2026"; Descricao = "Verificacao e atualizacao automatica de versoes instaladas" },
    [PSCustomObject]@{ Versao = "1.0.0"; Data = "07/04/2026"; Descricao = "Suporte a Git Bash como pre-requisito do Claude Code" }
)

# ----------------------------------------------------------
# Dependencias externas
# ----------------------------------------------------------

# ----------------------------------------------------------
# CATALOGO DE PACOTES - metadados centralizados
# (foundation para futura externalizacao em packages.json)
# Cada entrada descreve uma ferramenta com seus identificadores
# em diferentes gerenciadores. Use $script:PACKAGES['ClaudeCLI']
# para acessar.
# ----------------------------------------------------------
$script:PACKAGES = @{
    'Git' = @{
        DisplayName  = 'Git Bash'
        Type         = 'Installer'  # MSI/EXE direto
        Cmd          = 'git'
        WingetId     = 'Git.Git'
        Url          = 'https://github.com/git-for-windows/git/releases/latest'
        Required     = $true   # pre-requisito do Claude Code
    }
    'ClaudeCLI' = @{
        DisplayName  = 'Claude Code'
        Type         = 'Native'
        Cmd          = 'claude'
        NpmName      = '@anthropic-ai/claude-code'
        WingetId     = 'Anthropic.ClaudeCode'
        Required     = $false
    }
    'CodexCLI' = @{
        DisplayName  = 'Codex CLI'
        Type         = 'Npm'
        Cmd          = 'codex'
        NpmName      = '@openai/codex'
        WingetId     = $null
        Required     = $false
    }
    'OpenCode' = @{
        DisplayName  = 'OpenCode'
        Type         = 'Npm'
        Cmd          = 'opencode'
        NpmName      = 'opencode-ai'
        WingetId     = $null
        Required     = $false
    }
    'ClaudeDesk' = @{
        DisplayName  = 'Claude Desktop'
        Type         = 'Appx'
        AppxName     = '*Claude*'
        WingetId     = 'Anthropic.Claude'
        Required     = $false
    }
    'CodexDesk' = @{
        DisplayName  = 'ChatGPT/Codex Desktop'
        Type         = 'AppxStore'
        StoreId      = '9PLM9XGG6VKS'
        AppxName     = '*Codex*'
        Required     = $false
    }
    'OpenDesk' = @{
        DisplayName  = 'OpenCode Desktop'
        Type         = 'Winget'
        WingetId     = 'SST.OpenCodeDesktop'
        Required     = $false
    }
}

# Garante que a janela nunca feche sozinha
try {


# ----------------------------------------------------------
# Encoding: troca UTF-8 e habilita sequencias ANSI/VT no terminal
# ----------------------------------------------------------
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

try {
    $sig = @"
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
"@
    $k32    = Add-Type -MemberDefinition $sig -Name "K32VT" -Namespace "Win32" -PassThru
    $handle = [Win32.K32VT]::GetStdHandle(-11)
    $mode   = 0
    [Win32.K32VT]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    [Win32.K32VT]::SetConsoleMode($handle, ($mode -bor 0x0004)) | Out-Null
} catch { <# silencioso se nao suportado #> }

# ----------------------------------------------------------
# PRE-FLIGHT: detecta capacidades do ambiente
# (PS, .NET, HttpClient, Console UTF-8/VT/redirect, Proxy, IsServer/TS)
# Permite que o script funcione em qualquer computador, com fallbacks.
# ----------------------------------------------------------
$script:Compat = [PSCustomObject]@{
    PSVersion       = $PSVersionTable.PSVersion
    PSMajor         = $PSVersionTable.PSVersion.Major
    PSEdition       = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { "Desktop" }
    DotNetVersion   = $null
    HttpClient      = $false
    CimAvail        = $false
    WmiAvail        = $false
    ConsoleUTF8     = $false
    ConsoleVT       = $false
    ConsoleRedir    = $false
    UnicodeOk       = $false
    HasProxy        = $false
    ProxyAddress    = $null
    IsServer        = $false
    IsTerminalSrv   = $false
    Is64bit         = [Environment]::Is64BitOperatingSystem
    OsCaption       = $null
}

# .NET Framework version
try {
    $rel = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name Release -ErrorAction Stop
    $script:Compat.DotNetVersion = $rel.Release
} catch { }

# HttpClient (precisa de System.Net.Http.dll - normalmente .NET 4.5+)
try {
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $script:Compat.HttpClient = [bool]([type]"System.Net.Http.HttpClient")
} catch { $script:Compat.HttpClient = $false }

# CIM/WMI availability
try { $null = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop; $script:Compat.CimAvail = $true } catch { }
try { $null = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop; $script:Compat.WmiAvail = $true } catch { }

# Console: redirected, UTF-8, VT
try { $script:Compat.ConsoleRedir = ([Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) } catch { }
try { $script:Compat.ConsoleUTF8  = ([Console]::OutputEncoding.WebName -match 'utf-?8') } catch { }
try {
    if (-not $script:Compat.ConsoleRedir) {
        # Probe VT support: se o GetConsoleMode setou 0x0004 com sucesso anteriormente, o terminal aceita VT
        $h = [Win32.K32VT]::GetStdHandle(-11)
        $m = 0
        if ([Win32.K32VT]::GetConsoleMode($h, [ref]$m)) {
            $script:Compat.ConsoleVT = (($m -band 0x0004) -ne 0)
        }
    }
} catch { }

# Unicode rendering: usar simbolos Unicode somente se console for UTF-8 E nao redirecionado
$script:Compat.UnicodeOk = ($script:Compat.ConsoleUTF8 -and (-not $script:Compat.ConsoleRedir))

# Proxy (sistema)
try {
    $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $testUri = [Uri]"https://registry.npmjs.org"
    $resolved = $proxy.GetProxy($testUri)
    if ($resolved -and $resolved.AbsoluteUri -ne $testUri.AbsoluteUri) {
        $script:Compat.HasProxy = $true
        $script:Compat.ProxyAddress = $resolved.AbsoluteUri
    }
} catch { }

# OS type: Server vs Workstation, Terminal Services
try {
    if ($script:Compat.CimAvail) {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    } elseif ($script:Compat.WmiAvail) {
        $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
    }
    if ($os) {
        $script:Compat.OsCaption = $os.Caption
        # ProductType: 1=Workstation, 2=DC, 3=Server
        $script:Compat.IsServer = ($os.ProductType -ne 1)
    }
} catch { }
try {
    # Terminal Services session: SESSIONNAME comeca com RDP-Tcp ou nao e Console
    if ($env:SESSIONNAME -and ($env:SESSIONNAME -ne "Console")) {
        $script:Compat.IsTerminalSrv = $true
    }
} catch { }

# --- Wrapper seguro para [Console]::Write (evita erro quando saida e redirecionada) ---
function Write-ConsoleSafe {
    param([string]$Text)
    if ($script:Compat.ConsoleRedir) {
        try { [Console]::Out.Write($Text) } catch { Write-Host $Text -NoNewline }
    } else {
        try { [Console]::Write($Text) } catch { Write-Host $Text -NoNewline }
    }
}

# --- Cores para output (visual dashboard) ---
$script:PhaseCurrent    = 0
$script:PhaseTotal      = 0
$script:ScriptStartTime = $null
$script:InstallResults  = @()  # resumo final
$script:OperationFailures = @{}
$script:StartupHealthFindings = @()

# Caracteres: usa Unicode quando suportado, ASCII como fallback (Windows 7/CMD legado/PS sem UTF-8)
if ($script:Compat.UnicodeOk) {
    $script:SymOk     = [char]0x2713  # ✓
    $script:SymFail   = [char]0x2717  # ✗
    $script:SymWarn   = [char]0x26A0  # ⚠
    $script:SymStep   = [char]0x25B6  # ▶
    $script:SymInfo   = [char]0x2139  # ℹ
    $script:SymBullet = [char]0x2022  # •
    $script:SymUp     = [char]0x2191  # ↑ (atualizado)
    $script:SymDown   = [char]0x2193  # ↓
    # Box drawing arredondado (cantos suaves, padrao moderno: spinner npm/cargo)
    $script:BoxTL     = [char]0x256D  # ╭
    $script:BoxTR     = [char]0x256E  # ╮
    $script:BoxBL     = [char]0x2570  # ╰
    $script:BoxBR     = [char]0x256F  # ╯
    $script:BoxH      = [char]0x2500  # ─
    $script:BoxV      = [char]0x2502  # │
    # Blocos para progress bar (gradient natural cheio -> medio -> leve -> vazio)
    $script:BarFull   = [char]0x2588  # █
    $script:BarMid    = [char]0x2593  # ▓
    $script:BarLow    = [char]0x2592  # ▒
    $script:BarEmpty  = [char]0x2591  # ░
    # Spinner Braille (padrao npm, cargo, deno, pip)
    $script:SpinnerFrames = @(
        [char]0x280B, [char]0x2819, [char]0x2839, [char]0x2838,
        [char]0x283C, [char]0x2834, [char]0x2826, [char]0x2827,
        [char]0x2807, [char]0x280F
    )
} else {
    $script:SymOk     = '+'
    $script:SymFail   = 'X'
    $script:SymWarn   = '!'
    $script:SymStep   = '>'
    $script:SymInfo   = 'i'
    $script:SymBullet = '*'
    $script:SymUp     = '^'
    $script:SymDown   = 'v'
    $script:BoxTL     = '+'
    $script:BoxTR     = '+'
    $script:BoxBL     = '+'
    $script:BoxBR     = '+'
    $script:BoxH      = '-'
    $script:BoxV      = '|'
    $script:BarFull   = '#'
    $script:BarMid    = '='
    $script:BarLow    = '-'
    $script:BarEmpty  = '.'
    $script:SpinnerFrames = @('|','/','-','\')
}

function Start-Dashboard {
    param([int]$TotalPhases = 0)
    $script:PhaseCurrent    = 0
    $script:PhaseTotal      = $TotalPhases
    $script:ScriptStartTime = Get-Date
    $script:InstallResults  = @()
    $script:OperationFailures = @{}
    $script:StartupHealthFindings = @()
}

function Set-PreferredConsoleSize {
    param([int]$Width = 140, [int]$Height = 42)

    try {
        $raw = $Host.UI.RawUI
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
    } catch { }
}

function Write-Banner {
    Set-PreferredConsoleSize
    try { Clear-Host } catch { }
    Write-Host ""
    Write-Host "  I A   T O O L S   I N S T A L L E R" -ForegroundColor White
    Write-Host ("  Claude | Codex | OpenCode | v{0}" -f $SCRIPT_VERSION) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-CompactHeader {
    param([Parameter(Mandatory)][string]$Title)

    Set-PreferredConsoleSize
    try { Clear-Host } catch { }
    Write-Host ""
    Write-Host "  I A   T O O L S   I N S T A L L E R" -ForegroundColor White
    Write-Host ("  {0} | v{1}" -f $Title, $SCRIPT_VERSION) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Phase {
    param([string]$Title)
    $script:PhaseCurrent++
    $prefix = if ($script:PhaseTotal -gt 0) { "[$($script:PhaseCurrent)/$($script:PhaseTotal)]" } else { "[$($script:PhaseCurrent)]" }
    $elapsed = if ($script:ScriptStartTime) { "  " + $script:SymBullet + "  " + ((Get-Date) - $script:ScriptStartTime).ToString("mm\:ss") + " transcorridos" } else { "" }

    $title = "FASE $prefix  $Title"
    if ($title.Length -gt 58) { $title = $title.Substring(0, 58) }
    $titleLine = $title.PadRight(58)

    $hLine = ([string]$script:BoxH) * 59

    Write-Host ""
    Write-Host ("  $($script:BoxTL)$hLine$($script:BoxTR)") -ForegroundColor DarkCyan
    Write-Host ("  $($script:BoxV) {0} $($script:BoxV)" -f $titleLine) -ForegroundColor Cyan
    if ($elapsed) {
        $elapsedLine = $elapsed.PadRight(58)
        if ($elapsedLine.Length -gt 58) { $elapsedLine = $elapsedLine.Substring(0,58) }
        Write-Host ("  $($script:BoxV) {0} $($script:BoxV)" -f $elapsedLine) -ForegroundColor DarkGray
    }
    Write-Host ("  $($script:BoxBL)$hLine$($script:BoxBR)") -ForegroundColor DarkCyan
}

function Write-Step  { param($msg) Write-Host ("  {0} {1}" -f $script:SymStep, $msg) -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host ("  {0} {1}" -f $script:SymOk,   $msg) -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host ("  {0} {1}" -f $script:SymWarn, $msg) -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host ("  {0} {1}" -f $script:SymFail, $msg) -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host ("  {0} {1}" -f $script:SymInfo, $msg) -ForegroundColor Gray }

function Show-Spinner {
    param([ScriptBlock]$Action, [string]$Message = "Processando...", [int]$TimeoutSec = 300)
    # Frames Braille (Unicode) com fallback ASCII vindos de $script:SpinnerFrames
    $chars = $script:SpinnerFrames
    $i = 0
    $job = Start-Job -ScriptBlock $Action
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    # Velocidade ajustada: Braille e suave em ~80ms/frame, ASCII em 120ms
    $delay = if ($script:Compat.UnicodeOk) { 80 } else { 120 }
    while ($job.State -eq 'Running' -and (Get-Date) -lt $deadline) {
        $c = $chars[$i % $chars.Length]
        $line = "  $c  $Message"
        if (-not $script:Compat.ConsoleRedir) {
            try { [Console]::Write("`r" + $line.PadRight(80)) } catch { Write-Host $line }
        } else {
            # Em saida redirecionada, imprime so a primeira vez para nao poluir log
            if ($i -eq 0) { Write-Host $line }
        }
        Start-Sleep -Milliseconds $delay
        $i++
    }
    if (-not $script:Compat.ConsoleRedir) {
        try { [Console]::Write("`r" + (" " * 80) + "`r") } catch { }
    }
    if ($job.State -eq 'Running') {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-Fail "Timeout aguardando operacao."
        return $null
    }
    $result = Receive-Job $job -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
    return $result
}

function Get-NpmCommandPath {
    try {
        $cmd = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd -and $cmd.Source) { return $cmd.Source }
    } catch { }
    return $null
}

function Invoke-ProcessProbe {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string]$Arguments = '--version',
        [int]$TimeoutSec = 12
    )

    $result = [ordered]@{
        Success  = $false
        ExitCode = $null
        Output   = ''
        Error    = ''
        TimedOut = $false
    }

    try {
        if (-not (Test-Path -LiteralPath $FilePath -ErrorAction SilentlyContinue)) {
            $result.Error = "Arquivo nao encontrado: $FilePath"
            return [PSCustomObject]$result
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $extension = [System.IO.Path]::GetExtension($FilePath)
        if ($extension -in @('.cmd', '.bat')) {
            $comspec = $env:ComSpec
            if (-not $comspec -or -not (Test-Path -LiteralPath $comspec -ErrorAction SilentlyContinue)) {
                $comspec = Join-Path $env:SystemRoot 'System32\cmd.exe'
            }
            $psi.FileName = $comspec
            $psi.Arguments = "/d /s /c `"`"$FilePath`" $Arguments`""
        } else {
            $psi.FileName = $FilePath
            $psi.Arguments = $Arguments
        }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $result.TimedOut = $true
            $result.Error = "Timeout depois de $TimeoutSec segundos."
            try { $proc.Kill() } catch { }
            return [PSCustomObject]$result
        }

        $result.ExitCode = $proc.ExitCode
        $result.Output = $proc.StandardOutput.ReadToEnd().Trim()
        $result.Error = $proc.StandardError.ReadToEnd().Trim()
        $result.Success = ($proc.ExitCode -eq 0)
    } catch {
        $result.Error = $_.Exception.Message
    }

    return [PSCustomObject]$result
}

function Invoke-PowerShellCommandProbe {
    param(
        [Parameter(Mandatory=$true)][string]$CommandName,
        [int]$TimeoutSec = 15
    )

    $shellExe = if ($PSVersionTable.PSEdition -eq 'Core') {
        Join-Path $PSHOME 'pwsh.exe'
    } else {
        Join-Path $PSHOME 'powershell.exe'
    }
    if (-not (Test-Path -LiteralPath $shellExe -ErrorAction SilentlyContinue)) {
        $shellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    try {
        $resolved = Get-Command $CommandName -CommandType Application,ExternalScript -ErrorAction Stop | Select-Object -First 1
        if (-not $resolved -or -not $resolved.Source) { throw "Comando nao resolvido: $CommandName" }

        $source = $resolved.Source
        if ([System.IO.Path]::GetExtension($source) -ieq '.ps1') {
            $quotedSource = '"' + ($source -replace '"','\"') + '"'
            return Invoke-ProcessProbe -FilePath $shellExe -Arguments "-NoLogo -NoProfile -NonInteractive -File $quotedSource --version" -TimeoutSec $TimeoutSec
        }

        return Invoke-ProcessProbe -FilePath $source -Arguments '--version' -TimeoutSec $TimeoutSec
    } catch {
        return [PSCustomObject]@{
            Success  = $false
            ExitCode = -1
            TimedOut = $false
            Output   = ''
            Error    = $_.Exception.Message
        }
    }
}

function Invoke-NpmConfigValueSafe {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('prefix','cache')][string]$Name,
        [int]$TimeoutSec = 4
    )

    try {
        $npmCmd = Get-NpmCommandPath
        if (-not $npmCmd) { return '' }
        $probe = Invoke-ProcessProbe -FilePath $npmCmd -Arguments "config get $Name" -TimeoutSec $TimeoutSec
        if (-not $probe.Success) { return '' }
        return (($probe.Output -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1).Trim()
    } catch { }
    return ''
}

function Invoke-NpmPrefixSafe {
    param([int]$TimeoutSec = 4)
    return Invoke-NpmConfigValueSafe -Name 'prefix' -TimeoutSec $TimeoutSec
}
function Get-CliToolInfo {
    param(
        [Parameter(Mandatory=$true)][string]$Cmd,
        [string]$NpmPackage = ""
    )

    $u = Get-UsuarioInterativo
    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $cmdInfo = Get-Command $Cmd -ErrorAction SilentlyContinue
        if ($cmdInfo -and $cmdInfo.Source) { [void]$candidates.Add($cmdInfo.Source) }
    } catch { }
    $npmPrefix = Invoke-NpmPrefixSafe

    $baseDirs = @(
        "$($u.AppData)\npm",
        "$env:APPDATA\npm",
        "$npmPrefix",
        "$env:ProgramFiles\nodejs",
        "C:\ProgramData\npm",
        "$($u.UserProfile)\.local\bin",
        "$env:USERPROFILE\.local\bin",
        "$($u.LocalAppData)\Microsoft\WinGet\Links",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
        "$($u.LocalAppData)\Programs\Codex",
        "$env:LOCALAPPDATA\Programs\Codex"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($dir in $baseDirs) {
        foreach ($ext in @('.cmd', '.exe', '', '.ps1')) {
            [void]$candidates.Add((Join-Path $dir ($Cmd + $ext)))
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue)) { continue }

        $version = ""
        $commandOk = $false
        if ([System.IO.Path]::GetExtension($candidate) -ieq '.ps1') {
            # Shims npm .ps1 normalmente terminam com 'exit'. Testa em outro
            # processo para que esse exit nunca encerre o instalador principal.
            $probe = Invoke-PowerShellCommandProbe -CommandName $candidate
            $version = $probe.Output.Trim()
            $commandOk = ($probe.Success -and -not [string]::IsNullOrWhiteSpace($version))
        } else {
            try {
                $out = & $candidate --version 2>&1 | Out-String
                $version = $out.Trim()
                $commandOk = ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($version))
            } catch { }
        }

        if (-not $commandOk) { continue }

        return [PSCustomObject]@{
            Installed = $true
            Version   = $version
            Source    = $candidate
            Method    = 'command'
        }
    }

    if ($NpmPackage) {
        $npmPackagePath = $NpmPackage -replace '/', '\'
        $packageJsonCandidates = @(
            (Join-Path "$($u.AppData)\npm\node_modules" (Join-Path $npmPackagePath 'package.json')),
            (Join-Path "$env:APPDATA\npm\node_modules" (Join-Path $npmPackagePath 'package.json')),
            (Join-Path "$npmPrefix\node_modules" (Join-Path $npmPackagePath 'package.json')),
            (Join-Path "C:\ProgramData\npm\node_modules" (Join-Path $npmPackagePath 'package.json'))
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

        foreach ($packageJson in $packageJsonCandidates) {
            if (-not (Test-Path -LiteralPath $packageJson -ErrorAction SilentlyContinue)) { continue }
            try {
                $pkg = Get-Content -LiteralPath $packageJson -Raw -ErrorAction Stop | ConvertFrom-Json
                return [PSCustomObject]@{
                    Installed = $false
                    Version   = $pkg.version
                    Source    = $packageJson
                    Method    = 'broken-npm-package'
                }
            } catch {
                return [PSCustomObject]@{
                    Installed = $false
                    Version   = ""
                    Source    = $packageJson
                    Method    = 'broken-npm-package'
                }
            }
        }
    }

    return [PSCustomObject]@{
        Installed = $false
        Version   = ""
        Source    = ""
        Method    = ""
    }
}

function Get-CodexDesktopInfo {
    param([bool]$WingetOk = $false)

    if ($WingetOk) {
        foreach ($args in @(
            @('list','--id','9PLM9XGG6VKS','--exact','--accept-source-agreements'),
            @('list','--name','ChatGPT','--accept-source-agreements'),
            @('list','--name','Codex','--accept-source-agreements')
        )) {
            try {
                $output = & winget @args 2>&1 | Out-String
                if ($output -match '(?i)(9PLM9XGG6VKS|OpenAI\s+Codex|ChatGPT|Codex)' -and
                    $output -notmatch '(?i)(Nenhum pacote|No installed package|No package found|Nenhum pacote encontrado)') {
                    return [PSCustomObject]@{ Installed = $true; Version = ""; Source = 'winget'; Method = ($args -join ' ') }
                }
            } catch { }
        }
    }

    foreach ($allUsers in @($false)) {
        try {
            $packages = if ($allUsers) {
                Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            } else {
                Get-AppxPackage -ErrorAction SilentlyContinue
            }

            $pkg = $packages | Where-Object {
                $_.Name -match '(?i)(ChatGPT|Codex|OpenAI)' -or
                $_.PackageFullName -match '(?i)(ChatGPT|Codex|OpenAI)' -or
                $_.PackageFamilyName -match '(?i)(ChatGPT|Codex|OpenAI)' -or
                $_.InstallLocation -match '(?i)(ChatGPT|Codex|OpenAI)'
            } | Select-Object -First 1

            if ($pkg) {
                return [PSCustomObject]@{ Installed = $true; Version = $pkg.Version; Source = $pkg.PackageFullName; Method = 'appx' }
            }
        } catch { }
    }

    try {
        $startApp = Get-StartApps | Where-Object {
            $_.Name -match '(?i)(ChatGPT|Codex|OpenAI)' -or $_.AppID -match '(?i)(ChatGPT|Codex|OpenAI|9PLM9XGG6VKS)'
        } | Select-Object -First 1
        if ($startApp) {
            return [PSCustomObject]@{ Installed = $true; Version = ""; Source = $startApp.Name; Method = 'start-menu' }
        }
    } catch { }

    $u = Get-UsuarioInterativo
    $aliasCandidates = @(
        "$($u.LocalAppData)\Microsoft\WindowsApps\Codex.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\Codex.exe"
    ) | Select-Object -Unique

    foreach ($alias in $aliasCandidates) {
        if (Test-Path -LiteralPath $alias -ErrorAction SilentlyContinue) {
            return [PSCustomObject]@{ Installed = $true; Version = ""; Source = $alias; Method = 'windowsapps-alias' }
        }
    }

    $shortcutRoots = @(
        "$($u.AppData)\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($root in $shortcutRoots) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { continue }
        try {
            $lnk = Get-ChildItem -LiteralPath $root -Filter '*Codex*.lnk' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($lnk) {
                return [PSCustomObject]@{ Installed = $true; Version = ""; Source = $lnk.FullName; Method = 'start-menu-shortcut' }
            }
        } catch { }
    }

    $desktopDirs = @(
        "$($u.LocalAppData)\Programs\Codex",
        "$($u.LocalAppData)\Programs\OpenAI Codex",
        "$($u.LocalAppData)\Codex",
        "$($u.LocalAppData)\OpenAI\Codex",
        "$env:LOCALAPPDATA\Programs\Codex",
        "$env:LOCALAPPDATA\Programs\OpenAI Codex",
        "$env:ProgramFiles\Codex",
        "$env:ProgramFiles\OpenAI\Codex",
        "${env:ProgramFiles(x86)}\Codex",
        "${env:ProgramFiles(x86)}\OpenAI\Codex"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($dir in $desktopDirs) {
        if (-not (Test-Path -LiteralPath $dir -ErrorAction SilentlyContinue)) { continue }
        try {
            $exe = Get-ChildItem -LiteralPath $dir -Filter '*codex*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exe) {
                $version = ""
                try { $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe.FullName).ProductVersion } catch { }
                return [PSCustomObject]@{ Installed = $true; Version = $version; Source = $exe.FullName; Method = 'desktop-folder' }
            }
        } catch { }
        return [PSCustomObject]@{ Installed = $true; Version = ""; Source = $dir; Method = 'desktop-folder' }
    }

    return [PSCustomObject]@{ Installed = $false; Version = ""; Source = ""; Method = "" }
}
function Get-DesktopToolInfo {
    param(
        [string]$DisplayName,
        [string[]]$WingetIds = @(),
        [string[]]$NamePatterns = @(),
        [string[]]$AppxPatterns = @(),
        [string[]]$ExePatterns = @(),
        [string[]]$FolderCandidates = @(),
        [bool]$WingetOk = $false
    )

    if ($WingetOk) {
        foreach ($id in $WingetIds) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            try {
                $output = & winget list --id $id --exact --accept-source-agreements 2>&1 | Out-String
                if ($output -match [regex]::Escape($id) -and
                    $output -notmatch '(?i)(Nenhum pacote|No installed package|No package found|Nenhum pacote encontrado)') {
                    return [PSCustomObject]@{ Installed = $true; Version = ""; Source = 'winget'; Method = "winget list --id $id" }
                }
            } catch { }
        }

        foreach ($pattern in $NamePatterns) {
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            try {
                $output = & winget list --name $DisplayName --accept-source-agreements 2>&1 | Out-String
                if ($output -match $pattern -and
                    $output -notmatch '(?i)(Nenhum pacote|No installed package|No package found|Nenhum pacote encontrado)') {
                    return [PSCustomObject]@{ Installed = $true; Version = ""; Source = 'winget'; Method = "winget list --name $DisplayName" }
                }
            } catch { }
        }
    }

    foreach ($allUsers in @($false)) {
        try {
            $packages = if ($allUsers) { Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue } else { Get-AppxPackage -ErrorAction SilentlyContinue }
            foreach ($pattern in $AppxPatterns) {
                if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
                $pkg = $packages | Where-Object {
                    $_.Name -match $pattern -or
                    $_.PackageFullName -match $pattern -or
                    $_.PackageFamilyName -match $pattern -or
                    $_.InstallLocation -match $pattern
                } | Select-Object -First 1
                if ($pkg) {
                    return [PSCustomObject]@{ Installed = $true; Version = $pkg.Version; Source = $pkg.PackageFullName; Method = 'appx' }
                }
            }
        } catch { }
    }

    try {
        $startApp = Get-StartApps | Where-Object {
            $matched = $false
            foreach ($pattern in $NamePatterns) {
                if ($_.Name -match $pattern -or $_.AppID -match $pattern) { $matched = $true; break }
            }
            $matched
        } | Select-Object -First 1
        if ($startApp) {
            return [PSCustomObject]@{ Installed = $true; Version = ""; Source = $startApp.Name; Method = 'start-menu' }
        }
    } catch { }

    $u = Get-UsuarioInterativo
    $shortcutRoots = @(
        "$($u.AppData)\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($root in $shortcutRoots) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { continue }
        foreach ($pattern in $NamePatterns) {
            try {
                $lnk = Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match $pattern } | Select-Object -First 1
                if ($lnk) {
                    return [PSCustomObject]@{ Installed = $true; Version = ""; Source = $lnk.FullName; Method = 'start-menu-shortcut' }
                }
            } catch { }
        }
    }

    foreach ($dir in ($FolderCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $dir -ErrorAction SilentlyContinue)) { continue }
        foreach ($exePattern in $ExePatterns) {
            try {
                $exe = Get-ChildItem -LiteralPath $dir -Filter $exePattern -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($exe) {
                    $version = ""
                    try { $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe.FullName).ProductVersion } catch { }
                    return [PSCustomObject]@{ Installed = $true; Version = $version; Source = $exe.FullName; Method = 'desktop-folder' }
                }
            } catch { }
        }
        return [PSCustomObject]@{ Installed = $true; Version = ""; Source = $dir; Method = 'desktop-folder' }
    }

    return [PSCustomObject]@{ Installed = $false; Version = ""; Source = ""; Method = "" }
}

function Get-ClaudeDesktopInfo {
    param([bool]$WingetOk = $false)
    $u = Get-UsuarioInterativo
    Get-DesktopToolInfo -DisplayName 'Claude' -WingetIds @('Anthropic.Claude') -NamePatterns @('(?i)(Claude|Anthropic)') -AppxPatterns @('(?i)(Claude|Anthropic)') -ExePatterns @('*claude*.exe') -FolderCandidates @(
        "$($u.LocalAppData)\AnthropicClaude",
        "$env:LOCALAPPDATA\AnthropicClaude",
        "$($u.LocalAppData)\Programs\Claude",
        "$env:LOCALAPPDATA\Programs\Claude",
        "$env:ProgramFiles\Claude",
        "$env:ProgramFiles\Anthropic\Claude"
    ) -WingetOk $WingetOk
}

function Get-OpenCodeDesktopInfo {
    param([bool]$WingetOk = $false)
    $u = Get-UsuarioInterativo
    Get-DesktopToolInfo -DisplayName 'OpenCode' -WingetIds @('SST.OpenCodeDesktop') -NamePatterns @('(?i)(OpenCode|SST\.OpenCodeDesktop)') -AppxPatterns @('(?i)OpenCode') -ExePatterns @('*opencode*.exe') -FolderCandidates @(
        "$($u.LocalAppData)\OpenCode",
        "$env:LOCALAPPDATA\OpenCode",
        "$($u.LocalAppData)\Programs\OpenCode",
        "$env:LOCALAPPDATA\Programs\OpenCode",
        "$env:ProgramFiles\OpenCode",
        "${env:ProgramFiles(x86)}\OpenCode"
    ) -WingetOk $WingetOk
}

function Test-WingetUpgradeAvailable {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [string]$Source = ""
    )

    try {
        $args = @('list','--id',$Id,'--exact','--upgrade-available','--include-unknown','--accept-source-agreements','--disable-interactivity')
        if (-not [string]::IsNullOrWhiteSpace($Source)) { $args += @('--source',$Source) }
        $output = & winget @args 2>&1 | Out-String
        return ($output -match [regex]::Escape($Id))
    } catch {
        return $false
    }
}

function Add-InstallResult {
    param(
        [string]$Nome,
        [string]$Status,   # "OK", "FALHOU", "PULADO", "ATUALIZADO"
        [string]$Versao = "",
        [string]$Local = "",
        [string]$Obs = ""
    )
    $script:InstallResults += [PSCustomObject]@{
        Nome    = $Nome
        Status  = $Status
        Versao  = $Versao
        Local   = $Local
        Obs     = $Obs
    }
}

function Set-OperationFailure {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Reason
    )
    $script:OperationFailures[$Name] = $Reason
}

function Get-OperationFailure {
    param([Parameter(Mandatory=$true)][string]$Name)
    if ($script:OperationFailures.ContainsKey($Name)) { return $script:OperationFailures[$Name] }
    return $null
}

function Show-Summary {
    # Formata tempo total como "2m 34s" ou "34s" para leitura natural
    $elapsedSpan = if ($script:ScriptStartTime) { (Get-Date) - $script:ScriptStartTime } else { [TimeSpan]::Zero }
    $elapsedStr = if ($elapsedSpan.TotalMinutes -ge 1) {
        "{0}m {1}s" -f [int]$elapsedSpan.TotalMinutes, $elapsedSpan.Seconds
    } else {
        "{0}s" -f [int]$elapsedSpan.TotalSeconds
    }

    # Conta resultados por categoria
    $totOk     = @($script:InstallResults | Where-Object { $_.Status -in @('OK','ATUALIZADO') }).Count
    $totFail   = @($script:InstallResults | Where-Object { $_.Status -eq 'FALHOU' }).Count
    $totSkip   = @($script:InstallResults | Where-Object { $_.Status -eq 'PULADO' }).Count
    $totTotal  = @($script:InstallResults).Count

    # Header colorido conforme resultado geral
    $headerColor = if ($totFail -gt 0) { 'Red' } elseif ($totOk -eq $totTotal -and $totTotal -gt 0) { 'Green' } else { 'Yellow' }
    $headerLabel = if ($totFail -gt 0) { 'CONCLUIDO COM FALHAS' } elseif ($totTotal -gt 0) { 'TUDO CERTO' } else { 'NADA A FAZER' }

    $hLine = ([string]$script:BoxH) * 61

    Write-Host ""
    Write-Host ("  $($script:BoxTL)$hLine$($script:BoxTR)") -ForegroundColor Cyan
    # Linha 1: titulo + tempo total
    $linha1 = "  RESUMO DA INSTALACAO  (tempo total: $elapsedStr)".PadRight(61)
    if ($linha1.Length -gt 61) { $linha1 = $linha1.Substring(0, 61) }
    Write-Host ("  $($script:BoxV)$linha1$($script:BoxV)") -ForegroundColor White
    # Linha 2: status geral + contagem
    $linha2 = "  $($script:SymBullet) $headerLabel  ($totOk/$totTotal sucesso, $totFail falhas, $totSkip pulados)".PadRight(61)
    if ($linha2.Length -gt 61) { $linha2 = $linha2.Substring(0, 61) }
    Write-Host ("  $($script:BoxV)$linha2$($script:BoxV)") -ForegroundColor $headerColor
    Write-Host ("  $($script:BoxBL)$hLine$($script:BoxBR)") -ForegroundColor Cyan

    if (-not $script:InstallResults -or $script:InstallResults.Count -eq 0) {
        Write-Host "  (Nenhuma ferramenta processada)" -ForegroundColor DarkGray
    } else {
        Write-Host ""
        # Cabecalho da tabela
        Write-Host ("    {0,-18} {1,-14} {2}" -f "FERRAMENTA","STATUS","VERSAO / OBS") -ForegroundColor DarkGray
        $div = ([string]$script:BoxH) * 60
        Write-Host "    $div" -ForegroundColor DarkGray

        foreach ($r in $script:InstallResults) {
            # Badge colorido por status
            $badge   = ''
            $badgeColor = 'Yellow'
            switch ($r.Status) {
                'OK'         { $badge = "[$($script:SymOk) INSTALADO]"; $badgeColor = 'Green' }
                'ATUALIZADO' { $badge = "[$($script:SymUp) ATUALIZADO]"; $badgeColor = 'Cyan' }
                'PULADO'     { $badge = "[$($script:SymBullet) PULADO]";   $badgeColor = 'DarkGray' }
                'FALHOU'     { $badge = "[$($script:SymFail) FALHOU]";   $badgeColor = 'Red' }
                default      { $badge = "[$($r.Status)]" }
            }

            $obs = if ($r.Versao) { $r.Versao } elseif ($r.Obs) { $r.Obs } else { "" }
            if ($obs.Length -gt 32) { $obs = $obs.Substring(0,29) + "..." }
            $nome = $r.Nome
            if ($nome.Length -gt 18) { $nome = $nome.Substring(0,18) }

            # Linha em segmentos coloridos: nome (white) badge (color) obs (DarkGray)
            Write-Host ("    {0,-18} " -f $nome) -ForegroundColor White -NoNewline
            Write-Host ("{0,-14}" -f $badge)    -ForegroundColor $badgeColor -NoNewline
            Write-Host (" {0}" -f $obs)         -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

# ----------------------------------------------------------
# Invoke-FastDownload: download via HttpClient (5-10x mais rapido
# que Invoke-WebRequest), com barra de progresso visual
# (%, MB baixados/total, MB/s, ETA) e fallback automatico.
# ----------------------------------------------------------
function Invoke-FastDownload {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile,
        [string]$Label = "",
        [int]$BufferSize = 1048576,
        [int]$TimeoutSec = 600,
        [int]$MaxRetries = 3,
        [switch]$Silent
    )

    # Se HttpClient nao esta disponivel, marca para usar fallback IWR direto
    $usarFallbackDireto = (-not $script:Compat.HttpClient)

    # Garante TLS moderno (importante para GitHub/Microsoft)
    try {
        $tls = [Net.SecurityProtocolType]'Tls12'
        try { $tls = $tls -bor [Net.SecurityProtocolType]'Tls13' } catch { }
        [Net.ServicePointManager]::SecurityProtocol = $tls
    } catch { }
    try { [Net.ServicePointManager]::DefaultConnectionLimit = 100 } catch { }

    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    if (-not $Label) { $Label = Split-Path -Leaf $OutFile }

    $outDir = Split-Path -Parent $OutFile
    if ($outDir -and -not (Test-Path -LiteralPath $outDir -ErrorAction SilentlyContinue)) {
        try { New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop | Out-Null } catch { }
    }

    $handler = $null
    $client  = $null
    $response= $null
    $sourceStream = $null
    $targetStream = $null
    $ok = $false

    if ($usarFallbackDireto) {
        if (-not $Silent) { Write-Info "HttpClient indisponivel; usando Invoke-WebRequest." }
        # Pula bloco HttpClient inteiro: cai para fallback abaixo
    } else {

    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $true
        try { $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate } catch { }

        # Proxy do sistema (corporativo) se detectado
        if ($script:Compat.HasProxy) {
            try {
                $handler.UseProxy = $true
                $handler.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
                try { $handler.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials } catch { }
            } catch { }
        }

        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        try { $client.DefaultRequestHeaders.UserAgent.ParseAdd("ia-install/$SCRIPT_VERSION") } catch { }

        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "HTTP $([int]$response.StatusCode) $($response.ReasonPhrase)"
        }

        $totalBytes = -1L
        try { if ($response.Content.Headers.ContentLength) { $totalBytes = [long]$response.Content.Headers.ContentLength } } catch { }
        $totalMB = if ($totalBytes -gt 0) { [math]::Round($totalBytes / 1MB, 2) } else { 0 }

        $sourceStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $targetStream = [System.IO.File]::Create($OutFile)

        $buffer    = New-Object byte[] $BufferSize
        $totalRead = 0L
        $startTime = Get-Date
        $lastUpdate= $startTime

        if (-not $Silent) {
            Write-Host ""
            $tamStr = if ($totalMB -gt 0) { "($totalMB MB)" } else { "(tamanho desconhecido)" }
            Write-Host ("  {0}  Baixando: {1} {2}" -f $script:SymStep, $Label, $tamStr) -ForegroundColor Cyan
        }

        while ($true) {
            $read = $sourceStream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $targetStream.Write($buffer, 0, $read)
            $totalRead += $read

            if (-not $Silent) {
                $now = Get-Date
                if (($now - $lastUpdate).TotalMilliseconds -ge 120) {
                    $elapsedSec = ($now - $startTime).TotalSeconds
                    if ($elapsedSec -lt 0.001) { $elapsedSec = 0.001 }
                    $speedBps = $totalRead / $elapsedSec
                    $speedMBs = $speedBps / 1MB
                    $recMB    = [math]::Round($totalRead / 1MB, 2)

                    if ($totalBytes -gt 0) {
                        $percent = [math]::Min(100.0, ($totalRead * 100.0 / $totalBytes))
                        $barWidth = 28
                        $filled = [int][math]::Floor($barWidth * $percent / 100)
                        if ($filled -gt $barWidth) { $filled = $barWidth }
                        if ($filled -lt 0) { $filled = 0 }
                        # Bar com bloco solido + frame parcial (semi-cheio na fronteira) + vazio leve
                        # Resultado em Unicode: "█████▓░░░░"  (cheio - meio - vazio leve)
                        $partial = ''
                        $remaining = $barWidth - $filled
                        if ($remaining -gt 0 -and $percent -lt 100) {
                            # Calcula fracao do bloco seguinte (0-1)
                            $frac = ($barWidth * $percent / 100) - $filled
                            if ($frac -gt 0.66) {
                                $partial = [string]$script:BarMid       # ▓
                            } elseif ($frac -gt 0.33) {
                                $partial = [string]$script:BarLow       # ▒
                            } elseif ($frac -gt 0) {
                                $partial = [string]$script:BarEmpty     # ░
                            }
                            if ($partial) { $remaining-- }
                        }
                        $bar = ([string]$script:BarFull * $filled) + $partial + ([string]$script:BarEmpty * $remaining)
                        $etaSec = if ($speedBps -gt 0 -and $totalBytes -gt $totalRead) { [int](($totalBytes - $totalRead) / $speedBps) } else { 0 }
                        $etaStr = "{0:D2}:{1:D2}" -f ([int]([int]$etaSec / 60)), ([int]$etaSec % 60)
                        $line = "  [{0}] {1,5:N1}% | {2,7:N2}/{3,7:N2} MB | {4,5:N1} MB/s | ETA {5}" -f $bar, $percent, $recMB, $totalMB, $speedMBs, $etaStr
                    } else {
                        $line = ("  Recebido: {0,8:N2} MB | {1,5:N1} MB/s | {2,6:N1}s" -f $recMB, $speedMBs, $elapsedSec)
                    }

                    if (-not $script:Compat.ConsoleRedir) {
                        try { [Console]::Write("`r" + $line.PadRight(90)) } catch { }
                    }
                    $lastUpdate = $now
                }
            }
        }

        try { $targetStream.Flush() } catch { }

        if (-not $Silent) {
            $elapsedFinal = ((Get-Date) - $startTime).TotalSeconds
            if ($elapsedFinal -lt 0.001) { $elapsedFinal = 0.001 }
            $finalMB    = [math]::Round($totalRead / 1MB, 2)
            $finalSpeed = ($totalRead / $elapsedFinal) / 1MB
            if (-not $script:Compat.ConsoleRedir) {
                try { [Console]::Write("`r" + (" " * 90) + "`r") } catch { }
            }
            Write-Host ("  {0} Download concluido: {1:N2} MB em {2:N1}s ({3:N1} MB/s)" -f $script:SymOk, $finalMB, $elapsedFinal, $finalSpeed) -ForegroundColor Green
        }
        $ok = $true
    }
    catch {
        if (-not $Silent) {
            if (-not $script:Compat.ConsoleRedir) {
                try { [Console]::Write("`r" + (" " * 90) + "`r") } catch { }
            }
            Write-Warn "Download rapido falhou: $($_.Exception.Message)"
            Write-Info "Tentando fallback via Invoke-WebRequest..."
        }
    }
    finally {
        if ($targetStream) { try { $targetStream.Dispose() } catch { } }
        if ($sourceStream) { try { $sourceStream.Dispose() } catch { } }
        if ($response)     { try { $response.Dispose() }     catch { } }
        if ($client)       { try { $client.Dispose() }       catch { } }
        if ($handler)      { try { $handler.Dispose() }      catch { } }
        $ProgressPreference = $oldProgress
    }

    } # fim do bloco HttpClient (else de $usarFallbackDireto)

    if (-not $ok) {
        # Fallback com retry e exponential backoff
        $ProgressPreference = 'SilentlyContinue'
        for ($tentativa = 1; $tentativa -le $MaxRetries; $tentativa++) {
            try {
                if ($script:Compat.HasProxy) {
                    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing `
                        -Proxy $script:Compat.ProxyAddress -ProxyUseDefaultCredentials -ErrorAction Stop
                } else {
                    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
                }
                if (-not $Silent) { Write-Ok "Download concluido via fallback." }
                $ok = $true
                break
            } catch {
                if ($tentativa -lt $MaxRetries) {
                    $espera = [Math]::Pow(2, $tentativa)  # 2s, 4s, 8s
                    if (-not $Silent) { Write-Warn "Tentativa $tentativa falhou. Aguardando $espera s..." }
                    Start-Sleep -Seconds $espera
                } else {
                    if (-not $Silent) { Write-Fail "Falha no download apos $MaxRetries tentativas: $($_.Exception.Message)" }
                    $ok = $false
                }
            }
        }
        $ProgressPreference = $oldProgress
    }

    return $ok
}

<#
.SYNOPSIS
    Pausa entre etapas para leitura humana. No-op em modo nao-interativo.
.PARAMETER Seconds
    Segundos a aguardar (default 3).
#>
function Wait-Readable {
    param([int]$Seconds = 3)
    if ($script:NonInteractive) { return }
    Start-Sleep -Seconds $Seconds
}
# Alias retrocompat
Set-Alias -Name Pause-Readable -Value Wait-Readable -Scope Script -ErrorAction SilentlyContinue

<#
.SYNOPSIS
    Confirmacao por tecla. ENTER=sim, ESC=nao. Em modo Silent retorna $true automaticamente.
.PARAMETER Mensagem
    Texto do prompt.
.OUTPUTS
    [bool] $true para confirmar, $false para cancelar.
#>
function Clear-KeyBuffer {
    try {
        while ([Console]::KeyAvailable) {
            [void][Console]::ReadKey($true)
        }
    } catch { }
}
function Confirm-Tecla {
    [CmdletBinding()]
    param([string]$Mensagem)

    # Modo nao-interativo: assume sim
    if ($script:NonInteractive) {
        Write-Verbose "[NonInteractive] Auto-confirmando: $Mensagem"
        return $true
    }

    Clear-KeyBuffer


    Write-Host "  $Mensagem [ENTER = sim | ESC = nao] " -ForegroundColor White -NoNewline
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') {
            Write-Host "Sim" -ForegroundColor Green
            return $true
        }
        if ($key.Key -eq 'Escape') {
            Write-Host "Nao" -ForegroundColor Gray
            return $false
        }
    }
}

# --- Verifica suporte AVX no processador ---
function Test-AVXSupport {
    try {
        $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
        # Tenta detectar AVX via registros do processador
        $avxTest = [System.Runtime.Intrinsics.X86.Avx]::IsSupported
        return $avxTest
    } catch {
        return $false
    }
}

# ----------------------------------------------------------
# USUARIO REAL (interativo) vs admin elevado via UAC
# Em TS/Terminal Server, o usuario comum roda o script e o UAC
# sobe a janela como outra conta (ex.: admif). Precisamos instalar
# tudo no perfil do usuario REAL, nao do admin elevado.
# ----------------------------------------------------------
$script:UsuarioReal = $null

<#
.SYNOPSIS
    Retorna dados do usuario interativo real (dono da sessao do explorer.exe).
.DESCRIPTION
    Em cenario UAC com outro usuario (TS: usuario comum roda o script e UAC
    sobe a janela como admif), o $env:USERNAME e o admin elevado. Esta funcao
    detecta o REAL usuario via WMI Win32_Process.GetOwner() do explorer.exe
    e retorna SID, perfil, AppData, etc. Resultado e cacheado em $script:UsuarioReal.
.OUTPUTS
    PSCustomObject com:
      Username, Domain, Sid, UserProfile, AppData, LocalAppData,
      ElevadoComOutroUsr (bool: indica se UAC foi com outra conta)
.EXAMPLE
    $u = Get-UsuarioInterativo
    if ($u.ElevadoComOutroUsr) { Write-Warn "UAC com outro usuario detectado" }
#>
function Get-UsuarioInterativo {
    [CmdletBinding()]
    param()
    # Usa cache ($script:UsuarioReal) para nao repetir a query
    if ($null -ne $script:UsuarioReal) { return $script:UsuarioReal }

    # Valores padrao: usuario atual (processo em execucao)
    $info = [PSCustomObject]@{
        Username           = $env:USERNAME
        Domain             = $env:USERDOMAIN
        Sid                = $null
        UserProfile        = $env:USERPROFILE
        AppData            = $env:APPDATA
        LocalAppData       = $env:LOCALAPPDATA
        ElevadoComOutroUsr = $false  # true se admif elevou sobre bi01
    }

    try {
        # Considera somente o Explorer da mesma sessao do processo. Em Terminal
        # Server podem existir varios explorer.exe; usar o primeiro apontaria
        # instalacoes e PATH para outro usuario conectado.
        $currentSessionId = (Get-Process -Id $PID -ErrorAction Stop).SessionId
        $procs = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe' AND SessionId=$currentSessionId" -ErrorAction Stop
        foreach ($p in $procs) {
            try {
                $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop
            } catch {
                $owner = $null
            }
            if ($owner -and $owner.User -and $owner.ReturnValue -eq 0) {
                $realUser   = $owner.User
                $realDomain = $owner.Domain
                if ($realUser -and $realUser -ne $env:USERNAME) {
                    $info.Username           = $realUser
                    $info.Domain             = $realDomain
                    $info.ElevadoComOutroUsr = $true
                }
                break
            }
        }

        # Se usuario real e diferente do atual, resolve SID e paths do perfil
        if ($info.ElevadoComOutroUsr) {
            # Resolve SID
            try {
                $nt = if ($info.Domain) {
                    New-Object System.Security.Principal.NTAccount($info.Domain, $info.Username)
                } else {
                    New-Object System.Security.Principal.NTAccount($info.Username)
                }
                $info.Sid = $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
            } catch { }

            # Resolve caminho do perfil via ProfileList
            if ($info.Sid) {
                try {
                    $profKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($info.Sid)"
                    $profImg = (Get-ItemProperty -Path $profKey -Name ProfileImagePath -ErrorAction Stop).ProfileImagePath
                    # Expande variaveis como %SystemDrive%
                    $profImg = [Environment]::ExpandEnvironmentVariables($profImg)
                    if ($profImg -and (Test-Path -LiteralPath $profImg -ErrorAction SilentlyContinue)) {
                        $info.UserProfile  = $profImg
                        $info.AppData      = "$profImg\AppData\Roaming"
                        $info.LocalAppData = "$profImg\AppData\Local"
                    }
                } catch { }
            }
        }
    } catch {
        # Qualquer falha: fica com valores padrao (processo atual)
    }

    $script:UsuarioReal = $info
    return $info
}

<#
.SYNOPSIS
    Grava uma variavel de ambiente no hive do usuario real (UAC-aware).
.DESCRIPTION
    Em cenario UAC com outra conta, escreve em HKU:\<SID>\Environment do usuario
    interativo (dono do explorer.exe), nao no ramo do admin elevado. Carrega o
    NTUSER.DAT do usuario via reg load se necessario.
.PARAMETER Name
    Nome da variavel (ex.: "Path", "CLAUDE_CODE_GIT_BASH_PATH").
.PARAMETER Value
    Valor a gravar.
.PARAMETER Append
    Se especificado, concatena ao valor existente usando ";" como separador
    e evita duplicar entradas iguais.
.EXAMPLE
    Set-UserEnvVar -Name "Path" -Value "$env:USERPROFILE\.local\bin" -Append
.OUTPUTS
    [bool] $true se gravou com sucesso.
#>
function Set-UserEnvVar {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Value,
        [switch]$Append
    )
    $u = Get-UsuarioInterativo

    if (-not $u.ElevadoComOutroUsr -or -not $u.Sid) {
        try {
            # Cenario normal: grava no ramo do usuario atual
            if ($Append) {
                $existing = [Environment]::GetEnvironmentVariable($Name, "User")
                if ($existing -and ($existing -split ";" | Where-Object { $_ -ieq $Value })) {
                    return $true  # ja presente, nao duplica
                }
                $new = if ($existing) { "$($existing.TrimEnd(';'));$Value" } else { $Value }
                [Environment]::SetEnvironmentVariable($Name, $new, "User")
            } else {
                [Environment]::SetEnvironmentVariable($Name, $Value, "User")
            }
            return $true
        } catch {
            return $false
        }
    }

    # Cenario TS/UAC: grava no hive do usuario real
    $hiveRoot   = "Registry::HKEY_USERS\$($u.Sid)"
    $envKey     = "$hiveRoot\Environment"
    $hiveExistia = Test-Path -LiteralPath $hiveRoot -ErrorAction SilentlyContinue
    $carreguei   = $false

    if (-not $hiveExistia) {
        # Usuario nao esta com hive montado - carrega NTUSER.DAT temporariamente
        $ntuser = Join-Path $u.UserProfile "NTUSER.DAT"
        if (Test-Path -LiteralPath $ntuser -ErrorAction SilentlyContinue) {
            $null = reg load "HKU\$($u.Sid)" "`"$ntuser`"" 2>&1
            Start-Sleep -Milliseconds 300
            $carreguei = Test-Path -LiteralPath $hiveRoot -ErrorAction SilentlyContinue
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $envKey -ErrorAction SilentlyContinue)) {
            New-Item -Path $envKey -Force -ErrorAction SilentlyContinue | Out-Null
        }

        if ($Append) {
            $existing = $null
            try {
                $existing = (Get-ItemProperty -Path $envKey -Name $Name -ErrorAction Stop).$Name
            } catch { }
            if ($existing -and ($existing -split ";" | Where-Object { $_ -ieq $Value })) {
                return $true  # ja presente
            }
            $new = if ($existing) { "$($existing.TrimEnd(';'));$Value" } else { $Value }
            # PATH e ExpandString, outras vars normalmente String
            if ($Name -ieq "Path") {
                New-ItemProperty -Path $envKey -Name $Name -Value $new -PropertyType ExpandString -Force | Out-Null
            } else {
                New-ItemProperty -Path $envKey -Name $Name -Value $new -PropertyType String -Force | Out-Null
            }
        } else {
            if ($Name -ieq "Path") {
                New-ItemProperty -Path $envKey -Name $Name -Value $Value -PropertyType ExpandString -Force | Out-Null
            } else {
                New-ItemProperty -Path $envKey -Name $Name -Value $Value -PropertyType String -Force | Out-Null
            }
        }
        return $true
    } catch {
        return $false
    } finally {
        if ($carreguei) {
            [gc]::Collect()
            Start-Sleep -Milliseconds 300
            $null = reg unload "HKU\$($u.Sid)" 2>&1
        }
    }
}

# --- Le variavel de ambiente do hive do usuario real ---
function Get-UserEnvVar {
    param([Parameter(Mandatory)][string]$Name)
    $u = Get-UsuarioInterativo

    if (-not $u.ElevadoComOutroUsr -or -not $u.Sid) {
        return [Environment]::GetEnvironmentVariable($Name, "User")
    }

    $envKey = "Registry::HKEY_USERS\$($u.Sid)\Environment"
    $hiveExistia = Test-Path -LiteralPath "Registry::HKEY_USERS\$($u.Sid)" -ErrorAction SilentlyContinue
    $carreguei = $false
    if (-not $hiveExistia) {
        $ntuser = Join-Path $u.UserProfile "NTUSER.DAT"
        if (Test-Path -LiteralPath $ntuser -ErrorAction SilentlyContinue) {
            $null = reg load "HKU\$($u.Sid)" "`"$ntuser`"" 2>&1
            Start-Sleep -Milliseconds 300
            $carreguei = $true
        }
    }
    try {
        if (Test-Path -LiteralPath $envKey -ErrorAction SilentlyContinue) {
            return (Get-ItemProperty -Path $envKey -Name $Name -ErrorAction SilentlyContinue).$Name
        }
        return $null
    } finally {
        if ($carreguei) {
            [gc]::Collect()
            Start-Sleep -Milliseconds 300
            $null = reg unload "HKU\$($u.Sid)" 2>&1
        }
    }
}

<#
.SYNOPSIS
    Dispara WM_SETTINGCHANGE para o Explorer e processos abertos verem mudancas em variaveis de ambiente.
.DESCRIPTION
    Sem esse broadcast, novos terminais ainda enxergam o PATH antigo ate o usuario fazer logoff/logon.
    Usa SendMessageTimeout via P/Invoke (user32.dll) para nao travar caso algum processo nao responda.
.EXAMPLE
    Send-EnvChangeNotification
#>
function Send-EnvChangeNotification {
    [CmdletBinding()]
    param()
    try {
        if (-not ("NativeMethods" -as [type])) {
            Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
                [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Auto)]
                public static extern System.IntPtr SendMessageTimeout(
                    System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam,
                    uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
"@ -ErrorAction SilentlyContinue
        }
        $HWND_BROADCAST = [System.IntPtr]0xFFFF
        $WM_SETTINGCHANGE = 0x001A
        $result = [System.UIntPtr]::Zero
        [void][Win32.NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [System.UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result)
    } catch { }
}
# Alias retrocompat (verbo nao aprovado, mas mantido para nao quebrar referencias internas)
Set-Alias -Name Broadcast-EnvChange -Value Send-EnvChangeNotification -Scope Script -ErrorAction SilentlyContinue

# --- Deteccao confiavel de npm (PS 5.1 compativel) ---
# Usa Get-Command (nao depende de $ErrorActionPreference=Stop)
# Em UAC-elevado-com-outra-conta, considera o APPDATA do usuario real.
# Inclui paths user-scope para cenario sem admin (portable ou winget --scope user).
function Test-NpmDisponivel {
    $u = Get-UsuarioInterativo
    $nodePaths = @(
        "$env:ProgramFiles\nodejs",
        "${env:ProgramFiles(x86)}\nodejs",
        (Join-Path $u.LocalAppData "nodejs"),                  # portable do usuario real (TS/UAC)
        "$env:LOCALAPPDATA\nodejs",                            # portable do processo atual
        "$($u.AppData)\npm",                                   # npm prefix do usuario real
        "$env:APPDATA\npm"                                     # fallback: perfil do admin elevado
    )
    # winget --scope user instala em pasta versionada
    try {
        $wingetUser = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
        if (Test-Path -LiteralPath $wingetUser -ErrorAction SilentlyContinue) {
            $nodejsWinget = Get-ChildItem -LiteralPath $wingetUser -Directory `
                -Filter "OpenJS.NodeJS*" -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName
            if ($nodejsWinget) { $nodePaths += $nodejsWinget }
        }
    } catch { }

    foreach ($p in $nodePaths) {
        if ($p -and (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) -and ($env:Path -notlike "*$p*")) {
            $env:Path = "$p;$env:Path"
        }
    }
    $cmd = Get-NpmCommandPath
    if (-not $cmd) { return $false }
    # Confirma executando (pode existir .cmd quebrado)
    try {
        $out = & $cmd --version 2>$null
        return ($LASTEXITCODE -eq 0 -and $out -match '\d')
    } catch {
        return $false
    }
}

# --- Recarrega PATH combinado de Machine+User (apos instalacoes que mexem no PATH) ---
function Update-SessionPath {
    try {
        $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $user    = [Environment]::GetEnvironmentVariable("Path", "User")
        $combo   = @()
        if ($machine) { $combo += $machine }
        if ($user)    { $combo += $user }
        $env:Path = ($combo -join ";")
    } catch { }
}

# --- Cache para evitar reinstalar Node.js em loop na mesma sessao ---
$script:NodeJSTentado   = $false
$script:NodeJSResultado = $false

<#
.SYNOPSIS
    Instala Node.js no perfil do usuario via .zip portable (sem necessidade de admin).
.DESCRIPTION
    Baixa o .zip oficial do nodejs.org, extrai em %LOCALAPPDATA%\nodejs e
    grava o caminho no PATH do usuario via Set-UserEnvVar (UAC-aware).
    Detecta arquitetura (x64/x86/arm64) automaticamente.
.OUTPUTS
    [bool] $true em sucesso, $false em falha.
#>
function Install-NodeJSPortable {
    [CmdletBinding()]
    param()

    $u = Get-UsuarioInterativo
    $targetDir = Join-Path $u.LocalAppData "nodejs"

    try {
        Write-Step "Buscando ultima versao LTS do Node.js..."
        $nodeInfo = Invoke-RestMethod "https://nodejs.org/dist/index.json" -ErrorAction Stop
        $lts      = $nodeInfo | Where-Object { $_.lts } | Select-Object -First 1
        if (-not $lts) { throw "Nao encontrei release LTS no index.json" }
        $version = $lts.version  # ex: v20.18.1

        # Detecta arquitetura
        $arch = 'x64'
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
        elseif (-not [Environment]::Is64BitOperatingSystem) { $arch = 'x86' }

        $zipName = "node-$version-win-$arch.zip"
        $url     = "https://nodejs.org/dist/$version/$zipName"
        $zipPath = Join-Path $env:TEMP $zipName

        Write-Step "Baixando Node.js $version ($arch) portable..."
        $ok = Invoke-FastDownload -Url $url -OutFile $zipPath -Label "Node.js $version ($arch)"
        if (-not $ok -or -not (Test-Path -LiteralPath $zipPath)) {
            throw "Download falhou"
        }

        # Backup + extract
        if (Test-Path -LiteralPath $targetDir) {
            Write-Step "Removendo instalacao anterior em $targetDir..."
            Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        $tempExtract = Join-Path $env:TEMP ("node-extract-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

        Write-Step "Extraindo para $targetDir..."
        try {
            Expand-Archive -LiteralPath $zipPath -DestinationPath $tempExtract -Force -ErrorAction Stop
        } catch {
            # Fallback para .NET ZipFile (PS 5.1 sem Expand-Archive)
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $tempExtract)
        }

        # O zip contem uma pasta tipo "node-v20.18.1-win-x64". Move conteudo direto.
        $extracted = Get-ChildItem -LiteralPath $tempExtract -Directory | Select-Object -First 1
        if (-not $extracted) {
            throw "Estrutura inesperada no zip extraido."
        }

        # Garante que o diretorio pai existe (LocalAppData sempre existe, mas por seguranca)
        $parent = Split-Path -Parent $targetDir
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Move-Item -LiteralPath $extracted.FullName -Destination $targetDir -Force

        # Cleanup
        Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

        # Adiciona ao PATH do usuario (UAC-aware via Set-UserEnvVar)
        Write-Step "Adicionando $targetDir ao PATH do usuario..."
        Set-UserEnvVar -Name "Path" -Value $targetDir -Append
        Set-UserEnvVar -Name "Path" -Value (Join-Path $u.AppData "npm") -Append

        # Atualiza PATH da sessao atual
        if ($env:Path -notlike "*$targetDir*") {
            $env:Path = "$targetDir;$env:Path"
        }
        $userNpm = Join-Path $u.AppData "npm"
        if ($env:Path -notlike "*$userNpm*") {
            $env:Path = "$userNpm;$env:Path"
        }

        Write-Ok "Node.js $version instalado em $targetDir (perfil do usuario)."
        return $true
    } catch {
        Write-Fail "Falha na instalacao portable: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Instala Node.js LTS no perfil do usuario atual.
.DESCRIPTION
    Tenta o pacote portable do WinGet em scope=user e usa o .zip oficial como
    fallback. Nunca instala por maquina nem solicita elevacao UAC.
.PARAMETER WingetOk
    Indica se winget esta disponivel na sessao atual.
#>
function Install-NodeJS {
    param([bool]$WingetOk)

    $nodeInstalled = $false
    Write-Info "Instalando Node.js no perfil do usuario, sem privilegios administrativos."

    if ($WingetOk) {
        try {
            Write-Step "Instalando Node.js LTS portable via WinGet (scope=user)..."
            & winget install --id OpenJS.NodeJS.LTS --exact --silent --scope user `
                --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
                Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
            if ($LASTEXITCODE -eq 0) {
                $nodeInstalled = $true
            } else {
                Write-Warn "WinGet encerrou com o codigo $LASTEXITCODE. Usando o pacote portable oficial."
            }
        } catch {
            Write-Warn "WinGet nao conseguiu instalar Node.js em scope=user: $($_.Exception.Message)"
        }
    }

    if (-not $nodeInstalled) {
        $nodeInstalled = Install-NodeJSPortable
    }

    if ($nodeInstalled) {
        # Recarrega PATH completo do registro (WinGet ou Set-UserEnvVar atualizou User)
        Update-SessionPath

        # Garante caminhos padrao - inclui user-scope (LocalAppData\nodejs) para
        # cenario sem admin (instalacao portable ou winget --scope user)
        $u = Get-UsuarioInterativo
        $nodePaths = @(
            "$env:ProgramFiles\nodejs",
            "${env:ProgramFiles(x86)}\nodejs",
            (Join-Path $u.LocalAppData "nodejs"),                            # portable user
            "$env:LOCALAPPDATA\nodejs",                                       # admin elevado portable
            "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\OpenJS.NodeJS.LTS_*",# winget user
            "$($u.AppData)\npm",
            "$env:APPDATA\npm"
        )
        foreach ($p in $nodePaths) {
            # Resolve wildcards (winget cria pasta com versao no nome)
            $expanded = if ($p -match '\*') { Get-ChildItem -Path $p -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName } else { @($p) }
            foreach ($e in $expanded) {
                if ($e -and (Test-Path -LiteralPath $e -ErrorAction SilentlyContinue) -and ($env:Path -notlike "*$e*")) {
                    $env:Path = "$e;$env:Path"
                }
            }
        }

        # Sondagem: aguarda ate 15s pelo npm ficar disponivel
        # (em servidores o MSI pode concluir antes do shim do npm existir)
        $npmOk = $false
        for ($i = 0; $i -lt 15; $i++) {
            if (Test-NpmDisponivel) { $npmOk = $true; break }
            Start-Sleep -Seconds 1
        }

        if ($npmOk) {
            Write-Ok "Node.js instalado com sucesso."
            return $true
        } else {
            Write-Warn "Node.js instalado, mas npm nao ficou disponivel na sessao atual."
            Write-Warn "Feche e reabra o terminal e execute o script novamente."
            return $false
        }
    }

    return $false
}

# --- Garante que Node.js/npm esta disponivel, instalando se necessario ---
# Usa cache por sessao para nao reinstalar em loop quando falha na 1a chamada
function Ensure-NodeJS {
    param([bool]$WingetOk)

    # Verifica se ja esta disponivel (refresca PATH e testa)
    if (Test-NpmDisponivel) {
        $script:NodeJSTentado   = $true
        $script:NodeJSResultado = $true
        return $true
    }

    # Ja tentamos instalar nesta sessao e falhou? Nao repetir.
    if ($script:NodeJSTentado) {
        return $script:NodeJSResultado
    }

    # npm nao encontrado - instalar Node.js (primeira e unica tentativa)
    Write-Warn "Node.js/npm nao encontrado. Instalando automaticamente..."
    $script:NodeJSTentado   = $true
    $script:NodeJSResultado = Install-NodeJS -WingetOk $WingetOk
    return $script:NodeJSResultado
}

# --- Normaliza uma entrada de PATH apenas para comparacao ---
function ConvertTo-NormalizedPathEntry {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $entry = $Value.Trim()
    if ($entry.Length -ge 2 -and $entry.StartsWith('"') -and $entry.EndsWith('"')) {
        $entry = $entry.Substring(1, $entry.Length - 2).Trim()
    }
    try { $entry = [Environment]::ExpandEnvironmentVariables($entry) } catch { }
    if ($entry.Length -gt 3) { $entry = $entry.TrimEnd('\') }
    return $entry
}

function Test-DirectoryWriteAccess {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container -ErrorAction SilentlyContinue)) { return $false }
    $testFile = Join-Path $Path ('.ia-install-write-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $stream = [System.IO.File]::Open($testFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Close()
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        try { if ($stream) { $stream.Close() } } catch { }
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Find-GitBashExecutable {
    $u = Get-UsuarioInterativo
    $candidates = New-Object System.Collections.Generic.List[string]
    $configured = Get-UserEnvVar -Name 'CLAUDE_CODE_GIT_BASH_PATH'
    if ($configured) {
        [void]$candidates.Add($configured)
        [void]$candidates.Add((Join-Path $configured 'bin\bash.exe'))
        [void]$candidates.Add((Join-Path $configured 'usr\bin\bash.exe'))
    }

    $gitRoots = @(
        (Join-Path $u.LocalAppData 'Programs\Git'),
        (Join-Path $env:ProgramFiles 'Git')
    )
    if (${env:ProgramFiles(x86)}) { $gitRoots += (Join-Path ${env:ProgramFiles(x86)} 'Git') }
    foreach ($root in $gitRoots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        [void]$candidates.Add((Join-Path $root 'bin\bash.exe'))
        [void]$candidates.Add((Join-Path $root 'usr\bin\bash.exe'))
    }

    try {
        $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gitCommand -and $gitCommand.Source) {
            $gitRoot = Split-Path (Split-Path $gitCommand.Source -Parent) -Parent
            [void]$candidates.Add((Join-Path $gitRoot 'bin\bash.exe'))
            [void]$candidates.Add((Join-Path $gitRoot 'usr\bin\bash.exe'))
        }
    } catch { }

    return $candidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf -ErrorAction SilentlyContinue) } |
        Select-Object -Unique -First 1
}

# --- Verifica e corrige o PATH para ferramentas CLI ---
function Test-And-Fix-Path {
    $u = Get-UsuarioInterativo
    $caminhos = @(
        (Join-Path $u.AppData 'npm'),
        (Join-Path $u.LocalAppData 'nodejs'),
        (Join-Path $u.LocalAppData 'Microsoft\WinGet\Links'),
        (Join-Path $u.LocalAppData 'Programs\Git\cmd'),
        (Join-Path $u.LocalAppData 'Programs\Git\bin'),
        (Join-Path $env:ProgramFiles 'nodejs'),
        (Join-Path $u.UserProfile '.local\bin')
    )
    if (${env:ProgramFiles(x86)}) { $caminhos += (Join-Path ${env:ProgramFiles(x86)} 'nodejs') }
    $caminhos = $caminhos | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    # Le e saneia somente o PATH do usuario. Entradas inexistentes nao sao
    # removidas automaticamente, pois podem apontar para rede ou midia offline.
    $pathUsuario = Get-UserEnvVar -Name 'Path'
    if (-not $pathUsuario) { $pathUsuario = '' }
    $cleanEntries = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $atualizado = $false
    $corrigidos = New-Object System.Collections.Generic.List[string]

    foreach ($rawEntry in ($pathUsuario -split ';')) {
        if ([string]::IsNullOrWhiteSpace($rawEntry)) {
            if ($pathUsuario.Length -gt 0) { $atualizado = $true }
            continue
        }
        $cleanEntry = $rawEntry.Trim()
        if ($cleanEntry.Length -ge 2 -and $cleanEntry.StartsWith('"') -and $cleanEntry.EndsWith('"')) {
            $cleanEntry = $cleanEntry.Substring(1, $cleanEntry.Length - 2).Trim()
            $atualizado = $true
        }
        $key = ConvertTo-NormalizedPathEntry -Value $cleanEntry
        if ([string]::IsNullOrWhiteSpace($key)) { $atualizado = $true; continue }
        if ($seen.ContainsKey($key)) { $atualizado = $true; continue }
        $seen[$key] = $true
        [void]$cleanEntries.Add($cleanEntry)
    }

    $pathMaquina = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $allKeys = @{}
    foreach ($entry in (($pathMaquina + ';' + ($cleanEntries -join ';')) -split ';')) {
        $key = ConvertTo-NormalizedPathEntry -Value $entry
        if ($key) { $allKeys[$key] = $true }
    }

    foreach ($dir in $caminhos) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container -ErrorAction SilentlyContinue)) { continue }
        $key = ConvertTo-NormalizedPathEntry -Value $dir
        if (-not $allKeys.ContainsKey($key)) {
            [void]$cleanEntries.Add($dir)
            $allKeys[$key] = $true
            $atualizado = $true
            [void]$corrigidos.Add($dir)
        }
    }

    if ($atualizado) {
        $novoPath = $cleanEntries -join ';'
        if (Set-UserEnvVar -Name 'Path' -Value $novoPath) {
            Write-Warn "PATH do usuario '$($u.Username)' foi normalizado."
            foreach ($c in $corrigidos) { Write-Ok "  + $c" }
            $null = Send-EnvChangeNotification
        } else {
            Write-Fail 'Nao foi possivel gravar o PATH corrigido no perfil do usuario.'
            return $false
        }
    } else {
        Write-Ok 'PATH do usuario sem duplicidades e com as entradas necessarias.'
    }

    Update-SessionPath
    foreach ($dir in $caminhos) {
        if ((Test-Path -LiteralPath $dir -PathType Container -ErrorAction SilentlyContinue) -and
            -not (($env:Path -split ';' | ForEach-Object { ConvertTo-NormalizedPathEntry $_ }) -contains (ConvertTo-NormalizedPathEntry $dir))) {
            Write-Fail "A sessao atual ainda nao enxerga: $dir"
            return $false
        }
    }
    return $true
}

<#
.SYNOPSIS
    Repara um arquivo .npmrc corrompido e define prefix/cache corretos.
.DESCRIPTION
    Detecta linhas malformadas tipo "prefix=X\npmcache=Y" (resultado de Set-Content
    em PowerShell concatenando valores em uma unica linha sem CRLF). Quebra essas
    linhas, remove duplicatas de prefix/cache e regrava o arquivo via System.IO.File
    com UTF-8 sem BOM e CRLF explicito (evita que npm interprete mal o arquivo).
.PARAMETER Path
    Caminho do arquivo .npmrc (geralmente $env:USERPROFILE\.npmrc).
.PARAMETER Prefix
    Diretorio onde npm instala pacotes globais (geralmente $env:APPDATA\npm).
.PARAMETER Cache
    Diretorio do cache do npm (geralmente $env:APPDATA\npm-cache).
.OUTPUTS
    [bool] $true se gravou com sucesso, $false caso contrario.
.EXAMPLE
    Repair-NpmRc -Path "$env:USERPROFILE\.npmrc" -Prefix "$env:APPDATA\npm" -Cache "$env:APPDATA\npm-cache"
#>
function Repair-NpmRc {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Prefix,
        [Parameter(Mandatory=$true)][string]$Cache
    )

    if (-not $PSCmdlet.ShouldProcess($Path, "Reparar .npmrc com prefix=$Prefix cache=$Cache")) {
        return $false
    }

    try {
        $linhas = New-Object System.Collections.Generic.List[string]

        if (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue) {
            try {
                $conteudo = [System.IO.File]::ReadAllText($Path)
                # Quebra antes de "cache=" ou "prefix=" quando embutidos no meio da linha
                $conteudo = $conteudo -replace '(?<!\r?\n)(?<!^)cache\s*=', "`r`ncache="
                $conteudo = $conteudo -replace '(?<!\r?\n)(?<!^)prefix\s*=', "`r`nprefix="
                foreach ($l in ($conteudo -split "`r?`n")) {
                    if ([string]::IsNullOrWhiteSpace($l)) { continue }
                    # Pula linhas prefix/cache (serao reescritas com valores corretos)
                    if ($l -match '^\s*(prefix|cache)\s*=') { continue }
                    # Pula linhas com "prefix=" ou "cache=" embutido (corrompidas)
                    if ($l -match '\S\s*(prefix|cache)\s*=') { continue }
                    [void]$linhas.Add($l)
                }
            } catch { }
        }

        [void]$linhas.Add("prefix=$Prefix")
        [void]$linhas.Add("cache=$Cache")

        # Garante que o diretorio pai existe
        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent -ErrorAction SilentlyContinue)) {
            try { New-Item -ItemType Directory -Path $parent -Force -ErrorAction SilentlyContinue | Out-Null } catch { }
        }

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, (($linhas -join "`r`n") + "`r`n"), $utf8NoBom)
        return $true
    } catch {
        return $false
    }
}

function Invoke-StartupHealthCheck {
    param(
        [bool]$CheckGit        = $false,
        [bool]$CheckClaudeCLI  = $false,
        [bool]$CheckCodexCLI   = $false,
        [bool]$CheckOpenCode   = $false,
        [bool]$CheckClaudeDesk = $false,
        [bool]$CheckCodexDesk  = $false,
        [bool]$CheckOpenDesk   = $false,
        [switch]$RecordFailures
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $repairs = New-Object System.Collections.Generic.List[string]
    $u = Get-UsuarioInterativo
    $hasCli = $CheckGit -or $CheckClaudeCLI -or $CheckCodexCLI -or $CheckOpenCode
    $anySelected = $hasCli -or $CheckClaudeDesk -or $CheckCodexDesk -or $CheckOpenDesk

    Write-Host '  Saude de inicializacao:' -ForegroundColor White

    if ($anySelected) {
        foreach ($baseDir in @(
            [PSCustomObject]@{ Name = 'USERPROFILE'; Path = $u.UserProfile; Writable = $false },
            [PSCustomObject]@{ Name = 'APPDATA'; Path = $u.AppData; Writable = $true },
            [PSCustomObject]@{ Name = 'LOCALAPPDATA'; Path = $u.LocalAppData; Writable = $true },
            [PSCustomObject]@{ Name = 'TEMP'; Path = $env:TEMP; Writable = $true }
        )) {
            if ([string]::IsNullOrWhiteSpace($baseDir.Path) -or
                -not [System.IO.Path]::IsPathRooted($baseDir.Path) -or
                -not (Test-Path -LiteralPath $baseDir.Path -PathType Container -ErrorAction SilentlyContinue)) {
                [void]$findings.Add([PSCustomObject]@{ Tool = 'Ambiente'; Critical = $true; Message = "$($baseDir.Name) e invalido ou nao existe: '$($baseDir.Path)'" })
            } elseif ($baseDir.Writable -and -not (Test-DirectoryWriteAccess -Path $baseDir.Path)) {
                [void]$findings.Add([PSCustomObject]@{ Tool = 'Ambiente'; Critical = $true; Message = "Sem permissao de gravacao em $($baseDir.Name): $($baseDir.Path)" })
            }
        }
    }

    if ($hasCli) {
        if (-not (Test-And-Fix-Path)) {
            [void]$findings.Add([PSCustomObject]@{ Tool = 'Ambiente'; Critical = $true; Message = 'PATH nao pode ser corrigido ou recarregado.' })
        }

        if ($env:Path -and $env:Path.Length -gt 8191) {
            [void]$findings.Add([PSCustomObject]@{ Tool = 'PATH'; Critical = $false; Message = "PATH efetivo possui $($env:Path.Length) caracteres; comandos via cmd.exe podem falhar acima de 8191." })
        }
        $effectivePathEntries = @($env:Path -split ';' | ForEach-Object { ConvertTo-NormalizedPathEntry $_ } | Where-Object { $_ })
        $duplicateEffective = @($effectivePathEntries | Group-Object | Where-Object { $_.Count -gt 1 } | Select-Object -First 5)
        if ($duplicateEffective.Count -gt 0) {
            [void]$findings.Add([PSCustomObject]@{ Tool = 'PATH'; Critical = $false; Message = "Entradas duplicadas permanecem no PATH efetivo (possivelmente no escopo da maquina): $($duplicateEffective.Name -join ', ')" })
        }

        # PATHs antigos relacionados a estas ferramentas sao informados, mas nao
        # removidos automaticamente: podem ser unidades de rede temporariamente offline.
        $staleRelevant = New-Object System.Collections.Generic.List[string]
        foreach ($entry in ((Get-UserEnvVar -Name 'Path') -split ';')) {
            $expanded = ConvertTo-NormalizedPathEntry -Value $entry
            if (-not $expanded) { continue }
            if ($entry -match '%[^%]+%' -and $expanded -match '%[^%]+%') {
                [void]$findings.Add([PSCustomObject]@{ Tool = 'PATH'; Critical = $false; Message = "Variavel nao resolvida no PATH: $entry" })
                continue
            }
            if ($expanded -match '(?i)(\\npm($|\\)|\\nodejs($|\\)|\\\.local\\bin($|\\)|\\Git\\(cmd|bin)($|\\)|WinGet\\Links)' -and
                $expanded -notmatch '%' -and
                -not (Test-Path -LiteralPath $expanded -ErrorAction SilentlyContinue)) {
                [void]$staleRelevant.Add($expanded)
            }
        }
        foreach ($stale in ($staleRelevant | Select-Object -Unique -First 5)) {
            [void]$findings.Add([PSCustomObject]@{ Tool = 'PATH'; Critical = $false; Message = "Entrada relacionada a IA nao existe: $stale" })
        }

        $requiredPathExt = @('.COM','.EXE','.BAT','.CMD')
        $processPathExt = if ($env:PATHEXT) { $env:PATHEXT } else { '' }
        $pathExtEntries = @($processPathExt -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim().ToUpperInvariant() })
        $missingPathExt = @($requiredPathExt | Where-Object { $pathExtEntries -notcontains $_ })
        if ($missingPathExt.Count -gt 0) {
            $newPathExt = (@($pathExtEntries) + $missingPathExt | Select-Object -Unique) -join ';'
            if (Set-UserEnvVar -Name 'PATHEXT' -Value $newPathExt) {
                $env:PATHEXT = $newPathExt
                [void]$repairs.Add('PATHEXT restaurado com suporte a .EXE, .BAT e .CMD.')
            } else {
                [void]$findings.Add([PSCustomObject]@{ Tool = 'Ambiente'; Critical = $true; Message = 'PATHEXT nao inclui extensoes executaveis padrao e nao pode ser corrigido.' })
            }
        }

        if (-not $env:ComSpec -or -not (Test-Path -LiteralPath $env:ComSpec -PathType Leaf -ErrorAction SilentlyContinue)) {
            $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
            if ((Test-Path -LiteralPath $cmdExe -PathType Leaf -ErrorAction SilentlyContinue) -and
                (Set-UserEnvVar -Name 'ComSpec' -Value $cmdExe)) {
                $env:ComSpec = $cmdExe
                [void]$repairs.Add("ComSpec corrigido para $cmdExe.")
            } else {
                [void]$findings.Add([PSCustomObject]@{ Tool = 'Ambiente'; Critical = $true; Message = 'cmd.exe/ComSpec indisponivel; shims .cmd nao iniciarao.' })
            }
        }

        $dirsToCheck = @()
        if ($CheckClaudeCLI) { $dirsToCheck += (Join-Path $u.UserProfile '.local\bin') }
        if ($CheckCodexCLI -or $CheckOpenCode) {
            $dirsToCheck += (Join-Path $u.AppData 'npm')
            $dirsToCheck += (Join-Path $u.AppData 'npm-cache')
        }
        foreach ($dir in ($dirsToCheck | Where-Object { $_ } | Select-Object -Unique)) {
            if (-not (Test-Path -LiteralPath $dir -PathType Container -ErrorAction SilentlyContinue)) {
                try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { }
            }
            if (-not (Test-DirectoryWriteAccess -Path $dir)) {
                [void]$findings.Add([PSCustomObject]@{ Tool = 'Ambiente'; Critical = $true; Message = "Sem permissao de gravacao em: $dir" })
            }
        }
    }

    if ($CheckCodexCLI -or $CheckOpenCode) {
        $expectedPrefix = Join-Path $u.AppData 'npm'
        $expectedCache = Join-Path $u.AppData 'npm-cache'
        $npmCmd = Get-NpmCommandPath
        if ($npmCmd) {
            $npmSources = @(Get-Command npm.cmd -All -CommandType Application -ErrorAction SilentlyContinue |
                Where-Object { $_.Source } | Select-Object -ExpandProperty Source -Unique)
            if ($npmSources.Count -gt 1) {
                [void]$findings.Add([PSCustomObject]@{ Tool = 'npm'; Critical = $false; Message = "Mais de um npm.cmd foi encontrado. Em uso: $npmCmd. Todos: $($npmSources -join ', ')" })
            }
            $npmProbe = Invoke-ProcessProbe -FilePath $npmCmd -Arguments '--version'
            if (-not $npmProbe.Success) {
                [void]$findings.Add([PSCustomObject]@{ Tool = 'npm'; Critical = $true; Message = "npm existe, mas nao inicia (codigo $($npmProbe.ExitCode)): $($npmProbe.Error)" })
            } else {
                $prefixBefore = Invoke-NpmConfigValueSafe -Name 'prefix'
                $cacheBefore = Invoke-NpmConfigValueSafe -Name 'cache'
                if ((ConvertTo-NormalizedPathEntry $prefixBefore) -ine (ConvertTo-NormalizedPathEntry $expectedPrefix) -or
                    (ConvertTo-NormalizedPathEntry $cacheBefore) -ine (ConvertTo-NormalizedPathEntry $expectedCache)) {
                    $npmrc = Join-Path $u.UserProfile '.npmrc'
                    if (Repair-NpmRc -Path $npmrc -Prefix $expectedPrefix -Cache $expectedCache) {
                        [void]$repairs.Add(".npmrc ajustado para o perfil de $($u.Username).")
                    }
                }
                $prefixAfter = Invoke-NpmConfigValueSafe -Name 'prefix'
                $cacheAfter = Invoke-NpmConfigValueSafe -Name 'cache'
                if ((ConvertTo-NormalizedPathEntry $prefixAfter) -ine (ConvertTo-NormalizedPathEntry $expectedPrefix)) {
                    [void]$findings.Add([PSCustomObject]@{ Tool = 'npm'; Critical = $true; Message = "Prefixo npm incorreto: '$prefixAfter' (esperado '$expectedPrefix')." })
                }
                if ((ConvertTo-NormalizedPathEntry $cacheAfter) -ine (ConvertTo-NormalizedPathEntry $expectedCache)) {
                    [void]$findings.Add([PSCustomObject]@{ Tool = 'npm'; Critical = $true; Message = "Cache npm incorreto: '$cacheAfter' (esperado '$expectedCache')." })
                }
            }
        }

        try {
            $nodeCommands = @(Get-Command node.exe -All -CommandType Application -ErrorAction SilentlyContinue)
            $nodeCmd = $nodeCommands | Select-Object -First 1
            if ($nodeCmd -and $nodeCmd.Source) {
                $nodeProbe = Invoke-ProcessProbe -FilePath $nodeCmd.Source -Arguments '--version'
                if (-not $nodeProbe.Success) {
                    $hint = if ($env:NODE_OPTIONS) { ' Verifique tambem a variavel NODE_OPTIONS.' } else { '' }
                    [void]$findings.Add([PSCustomObject]@{ Tool = 'Node.js'; Critical = $true; Message = "node.exe nao inicia.$hint $($nodeProbe.Error)".Trim() })
                }
                $nodeSources = @($nodeCommands | Where-Object { $_.Source } | Select-Object -ExpandProperty Source -Unique)
                if ($nodeSources.Count -gt 1) {
                    [void]$findings.Add([PSCustomObject]@{ Tool = 'Node.js'; Critical = $false; Message = "Mais de um node.exe foi encontrado. Em uso: $($nodeCmd.Source). Todos: $($nodeSources -join ', ')" })
                }
            }
        } catch { }

        foreach ($certVar in @('NODE_EXTRA_CA_CERTS','SSL_CERT_FILE')) {
            $certPath = [Environment]::GetEnvironmentVariable($certVar, 'Process')
            if ($certPath -and -not (Test-Path -LiteralPath $certPath -PathType Leaf -ErrorAction SilentlyContinue)) {
                [void]$findings.Add([PSCustomObject]@{ Tool = 'Node.js'; Critical = $false; Message = "$certVar aponta para um certificado inexistente; conexoes HTTPS podem falhar." })
            }
        }
    }

    if ($CheckClaudeCLI -or $CheckClaudeDesk) {
        $bashExe = Find-GitBashExecutable
        $configuredBash = Get-UserEnvVar -Name 'CLAUDE_CODE_GIT_BASH_PATH'
        if ($bashExe) {
            if ((ConvertTo-NormalizedPathEntry $configuredBash) -ine (ConvertTo-NormalizedPathEntry $bashExe)) {
                if (Set-UserEnvVar -Name 'CLAUDE_CODE_GIT_BASH_PATH' -Value $bashExe) {
                    $env:CLAUDE_CODE_GIT_BASH_PATH = $bashExe
                    [void]$repairs.Add("CLAUDE_CODE_GIT_BASH_PATH corrigido para $bashExe.")
                } else {
                    [void]$findings.Add([PSCustomObject]@{ Tool = 'Claude Code'; Critical = $true; Message = 'Nao foi possivel corrigir CLAUDE_CODE_GIT_BASH_PATH.' })
                }
            }
            $bashProbe = Invoke-ProcessProbe -FilePath $bashExe -Arguments '--version'
            if (-not $bashProbe.Success) {
                [void]$findings.Add([PSCustomObject]@{ Tool = 'Claude Code'; Critical = $true; Message = "Git Bash foi encontrado, mas nao inicia: $($bashProbe.Error)" })
            }
        } elseif ($configuredBash) {
            [void]$findings.Add([PSCustomObject]@{ Tool = 'Claude Code'; Critical = $true; Message = "CLAUDE_CODE_GIT_BASH_PATH e invalido: $configuredBash" })
        }
    }

    $toolDefs = @(
        [PSCustomObject]@{ Enabled = $CheckClaudeCLI; Tool = 'Claude Code'; Cmd = 'claude'; Package = '@anthropic-ai/claude-code'; NpmShim = $false },
        [PSCustomObject]@{ Enabled = $CheckCodexCLI;  Tool = 'Codex CLI';   Cmd = 'codex';  Package = '@openai/codex';             NpmShim = $true  },
        [PSCustomObject]@{ Enabled = $CheckOpenCode; Tool = 'OpenCode';    Cmd = 'opencode'; Package = 'opencode-ai';             NpmShim = $true  }
    )

    foreach ($tool in $toolDefs) {
        if (-not $tool.Enabled) { continue }
        try {
            $currentResolution = Get-Command $tool.Cmd -ErrorAction SilentlyContinue
            if ($currentResolution -and $currentResolution.CommandType -in @('Alias','Function','Filter','Cmdlet')) {
                [void]$findings.Add([PSCustomObject]@{ Tool = $tool.Tool; Critical = $false; Message = "O nome '$($tool.Cmd)' esta sendo interceptado por $($currentResolution.CommandType) na sessao atual." })
            }
        } catch { }
        $info = Get-CliToolInfo -Cmd $tool.Cmd -NpmPackage $tool.Package
        if (-not $info.Installed) {
            if ($info.Method -eq 'broken-npm-package') {
                [void]$findings.Add([PSCustomObject]@{ Tool = $tool.Tool; Critical = $true; Message = "Pacote existe, mas o comando nao inicia: $($info.Source)" })
            }
            continue
        }

        $shellProbe = Invoke-PowerShellCommandProbe -CommandName $tool.Cmd
        if (-not $shellProbe.Success -and $tool.NpmShim) {
            $psShim = Join-Path $u.AppData ("npm\$($tool.Cmd).ps1")
            $cmdShim = Join-Path $u.AppData ("npm\$($tool.Cmd).cmd")
            $cmdProbe = if (Test-Path -LiteralPath $cmdShim -PathType Leaf -ErrorAction SilentlyContinue) {
                Invoke-ProcessProbe -FilePath $cmdShim -Arguments '--version'
            } else { $null }

            if ($cmdProbe -and $cmdProbe.Success -and (Test-Path -LiteralPath $psShim -PathType Leaf -ErrorAction SilentlyContinue)) {
                $backup = "$psShim.disabled-by-ia-install"
                if (Test-Path -LiteralPath $backup -ErrorAction SilentlyContinue) {
                    $backup = "$backup.$([DateTime]::Now.ToString('yyyyMMddHHmmss'))"
                }
                try {
                    Move-Item -LiteralPath $psShim -Destination $backup -Force -ErrorAction Stop
                    $shellProbe = Invoke-PowerShellCommandProbe -CommandName $tool.Cmd
                    if ($shellProbe.Success) {
                        [void]$repairs.Add("Shim PowerShell bloqueado de $($tool.Cmd) foi desativado; o .cmd funcional sera usado.")
                    } else {
                        Move-Item -LiteralPath $backup -Destination $psShim -Force -ErrorAction SilentlyContinue
                    }
                } catch { }
            }
        }

        if (-not $shellProbe.Success) {
            $probeMessage = if ($shellProbe.Error) { $shellProbe.Error } else { $shellProbe.Output }
            $probeMessage = (($probeMessage -split "`r?`n") | Where-Object { $_ } | Select-Object -First 1)
            [void]$findings.Add([PSCustomObject]@{ Tool = $tool.Tool; Critical = $true; Message = "O comando '$($tool.Cmd)' existe, mas falha ao iniciar no PowerShell: $probeMessage" })
        }

        try {
            $sources = @(Get-Command $tool.Cmd -All -ErrorAction SilentlyContinue |
                Where-Object { $_.Source -and (Test-Path -LiteralPath $_.Source -ErrorAction SilentlyContinue) } |
                Select-Object -ExpandProperty Source -Unique)
            $sourceDirs = @($sources | ForEach-Object { Split-Path $_ -Parent } | Select-Object -Unique)
            if ($sourceDirs.Count -gt 1) {
                $activeDir = Split-Path $info.Source -Parent
                $otherDirs = @($sourceDirs | Where-Object { $_ -ine $activeDir } | Select-Object -First 4)
                [void]$findings.Add([PSCustomObject]@{ Tool = $tool.Tool; Critical = $false; Message = "Multiplas instalacoes podem disputar o PATH. Em uso: $($info.Source). Outros locais: $($otherDirs -join ', ')" })
            }
        } catch { }
    }

    if ($CheckClaudeDesk -or $CheckCodexDesk -or $CheckOpenDesk) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $desktopWingetDefs = @(
                [PSCustomObject]@{ Enabled = $CheckClaudeDesk; Tool = 'Claude Desktop'; Id = 'Anthropic.Claude' },
                [PSCustomObject]@{ Enabled = $CheckCodexDesk;  Tool = 'ChatGPT/Codex Desktop'; Id = '9PLM9XGG6VKS' },
                [PSCustomObject]@{ Enabled = $CheckOpenDesk;   Tool = 'OpenCode Desktop'; Id = 'SST.OpenCodeDesktop' }
            )
            foreach ($desktop in $desktopWingetDefs) {
                if (-not $desktop.Enabled) { continue }
                try {
                    $listLines = @(& winget list --id $desktop.Id --exact --accept-source-agreements --disable-interactivity 2>&1)
                    $matchingRows = @($listLines | Where-Object { $_ -match [regex]::Escape($desktop.Id) })
                    if ($matchingRows.Count -gt 1) {
                        [void]$findings.Add([PSCustomObject]@{
                            Tool = $desktop.Tool
                            Critical = $false
                            Message = "O WinGet encontrou $($matchingRows.Count) registros com o mesmo ID $($desktop.Id). Uma versao antiga pode permanecer registrada e confundir atualizacoes."
                        })
                    }
                } catch { }
            }
        }

        try {
            $appxPatterns = New-Object System.Collections.Generic.List[string]
            if ($CheckClaudeDesk) { [void]$appxPatterns.Add('(?i)Claude') }
            if ($CheckCodexDesk)  { [void]$appxPatterns.Add('(?i)(ChatGPT|Codex|OpenAI)') }
            if ($CheckOpenDesk)   { [void]$appxPatterns.Add('(?i)OpenCode') }
            $allAppx = Get-AppxPackage -ErrorAction SilentlyContinue
            foreach ($pattern in $appxPatterns) {
                foreach ($pkg in @($allAppx | Where-Object { $_.Name -match $pattern -or $_.PackageFullName -match $pattern })) {
                    if ($pkg.Status -and $pkg.Status.ToString() -ne 'Ok') {
                        [void]$findings.Add([PSCustomObject]@{ Tool = $pkg.Name; Critical = $true; Message = "Pacote AppX registrado com status $($pkg.Status)." })
                    }
                    if ($pkg.InstallLocation -and -not (Test-Path -LiteralPath $pkg.InstallLocation -PathType Container -ErrorAction SilentlyContinue)) {
                        [void]$findings.Add([PSCustomObject]@{ Tool = $pkg.Name; Critical = $true; Message = "Diretorio AppX ausente: $($pkg.InstallLocation)" })
                    }
                }
            }
        } catch { }
    }

    foreach ($repair in $repairs) { Write-Ok "Reparado: $repair" }
    foreach ($finding in $findings) {
        if ($finding.Critical) { Write-Fail "$($finding.Tool): $($finding.Message)" }
        else { Write-Warn "$($finding.Tool): $($finding.Message)" }
    }
    if ($findings.Count -eq 0) { Write-Ok 'Nenhum problema de inicializacao detectado.' }
    Write-Host ''

    $script:StartupHealthFindings = @($findings | ForEach-Object { $_ })
    if ($RecordFailures) {
        foreach ($finding in $findings | Where-Object { $_.Critical -and $_.Tool -in @('Claude Code','Codex CLI','OpenCode') }) {
            Set-OperationFailure -Name $finding.Tool -Reason $finding.Message
        }
    }

    return [PSCustomObject]@{
        Repairs = @($repairs | ForEach-Object { $_ })
        Findings = @($findings | ForEach-Object { $_ })
        Healthy = (@($findings | Where-Object { $_.Critical }).Count -eq 0)
    }
}

# --- Wrapper de 'npm install -g' que forca instalacao no perfil do usuario real ---
# Em UAC-elevado-com-outra-conta, usa --prefix apontando para o APPDATA do usuario
# interativo, nao do admin elevado. Tambem garante diretorio do npm cache coerente.
function Invoke-NpmInstallGlobal {
    param([string]$Package)

    $u = Get-UsuarioInterativo
    $npmPrefix = "$($u.AppData)\npm"

    # Garante diretorio do prefix (admin tem permissao para criar no perfil do usuario)
    if (-not (Test-Path -LiteralPath $npmPrefix -ErrorAction SilentlyContinue)) {
        try { New-Item -ItemType Directory -Path $npmPrefix -Force -ErrorAction Stop | Out-Null } catch { }
    }

    # Usa cache no perfil do usuario real tambem
    $npmCache = "$($u.AppData)\npm-cache"
    if (-not (Test-Path -LiteralPath $npmCache -ErrorAction SilentlyContinue)) {
        try { New-Item -ItemType Directory -Path $npmCache -Force -ErrorAction Stop | Out-Null } catch { }
    }

    # Repara .npmrc do usuario que roda o processo (pode ter sido corrompido por bug anterior)
    # npm lê o .npmrc do usuario efetivo; quando elevado como admif, e admif\.npmrc.
    $npmrcAtual = Join-Path $env:USERPROFILE ".npmrc"
    [void](Repair-NpmRc -Path $npmrcAtual -Prefix $npmPrefix -Cache $npmCache)

    # Tambem repara o .npmrc do usuario real (ajuda quando ele rodar 'npm install -g' manualmente)
    if ($u.UserProfile -and ($u.UserProfile -ne $env:USERPROFILE)) {
        $npmrcReal = Join-Path $u.UserProfile ".npmrc"
        [void](Repair-NpmRc -Path $npmrcReal -Prefix $npmPrefix -Cache $npmCache)
    }

    # --prefix sobrescreve config user/global; --cache ajusta cache
    $npmCmd = Get-NpmCommandPath
    if (-not $npmCmd) { return 9009 }

    & $npmCmd install -g $Package --prefix "$npmPrefix" --cache "$npmCache" 2>&1 |
        ForEach-Object { Write-Host $_ }

    return $LASTEXITCODE
}

# --- Verifica/instala/atualiza pacote npm global ---
function Invoke-NpmTool {
    param(
        [string]$Label,      # Nome amigavel exibido
        [string]$Cmd,        # Comando de terminal (ex: opencode, codex)
        [string]$Package,    # Nome do pacote npm (ex: opencode-ai)
        [string]$NpmName     # Mesmo que Package (usado na URL do registry)
    )

    Write-Step "Verificando $Label..."

    # Garante Node.js/npm instalado no perfil do usuario
    if (-not (Ensure-NodeJS -WingetOk $wingetOk)) {
        Write-Warn "Nao foi possivel garantir o Node.js. Pulando $Label."
        Set-OperationFailure -Name $Label -Reason "Node.js/npm indisponivel"
        Pause-Readable 3
        return
    }

    $u = Get-UsuarioInterativo
    $npmBinUser = "$($u.AppData)\npm"

    # Adiciona bin do usuario real na sessao para que 'codex', 'opencode', 'claude' sejam encontrados
    if ((Test-Path -LiteralPath $npmBinUser -ErrorAction SilentlyContinue) -and ($env:Path -notlike "*$npmBinUser*")) {
        $env:Path = "$npmBinUser;$env:Path"
    }

    $toolInfo = Get-CliToolInfo -Cmd $Cmd -NpmPackage $NpmName
    $installed = [bool]$toolInfo.Installed
    $currentVer = $toolInfo.Version

    if ($installed) {
        if ([string]::IsNullOrWhiteSpace($currentVer)) {
            Write-Ok "$Label ja instalado. Origem: $($toolInfo.Source)"
        } else {
            Write-Ok "$Label ja instalado. Versao atual: $currentVer"
        }
        Write-Step "Verificando atualizacoes do $Label..."
        try {
            $info       = Invoke-RestMethod "https://registry.npmjs.org/$NpmName/latest"
            $latestVer  = $info.version
            $installedV = ($currentVer -replace '^[^\d]*').Trim() -split '\s+' | Select-Object -First 1
            if ([string]::IsNullOrWhiteSpace($installedV)) {
                Write-Ok "$Label detectado em: $($toolInfo.Source)"
                Write-Warn "Versao instalada nao identificada. Verificando/atualizando via npm para garantir."
                $npmExit = Invoke-NpmInstallGlobal -Package $Package
                if ($npmExit -ne 0) { throw "npm encerrou com o codigo $npmExit." }
                $after = Get-CliToolInfo -Cmd $Cmd -NpmPackage $NpmName
                if (-not $after.Installed) { throw "$Label nao foi detectado depois da atualizacao." }
                $afterVersion = ($after.Version -replace '^[^\d]*').Trim() -split '\s+' | Select-Object -First 1
                if ($latestVer -and $afterVersion -ne $latestVer) { throw "Versao esperada $latestVer, mas foi detectada $afterVersion." }
                Write-Ok "$Label verificado/atualizado via npm."
                Pause-Readable 3
                return
            }

            Write-Ok "Versao instalada   : $installedV"
            Write-Ok "Versao mais recente: $latestVer"

            if ($installedV -eq $latestVer) {
                Write-Ok "$Label esta atualizado. Nenhuma acao necessaria."
                Pause-Readable 3
            } else {
                Write-Warn "Atualizacao disponivel: $installedV -> $latestVer"
                Pause-Readable 2
                Write-Step "Atualizando $Label via npm (prefix=$npmBinUser)..."
                $npmExit = Invoke-NpmInstallGlobal -Package $Package
                if ($npmExit -ne 0) { throw "npm encerrou com o codigo $npmExit." }
                $after = Get-CliToolInfo -Cmd $Cmd -NpmPackage $NpmName
                if (-not $after.Installed) { throw "$Label nao foi detectado depois da atualizacao." }
                $afterVersion = ($after.Version -replace '^[^\d]*').Trim() -split '\s+' | Select-Object -First 1
                if ($latestVer -and $afterVersion -ne $latestVer) { throw "Versao esperada $latestVer, mas foi detectada $afterVersion." }
                Write-Ok "$Label atualizado com sucesso."
                Pause-Readable 3
            }
        } catch {
            Set-OperationFailure -Name $Label -Reason $_.Exception.Message
            Write-Fail "Falha ao verificar/atualizar ${Label}: $($_.Exception.Message)"
            Pause-Readable 3
        }
    } else {
        Write-Step "$Label nao encontrado. Instalando em: $npmBinUser"
        try {
            $npmExit = Invoke-NpmInstallGlobal -Package $Package
            if ($npmExit -ne 0) { throw "npm encerrou com o codigo $npmExit." }
            $after = Get-CliToolInfo -Cmd $Cmd -NpmPackage $NpmName
            if (-not $after.Installed) { throw "$Label nao foi detectado depois da instalacao." }
            Write-Ok "$Label instalado com sucesso."
            Write-Warn "Abra um novo terminal para usar o comando '$Cmd'."
            Pause-Readable 3
        } catch {
            Set-OperationFailure -Name $Label -Reason $_.Exception.Message
            Write-Fail "Falha na instalacao do ${Label}: $_"
            Pause-Readable 3
        }
    }
}

# ----------------------------------------------------------
# FUNCAO DE DIAGNOSTICO - verifica estado de cada ferramenta
# Parametros: flags booleanas indicando quais ferramentas verificar
# Retorna: $true se pode prosseguir, $false se usuario cancelou
# ----------------------------------------------------------
function Invoke-Diagnostico {
    param(
        [bool]$CheckGit        = $false,
        [bool]$CheckClaudeCLI  = $false,
        [bool]$CheckCodexCLI   = $false,
        [bool]$CheckOpenCode   = $false,
        [bool]$CheckClaudeDesk = $false,
        [bool]$CheckCodexDesk  = $false,
        [bool]$CheckOpenDesk   = $false
    )

    Write-CompactHeader -Title 'Diagnostico do Ambiente'
    Write-Host ""
    Write-Host "  Verificando ferramentas selecionadas..." -ForegroundColor DarkGray
    Write-Host ""

    $null = Invoke-StartupHealthCheck `
        -CheckGit        $CheckGit `
        -CheckClaudeCLI  $CheckClaudeCLI `
        -CheckCodexCLI   $CheckCodexCLI `
        -CheckOpenCode   $CheckOpenCode `
        -CheckClaudeDesk $CheckClaudeDesk `
        -CheckCodexDesk  $CheckCodexDesk `
        -CheckOpenDesk   $CheckOpenDesk

    # Garante caminhos npm/node no PATH para deteccao
    $uDiag = Get-UsuarioInterativo
    $nodePaths = @("$env:ProgramFiles\nodejs", "$($uDiag.AppData)\npm", "$env:APPDATA\npm", "$($uDiag.UserProfile)\.local\bin")
    foreach ($p in $nodePaths) {
        $pExists = Test-Path -LiteralPath $p -ErrorAction SilentlyContinue
        if ($pExists -and ($env:Path -split ";" | Where-Object { $_ -ieq $p }) -eq $null) {
            $env:Path = "$p;$env:Path"
        }
    }

    $diagItens = @()

    # --- Git Bash ---
    if ($CheckGit) {
        $gitStatus = "Nao instalado"; $gitColor = "Red"; $gitAcao = "instalar"
        try {
            $gitCands = @("C:\Program Files\Git","C:\Program Files (x86)\Git","$env:LOCALAPPDATA\Programs\Git")
            $gitExe = $null
            foreach ($c in $gitCands) {
                if (Test-Path "$c\cmd\git.exe") { $gitExe = "$c\cmd\git.exe"; break }
            }
            if (-not $gitExe) {
                $reg = Get-ItemProperty "HKLM:\SOFTWARE\GitForWindows" -ErrorAction SilentlyContinue
                if ($reg) { $gitExe = "$($reg.InstallPath)\cmd\git.exe" }
            }
            if (-not $gitExe) {
                $gitCmd = Get-Command git -ErrorAction SilentlyContinue
                if ($gitCmd) { $gitExe = $gitCmd.Source }
            }
            if ($gitExe -and (Test-Path $gitExe)) {
                $gv = (& $gitExe --version 2>&1) -replace "git version " -replace "\.windows\.\d+$"
                $gitLatest = $null
                try {
                    $rel = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest" -ErrorAction SilentlyContinue
                    $gitLatest = ($rel.tag_name -replace "^v" -replace "\.windows\.\d+$")
                } catch {}
                if ($gitLatest -and $gv.Trim() -ne $gitLatest) {
                    $gitStatus = "v$($gv.Trim()) -> $gitLatest"; $gitColor = "Yellow"; $gitAcao = "atualizar"
                } else {
                    $gitStatus = "v$($gv.Trim()) - Atualizado"; $gitColor = "Green"; $gitAcao = "ok"
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "Git Bash      "; Status = $gitStatus; Cor = $gitColor; Acao = $gitAcao }
    }

    # --- Claude Code CLI ---
    if ($CheckClaudeCLI) {
        $claudeStatus = "Nao instalado"; $claudeColor = "Red"; $claudeAcao = "instalar"
        try {
            $claudeInfo = Get-CliToolInfo -Cmd "claude" -NpmPackage "@anthropic-ai/claude-code"
            if ($claudeInfo.Installed) {
                $instV = ($claudeInfo.Version -replace "^[^\d]*").Trim() -split "\s+" | Select-Object -First 1
                if ([string]::IsNullOrWhiteSpace($instV)) {
                    $claudeStatus = "Instalado ($($claudeInfo.Method))"; $claudeColor = "Green"; $claudeAcao = "ok"
                } else {
                    $npmInfo = Invoke-RestMethod "https://registry.npmjs.org/@anthropic-ai/claude-code/latest" -ErrorAction SilentlyContinue
                    if ($npmInfo -and $instV -ne $npmInfo.version) {
                        $claudeStatus = "v$instV -> $($npmInfo.version)"; $claudeColor = "Yellow"; $claudeAcao = "atualizar"
                    } else {
                        $claudeStatus = "v$instV - Atualizado"; $claudeColor = "Green"; $claudeAcao = "ok"
                    }
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "Claude Code   "; Status = $claudeStatus; Cor = $claudeColor; Acao = $claudeAcao }
    }
    # --- Codex CLI ---
    if ($CheckCodexCLI) {
        $codexCliStatus = "Nao instalado"; $codexCliColor = "Red"; $codexCliAcao = "instalar"
        try {
            $codexInfo = Get-CliToolInfo -Cmd "codex" -NpmPackage "@openai/codex"
            if ($codexInfo.Installed) {
                $instV = ($codexInfo.Version -replace "^[^\d]*").Trim() -split "\s+" | Select-Object -First 1
                if ([string]::IsNullOrWhiteSpace($instV)) {
                    $codexCliStatus = "Instalado ($($codexInfo.Method))"; $codexCliColor = "Green"; $codexCliAcao = "ok"
                } else {
                    $npmInfo = Invoke-RestMethod "https://registry.npmjs.org/@openai/codex/latest" -ErrorAction SilentlyContinue
                    if ($npmInfo -and $instV -ne $npmInfo.version) {
                        $codexCliStatus = "v$instV -> $($npmInfo.version)"; $codexCliColor = "Yellow"; $codexCliAcao = "atualizar"
                    } else {
                        $codexCliStatus = "v$instV - Atualizado"; $codexCliColor = "Green"; $codexCliAcao = "ok"
                    }
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "Codex CLI     "; Status = $codexCliStatus; Cor = $codexCliColor; Acao = $codexCliAcao }
    }
    # --- OpenCode CLI ---
    if ($CheckOpenCode) {
        $openCodeStatus = "Nao instalado"; $openCodeColor = "Red"; $openCodeAcao = "instalar"
        try {
            $openInfo = Get-CliToolInfo -Cmd "opencode" -NpmPackage "opencode-ai"
            if ($openInfo.Installed) {
                $instV = ($openInfo.Version -replace "^[^\d]*").Trim() -split "\s+" | Select-Object -First 1
                if ([string]::IsNullOrWhiteSpace($instV)) {
                    $openCodeStatus = "Instalado ($($openInfo.Method))"; $openCodeColor = "Green"; $openCodeAcao = "ok"
                } else {
                    $npmInfo = Invoke-RestMethod "https://registry.npmjs.org/opencode-ai/latest" -ErrorAction SilentlyContinue
                    if ($npmInfo -and $instV -ne $npmInfo.version) {
                        $openCodeStatus = "v$instV -> $($npmInfo.version)"; $openCodeColor = "Yellow"; $openCodeAcao = "atualizar"
                    } else {
                        $openCodeStatus = "v$instV - Atualizado"; $openCodeColor = "Green"; $openCodeAcao = "ok"
                    }
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "OpenCode CLI  "; Status = $openCodeStatus; Cor = $openCodeColor; Acao = $openCodeAcao }
    }
    # --- Claude Desktop ---
    if ($CheckClaudeDesk) {
        $claudeDeskStatus = "Nao instalado"; $claudeDeskColor = "Red"; $claudeDeskAcao = "instalar"
        try {
            $claudeDeskInfo = Get-ClaudeDesktopInfo -WingetOk $wingetOk
            if ($claudeDeskInfo.Installed) {
                if ($wingetOk -and (Test-WingetUpgradeAvailable -Id 'Anthropic.Claude')) {
                    $claudeDeskStatus = "Atualizacao disponivel"; $claudeDeskColor = "Yellow"; $claudeDeskAcao = "atualizar"
                } else {
                    if ($claudeDeskInfo.Version) { $claudeDeskStatus = "v$($claudeDeskInfo.Version) - Instalado" }
                    else { $claudeDeskStatus = "Instalado ($($claudeDeskInfo.Method))" }
                    $claudeDeskColor = "Green"; $claudeDeskAcao = "ok"
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "Claude Desktop"; Status = $claudeDeskStatus; Cor = $claudeDeskColor; Acao = $claudeDeskAcao }
    }
    # --- Codex Desktop ---
    if ($CheckCodexDesk) {
        $codexDeskStatus = "Nao instalado"; $codexDeskColor = "Red"; $codexDeskAcao = "instalar"
        try {
            $codexDeskInfo = Get-CodexDesktopInfo -WingetOk $wingetOk
            if ($codexDeskInfo.Installed) {
                if ($wingetOk -and (Test-WingetUpgradeAvailable -Id '9PLM9XGG6VKS' -Source 'msstore')) {
                    $codexDeskStatus = "Atualizacao disponivel"; $codexDeskColor = "Yellow"; $codexDeskAcao = "atualizar"
                } else {
                    if ($codexDeskInfo.Version) {
                        $codexDeskStatus = "v$($codexDeskInfo.Version) - Instalado"
                    } else {
                        $codexDeskStatus = "Instalado ($($codexDeskInfo.Method))"
                    }
                    $codexDeskColor = "Green"; $codexDeskAcao = "ok"
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "Codex Desktop "; Status = $codexDeskStatus; Cor = $codexDeskColor; Acao = $codexDeskAcao }
    }
    # --- OpenCode Desktop ---
    if ($CheckOpenDesk) {
        $openDeskStatus = "Nao instalado"; $openDeskColor = "Red"; $openDeskAcao = "instalar"
        try {
            $openDeskInfo = Get-OpenCodeDesktopInfo -WingetOk $wingetOk
            if ($openDeskInfo.Installed) {
                if ($wingetOk -and (Test-WingetUpgradeAvailable -Id 'SST.OpenCodeDesktop')) {
                    $openDeskStatus = "Atualizacao disponivel"; $openDeskColor = "Yellow"; $openDeskAcao = "atualizar"
                } else {
                    if ($openDeskInfo.Version) { $openDeskStatus = "v$($openDeskInfo.Version) - Instalado" }
                    else { $openDeskStatus = "Instalado ($($openDeskInfo.Method))" }
                    $openDeskColor = "Green"; $openDeskAcao = "ok"
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "OpenCode Desk "; Status = $openDeskStatus; Cor = $openDeskColor; Acao = $openDeskAcao }
    }
    # --- Exibe resultado ---
    Write-Host "  Ferramenta         Status" -ForegroundColor White
    Write-Host "  -----------------------------------------------" -ForegroundColor DarkGray
    foreach ($item in $diagItens) {
        $icone = switch ($item.Acao) {
            "ok"        { "[ OK]" }
            "atualizar" { "[AVS]" }
            default     { "[ERR]" }
        }
        Write-Host "  $icone $($item.Nome) : $($item.Status)" -ForegroundColor $item.Cor
    }
    Write-Host ""

    $acoesPendentes = $diagItens | Where-Object { $_.Acao -ne "ok" }

    # Monta hashtable de resultado com flags individuais
    $resultado = @{
        Prosseguir = $false
        Git        = $false
        ClaudeCLI  = $false
        CodexCLI   = $false
        OpenCode   = $false
        ClaudeDesk = $false
        CodexDesk  = $false
        OpenDesk   = $false
    }

    if ($diagItens.Count -eq 0) {
        Write-Warn "Nenhuma ferramenta foi avaliada no diagnostico. Prosseguindo com a selecao original."
        $resultado.Prosseguir = $true
        $resultado.Git        = $CheckGit
        $resultado.ClaudeCLI  = $CheckClaudeCLI
        $resultado.CodexCLI   = $CheckCodexCLI
        $resultado.OpenCode   = $CheckOpenCode
        $resultado.ClaudeDesk = $CheckClaudeDesk
        $resultado.CodexDesk  = $CheckCodexDesk
        $resultado.OpenDesk   = $CheckOpenDesk
        return $resultado
    }

    if ($acoesPendentes.Count -eq 0) {
        Write-Host "  Tudo instalado e atualizado! Nenhuma acao necessaria." -ForegroundColor Green
        Write-Host ""
        Write-Host "============================================================`n" -ForegroundColor Cyan
        return $resultado  # Prosseguir=false, nada a fazer
    }

    Write-Host "  Acoes necessarias:" -ForegroundColor White
    foreach ($a in $acoesPendentes) {
        $label = if ($a.Acao -eq "instalar") { "Instalar" } else { "Atualizar" }
        Write-Host "    - $label $($a.Nome.Trim())" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "============================================================`n" -ForegroundColor Cyan

    if (-not (Confirm-Tecla "Deseja prosseguir?")) {
        return $resultado  # Usuario cancelou
    }
    Write-Host ""

    # Define quais ferramentas precisam de acao
    $resultado.Prosseguir = $true
    foreach ($item in $acoesPendentes) {
        switch -Wildcard ($item.Nome.Trim()) {
            "Git Bash"      { $resultado.Git        = $true }
            "Claude Code"   { $resultado.ClaudeCLI  = $true }
            "Codex CLI"     { $resultado.CodexCLI   = $true }
            "OpenCode CLI"  { $resultado.OpenCode   = $true }
            "Claude Desktop"{ $resultado.ClaudeDesk = $true }
            "Codex Desktop" { $resultado.CodexDesk  = $true }
            "OpenCode Desk" { $resultado.OpenDesk   = $true }
        }
    }

    return $resultado
}

# ----------------------------------------------------------
# LOOP PRINCIPAL - menu principal: Instalar ou Remover
# Em modo nao-interativo (param block) executa apenas uma vez como Instalar
# ----------------------------------------------------------
$usuarioDaSessao = Get-UsuarioInterativo
if ($usuarioDaSessao.ElevadoComOutroUsr) {
    Write-Fail "O script foi elevado como '$env:USERNAME', mas a sessao pertence a '$($usuarioDaSessao.Username)'."
    Write-Warn "Feche esta janela e execute o script normalmente, sem 'Executar como administrador'."
    Write-Warn "Instaladores por usuario nao podem ser registrados corretamente por outra conta administrativa."
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
    return
}

function Invoke-NpmUninstallGlobal {
    param([Parameter(Mandatory=$true)][string]$Package)

    $u = Get-UsuarioInterativo
    $npmCmd = Get-NpmCommandPath
    if (-not $npmCmd) { return 9009 }

    $npmPrefix = Join-Path $u.AppData "npm"
    $npmCache = Join-Path $u.AppData "npm-cache"
    & $npmCmd uninstall -g $Package --prefix "$npmPrefix" --cache "$npmCache" 2>&1 |
        ForEach-Object { Write-Host $_ }
    return $LASTEXITCODE
}

do {

if ($Tudo -or $CLI -or $Desktop -or $Pacotes) {
    # Modo nao-interativo: pula menu principal
    $modoPrincipal = if ($Remover) { '2' } else { '1' }
    $acaoLabel     = if ($Remover) { 'Remover' } else { 'Instalar' }
    Write-Verbose "[NonInteractive] Modo principal automatico: $acaoLabel"
} else {
    Write-CompactHeader -Title 'Menu principal'
    Write-Host ""
    Write-Host "  O que deseja fazer?" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] Instalar / Atualizar ferramentas" -ForegroundColor Yellow
    Write-Host "  [2] Remover ferramentas" -ForegroundColor Yellow
    Write-Host "  [9] Versao e historico de atualizacoes" -ForegroundColor DarkGray
    Write-Host "  [0] Sair" -ForegroundColor Yellow
    Write-Host ""

    $modoPrincipal = $null
    while ($modoPrincipal -notin @('0','1','2','9')) {
        Write-Host "  Digite o numero da opcao: " -ForegroundColor White -NoNewline
        $key = [Console]::ReadKey($true)
        $modoPrincipal = $key.KeyChar.ToString()
        Write-Host $modoPrincipal
        if ($modoPrincipal -notin @('0','1','2','9')) {
            Write-Host "  Opcao invalida. Tente novamente." -ForegroundColor Red
        }
    }

    if ($modoPrincipal -eq '0') {
        Write-Host "`nSaindo..." -ForegroundColor Gray
        break
    }
}

# ── MODO VERSAO ───────────────────────────────────────────────
if ($modoPrincipal -eq '9') {
    Write-CompactHeader -Title 'Versao e Historico'
    Write-Host ""
    Write-Host "  Script  : Gerenciador de Ferramentas Dev" -ForegroundColor White
    Write-Host "  Versao  : $SCRIPT_VERSION" -ForegroundColor Green
    Write-Host "  Data    : $SCRIPT_DATA" -ForegroundColor White
    Write-Host ""
    Write-Host "  --------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Historico de alteracoes:" -ForegroundColor White
    Write-Host "  --------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $versaoAtual = ""
    foreach ($entry in $CHANGELOG) {
        if ($entry.Versao -ne $versaoAtual) {
            $versaoAtual = $entry.Versao
            Write-Host "  v$($entry.Versao)  ($($entry.Data))" -ForegroundColor Yellow
        }
        Write-Host "    - $($entry.Descricao)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "============================================================`n" -ForegroundColor Cyan
    Write-Host ""
    if (-not (Confirm-Tecla "Voltar ao menu?")) {
        Write-Host "`nSaindo..." -ForegroundColor Gray
        break
    }
    continue
}

# ── MODO REMOCAO ──────────────────────────────────────────────
if ($modoPrincipal -eq '2') {
    Write-CompactHeader -Title 'Remover ferramentas'
    Write-Host ""
    Write-Host "  Selecione o que deseja remover:" -ForegroundColor White
    Write-Host ""
    Write-Host "  --- Ferramentas CLI ---" -ForegroundColor DarkGray
    Write-Host "  [1] Tudo" -ForegroundColor Red
    Write-Host "  [2] Claude Code (CLI)" -ForegroundColor Red
    Write-Host "  [3] Codex CLI (OpenAI)" -ForegroundColor Red
    Write-Host "  [4] OpenCode" -ForegroundColor Red
    Write-Host "  [5] Somente CLI  [Claude Code + Codex CLI + OpenCode]" -ForegroundColor Red
    Write-Host ""
    Write-Host "  --- Apps Desktop ---" -ForegroundColor DarkGray
    Write-Host "  [6] Claude Desktop" -ForegroundColor Red
    Write-Host "  [7] Codex Desktop (OpenAI)" -ForegroundColor Red
    Write-Host "  [8] OpenCode Desktop" -ForegroundColor Red
    Write-Host "  [9] Somente Desktop  [Claude Desktop + Codex Desktop + OpenCode Desktop]" -ForegroundColor Red
    Write-Host ""
    Write-Host "  [0] Voltar" -ForegroundColor Yellow
    Write-Host ""

    # Modo nao-interativo: resolve a partir dos parametros
    if ($Remover -and ($Tudo -or $CLI -or $Desktop -or $Pacotes)) {
        $remClaudeCLI = $remCodexCLI = $remOpenCode = $false
        $remClaudeDesk = $remCodexDesk = $remOpenDesk = $false

        if ($Tudo) {
            $remClaudeCLI = $remCodexCLI = $remOpenCode = $true
            $remClaudeDesk = $remCodexDesk = $remOpenDesk = $true
            $opcaoRem = '1'
        } elseif ($CLI) {
            $remClaudeCLI = $remCodexCLI = $remOpenCode = $true
            $opcaoRem = '5'
        } elseif ($Desktop) {
            $remClaudeDesk = $remCodexDesk = $remOpenDesk = $true
            $opcaoRem = '9'
        } elseif ($Pacotes) {
            if ($Pacotes -contains 'ClaudeCLI')  { $remClaudeCLI  = $true }
            if ($Pacotes -contains 'CodexCLI')   { $remCodexCLI   = $true }
            if ($Pacotes -contains 'OpenCode')   { $remOpenCode   = $true }
            if ($Pacotes -contains 'ClaudeDesk') { $remClaudeDesk = $true }
            if ($Pacotes -contains 'CodexDesk')  { $remCodexDesk  = $true }
            if ($Pacotes -contains 'OpenDesk')   { $remOpenDesk   = $true }
            $opcaoRem = 'P'
        }
        Write-Host "  [NonInteractive] Selecao para remocao via parametros: $opcaoRem" -ForegroundColor Gray
    } else {
        $opcaoRem = $null
        while ($opcaoRem -notin @('0','1','2','3','4','5','6','7','8','9')) {
            Write-Host "  Digite o numero da opcao: " -ForegroundColor White -NoNewline
            $key = [Console]::ReadKey($true)
            $opcaoRem = $key.KeyChar.ToString()
            Write-Host $opcaoRem
            if ($opcaoRem -notin @('0','1','2','3','4','5','6','7','8','9')) {
                Write-Host "  Opcao invalida. Tente novamente." -ForegroundColor Red
            }
        }

        if ($opcaoRem -eq '0') { continue }

        $remClaudeCLI  = $opcaoRem -in @('1','2','5')
        $remCodexCLI   = $opcaoRem -in @('1','3','5')
        $remOpenCode   = $opcaoRem -in @('1','4','5')
        $remClaudeDesk = $opcaoRem -in @('1','6','9')
        $remCodexDesk  = $opcaoRem -in @('1','7','9')
        $remOpenDesk   = $opcaoRem -in @('1','8','9')
    }

    Write-Host ""
    Write-Host "  Itens que serao removidos:" -ForegroundColor White
    if ($remClaudeCLI)  { Write-Host "    - Claude Code (CLI)"          -ForegroundColor Red }
    if ($remCodexCLI)   { Write-Host "    - Codex CLI"                  -ForegroundColor Red }
    if ($remOpenCode)   { Write-Host "    - OpenCode"                   -ForegroundColor Red }
    if ($remClaudeDesk) { Write-Host "    - Claude Desktop"             -ForegroundColor Red }
    if ($remCodexDesk)  { Write-Host "    - Codex Desktop"              -ForegroundColor Red }
    if ($remOpenDesk)   { Write-Host "    - OpenCode Desktop"           -ForegroundColor Red }
    Write-Host ""

    if (-not (Confirm-Tecla "Confirmar remocao?")) { continue }

    try {
        $wingetOk = $false
        try {
            $null = & winget --version 2>&1
            $wingetOk = ($LASTEXITCODE -eq 0)
        } catch { }

        # Garante npm no PATH para remocao CLI
        $uRemocao = Get-UsuarioInterativo
        $npmPaths = @(
            "$env:ProgramFiles\nodejs",
            (Join-Path $uRemocao.LocalAppData "nodejs"),
            (Join-Path $uRemocao.AppData "npm"),
            (Join-Path $uRemocao.LocalAppData "Microsoft\WinGet\Links")
        )
        foreach ($p in $npmPaths) {
            if ((Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) -and ($env:Path -notlike "*$p*")) {
                $env:Path = "$p;$env:Path"
            }
        }

        if ($remClaudeCLI) {
            Write-Step "Removendo Claude Code (CLI)..."

            # Metodo 1: winget
            if ($wingetOk) {
                try {
                    $out = & winget uninstall --id Anthropic.ClaudeCode --exact --silent --scope user --accept-source-agreements --disable-interactivity 2>&1 | Out-String
                    Write-Host $out
                } catch { }
            }

            # Metodo 2: npm uninstall
            try { $null = Invoke-NpmUninstallGlobal -Package '@anthropic-ai/claude-code' } catch { }

            # Metodo 3: busca ampla por executavel claude em todos os locais conhecidos
            $claudeLocais = @(
                "$env:USERPROFILE\.local\bin\claude.exe",
                "$env:USERPROFILE\.local\bin\claude",
                "$env:USERPROFILE\.local\share\claude",
                "$env:APPDATA\npm\claude.exe",
                "$env:APPDATA\npm\claude",
                "$env:APPDATA\npm\claude.cmd",
                "$env:APPDATA\npm\claude.ps1",
                "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Links\claude.exe",
                "$env:USERPROFILE\.claude\local"
            )
            foreach ($p in $claudeLocais) {
                if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
                    Write-Ok "Encontrado em: $p"
                    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            # Busca dinamica: procura claude.exe em qualquer lugar no perfil do usuario
            try {
                $encontrados = Get-ChildItem -Path $env:USERPROFILE -Filter "claude.exe" -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch "AnthropicClaude" } # Exclui Claude Desktop
                foreach ($f in $encontrados) {
                    Write-Ok "Encontrado em: $($f.FullName)"
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                }
            } catch { }

            # Remove variaveis de ambiente relacionadas ao Claude Code
            Write-Step "Removendo variaveis de ambiente do Claude Code..."
            $claudeEnvVars = @(
                "CLAUDE_CODE_GIT_BASH_PATH",
                "CLAUDE_CODE_USE_BEDROCK",
                "CLAUDE_CODE_USE_VERTEX",
                "CLAUDE_CODE_API_KEY_HELPER_TTL_MS",
                "CLAUDE_CODE_SKIP_PERMISSIONS_CHECK"
            )
            foreach ($var in $claudeEnvVars) {
                $val = [Environment]::GetEnvironmentVariable($var, "User")
                if ($val) {
                    [Environment]::SetEnvironmentVariable($var, $null, "User")
                    Write-Ok "Variavel removida: $var"
                }
                # Configuracoes de maquina pertencem ao administrador e nao sao
                # alteradas no fluxo de usuario comum.
            }

            # Remove entradas do PATH que apontam para o Claude
            Write-Step "Limpando PATH..."
            $pathUser = [Environment]::GetEnvironmentVariable("Path", "User")
            $pathEntradas = $pathUser -split ";"
            $pathLimpo = ($pathEntradas | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '(?i)claude'
            }) -join ";"
            if ($pathLimpo -ne $pathUser) {
                [Environment]::SetEnvironmentVariable("Path", $pathLimpo, "User")
                Write-Ok "PATH atualizado."
            }

            # Verifica resultado
            $claudeAinda = (Get-CliToolInfo -Cmd 'claude' -NpmPackage '@anthropic-ai/claude-code').Installed
            if (-not $claudeAinda) {
                Write-Ok "Claude Code removido com sucesso."
            } else {
                Write-Warn "Claude Code ainda detectado. Pode ser necessario reiniciar o terminal."
            }
        }

        if ($remCodexCLI) {
            Write-Step "Removendo Codex CLI..."

            try { $null = Invoke-NpmUninstallGlobal -Package '@openai/codex' } catch { }

            $codexLocais = @(
                "$env:APPDATA\npm\codex.exe",
                "$env:APPDATA\npm\codex",
                "$env:APPDATA\npm\codex.cmd",
                "$env:APPDATA\npm\codex.ps1",
                "$env:APPDATA\npm\node_modules\@openai\codex",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Links\codex.exe"
            )
            foreach ($p in $codexLocais) {
                if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
                    Write-Ok "Encontrado em: $p"
                    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            # Remove variaveis de ambiente do Codex
            foreach ($var in @("OPENAI_API_KEY_PATH","CODEX_HOME")) {
                if ([Environment]::GetEnvironmentVariable($var, "User")) {
                    [Environment]::SetEnvironmentVariable($var, $null, "User")
                    Write-Ok "Variavel removida: $var"
                }
            }

            $codexAinda = (Get-CliToolInfo -Cmd 'codex' -NpmPackage '@openai/codex').Installed
            if (-not $codexAinda) {
                Write-Ok "Codex CLI removido com sucesso."
            } else {
                Write-Warn "Codex CLI ainda detectado. Pode ser necessario reiniciar o terminal."
            }
        }

        if ($remOpenCode) {
            Write-Step "Removendo OpenCode..."

            try { $null = Invoke-NpmUninstallGlobal -Package 'opencode-ai' } catch { }

            $openLocais = @(
                "$env:APPDATA\npm\opencode.exe",
                "$env:APPDATA\npm\opencode",
                "$env:APPDATA\npm\opencode.cmd",
                "$env:APPDATA\npm\opencode.ps1",
                "$env:APPDATA\npm\node_modules\opencode-ai",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Links\opencode.exe"
            )
            foreach ($p in $openLocais) {
                if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
                    Write-Ok "Encontrado em: $p"
                    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            $openAinda = (Get-CliToolInfo -Cmd 'opencode' -NpmPackage 'opencode-ai').Installed
            if (-not $openAinda) {
                Write-Ok "OpenCode removido com sucesso."
            } else {
                Write-Warn "OpenCode ainda detectado. Pode ser necessario reiniciar o terminal."
            }
        }

        if ($remClaudeDesk) {
            Write-Step "Removendo Claude Desktop..."
            $removido = $false

            # Metodo 1: desinstalador nativo (Update.exe)
            $updateExe = "$env:LOCALAPPDATA\AnthropicClaude\Update.exe"
            if (Test-Path -LiteralPath $updateExe -ErrorAction SilentlyContinue) {
                try {
                    $proc = Start-Process $updateExe -ArgumentList "--uninstall" -Wait -NoNewWindow -PassThru -ErrorAction Stop
                    $removido = ($proc.ExitCode -eq 0)
                } catch { }
            }

            # Metodo 2: winget
            if (-not $removido -and $wingetOk) {
                try {
                    $out = & winget uninstall --id Anthropic.Claude --exact --silent --scope user --accept-source-agreements --disable-interactivity 2>&1 | Out-String
                    Write-Host $out
                    if ($LASTEXITCODE -eq 0) { $removido = $true }
                } catch { }
            }

            # Metodo 3: pacote MSIX registrado para o usuario atual
            if (-not $removido) {
                try {
                    $pkg = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
                        $_.Name -match '(?i)(Claude|Anthropic)' -or $_.PackageFamilyName -match '(?i)(Claude|Anthropic)'
                    } | Select-Object -First 1
                    if ($pkg) {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                        $removido = $true
                    }
                } catch { }
            }

            # Metodo 4: remover pasta diretamente
            $claudeDeskPath = "$env:LOCALAPPDATA\AnthropicClaude"
            if (Test-Path -LiteralPath $claudeDeskPath -ErrorAction SilentlyContinue) {
                try { Remove-Item -LiteralPath $claudeDeskPath -Recurse -Force -ErrorAction SilentlyContinue; $removido = $true } catch { }
            }

            if ($removido) {
                Write-Ok "Claude Desktop removido com sucesso."
            } else {
                Write-Warn "Nao foi possivel remover automaticamente. Remova pelo Painel de Controle > Aplicativos."
            }
        }

        if ($remCodexDesk) {
            Write-Step "Removendo Codex Desktop..."
            $removido = $false
            if ($wingetOk) {
                # Tenta pelo ID da Store e pelo nome
                foreach ($id in @('9PLM9XGG6VKS', 'OpenAI.Codex')) {
                    try {
                        $sourceArgs = if ($id -eq '9PLM9XGG6VKS') { @('--source','msstore') } else { @() }
                        $out = & winget uninstall --id $id @sourceArgs --silent --accept-source-agreements --disable-interactivity 2>&1 | Out-String
                        if ($LASTEXITCODE -eq 0) {
                            $removido = $true; break
                        }
                    } catch { }
                }
            }
            if (-not $removido) {
                try {
                    $pkg = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
                        $_.Name -match '(?i)(ChatGPT|Codex|OpenAI)' -or $_.PackageFamilyName -match '(?i)(ChatGPT|Codex|OpenAI)'
                    } | Select-Object -First 1
                    if ($pkg) {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
                        $removido = $true
                    }
                } catch { }
            }
            if ($removido) {
                Write-Ok "Codex Desktop removido com sucesso."
            } else {
                Write-Warn "Nao foi possivel remover automaticamente. Remova pelo Painel de Controle."
            }
        }

        if ($remOpenDesk) {
            Write-Step "Removendo OpenCode Desktop..."
            $removido = $false
            if ($wingetOk) {
                try {
                    $out = & winget uninstall --id SST.OpenCodeDesktop --exact --silent --scope user --accept-source-agreements --disable-interactivity 2>&1 | Out-String
                    if ($LASTEXITCODE -eq 0) { $removido = $true }
                } catch { }
            }
            if (-not $removido) {
                try {
                    $pkg = Get-AppxPackage -Name "*OpenCode*" -ErrorAction SilentlyContinue
                    if ($pkg) {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
                        $removido = $true
                    }
                } catch { }
            }
            if ($removido) {
                Write-Ok "OpenCode Desktop removido com sucesso."
            } else {
                Write-Warn "Nao foi possivel remover automaticamente. Remova pelo Painel de Controle."
            }
        }

        Write-Host "`n============================================================" -ForegroundColor Cyan
        Write-Host "  Remocao concluida!" -ForegroundColor Green
        Write-Host "============================================================`n" -ForegroundColor Cyan

    } catch {
        Write-Host "`n[ERR] Erro durante remocao: $_" -ForegroundColor Red
    }

    Write-Host ""
    if (-not (Confirm-Tecla "Voltar ao menu?")) {
        Write-Host "`nSaindo..." -ForegroundColor Gray
        break
    }
    continue
}

# ── MODO INSTALACAO ───────────────────────────────────────────
Write-CompactHeader -Title 'Instalar / Atualizar'
Write-Host ""
Write-Host "  Selecione o que deseja instalar/atualizar:" -ForegroundColor White
Write-Host ""
Write-Host "  [1] Tudo  [CLI + Desktop]" -ForegroundColor Green
Write-Host ""
Write-Host "  --- Ferramentas CLI ---" -ForegroundColor DarkGray
Write-Host "  [2] Claude Code (CLI)           [instala Git Bash automaticamente]" -ForegroundColor Yellow
Write-Host "  [3] Codex CLI (OpenAI)" -ForegroundColor Yellow
Write-Host "  [4] OpenCode (CLI)" -ForegroundColor Yellow
Write-Host "  [5] Somente CLI  [Claude Code + Codex CLI + OpenCode]" -ForegroundColor Yellow
Write-Host ""
Write-Host "  --- Apps Desktop ---" -ForegroundColor DarkGray
Write-Host "  [6] Claude Desktop" -ForegroundColor Yellow
Write-Host "  [7] Codex Desktop (OpenAI)" -ForegroundColor Yellow
Write-Host "  [8] OpenCode Desktop" -ForegroundColor Yellow
Write-Host "  [9] Somente Desktop  [Claude Desktop + Codex Desktop + OpenCode Desktop]" -ForegroundColor Yellow
Write-Host ""
Write-Host "  [0] Voltar" -ForegroundColor Yellow
Write-Host ""

# --- Resolucao da opcao via parametros (modo nao-interativo) ou prompt (interativo) ---
$instalarGit        = $false
$instalarClaudeCLI  = $false
$instalarCodexCLI   = $false
$instalarOpenCode   = $false
$instalarClaudeDesk = $false
$instalarCodexDesk  = $false
$instalarOpenDesk   = $false
$codexDesktopOk     = $false

if ($Tudo -or $CLI -or $Desktop -or $Pacotes) {
    if ($Tudo) {
        $instalarGit = $instalarClaudeCLI = $instalarCodexCLI = $instalarOpenCode = $true
        $instalarClaudeDesk = $instalarCodexDesk = $instalarOpenDesk = $true
        $opcao = '1'
    } elseif ($CLI) {
        $instalarGit = $instalarClaudeCLI = $instalarCodexCLI = $instalarOpenCode = $true
        $opcao = '5'
    } elseif ($Desktop) {
        $instalarClaudeDesk = $instalarCodexDesk = $instalarOpenDesk = $true
        $opcao = '9'
    } elseif ($Pacotes) {
        if ($Pacotes -contains 'Git')        { $instalarGit        = $true }
        if ($Pacotes -contains 'ClaudeCLI')  { $instalarClaudeCLI  = $true; $instalarGit = $true }
        if ($Pacotes -contains 'CodexCLI')   { $instalarCodexCLI   = $true }
        if ($Pacotes -contains 'OpenCode')   { $instalarOpenCode   = $true }
        if ($Pacotes -contains 'ClaudeDesk') { $instalarClaudeDesk = $true }
        if ($Pacotes -contains 'CodexDesk')  { $instalarCodexDesk  = $true }
        if ($Pacotes -contains 'OpenDesk')   { $instalarOpenDesk   = $true }
        $opcao = 'P'
    }
    Write-Host "  [NonInteractive] Selecao via parametros: $opcao" -ForegroundColor Gray
} else {
    $opcao = $null
    while ($opcao -notin @('0','1','2','3','4','5','6','7','8','9')) {
        Write-Host "  Digite o numero da opcao: " -ForegroundColor White -NoNewline
        $key = [Console]::ReadKey($true)
        $opcao = $key.KeyChar.ToString()
        Write-Host $opcao
        if ($opcao -notin @('0','1','2','3','4','5','6','7','8','9')) {
            Write-Host "  Opcao invalida. Tente novamente." -ForegroundColor Red
        }
    }

    if ($opcao -eq '0') { continue }

    $instalarGit        = $opcao -in @('1','2','5')
    $instalarClaudeCLI  = $opcao -in @('1','2','5')
    $instalarCodexCLI   = $opcao -in @('1','3','5')
    $instalarOpenCode   = $opcao -in @('1','4','5')
    $instalarClaudeDesk = $opcao -in @('1','6','9')
    $instalarCodexDesk  = $opcao -in @('1','7','9')
    $instalarOpenDesk   = $opcao -in @('1','8','9')
}

Write-Host ""
Write-Host "  Itens selecionados:" -ForegroundColor White
if ($instalarGit)        { Write-Host "    - Git Bash"                  -ForegroundColor Cyan }
if ($instalarClaudeCLI)  { Write-Host "    - Claude Code (CLI)"         -ForegroundColor Cyan }
if ($instalarCodexCLI)   { Write-Host "    - Codex CLI"                 -ForegroundColor Cyan }
if ($instalarOpenCode)   { Write-Host "    - OpenCode"                  -ForegroundColor Cyan }
if ($instalarClaudeDesk) { Write-Host "    - Claude Desktop"            -ForegroundColor Cyan }
if ($instalarCodexDesk)  { Write-Host "    - Codex Desktop"             -ForegroundColor Cyan }
if ($instalarOpenDesk)   { Write-Host "    - OpenCode Desktop"          -ForegroundColor Cyan }
Write-Host ""
Pause-Readable 2

try {

# ----------------------------------------------------------
# Atualiza PATH na sessao para detectar ferramentas ja instaladas
# ----------------------------------------------------------
# Detecta usuario real (em cenario UAC com outra conta, retorna dono do explorer.exe)
$usuarioReal = Get-UsuarioInterativo

if ($usuarioReal.ElevadoComOutroUsr) {
    Write-Warn "UAC detectado: script rodando como '$env:USERNAME', usuario interativo e '$($usuarioReal.Username)'."
    Write-Ok  "Instalacoes CLI serao direcionadas para: $($usuarioReal.UserProfile)"
}

$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            "$($usuarioReal.UserProfile)\.local\bin" + ";" +
            "$($usuarioReal.AppData)\npm" + ";" +
            [Environment]::GetEnvironmentVariable("Path", "User")

# ----------------------------------------------------------
# Garante que npm instala no perfil do usuario logado
# (em TS/UAC, APPDATA do usuario real, nao do admin elevado)
# ----------------------------------------------------------
if ($instalarCodexCLI -or $instalarOpenCode) {
    $npmGlobalDir = "$($usuarioReal.AppData)\npm"
    try {
    # Cria o diretorio no perfil do usuario real (admin tem permissao)
    if (-not (Test-Path -LiteralPath $npmGlobalDir -ErrorAction SilentlyContinue)) {
        New-Item -ItemType Directory -Path $npmGlobalDir -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # Nao setamos npm config set prefix aqui porque quando elevado como admif,
    # afetaria o .npmrc do admif, nao o do usuario real. O --prefix explicito
    # em cada 'npm install -g' (via Invoke-NpmInstallGlobal) resolve isso.

    # Garante que esta no PATH da sessao
    if ($env:Path -notlike "*$npmGlobalDir*") {
        $env:Path = "$npmGlobalDir;$env:Path"
    }

    # Repara/reescreve .npmrc do usuario real (detecta e corrige linhas malformadas tipo
    # "prefix=X\npmcache=Y" observadas em v2.9.0 e anteriores). Helper Repair-NpmRc
    # garante CRLF + UTF8 sem BOM.
    $realNpmRc = Join-Path $usuarioReal.UserProfile ".npmrc"
    $realNpmCache = "$($usuarioReal.AppData)\npm-cache"
    [void](Repair-NpmRc -Path $realNpmRc -Prefix $npmGlobalDir -Cache $realNpmCache)

    # Tambem repara o .npmrc do usuario que roda o processo (admif em cenarios UAC)
    # para evitar que o npm leia um arquivo corrompido de execucoes anteriores.
    if ($env:USERPROFILE -and ($env:USERPROFILE -ne $usuarioReal.UserProfile)) {
        $adminNpmRc = Join-Path $env:USERPROFILE ".npmrc"
        [void](Repair-NpmRc -Path $adminNpmRc -Prefix $npmGlobalDir -Cache $realNpmCache)
    }
} catch { }

# ----------------------------------------------------------
# Detecta disponibilidade do WinGet na sessao do usuario
# ----------------------------------------------------------
$wingetOk = $false
try {
    $null = & winget --version 2>&1
    $wingetOk = ($LASTEXITCODE -eq 0)
    } catch { }
}

if ($wingetOk) {
    Write-Ok "winget disponivel. Usando instalacao silenciosa."
} else {
    Write-Warn "winget nao disponivel. Usando metodos alternativos."
}

# ----------------------------------------------------------
# DIAGNOSTICO - chama funcao e filtra apenas o que precisa de acao
# ----------------------------------------------------------
if ($SkipDiagnostico) {
    Write-Warn "Diagnostico inicial ignorado por -SkipDiagnostico. A selecao original sera processada."
    $diagResultado = [PSCustomObject]@{
        Prosseguir = $true
        Git        = $instalarGit
        ClaudeCLI  = $instalarClaudeCLI
        CodexCLI   = $instalarCodexCLI
        OpenCode   = $instalarOpenCode
        ClaudeDesk = $instalarClaudeDesk
        CodexDesk  = $instalarCodexDesk
        OpenDesk   = $instalarOpenDesk
    }
} else {
    $diagResultado = Invoke-Diagnostico `
        -CheckGit        $instalarGit `
        -CheckClaudeCLI  $instalarClaudeCLI `
        -CheckCodexCLI   $instalarCodexCLI `
        -CheckOpenCode   $instalarOpenCode `
        -CheckClaudeDesk $instalarClaudeDesk `
        -CheckCodexDesk  $instalarCodexDesk `
        -CheckOpenDesk   $instalarOpenDesk
}

if (-not $diagResultado.Prosseguir) {
    Write-Host ""
    if (-not (Confirm-Tecla "Voltar ao menu?")) { break }
    continue
}

# Atualiza flags para executar APENAS o que o diagnostico indicou precisar
if ($instalarGit)        { $instalarGit        = $diagResultado.Git }
if ($instalarClaudeCLI)  { $instalarClaudeCLI  = $diagResultado.ClaudeCLI }
if ($instalarCodexCLI)   { $instalarCodexCLI   = $diagResultado.CodexCLI }
if ($instalarOpenCode)   { $instalarOpenCode   = $diagResultado.OpenCode }
if ($instalarClaudeDesk) { $instalarClaudeDesk = $diagResultado.ClaudeDesk }
if ($instalarCodexDesk)  { $instalarCodexDesk  = $diagResultado.CodexDesk }
if ($instalarOpenDesk)   { $instalarOpenDesk   = $diagResultado.OpenDesk }

# ============================================================
# DASHBOARD: inicia banner e contador de fases
# ============================================================
$fasesAtivas = 0
if ($instalarGit)        { $fasesAtivas++ }
if ($instalarClaudeDesk) { $fasesAtivas++ }
if ($instalarClaudeCLI)  { $fasesAtivas++ }
if ($instalarCodexDesk)  { $fasesAtivas++ }
if ($instalarOpenDesk)   { $fasesAtivas++ }
if ($instalarCodexCLI)   { $fasesAtivas++ }
if ($instalarOpenCode)   { $fasesAtivas++ }
if ($instalarGit -or $instalarClaudeCLI -or $instalarCodexCLI -or $instalarOpenCode -or
    $instalarClaudeDesk -or $instalarCodexDesk -or $instalarOpenDesk) { $fasesAtivas++ }
Start-Dashboard -TotalPhases $fasesAtivas
Write-Banner

# ============================================================
# 1. GIT BASH
# ============================================================
if ($instalarGit) {
    Write-Phase "Git Bash"

    Write-Step "Verificando Git Bash..."

    # Resolve usuario interativo real (TS/UAC-aware)
    $uGit = Get-UsuarioInterativo
    if ($uGit.ElevadoComOutroUsr) {
        Write-Warn "Git Bash sera checado no perfil do usuario interativo '$($uGit.Username)', nao em '$env:USERNAME'."
    }

    # Candidatos de instalacao (ordem: user-scope real > system > user-scope do elevado > x86)
    $gitCandidatePaths = @(
        @{ Path = "$($uGit.LocalAppData)\Programs\Git"; Escopo = "user (real)"   ; Correto = $true  },
        @{ Path = "C:\Program Files\Git";               Escopo = "system"         ; Correto = $true  },
        @{ Path = "$env:ProgramFiles\Git";              Escopo = "system (proc)"  ; Correto = $true  },
        @{ Path = "${env:ProgramFiles(x86)}\Git";       Escopo = "system x86"     ; Correto = $true  },
        @{ Path = "C:\Program Files (x86)\Git";         Escopo = "system x86"     ; Correto = $true  },
        @{ Path = "$env:LOCALAPPDATA\Programs\Git";     Escopo = "user (elevado)" ; Correto = $false }
    )

    $gitBashPath      = $null
    $gitCmdExe        = $null
    $gitEscopoAtual   = $null
    $gitLocalErrado   = $false
    $gitCandidatosEncontrados = @()

    foreach ($c in $gitCandidatePaths) {
        $candidateCmd = "$($c.Path)\cmd\git.exe"
        if (Test-Path -LiteralPath $candidateCmd -ErrorAction SilentlyContinue) {
            $gitCandidatosEncontrados += [PSCustomObject]@{ Path = $c.Path; CmdExe = $candidateCmd; Escopo = $c.Escopo; Correto = $c.Correto }
            # Primeira descoberta vira a "atual", salvo se for substituida por uma correta adiante
            if (-not $gitBashPath) {
                $gitBashPath    = $c.Path
                $gitCmdExe      = $candidateCmd
                $gitEscopoAtual = $c.Escopo
                $gitLocalErrado = -not $c.Correto
            } elseif ($gitLocalErrado -and $c.Correto) {
                # Prefere instalacao em local correto se ja tinhamos detectado em local errado
                $gitBashPath    = $c.Path
                $gitCmdExe      = $candidateCmd
                $gitEscopoAtual = $c.Escopo
                $gitLocalErrado = $false
            }
        }
    }

    if ($gitCandidatosEncontrados.Count -gt 1) {
        Write-Warn "Foram encontradas $($gitCandidatosEncontrados.Count) instalacoes do Git Bash:"
        foreach ($g in $gitCandidatosEncontrados) {
            $tag = if ($g.Correto) { "OK" } else { "LOCAL ERRADO" }
            Write-Host "   - [$tag] $($g.Path) ($($g.Escopo))" -ForegroundColor DarkGray
        }
    }

    if ($gitLocalErrado) {
        Write-Warn "Git Bash atualmente apontando para local INCORRETO: $gitBashPath ($gitEscopoAtual)."
        Write-Warn "Em Terminal Server, o Git deve ficar em '$($uGit.LocalAppData)\Programs\Git' ou 'C:\Program Files\Git'."
    }

    # Fallback: Get-Command no PATH do processo atual
    if (-not $gitBashPath) {
        try {
            $gitInPath   = (Get-Command git -ErrorAction Stop).Source
            $gitBashPath = Split-Path (Split-Path $gitInPath -Parent) -Parent
            $gitCmdExe   = $gitInPath
            $gitEscopoAtual = "PATH"
            Write-Ok "Git encontrado via PATH: $gitInPath"
        } catch { }
    }

    # Fallback: registro Windows (HKLM e hive do usuario real se possivel)
    if (-not $gitBashPath) {
        try {
            $regPaths = @(
                "HKLM:\SOFTWARE\GitForWindows",
                "HKCU:\SOFTWARE\GitForWindows"
            )
            # Se temos SID do usuario real, tenta tambem o hive dele
            if ($uGit.Sid) {
                $regPaths = @("Registry::HKEY_USERS\$($uGit.Sid)\SOFTWARE\GitForWindows") + $regPaths
            }
            foreach ($reg in $regPaths) {
                $regVal = Get-ItemProperty -Path $reg -Name InstallPath -ErrorAction SilentlyContinue
                if ($regVal -and (Test-Path -LiteralPath "$($regVal.InstallPath)\cmd\git.exe" -ErrorAction SilentlyContinue)) {
                    $gitBashPath = $regVal.InstallPath
                    $gitCmdExe   = "$gitBashPath\cmd\git.exe"
                    $gitEscopoAtual = "registro"
                    Write-Ok "Git encontrado via registro: $gitBashPath"
                    break
                }
            }
        } catch { }
    }

    try {
        $release   = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $asset     = $release.assets | Where-Object { $_.name -match "Git-.*-64-bit\.exe" } | Select-Object -First 1
        $latestVer = ($release.tag_name -replace '^v' -replace '\.windows\.\d+$')
    } catch {
        Write-Warn "Nao foi possivel consultar a versao mais recente do Git Bash: $_"
        $latestVer = $null
        $asset     = $null
    }

    # ---- Se encontrado em local ERRADO, oferece reinstalacao em local correto ----
    if ($gitLocalErrado -and $asset) {
        Write-Warn "Reinstalando Git Bash no perfil correto para evitar problemas em sessoes multiplas..."
        $gitBashPathCorreto = "$($uGit.LocalAppData)\Programs\Git"
        $gitInstaller = "$env:TEMP\git-installer.exe"
        try {
            Write-Step "Baixando Git Bash..."
            $null = Invoke-FastDownload -Url $asset.browser_download_url -OutFile $gitInstaller -Label "Git Bash"
            Write-Step "Instalando em: $gitBashPathCorreto (user-scope do usuario real)"
            $installArgs = @(
                "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-",
                "/CURRENTUSER",
                "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS",
                "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh",
                "/DIR=`"$gitBashPathCorreto`""
            )
            $gitProc = Start-Process -FilePath $gitInstaller -ArgumentList $installArgs -Wait -NoNewWindow -PassThru -ErrorAction Stop
            if ($gitProc.ExitCode -ne 0) { throw "O instalador do Git encerrou com o codigo $($gitProc.ExitCode)." }
            if (Test-Path -LiteralPath "$gitBashPathCorreto\cmd\git.exe") {
                $gitBashPath    = $gitBashPathCorreto
                $gitCmdExe      = "$gitBashPathCorreto\cmd\git.exe"
                $gitEscopoAtual = "user (real)"
                $gitLocalErrado = $false
                Write-Ok "Git Bash reinstalado em: $gitBashPath"
            } else {
                Write-Warn "Reinstalacao nao produziu Git em $gitBashPathCorreto; mantendo instalacao anterior."
            }
        } catch {
            Set-OperationFailure -Name 'Git Bash' -Reason $_.Exception.Message
            Write-Fail "Erro ao reinstalar Git Bash no local correto: $_"
        } finally {
            if (Test-Path $gitInstaller) { Remove-Item $gitInstaller -Force }
        }
        Pause-Readable 3
    }

    if ($gitBashPath) {
        Write-Ok "Git Bash encontrado em: $gitBashPath ($gitEscopoAtual)"

        if ($latestVer -and (Test-Path $gitCmdExe)) {
            try {
                $installedOutput = & $gitCmdExe --version 2>&1
                $installedVer    = ($installedOutput -replace '^git version ' -replace '\.windows\.\d+$').Trim()

                Write-Ok "Versao instalada   : $installedVer"
                Write-Ok "Versao mais recente: $latestVer"

                if ($installedVer -eq $latestVer) {
                    Write-Ok "Git Bash esta atualizado. Nenhuma acao necessaria."
                    Pause-Readable 3
                } else {
                    Write-Warn "Atualizacao disponivel: $installedVer -> $latestVer"
                    Write-Step "Baixando e instalando atualizacao do Git Bash..."
                    $gitInstaller = "$env:TEMP\git-installer.exe"
                    try {
                        $null = Invoke-FastDownload -Url $asset.browser_download_url -OutFile $gitInstaller -Label "Git Bash $latestVer"
                        # Mesmo que exista uma copia de maquina, a atualizacao e
                        # instalada no perfil atual para nunca solicitar UAC.
                        $gitBashPathAlvo = "$($uGit.LocalAppData)\Programs\Git"
                        $installArgs = @(
                            "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-",
                            "/CURRENTUSER",
                            "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS",
                            "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh",
                            "/DIR=`"$gitBashPathAlvo`""
                        )
                        $gitProc = Start-Process -FilePath $gitInstaller -ArgumentList $installArgs -Wait -NoNewWindow -PassThru -ErrorAction Stop
                        $gitCmdAlvo = "$gitBashPathAlvo\cmd\git.exe"
                        if ($gitProc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $gitCmdAlvo)) {
                            throw "O instalador encerrou com codigo $($gitProc.ExitCode) e o Git nao foi confirmado no destino."
                        }
                        $versaoConfirmada = ((& $gitCmdAlvo --version 2>&1) -replace '^git version ' -replace '\.windows\.\d+$').Trim()
                        if ($versaoConfirmada -ne $latestVer) {
                            throw "Versao esperada $latestVer, mas foi detectada $versaoConfirmada."
                        }
                        $gitBashPath = $gitBashPathAlvo
                        $gitCmdExe = $gitCmdAlvo
                        Write-Ok "Git Bash atualizado para $latestVer em escopo de usuario."
                        Pause-Readable 3
                    } catch {
                        Set-OperationFailure -Name 'Git Bash' -Reason $_.Exception.Message
                        Write-Fail "Erro ao atualizar Git Bash: $_"
                        Pause-Readable 3
                    } finally {
                        if (Test-Path $gitInstaller) { Remove-Item $gitInstaller -Force }
                    }
                }
            } catch {
                Write-Warn "Nao foi possivel verificar a versao instalada do Git: $_"
                Pause-Readable 3
            }
        } else {
            Write-Warn "Nao foi possivel comparar versoes. Verifique manualmente se o Git Bash esta atualizado."
            Pause-Readable 3
        }

    } else {
        # Nenhuma instalacao encontrada - instala em user-scope do usuario real (preferido em TS)
        $gitBashPath = "$($uGit.LocalAppData)\Programs\Git"
        $gitCmdExe   = "$gitBashPath\cmd\git.exe"

        if (-not $asset) {
            Write-Fail "Nao foi possivel obter o instalador do Git Bash. Verifique sua conexao."
            Pause-Readable 3
        } else {
            Write-Step "Git Bash nao encontrado. Iniciando instalacao em user-scope do usuario real..."
            Write-Ok "Destino: $gitBashPath"
            Write-Ok "Versao encontrada: $($asset.name)"
            $gitInstaller = "$env:TEMP\git-installer.exe"
            try {
                Write-Step "Baixando Git Bash..."
                $null = Invoke-FastDownload -Url $asset.browser_download_url -OutFile $gitInstaller -Label "Git Bash"
                Write-Step "Instalando Git Bash (modo silencioso, /CURRENTUSER)..."
                $installArgs = @(
                    "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-",
                    "/CURRENTUSER",
                    "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS",
                    "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh",
                    "/DIR=`"$gitBashPath`""
                )
                $gitProc = Start-Process -FilePath $gitInstaller -ArgumentList $installArgs -Wait -NoNewWindow -PassThru -ErrorAction Stop
                if ($gitProc.ExitCode -ne 0) { throw "O instalador do Git encerrou com o codigo $($gitProc.ExitCode)." }
                if (Test-Path $gitCmdExe) {
                    Write-Ok "Git Bash instalado com sucesso em: $gitBashPath"
                    Pause-Readable 3
                } else {
                    Write-Fail "Instalacao do Git Bash falhou. Verifique manualmente."
                    Pause-Readable 3
                }
            } catch {
                Set-OperationFailure -Name 'Git Bash' -Reason $_.Exception.Message
                Write-Fail "Erro ao instalar Git Bash: $_"
                Pause-Readable 3
            } finally {
                if (Test-Path $gitInstaller) { Remove-Item $gitInstaller -Force }
            }
        }
    }

    if ($gitBashPath -and $instalarClaudeCLI) {
        Write-Step "Configurando CLAUDE_CODE_GIT_BASH_PATH..."
        $gitBashExe = Find-GitBashExecutable
        if (-not $gitBashExe) {
            foreach ($candidate in @(
                (Join-Path $gitBashPath 'bin\bash.exe'),
                (Join-Path $gitBashPath 'usr\bin\bash.exe')
            )) {
                if (Test-Path -LiteralPath $candidate -PathType Leaf -ErrorAction SilentlyContinue) {
                    $gitBashExe = $candidate
                    break
                }
            }
        }
        $currentVal = Get-UserEnvVar -Name "CLAUDE_CODE_GIT_BASH_PATH"
        if (-not $gitBashExe) {
            Write-Warn "Git foi detectado, mas o executavel bash.exe nao foi encontrado em $gitBashPath."
        } elseif ((ConvertTo-NormalizedPathEntry $currentVal) -ieq (ConvertTo-NormalizedPathEntry $gitBashExe)) {
            Write-Ok "CLAUDE_CODE_GIT_BASH_PATH ja esta configurado. Nenhuma alteracao necessaria."
        } else {
            $null = Set-UserEnvVar -Name "CLAUDE_CODE_GIT_BASH_PATH" -Value $gitBashExe
            $env:CLAUDE_CODE_GIT_BASH_PATH = $gitBashExe
            $null = Broadcast-EnvChange
            Write-Ok "CLAUDE_CODE_GIT_BASH_PATH = $gitBashExe (usuario '$($uGit.Username)')"
        }
        Pause-Readable 3
    }
}

# ============================================================
# 2. CLAUDE DESKTOP
#    Com winget    -> instalacao silenciosa
#    Sem winget    -> MSIX oficial mais recente (x64/ARM64)
# ============================================================
function Install-ClaudeDesktopMsix {
    [CmdletBinding()]
    param()

    $u = Get-UsuarioInterativo
    $windowsArch = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    } else {
        $env:PROCESSOR_ARCHITECTURE
    }

    $packageArch = switch ($windowsArch.ToUpperInvariant()) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        default { $null }
    }

    if (-not $packageArch) {
        Write-Fail "Arquitetura do Windows nao suportada pelo Claude Desktop: $windowsArch"
        Write-Warn "Use a pagina oficial: https://claude.com/download"
        return $false
    }

    $msixUrl = "https://claude.ai/api/desktop/win32/$packageArch/msix/latest/redirect"
    $keepPackage = [bool]$u.ElevadoComOutroUsr
    $packagePath = if ($keepPackage) {
        Join-Path $u.UserProfile "Downloads\Claude-latest-$packageArch.msix"
    } else {
        Join-Path $env:TEMP "Claude-latest-$packageArch.msix"
    }

    try {
        Write-Step "Baixando o MSIX oficial mais recente do Claude Desktop ($packageArch)..."
        $downloadOk = Invoke-FastDownload -Url $msixUrl -OutFile $packagePath -Label "Claude Desktop (MSIX $packageArch)"
        if (-not $downloadOk -or -not (Test-Path -LiteralPath $packagePath)) {
            throw "O download do pacote MSIX nao foi concluido."
        }

        # MSIX e um container ZIP e deve iniciar com a assinatura PK.
        $stream = [System.IO.File]::OpenRead($packagePath)
        try {
            $byte1 = $stream.ReadByte()
            $byte2 = $stream.ReadByte()
        } finally {
            $stream.Dispose()
        }
        if ($byte1 -ne 0x50 -or $byte2 -ne 0x4B) {
            throw "O arquivo baixado nao possui uma assinatura MSIX valida."
        }

        if ($u.ElevadoComOutroUsr) {
            Write-Warn "UAC executado com outra conta; o MSIX nao sera registrado no perfil do administrador."
            Write-Ok "Pacote atual salvo para o usuario '$($u.Username)': $packagePath"
            Write-Warn "Abra esse arquivo na sessao do usuario para concluir a instalacao."
            return $false
        }

        if (-not (Get-Command Add-AppxPackage -ErrorAction SilentlyContinue)) {
            throw "Add-AppxPackage nao esta disponivel neste Windows."
        }

        Write-Step "Instalando o pacote MSIX oficial..."
        Add-AppxPackage -Path $packagePath -ForceApplicationShutdown -ErrorAction Stop | Out-Null

        $installedInfo = Get-ClaudeDesktopInfo -WingetOk $false
        if (-not $installedInfo.Installed) {
            throw "A instalacao terminou, mas o Claude Desktop nao foi detectado."
        }

        Write-Ok "Claude Desktop instalado com sucesso pelo MSIX oficial."
        Write-Ok "Pesquise por 'Claude' no Menu Iniciar para abrir o app."
        return $true
    } catch {
        Set-OperationFailure -Name 'Claude Desktop' -Reason $_.Exception.Message
        Write-Fail "Falha ao instalar o Claude Desktop pelo MSIX oficial: $_"
        Write-Warn "Baixe manualmente em: https://claude.com/download"
        return $false
    } finally {
        if (-not $keepPackage -and (Test-Path -LiteralPath $packagePath -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-ClaudeCodeNative {
    $u = Get-UsuarioInterativo
    if ($u.ElevadoComOutroUsr) {
        Write-Fail "Claude Code deve ser instalado na sessao do proprio usuario."
        return $false
    }

    $installerPath = Join-Path $env:TEMP "claude-code-install.ps1"
    try {
        Write-Step "Baixando o instalador nativo atual do Claude Code..."
        $ok = Invoke-FastDownload -Url "https://claude.ai/install.ps1" -OutFile $installerPath -Label "Claude Code"
        if (-not $ok -or -not (Test-Path -LiteralPath $installerPath)) {
            throw "O instalador oficial nao foi baixado."
        }

        $installerText = Get-Content -LiteralPath $installerPath -Raw -ErrorAction Stop
        if ($installerText -match '(?i)<html' -or $installerText -notmatch '(?i)claude') {
            throw "A resposta recebida nao parece ser o instalador PowerShell do Claude Code."
        }

        $windowsPowerShell = Get-Command powershell.exe -ErrorAction Stop
        Write-Step "Executando o instalador nativo no perfil '$($u.Username)'..."
        $proc = Start-Process -FilePath $windowsPowerShell.Source `
            -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$installerPath`"") `
            -Wait -NoNewWindow -PassThru -ErrorAction Stop
        if ($proc.ExitCode -ne 0) {
            throw "O instalador encerrou com o codigo $($proc.ExitCode)."
        }

        $claudeBin = Join-Path $u.UserProfile ".local\bin"
        $null = Set-UserEnvVar -Name "Path" -Value $claudeBin -Append
        if ($env:Path -notlike "*$claudeBin*") { $env:Path = "$claudeBin;$env:Path" }

        $installed = Get-CliToolInfo -Cmd "claude" -NpmPackage "@anthropic-ai/claude-code"
        if (-not $installed.Installed) {
            throw "A instalacao terminou, mas o comando claude nao foi detectado."
        }

        Write-Ok "Claude Code instalado/atualizado em escopo de usuario."
        return $true
    } catch {
        Set-OperationFailure -Name 'Claude Code' -Reason $_.Exception.Message
        Write-Fail "Falha no instalador nativo do Claude Code: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }
}

if ($instalarClaudeDesk) {
    Write-Phase "Claude Desktop"

    Write-Step "Verificando Claude Desktop..."

    $claudeDesktopInfo = Get-ClaudeDesktopInfo -WingetOk $wingetOk
    if ($claudeDesktopInfo.Installed) {
        if ($claudeDesktopInfo.Version) {
            Write-Ok "Claude Desktop ja esta instalado. Versao: $($claudeDesktopInfo.Version)"
        } else {
            Write-Ok "Claude Desktop ja esta instalado. Origem: $($claudeDesktopInfo.Method)"
        }
        if ($wingetOk) {
            Write-Step "Verificando atualizacoes..."
            try {
                & winget upgrade --id Anthropic.Claude --exact --silent --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
                    Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                    ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
                if ($LASTEXITCODE -ne 0) { throw "WinGet encerrou com o codigo $LASTEXITCODE." }
                if (Test-WingetUpgradeAvailable -Id 'Anthropic.Claude') { throw "A atualizacao continua pendente depois da execucao do WinGet." }
                Write-Ok "Atualizacao do Claude Desktop concluida."
            } catch {
                Write-Warn "WinGet nao conseguiu atualizar o Claude Desktop: $_"
                Write-Step "Tentando o pacote MSIX oficial mais recente..."
                $null = Install-ClaudeDesktopMsix
            }
        }
        Pause-Readable 3
    } elseif ($wingetOk) {
        Write-Step "Instalando Claude Desktop via winget (silencioso)..."
        try {
            & winget install --id Anthropic.Claude --exact --silent --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
                Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
            if ($LASTEXITCODE -ne 0) {
                throw "WinGet encerrou com o codigo $LASTEXITCODE."
            }

            $claudeDesktopInfo = Get-ClaudeDesktopInfo -WingetOk $true
            if (-not $claudeDesktopInfo.Installed) {
                throw "O WinGet terminou sem erro, mas o Claude Desktop nao foi detectado."
            }

            Write-Ok "Claude Desktop instalado com sucesso via WinGet."
            Write-Ok "Pesquise por 'Claude' no Menu Iniciar para abrir o app."
        } catch {
            Write-Warn "Falha ao instalar via WinGet: $_"
            Write-Step "Tentando o pacote MSIX oficial mais recente..."
            $null = Install-ClaudeDesktopMsix
        }
        Pause-Readable 3
    } else {
        Write-Warn "winget nao disponivel neste sistema."
        Write-Host ""
        Write-Host "  O script pode baixar e instalar o MSIX oficial mais recente:" -ForegroundColor White
        Write-Host "  https://claude.com/download" -ForegroundColor Cyan
        Write-Host ""
        if (Confirm-Tecla 'Deseja baixar e instalar o pacote atual agora?') {
            $null = Install-ClaudeDesktopMsix
        }
        Pause-Readable 3
    }
}

# ============================================================
# 3. CLAUDE CODE (CLI)
# ============================================================
if ($instalarClaudeCLI) {
    Write-Phase "Claude Code CLI"
    Write-Step "Verificando Claude Code (CLI)..."
    $claudeInfo = Get-CliToolInfo -Cmd "claude" -NpmPackage "@anthropic-ai/claude-code"
    if ($claudeInfo.Installed) {
        Write-Ok "Claude Code ja esta instalado. Versao: $($claudeInfo.Version)"
        Write-Step "Verificando atualizacoes..."
        try {
            $npmInfo      = Invoke-RestMethod "https://registry.npmjs.org/@anthropic-ai/claude-code/latest"
            $latestVer    = $npmInfo.version
            $installedVer = ($claudeInfo.Version -replace '^[^\d]*').Trim() -split '\s+' | Select-Object -First 1
            if ([string]::IsNullOrWhiteSpace($installedVer)) {
                Write-Ok "Claude Code detectado em: $($claudeInfo.Source)"
                Write-Warn "Versao instalada nao identificada. Reaplicando o instalador nativo atual."
                $null = Install-ClaudeCodeNative
            } elseif ($installedVer -eq $latestVer) {
                Write-Ok "Versao instalada   : $installedVer"
                Write-Ok "Versao mais recente: $latestVer"
                Write-Ok "Claude Code esta atualizado. Nenhuma acao necessaria."
            } else {
                Write-Ok "Versao instalada   : $installedVer"
                Write-Ok "Versao mais recente: $latestVer"
                Write-Warn "Atualizacao disponivel: $installedVer -> $latestVer"
                $null = Install-ClaudeCodeNative
            }
        } catch {
            Write-Warn "Nao foi possivel verificar atualizacoes: $_"
            Write-Step "Tentando o instalador nativo atual mesmo assim..."
            $null = Install-ClaudeCodeNative
        }
    } else {
        Write-Step "Claude Code nao encontrado. Instalando pelo metodo nativo oficial..."
        $null = Install-ClaudeCodeNative
    }
    Pause-Readable 3
}

# ============================================================
# 5. CODEX DESKTOP (OpenAI)
#    Com winget    -> instalacao silenciosa
#    Sem winget    -> orienta download manual (Microsoft Store)
# ============================================================
if ($instalarCodexDesk) {
    Write-Phase "Codex Desktop"

    Write-Step "Verificando Codex Desktop (OpenAI)..."

    $codexDesktopOk = $false
    $codexDesktopInfo = Get-CodexDesktopInfo -WingetOk $wingetOk

    if ($codexDesktopInfo.Installed) {
        $codexDesktopOk = $true
        if ($codexDesktopInfo.Version) {
            Write-Ok "Codex Desktop ja esta instalado. Versao: $($codexDesktopInfo.Version)"
        } else {
            Write-Ok "Codex Desktop ja esta instalado. Origem: $($codexDesktopInfo.Method)"
        }

        if ($wingetOk) {
            Write-Step "Verificando atualizacoes..."
            try {
                & winget upgrade --id 9PLM9XGG6VKS --source msstore --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
                    Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                    ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
                if ($LASTEXITCODE -ne 0) { throw "WinGet encerrou com o codigo $LASTEXITCODE." }
                if (Test-WingetUpgradeAvailable -Id '9PLM9XGG6VKS' -Source 'msstore') { throw "A atualizacao continua pendente depois da execucao do WinGet." }
                Write-Ok "Verificacao do ChatGPT/Codex Desktop concluida."
            } catch {
                Set-OperationFailure -Name 'Codex Desktop' -Reason $_.Exception.Message
                Write-Warn "Nao foi possivel verificar atualizacoes: $_"
            }
        }
        Pause-Readable 3
    } elseif ($wingetOk) {
        Write-Step "Codex Desktop nao encontrado. Instalando via winget (silencioso)..."
        try {
            & winget install --id 9PLM9XGG6VKS --source msstore --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
                Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
            if ($LASTEXITCODE -ne 0) { throw "WinGet encerrou com o codigo $LASTEXITCODE." }
            $codexDepois = Get-CodexDesktopInfo -WingetOk $true
            if (-not $codexDepois.Installed) { throw "A instalacao terminou, mas o aplicativo nao foi detectado." }
            $codexDesktopOk = $true
            Write-Ok "ChatGPT/Codex Desktop instalado com sucesso."
            Write-Ok "Pesquise por 'ChatGPT' no Menu Iniciar para abrir o app."
            Pause-Readable 3
        } catch {
            Set-OperationFailure -Name 'Codex Desktop' -Reason $_.Exception.Message
            Write-Fail "Falha ao instalar Codex Desktop: $_"
            Write-Warn "Tente manualmente: https://apps.microsoft.com/detail/9plm9xgg6vks"
            Pause-Readable 4
        }
    } else {
        Write-Warn "winget nao disponivel neste sistema."
        Write-Host ""
        Write-Host "  Baixe e instale o Codex Desktop manualmente:" -ForegroundColor White
        Write-Host "  https://get.microsoft.com/installer/download/9PLM9XGG6VKS?cid=website_cta_psi" -ForegroundColor Cyan
        Write-Host ""
        if (Confirm-Tecla 'Deseja realizar o download agora?') {
            $uCodexDesk = Get-UsuarioInterativo
            $setupPath = Join-Path $uCodexDesk.UserProfile "Downloads\ChatGPTSetup.exe"
            try {
                Write-Step "Baixando Codex Desktop..."
                $null = Invoke-FastDownload -Url "https://get.microsoft.com/installer/download/9PLM9XGG6VKS?cid=website_cta_psi" -OutFile $setupPath -Label "Codex Desktop"
                $bytes = [System.IO.File]::ReadAllBytes($setupPath)
                if ($bytes[0] -eq 77 -and $bytes[1] -eq 90) {
                    Write-Ok "Download concluido: $setupPath"
                    Write-Warn "Execute o arquivo para instalar o ChatGPT/Codex Desktop."
                } else {
                    Remove-Item $setupPath -Force
                    Write-Fail "O arquivo baixado nao e valido. Acesse o link manualmente."
                }
            } catch {
                Write-Fail "Falha no download: $_"
            }
        }
        Pause-Readable 3
    }
}

# ============================================================
# 5b. OPENCODE DESKTOP
# ============================================================
function Install-OpenCodeDesktopOfficial {
    [CmdletBinding()]
    param()

    $u = Get-UsuarioInterativo
    if ($u.ElevadoComOutroUsr) {
        Write-Fail "OpenCode Desktop deve ser instalado na sessao do proprio usuario."
        return $false
    }

    $windowsArch = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    } else {
        $env:PROCESSOR_ARCHITECTURE
    }
    $packageArch = switch ($windowsArch.ToUpperInvariant()) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        default { $null }
    }
    if (-not $packageArch) {
        Write-Fail "Arquitetura do Windows nao suportada pelo OpenCode Desktop: $windowsArch"
        return $false
    }

    $installerPath = Join-Path $env:TEMP "opencode-desktop-$packageArch.exe"
    try {
        Write-Step "Consultando a versao oficial mais recente do OpenCode Desktop..."
        $release = Invoke-RestMethod 'https://api.github.com/repos/anomalyco/opencode/releases/latest' `
            -Headers @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'inf-tools-ia-install' } `
            -ErrorAction Stop
        $assetPattern = "^opencode-desktop-(?:win|windows)-$packageArch\.exe$"
        $asset = $release.assets | Where-Object { $_.name -match $assetPattern } | Select-Object -First 1
        if (-not $asset) {
            throw "A release $($release.tag_name) nao possui instalador Windows $packageArch."
        }

        Write-Step "Baixando $($asset.name) da release oficial $($release.tag_name)..."
        $ok = Invoke-FastDownload -Url $asset.browser_download_url -OutFile $installerPath -Label "OpenCode Desktop"
        if (-not $ok -or -not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
            throw "O download do instalador oficial nao foi concluido."
        }

        $stream = [System.IO.File]::OpenRead($installerPath)
        try {
            $byte1 = $stream.ReadByte()
            $byte2 = $stream.ReadByte()
        } finally {
            $stream.Dispose()
        }
        if ($byte1 -ne 0x4D -or $byte2 -ne 0x5A) {
            throw "O arquivo baixado nao possui uma assinatura executavel valida."
        }

        Write-Step "Instalando OpenCode Desktop no perfil do usuario..."
        $proc = Start-Process -FilePath $installerPath -ArgumentList @('/S') `
            -Wait -PassThru -ErrorAction Stop
        if ($proc.ExitCode -ne 0) {
            throw "O instalador encerrou com o codigo $($proc.ExitCode)."
        }

        $installedInfo = Get-OpenCodeDesktopInfo -WingetOk $false
        if (-not $installedInfo.Installed) {
            throw "A instalacao terminou, mas o OpenCode Desktop nao foi detectado."
        }

        Write-Ok "OpenCode Desktop instalado com sucesso pelo pacote oficial."
        Write-Ok "Procure por 'OpenCode' no Menu Iniciar para abrir o app."
        return $true
    } catch {
        Set-OperationFailure -Name 'OpenCode Desktop' -Reason $_.Exception.Message
        Write-Fail "Falha no instalador oficial do OpenCode Desktop: $($_.Exception.Message)"
        Write-Warn "Baixe manualmente em: https://opencode.ai/download"
        return $false
    } finally {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }
}

if ($instalarOpenDesk) {
    Write-Phase "OpenCode Desktop"

    Write-Step "Verificando OpenCode Desktop..."

    $openDesktopInfo = Get-OpenCodeDesktopInfo -WingetOk $wingetOk
    if ($openDesktopInfo.Installed) {
        if ($openDesktopInfo.Version) {
            Write-Ok "OpenCode Desktop ja esta instalado. Versao: $($openDesktopInfo.Version)"
        } else {
            Write-Ok "OpenCode Desktop ja esta instalado. Origem: $($openDesktopInfo.Method)"
        }
        if ($wingetOk) {
            Write-Step "Verificando atualizacoes..."
            try {
                & winget upgrade --id SST.OpenCodeDesktop --exact --silent --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
                    Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                    ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
                if ($LASTEXITCODE -ne 0) { throw "WinGet encerrou com o codigo $LASTEXITCODE." }
                if (Test-WingetUpgradeAvailable -Id 'SST.OpenCodeDesktop') { throw "A atualizacao continua pendente depois da execucao do WinGet." }
                Write-Ok "Verificacao do OpenCode Desktop concluida."
            } catch {
                Write-Warn "Nao foi possivel verificar atualizacoes: $_"
                Write-Step "Tentando o instalador oficial mais recente..."
                $null = Install-OpenCodeDesktopOfficial
            }
        }
        Pause-Readable 3
    } elseif ($wingetOk) {
        Write-Step "OpenCode Desktop nao encontrado. Instalando via winget..."
        try {
            & winget install --id SST.OpenCodeDesktop --exact --silent --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
                Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
            if ($LASTEXITCODE -ne 0) { throw "WinGet encerrou com o codigo $LASTEXITCODE." }
            $openDepois = Get-OpenCodeDesktopInfo -WingetOk $true
            if (-not $openDepois.Installed) { throw "A instalacao terminou, mas o OpenCode Desktop nao foi detectado." }
            Write-Ok "OpenCode Desktop instalado com sucesso."
            Write-Ok "Procure por 'OpenCode' no Menu Iniciar para abrir o app."
            Pause-Readable 3
        } catch {
            Write-Warn "Falha ao instalar OpenCode Desktop via WinGet: $_"
            Write-Step "Tentando o instalador oficial mais recente..."
            $null = Install-OpenCodeDesktopOfficial
            Pause-Readable 4
        }
    } else {
        Write-Warn "winget nao disponivel. Usando o instalador oficial do OpenCode Desktop."
        $null = Install-OpenCodeDesktopOfficial
        Pause-Readable 3
    }
}

# ============================================================
# 6. CODEX CLI (OpenAI) — npm i -g @openai/codex
# (usa Invoke-NpmTool para passar --prefix/--cache explicitos e
#  evitar dependencia de .npmrc do usuario que pode estar malformado)
# ============================================================
if ($instalarCodexCLI) {
    Write-Phase "Codex CLI"
    Invoke-NpmTool -Label "Codex CLI" -Cmd "codex" -Package "@openai/codex" -NpmName "@openai/codex"
}

# ============================================================
# 7. OPENCODE   via npm
# ============================================================
if ($instalarOpenCode) {
    Write-Phase "OpenCode (npm)"
    Invoke-NpmTool -Label "OpenCode" -Cmd "opencode" -Package "opencode-ai" -NpmName "opencode-ai"
}

# ----------------------------------------------------------
# PATH: garantir diretorio e entrada no PATH do usuario
# (apenas quando ferramentas CLI foram selecionadas)
# ----------------------------------------------------------
$algumaCLI = $instalarGit -or $instalarClaudeCLI -or $instalarCodexCLI -or $instalarOpenCode

if ($algumaCLI) {
    # ---- SEMPRE resolve o usuario interativo real (suporta UAC com outro admin) ----
    $uPath = Get-UsuarioInterativo
    if ($uPath.ElevadoComOutroUsr) {
        Write-Warn "PATH sera gravado no hive do usuario interativo '$($uPath.Username)' (nao em '$env:USERNAME')."
    }

    $targetDir = "$($uPath.UserProfile)\.local\bin"

    Write-Step "Verificando diretorio $targetDir..."
    if (-not (Test-Path -LiteralPath $targetDir -ErrorAction SilentlyContinue)) {
        try {
            New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction Stop | Out-Null
            Write-Ok "Diretorio criado: $targetDir"
        } catch {
            Write-Warn "Nao foi possivel criar ${targetDir}: $($_.Exception.Message)"
        }
    } else {
        Write-Ok "Diretorio ja existe: $targetDir"
    }

    # Diretorios que precisam estar no PATH para CMD e PowerShell
    # Marcamos quais podem ser criados automaticamente (apenas dentro do perfil do usuario real)
    $pathDirs = @(
        @{ Path = $targetDir;                                Criar = $true  },  # %USERPROFILE%\.local\bin (usuario real)
        @{ Path = "$($uPath.AppData)\npm";                   Criar = $true  },  # npm do usuario real
        @{ Path = "$($uPath.LocalAppData)\Programs\Git\cmd"; Criar = $false },  # Git Bash user-scope (preferido em TS)
        @{ Path = "$($uPath.LocalAppData)\Programs\Git\bin"; Criar = $false },  # Git Bash user-scope
        @{ Path = "$env:ProgramFiles\nodejs";                Criar = $false },  # Node.js system-wide
        @{ Path = "$env:ProgramFiles\Git\cmd";               Criar = $false },  # Git Bash system-wide
        @{ Path = "$env:ProgramFiles\Git\bin";               Criar = $false }   # Git Bash system-wide
    )

    Write-Step "Verificando e corrigindo PATH do usuario real..."
    $null = Test-And-Fix-Path

    # Le PATH direto do hive do usuario interativo real (nao do usuario elevado)
    $currentPath = Get-UserEnvVar -Name "Path"
    if ([string]::IsNullOrWhiteSpace($currentPath)) { $currentPath = "" }
    $pathAtualizado = $false

    foreach ($entrada in $pathDirs) {
        $dir   = $entrada.Path
        $criar = $entrada.Criar

        if (-not (Test-Path -LiteralPath $dir -ErrorAction SilentlyContinue)) {
            if ($criar) {
                try {
                    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
                } catch {
                    Write-Warn "Nao foi possivel criar ${dir}: $($_.Exception.Message)"
                    continue
                }
            } else {
                # Diretorio protegido ou opcional - so adiciona ao PATH se ja existir
                continue
            }
        }
        $jaExiste = ($currentPath -split ";") | Where-Object { $_ -ieq $dir }
        if (-not $jaExiste) {
            $currentPath = ($currentPath.TrimEnd(";") + ";" + $dir).TrimStart(";")
            Write-Ok "Adicionado ao PATH (usuario real): $dir"
            $pathAtualizado = $true
        } else {
            Write-Ok "Ja no PATH (usuario real): $dir"
        }
    }

    if ($pathAtualizado) {
        # Grava no hive do usuario interativo real (HKU:\SID\Environment)
        $okSet = Set-UserEnvVar -Name "Path" -Value $currentPath
        if ($okSet) {
            Write-Ok "PATH do usuario '$($uPath.Username)' atualizado com sucesso."
            # Broadcast WM_SETTINGCHANGE para que Explorer/novos processos vejam as mudancas
            $null = Broadcast-EnvChange
            Write-Ok "Broadcast WM_SETTINGCHANGE enviado (novos terminais ja vao enxergar)."
        } else {
            Write-Warn "Falha ao gravar PATH no hive do usuario real. Fallback escopo User local..."
            try {
                [Environment]::SetEnvironmentVariable("Path", $currentPath, "User")
                Write-Ok "PATH gravado em fallback (escopo User do processo atual)."
            } catch {
                Write-Fail "Nao foi possivel gravar PATH: $($_.Exception.Message)"
            }
        }
        Write-Warn "Abra um novo CMD ou PowerShell para que as alteracoes tenham efeito."
        Pause-Readable 3
    } else {
        Write-Ok "PATH ja contempla todas as entradas necessarias."
    }

    # Atualiza PATH na sessao atual (PowerShell corrente) combinando Machine + User(real)
    $pathMaquinaAtual = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = ($pathMaquinaAtual.TrimEnd(";") + ";" + $currentPath.TrimStart(";")).TrimEnd(";")
}

# ----------------------------------------------------------
# TESTE FINAL DE INICIALIZACAO (apos instalacoes e PATH)
# ----------------------------------------------------------
if ($algumaCLI -or $instalarClaudeDesk -or $instalarCodexDesk -or $instalarOpenDesk) {
    Write-Phase 'Teste final de inicializacao'
    $null = Invoke-StartupHealthCheck `
        -CheckGit        $instalarGit `
        -CheckClaudeCLI  $instalarClaudeCLI `
        -CheckCodexCLI   $instalarCodexCLI `
        -CheckOpenCode   $instalarOpenCode `
        -CheckClaudeDesk $instalarClaudeDesk `
        -CheckCodexDesk  $instalarCodexDesk `
        -CheckOpenDesk   $instalarOpenDesk `
        -RecordFailures
}

# ----------------------------------------------------------
# VERIFICACAO FINAL e RESUMO VISUAL
# ----------------------------------------------------------
$algumInstalado = $false

$gitFailure = Get-OperationFailure -Name 'Git Bash'
if ($instalarGit -and $gitFailure) {
    Add-InstallResult -Nome "Git Bash" -Status "FALHOU" -Obs $gitFailure
} elseif ($instalarGit -and $gitCmdExe -and (Test-Path $gitCmdExe)) {
    try {
        $v = (& $gitCmdExe --version 2>&1 | Out-String).Trim()
        Add-InstallResult -Nome "Git Bash" -Status "OK" -Versao $v -Local $gitBashPath
        $algumInstalado = $true
    } catch {
        Add-InstallResult -Nome "Git Bash" -Status "FALHOU" -Obs "nao respondeu --version"
    }
} elseif ($instalarGit) {
    Add-InstallResult -Nome "Git Bash" -Status "FALHOU" -Obs "nao detectado"
}

if ($instalarClaudeCLI) {
    $claudeInfoFinal = Get-CliToolInfo -Cmd "claude" -NpmPackage "@anthropic-ai/claude-code"
    $claudeFailure = Get-OperationFailure -Name 'Claude Code'
    if ($claudeFailure) {
        Add-InstallResult -Nome "Claude Code" -Status "FALHOU" -Obs $claudeFailure
    } elseif ($claudeInfoFinal.Installed) {
        Add-InstallResult -Nome "Claude Code" -Status "OK" -Versao $claudeInfoFinal.Version -Local $claudeInfoFinal.Source
        $algumInstalado = $true
    } else {
        Add-InstallResult -Nome "Claude Code" -Status "FALHOU" -Obs "nao detectado no PATH/npm"
    }
}
if ($instalarCodexCLI) {
    $codexCliInfoFinal = Get-CliToolInfo -Cmd "codex" -NpmPackage "@openai/codex"
    $codexFailure = Get-OperationFailure -Name 'Codex CLI'
    if ($codexFailure) {
        Add-InstallResult -Nome "Codex CLI" -Status "FALHOU" -Obs $codexFailure
    } elseif ($codexCliInfoFinal.Installed) {
        Add-InstallResult -Nome "Codex CLI" -Status "OK" -Versao $codexCliInfoFinal.Version -Local $codexCliInfoFinal.Source
        $algumInstalado = $true
    } else {
        Add-InstallResult -Nome "Codex CLI" -Status "FALHOU" -Obs "nao detectado no PATH/npm"
    }
}
if ($instalarOpenCode) {
    $openInfoFinal = Get-CliToolInfo -Cmd "opencode" -NpmPackage "opencode-ai"
    $openFailure = Get-OperationFailure -Name 'OpenCode'
    if ($openFailure) {
        Add-InstallResult -Nome "OpenCode" -Status "FALHOU" -Obs $openFailure
    } elseif ($openInfoFinal.Installed) {
        Add-InstallResult -Nome "OpenCode" -Status "OK" -Versao $openInfoFinal.Version -Local $openInfoFinal.Source
        $algumInstalado = $true
    } else {
        Add-InstallResult -Nome "OpenCode" -Status "FALHOU" -Obs "nao detectado no PATH/npm"
    }
}
if ($instalarClaudeDesk) {
    $claudeDeskInfoFinal = Get-ClaudeDesktopInfo -WingetOk $wingetOk
    $claudeDeskFailure = Get-OperationFailure -Name 'Claude Desktop'
    if ($claudeDeskFailure) {
        Add-InstallResult -Nome "Claude Desktop" -Status "FALHOU" -Obs $claudeDeskFailure
    } elseif ($claudeDeskInfoFinal.Installed) {
        Add-InstallResult -Nome "Claude Desktop" -Status "OK" -Versao $claudeDeskInfoFinal.Version -Local $claudeDeskInfoFinal.Source
        $algumInstalado = $true
    } elseif ($wingetOk) {
        Add-InstallResult -Nome "Claude Desktop" -Status "FALHOU" -Obs "nao detectado"
    } else {
        Add-InstallResult -Nome "Claude Desktop" -Status "PULADO" -Obs "sem winget"
    }
}

if ($instalarCodexDesk) {
    $codexDeskInfoFinal = Get-CodexDesktopInfo -WingetOk $wingetOk
    $codexDeskFailure = Get-OperationFailure -Name 'Codex Desktop'
    if ($codexDeskFailure) {
        Add-InstallResult -Nome "Codex Desktop" -Status "FALHOU" -Obs $codexDeskFailure
    } elseif ($codexDesktopOk -or $codexDeskInfoFinal.Installed) {
        Add-InstallResult -Nome "Codex Desktop" -Status "OK" -Versao $codexDeskInfoFinal.Version -Local $codexDeskInfoFinal.Source
        $algumInstalado = $true
    } elseif ($wingetOk) {
        Add-InstallResult -Nome "Codex Desktop" -Status "FALHOU" -Obs "nao detectado"
    } else {
        Add-InstallResult -Nome "Codex Desktop" -Status "PULADO" -Obs "sem winget"
    }
}
if ($instalarOpenDesk) {
    $openDeskInfoFinal = Get-OpenCodeDesktopInfo -WingetOk $wingetOk
    $openDeskFailure = Get-OperationFailure -Name 'OpenCode Desktop'
    if ($openDeskFailure) {
        Add-InstallResult -Nome "OpenCode Desktop" -Status "FALHOU" -Obs $openDeskFailure
    } elseif ($openDeskInfoFinal.Installed) {
        Add-InstallResult -Nome "OpenCode Desktop" -Status "OK" -Versao $openDeskInfoFinal.Version -Local $openDeskInfoFinal.Source
        $algumInstalado = $true
    } elseif ($wingetOk) {
        Add-InstallResult -Nome "OpenCode Desktop" -Status "FALHOU" -Obs "nao detectado"
    } else {
        Add-InstallResult -Nome "OpenCode Desktop" -Status "PULADO" -Obs "sem winget"
    }
}

# --- Mostra o resumo visual ---
Show-Summary

$temCLI     = $instalarGit -or $instalarClaudeCLI -or $instalarCodexCLI -or $instalarOpenCode
$temDesktop = $instalarClaudeDesk -or $instalarCodexDesk -or $instalarOpenDesk

if ($algumInstalado) {
    Write-Host ""
    if ($temCLI -and $temDesktop) {
        Write-Ok   "CLI: abra um novo terminal para usar os comandos."
        Write-Ok   "Desktop: pesquise os apps no Menu Iniciar."
    } elseif ($temCLI) {
        Write-Ok   "Abra um novo terminal para usar as ferramentas instaladas."
    } elseif ($temDesktop) {
        Write-Ok   "Pesquise os apps instalados no Menu Iniciar."
    }
    Write-Host ""
}

} catch {
    Write-Host "`n[ERR] Ocorreu um erro inesperado: $_" -ForegroundColor Red
}

Write-Host ""
if (-not (Confirm-Tecla "Voltar ao menu?")) {
    Write-Host "`nSaindo..." -ForegroundColor Gray
    break
}

# Em modo nao-interativo executa o loop apenas uma vez
} while (-not $script:NonInteractive -and -not ($Tudo -or $CLI -or $Desktop -or $Pacotes))

} catch {
    Write-Host "`n[ERR] Erro fatal: $_" -ForegroundColor Red
    Write-Host "[ERR] Linha: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host ""
    if (-not $script:NonInteractive) {
        Read-Host "Pressione ENTER para fechar"
    }
} finally {
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}


















