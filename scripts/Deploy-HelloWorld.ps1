Import-Module WebAdministration

# Configuration 

$sitename = "HelloWorld"
$appName = "HelloWorld"
$appPoolName = "HelloWorldPool"
    
$sitePath = "C:\Eurofins\HelloWorld"
$logPath = "C:\Eurofins\IISLogs"

$groupName = "HelloWorldGroup"
$localUserName = "HelloWorldUser"
$appPoolUser = ".\$localuserName"
$password = "HelloWorld123!"

# Create local user

if (-not (Get-LocalUser -Name $localUserName -ErrorAction SilentlyContinue)) {
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    New-LocalUser -Name $localUserName -Password $securePassword | Out-Null
}

# Create local group

if (-not (Get-LocalGroup -Name $groupName -ErrorAction SilentlyContinue)) {
    New-LocalGroup -Name $groupName
}

if (-not (Get-LocalGroupMember -Group $groupName -Member $localUserName -ErrorAction SilentlyContinue)) {
    Add-LocalGroupMember `
        -Group $groupName `
        -Member $localUserName
}

# Create Application Pool

if (-not (Test-Path "IIS:\AppPools\$appPoolName")) {
    New-WebAppPool -Name $appPoolName
}

# Configure Application Pool Identity

Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name processModel.identityType -Value 3
Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name processModel.userName -Value $appPoolUser
Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name processModel.password -Value $password

# Create Website 

if (-not (Get-Website -Name $sitename -ErrorAction SilentlyContinue)) {
    New-Website `
        -Name $sitename `
        -PhysicalPath $sitePath `
        -Port 8080 `
        -HostHeader "localhost"
}

# Configure IIS log location

if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath
}

Set-WebConfigurationProperty `
    -Filter "system.applicationHost/sites/site[@name='$siteName']/logFile"  `
    -Name "directory" `
    -Value $logPath

# Create HTTPS certificate

$certificate = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -eq "CN=localhost" -and $_.NotAfter -gt (Get-Date) } |
    Select-Object -First 1

if (-not $certificate) {
    $certificate = New-SelfSignedCertificate `
        -DnsName "localhost" `
        -CertStoreLocation "Cert:\LocalMachine\My"
}



# Create HTTPS binding

if (-not (Get-WebBinding -Name $sitename -Protocol "https" -Port 443 -HostHeader "localhost" -ErrorAction SilentlyContinue)) {
    New-WebBinding `
        -Name $sitename `
        -Protocol "https" `
        -Port 443 `
        -HostHeader "localhost"
}

$httpsBinding = Get-WebBinding -Name $sitename -Protocol "https" -Port 443 -HostHeader "localhost"

if (-not $httpsBinding.certificateHash) {
    $httpsBinding.AddSslCertificate($certificate.Thumbprint, "My")
}

# Create IIS application 

if (-not (Get-WebApplication -Site $sitename -Name $appName -ErrorAction SilentlyContinue)) {
    New-WebApplication `
        -Site $sitename `
        -Name $appName `
        -PhysicalPath $sitePath `
        -ApplicationPool $appPoolName
}

# Start IIS

Start-WebAppPool -Name $appPoolName
Start-Website -name $siteName

Write-Host "HelloWorld deployment completed." 







