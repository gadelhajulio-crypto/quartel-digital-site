$ErrorActionPreference = "SilentlyContinue"
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out = "AAA_EVIDENCIAS_$ts.txt"

function Sec($t) {
  Add-Content -Encoding UTF8 $out ""
  Add-Content -Encoding UTF8 $out "========================================"
  Add-Content -Encoding UTF8 $out $t
  Add-Content -Encoding UTF8 $out "========================================"
}

function DumpFile($p) {
  Sec ("FILE - " + $p)
  if (Test-Path $p) {
    Get-Content -Raw -Encoding UTF8 $p | Add-Content -Encoding UTF8 $out
  } else {
    Add-Content -Encoding UTF8 $out "NOT FOUND"
  }
}

# Header
Set-Content -Encoding UTF8 $out ("AAA RAW EVIDENCE" + [Environment]::NewLine + "Generated: " + (Get-Date -Format o) + [Environment]::NewLine + "PWD: " + (Get-Location) + [Environment]::NewLine)

# H1.1 Routes inventory
Sec "H1.1 - Routes inventory"
if (Test-Path "app")     { Get-ChildItem app -Recurse | Select-Object FullName | Out-String | Add-Content -Encoding UTF8 $out }
if (Test-Path "src/app") { Get-ChildItem "src/app" -Recurse | Select-Object FullName | Out-String | Add-Content -Encoding UTF8 $out }

# H1.2 Critical files
Sec "H1.2 - Critical files"
DumpFile "app/_layout.tsx"
DumpFile "src/app/_layout.tsx"
DumpFile "src/context/AuthContext.tsx"
DumpFile "context/AuthContext.tsx"
DumpFile "src/types/auth.ts"
DumpFile "src/screens/LoginScreen.tsx"
DumpFile "app/login.tsx"
DumpFile "app/(auth)/login.tsx"
DumpFile "src/app/(auth)/login.tsx"

# H1.2 Scan common auth related files
Sec "H1.2 - Scan auth/service/session/storage/interceptor files"
Get-ChildItem -Recurse -File -Include "*auth*.ts","*auth*.tsx","*supabase*.ts","*session*.ts","*storage*.ts","*interceptor*.ts" |
  Select-Object FullName | Out-String | Add-Content -Encoding UTF8 $out

# H1.3 Static searches
Sec "H1.3 - Static searches"
$patterns = @(
  "if \(session",
  "session \&\&",
  "router\.replace",
  "requires_mfa",
  "signOut",
  "authStatus",
  "isAuthenticated",
  "session_revoked_reason",
  "v_auth_session"
)

foreach ($pat in $patterns) {
  Sec ("SEARCH - " + $pat)
  Select-String -Path "." -Pattern $pat -Recurse -ErrorAction SilentlyContinue |
    Select-Object Path, LineNumber, Line |
    Format-Table -AutoSize | Out-String |
    Add-Content -Encoding UTF8 $out
}

Sec "END"
Write-Host ""
Write-Host ("Generated file: " + $out)
Write-Host "Open it and paste into chat."