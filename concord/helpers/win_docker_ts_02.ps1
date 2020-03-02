Write-Host -NoNewline "Geting DockerVM ... "
$vm = Get-VM -Name DockerDesktopVM
#Start-Sleep -Seconds 1
Write-Host "Successful"
Write-Host "$vm"

$feature = "Time Synchronization"

Write-Host -NoNewline "DockerVM feature[$feature] disable ... "
Disable-VMIntegrationService -vm $vm -Name $feature
#Start-Sleep -Seconds 1
Write-Host "Successful"

Write-Host -NoNewline "DockerVM feature[$feature] enable ... "
Enable-VMIntegrationService -vm $vm -Name $feature
#Start-Sleep -Seconds 1
Write-Host "Successful"
#Start-Sleep -Seconds 1
