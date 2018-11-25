if (Test-Path "SpeechCLI") {
    Write-Host "SpeechCLI already present."
    exit
}

$currentDir = (Get-Item -Path ".\" -Verbose).FullName

Write-Host "Downloading Speech CLI for Ubuntu."
Invoke-WebRequest -Uri "https://martinovo.blob.core.windows.net/speech/ubuntu-x64-latest.zip" -OutFile "$currentDir/speech-cli.zip"

Write-Host "Unpacking Speech CLI."
Add-Type -Assembly System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory("$currentDir/speech-cli.zip", "$currentDir/");

Write-Host "Done."