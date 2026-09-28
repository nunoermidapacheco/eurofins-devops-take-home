# Configuration

$serviceName = "HelloWorldMonitor"
$exePath = "C:\Eurofins\HelloWorldMonitor\HelloWorldMonitor.exe"
$user = ".\HelloWorldUser"
$password = "HelloWorld123!"

# Create the service (auto-start, specific user)

sc.exe create $serviceName binPath= $exePath obj= $user password= $password start= auto

# Error recovery: restart after 300 seconds

sc.exe failure $serviceName reset= 86400 actions= restart/300000
sc.exe failureflag $serviceName 1

# Start the service

sc.exe start $serviceName

Write-Host "HelloWorldMonitor service installed."