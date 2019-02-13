if (Test-Path "SpeechCLI") {
    Write-Host "SpeechCLI already present."
    exit
}

$version = "1.3.0"

$currentDir = (Get-Item -Path ".\" -Verbose).FullName

Write-Host "Downloading Speech CLI for Ubuntu."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "https://github.com/msimecek/Azure-Speech-CLI/releases/download/$version/ubuntu-x64-$version.zip" -OutFile "$currentDir/speech-cli.zip"

Write-Host "Unpacking Speech CLI."
Add-Type -Assembly System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory("$currentDir/speech-cli.zip", "$currentDir/");

Write-Host "Done."