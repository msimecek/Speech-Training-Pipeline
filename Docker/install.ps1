if (Test-Path "SpeechCLI") {
    Write-Host "SpeechCLI already present."
    exit
}

$currentDir = (Get-Item -Path ".\" -Verbose).FullName

Write-Host "Downloading Speech CLI for Ubuntu."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "https://github.com/msimecek/Azure-Speech-CLI/releases/download/1.1.0/ubuntu-x64-1.1.0.zip" -OutFile "$currentDir/speech-cli.zip"

Write-Host "Unpacking Speech CLI."
Add-Type -Assembly System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory("$currentDir/speech-cli.zip", "$currentDir/");

Write-Host "Done."