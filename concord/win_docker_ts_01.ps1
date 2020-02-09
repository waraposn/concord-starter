Write-Host "Running Admin elevated PS script [$args\win_docker_ts_02.ps1]"
Start-Sleep -Seconds 1
Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File $args\win_docker_ts_02.ps1" -Verb RunAs
