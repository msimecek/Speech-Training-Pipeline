if (($null -eq $env:mode) -or ($env:mode -eq "standard")) {
    /usr/src/process-docker.ps1
}
elseif ($env:mode -eq "prechunked") {
    /usr/src/process-prechunked.ps1
}
elseif ($env:mode -eq "debug") {
    Write-Host "Started in debug mode."
    /bin/bash
}
else {
    Write-Error -Message "Invalid mode. Set the 'mode' environmental variable to either 'standard' or 'prechunked'."
}