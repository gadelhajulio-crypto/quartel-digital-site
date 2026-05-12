$ErrorActionPreference = "SilentlyContinue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = "AAA_EVIDENCIAS_$timestamp.txt"

function Add-Section($title) {
@"
========================================
$title
========================================
"@ | Add-Content -Encoding UTF8 $outFile
}

function Add-Cmd($cmd) {
@"

$ $cmd
----------------------------------------
"@ | Add-Content -Encoding UTF8 $outFile

    try {
        (Invoke-Expression $cmd | Out-String) | Add-Content -Encoding UTF8 $outFile
    } catch {
        ("ERRO: " + $_.Exception.Message) | Add-Content -Encoding UTF8 $outFile
    }
}

function Add-File($path) {
    Add-Section "FILE — $path"
    if (Test-Path $path) {
        Get-Content -Raw -Encoding UTF8 $path | Add-Content -Encoding UTF8 $outFile
    } else {
        "Arquivo não encontrado." | Add-Content -Encoding UTF8 $outFile
    }
}

# Header
@"
RELATÓRIO AAA — EVIDÊNCIAS BRUTAS
Gerado em: $(Get-Date -Format o)
PWD: $(Get-Location)

"@ | Set-Content -Encoding UTF8 $outFile

# H1.1
Add-Section "H1.1 — Inventário de rotas"
if (Test-Path "app")     { Add-Cmd "Get-ChildItem app -Recurse | Select-Object FullName" }
if (Test-Path "src/app") { Add-Cmd "Get-ChildItem src/app -Recurse | Select-Object FullName" }

# H1.2
Add-Section "H1.2 — Arquivos críticos"
Add-File "app/_layout.tsx"
Add-File "src/app/_layout.tsx"
Add-File "src/context/AuthContext.tsx"
Add-File "context/AuthContext.tsx"
Add-File "src/types/auth.ts"
Add-File "src/screens/LoginScreen.tsx"
Add-File "app/login.tsx"
Add-File "app/(auth)/login.tsx"
Add-File "src/app/(auth)/login.tsx"

# Scan de arquivos comuns
Add-Section "H1.2 — Scan serviços de auth (nomes comuns)"
Add-Cmd "Get-ChildItem -Recurse -File -Include *auth*.ts,*auth*.tsx,*supabase*.ts,*session*.ts,*storage*.ts,*interceptor*.ts | Select-Object FullName"

# H1.3
Add-Section "H1.3 — Buscas estáticas (Select-String)"
$patterns = @(
  "if \(session",
  "session &&",
  "router\.replace",
  "requires_mfa",
  "signOut",
  "authStatus",
  "isAuthenticated",
  "session_revoked_reason",
  "v_auth_session"
)

foreach ($p in $patterns) {
    Add-Section "SEARCH — $p"
    try {
        Select-String -Path "." -Pattern $p -Recurse -ErrorAction SilentlyContinue |
          Select-Object Path, LineNumber, Line |
          Format-Table -AutoSize | Out-String |
          Add-Content -Encoding UTF8 $outFile
    } catch {
        ("ERRO SEARCH: " + $_.Exception.Message) | Add-Content -Encoding UTF8 $outFile
    }
}

Add-Section "FIM"
Write-Host ""
Write-Host "Arquivo gerado: $outFile"
Write-Host "Abra o arquivo e cole aqui no chat."