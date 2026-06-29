param (
    [Parameter(Mandatory=$false)]
    [string]$PemKeyPath,

    [Parameter(Mandatory=$false)]
    [string]$Ec2IpAddress
)

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "      IGRIS AWS Deployment Script         " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Resolve the script's own directory (portable, no hardcoded paths)
$BackendDir = $PSScriptRoot

# Prompt for inputs if not provided
if (-not $PemKeyPath) {
    $PemKeyPath = Read-Host "Enter full path to your .pem key file (e.g., C:\Users\sanja\Downloads\igris-key.pem)"
}
if (-not $Ec2IpAddress) {
    $Ec2IpAddress = Read-Host "Enter the Public IPv4 Address of your EC2 instance"
}

# Validate .pem file
if (-not (Test-Path $PemKeyPath)) {
    Write-Host "ERROR: .pem file not found at: $PemKeyPath" -ForegroundColor Red
    exit 1
}

# Validate .env exists and has been configured
$EnvFile = Join-Path $BackendDir ".env"
if (-not (Test-Path $EnvFile)) {
    Write-Host "ERROR: .env file not found at: $EnvFile" -ForegroundColor Red
    Write-Host "Please copy .env.example to .env and fill in your secrets before deploying." -ForegroundColor Yellow
    exit 1
}
if (Select-String -Path $EnvFile -Pattern "CHANGE_ME|your_.*_here|^JWT_SECRET=$" -Quiet) {
    Write-Host "WARNING: .env still contains placeholder values." -ForegroundColor Yellow
    Write-Host "         Fill in all secrets (JWT_SECRET, DB_PASSWORD, etc.) before deploying." -ForegroundColor Yellow
    Write-Host "Proceeding with automated deployment..." -ForegroundColor Cyan
}

# Fix .pem permissions (Windows OpenSSH requirement)
Write-Host "[1/5] Fixing .pem file permissions..." -ForegroundColor Yellow
icacls.exe $PemKeyPath /c /t /inheritance:d | Out-Null
icacls.exe $PemKeyPath /c /t /remove "Administrator" "BUILTIN\Administrators" "BUILTIN\Everyone" "System" "Users" | Out-Null
icacls.exe $PemKeyPath /c /t /grant "$($env:USERNAME):(R)" | Out-Null
Write-Host "      Done." -ForegroundColor Green

# Build the deployment bundle
Write-Host "[2/5] Preparing deployment bundle..." -ForegroundColor Yellow
$zipPath  = "$env:TEMP\igris_backend.zip"
$tempDir  = "$env:TEMP\igris_deploy_temp"

if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# Copy all backend files (excluding dev artifacts)
$excludeFolders = @("node_modules", "logs", "data", ".git", ".venv", "__pycache__")
Get-ChildItem -Path $BackendDir -Force | Where-Object {
    $_.Name -notin $excludeFolders
} | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $tempDir -Recurse -Force
}

# Ensure .env is present (dotfiles can be skipped by some shells)
if (Test-Path $EnvFile) {
    Copy-Item -Path $EnvFile -Destination $tempDir -Force
    Write-Host "      .env included in bundle." -ForegroundColor Green
} else {
    Write-Host "      WARNING: .env not found -- backend will not start!" -ForegroundColor Red
}

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath
Remove-Item $tempDir -Recurse -Force

$zipSizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host "      Bundle created: $zipSizeMB MB" -ForegroundColor Green

# Upload to EC2
Write-Host "[3/5] Uploading to EC2 ($Ec2IpAddress)..." -ForegroundColor Yellow
$setupScript = Join-Path $BackendDir "setup_server.sh"
$scpArgs = "-o", "StrictHostKeyChecking=no", "-i", $PemKeyPath,
           $zipPath, $setupScript,
           "ubuntu@${Ec2IpAddress}:~/"
& scp @scpArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Upload failed. Check:" -ForegroundColor Red
    Write-Host "  - EC2 instance is running (not stopped)" -ForegroundColor Red
    Write-Host "  - Security group allows inbound port 22 (SSH)" -ForegroundColor Red
    Write-Host "  - IP address is correct: $Ec2IpAddress" -ForegroundColor Red
    Write-Host "  - .pem key matches the instance key pair" -ForegroundColor Red
    exit 1
}
Write-Host "      Upload complete." -ForegroundColor Green

# Execute setup on EC2
Write-Host "[4/5] Running server setup on EC2 (takes ~5 min on first run)..." -ForegroundColor Yellow
$sshArgs = "-o", "StrictHostKeyChecking=no", "-i", $PemKeyPath,
           "ubuntu@${Ec2IpAddress}",
           "chmod +x ~/setup_server.sh && ~/setup_server.sh 2>&1"
& ssh @sshArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Server setup failed. To debug, SSH in:" -ForegroundColor Red
    Write-Host "  ssh -i `"$PemKeyPath`" ubuntu@$Ec2IpAddress" -ForegroundColor Yellow
    Write-Host "  sudo docker compose -f ~/igris_backend/docker-compose.prod.yml logs" -ForegroundColor Yellow
    exit 1
}

# Cleanup local temp file
Write-Host "[5/5] Cleaning up..." -ForegroundColor Yellow
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

# Done
Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "       DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Backend URL  : http://${Ec2IpAddress}:8080/api" -ForegroundColor Green
Write-Host "  Health Check : http://${Ec2IpAddress}:8080/health" -ForegroundColor Green
Write-Host ""
Write-Host "  In the IGRIS mobile app:" -ForegroundColor Cyan
Write-Host "    Settings -> API Keys and Server -> Backend Server URL" -ForegroundColor Cyan
Write-Host "    Enter: http://${Ec2IpAddress}:8080/api" -ForegroundColor Cyan
Write-Host ""
Write-Host "  To view live logs after deployment:" -ForegroundColor Cyan
Write-Host "    ssh -i `"$PemKeyPath`" ubuntu@$Ec2IpAddress" -ForegroundColor Cyan
Write-Host "    sudo docker compose -f ~/igris_backend/docker-compose.prod.yml logs -f" -ForegroundColor Cyan
Write-Host ""
