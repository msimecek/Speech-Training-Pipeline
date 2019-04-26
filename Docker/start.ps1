if (($null -eq $env:mode) -or ($env:mode -eq "standard")) {
    Write-Host "Started in standard mode."
    /usr/src/process-docker.ps1
}
elseif ($env:mode -eq "prechunked") {
    Write-Host "Started in prechunked mode."
    /usr/src/process-prechunked.ps1
}
elseif ($env:mode -eq "baseline") {
    Write-Host "Started in baseline mode."
    /usr/src/process-baseline.ps1
}
elseif ($env:mode -eq "debug") {
    Write-Host "Started in debug mode."
    /bin/bash
}
else {
    Write-Error -Message "Invalid mode. Set the 'mode' environmental variable to either 'standard' or 'prechunked'."
}