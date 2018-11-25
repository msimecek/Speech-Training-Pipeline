﻿#
# Before running this script, change initial variables to reflect your environment.
# Run this script from an empty working folder - it will download and produce many files.
#

# TXT file with links to source WAV files. One line = one file.
#$sourceFileUrl = "https://<url>/<file>.txt"
$sourceFileUrl = $env:sourceFileUrl

# TXT file with links to transcription files corresponding to WAV files. One file = complete trascript of the whole WAV file (no timestamps, only text).
#$sourceTranscriptUrl = "https://<url>/<file>.txt"
$sourceTranscriptUrl = $env:sourceTranscriptUrl

# TXT file with language model. Not used in this script.
#$sourceLanguageUrl = "https://<url>/<file>.txt"
$sourceLanguageUrl = $env:sourceLanguageUrl

# ZIP file containing FFmpeg tool (expects ffmpeg.exe in root).
#$ffmpegUrl = "https://<url>/ffmpeg.zip"
$ffmpegUrl = $env:ffmpegUrl

# ZIP file containing Speech Service CLI tool
#$speechCliUrl = "https://<url>.blob.core.windows.net/win-x64-280.zip"
$speechCliUrl = $env:speechCliUrl

# Key to Speech API (get from Azure portal or from Speech, aka CRIS, portal).
#$speechKey = ""
$speechKey = $env:speechKey

# Region where the Speech API is deployed (get from Azure portal or from Speech portal).
#$speechRegion = "northeurope"
$speechRegion = $env:speechRegion

# GUID of speech endpoint to run the initial transcription against. Better endpoint (e.g. with language model, pre-trained etc.) = better results. Get from Speech portal (CRIS.ai).
#$speechEndpoint = ""
$speechEndpoint = $env:speechEndpoint

# If there's a language model already pre-trained, use that.
$languageModelId = $env:languageModelId

# How are datasets, models, tests and endpoints named in Speech Service.
#$processName = ""
$processName = $env:processName

#-----------------------------------------------------

$rootDir = (Get-Item -Path ".\" -Verbose).FullName;

# Test tools.
Write-Host "Checking dependencies."
pip --version
python --version
npm --version
node --version
/usr/bin/SpeechCLI/speech --version

# Parse source files into arrays and remove empty lines. Each line is expected to be a file URL.
Write-Host "Downloading source files."
$sourceWavs = @()
$sourceTxts = @()

$sourceWavs += (Invoke-WebRequest $sourceFileUrl | Select -ExpandProperty Content) -Split '\n' | ? {$_}
$sourceTxts += (Invoke-WebRequest $sourceTranscriptUrl | Select -ExpandProperty Content) -Split '\n' | ? {$_}

# Download WAV files locally
New-Item $rootDir/SourceWavs -ItemType Directory -Force

# Inline syntax
#$sourceWavs | % {$i = 0} { Invoke-WebRequest $_ -OutFile .\SourceWavs\$i.wav; $i++ }

for ($i = 0; $i -lt $sourceWavs.Count; $i++) {  
    # Download WAV file locally to prevent Storage transfer errors    
    Write-Host "($($i + 1)/$($sourceWavs.Count) Downloading source WAV locally."
    Invoke-WebRequest $sourceWavs[$i] -OutFile ./SourceWavs/$i.wav

    # Run FFmpeg on source files - chunk & convert
    New-Item ./Chunks-$i -ItemType Directory -Force
    if ($docker -eq "false") {
        ./ffmpeg/ffmpeg.exe -i $rootDir/SourceWavs/$i.wav -acodec pcm_s16le -vn -ar 16000  -f segment -segment_time 10 -ac 1 $rootDir/Chunks-$i/$i-part%03d.wav
    }
    else {
        ffmpeg -i $rootDir/SourceWavs/$i.wav -acodec pcm_s16le -vn -ar 16000  -f segment -segment_time 10 -ac 1 $rootDir/Chunks-$i/$i-part%03d.wav
    }

    # Download full transcript
    Invoke-WebRequest $sourceTxts[$i] -OutFile $rootDir/$processName-source-transcript-$i.txt

    [byte[]]$byte = Get-Content -ReadCount 4 -TotalCount 4 -Path "$rootDir/$processName-source-transcript-$i.txt" -AsByteStream
    if (!($byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf))
    { 
        Throw "source-transcript-$i.txt is not encoded in 'UTF-8 Signature'."
    }
}

# Get Batcher script
# install dependencies
git clone https://github.com/shanepeckham/CustomSpeech-Processing-Pipeline.git
cd $rootDir/CustomSpeech-Processing-Pipeline/Batcher
npm install

#TODO: if language data available, create baseline endpoint with language model first

# Run Batcher, if there's no machine-transcript present
# - machine transcript creation is time consuming, this allows to skip it if the process needs to be run again
for ($i = 0; $i -lt $sourceWavs.Count; $i++) {
    If (!(Test-Path "$rootDir/$processName-machine-transcript-$i.txt")) {
       node batcher.js --key $speechKey --region $speechRegion --endpoint $speechEndpoint --input "$rootDir/Chunks-$i" --output "$rootDir/$processName-machine-transcript-$i.txt"
    }
}

# Run Transcriber
cd $rootDir/CustomSpeech-Processing-Pipeline/Transcriber
pip3 install -r requirements.txt
python3 -m spacy download en_core_web_lg

New-Item $rootDir/$processName-Cleaned -ItemType Directory -Force
New-Item $rootDir/$processName-Compiled -ItemType Directory -Force

$cleaned = @()
for ($i = 0; $i -lt $sourceWavs.Count; $i++) 
{
    # TODO: exclude from loop, when machine transcript empty
    
    # python transcriber.py -t '11_WTA_ROM_STEPvGARC_2018/11_WTA_ROM_STEPvGARC_2018.txt' -a '11_WTA_ROM_STEPvGARC_2018/11_WTA_ROM_STEPvGARC_OFFSET.txt' -g '11_WTA_ROM_STEPvGARC_TRANSCRIPT_testfunc2.txt'
    # -t = TRANSCRIBED_FILE = official full transcript
    # -a = audio processed file = output from batcher
    # -g = output file
    python3 transcriber.py -t "$rootDir/$processName-source-transcript-$i.txt" -a "$rootDir/$processName-machine-transcript-$i.txt" -g "$rootDir/$processName-matched-transcript-$i.txt"

    # Cleanup (remove NEEDS MANUAL CHECK and files which don't have transcript)
    $present = Get-Content -Path "$rootDir/$processName-matched-transcript-$i.txt" | Where-Object {$_ -notlike "*NEEDS MANUAL CHECK*"}
    
    ForEach ($line in $present) {
        $filename = ($line -split '\t')[0]
        Copy-Item -Path "$rootDir/Chunks-$i/$filename" -Destination "$rootDir/$processName-Cleaned/$filename" # copy all to one place
    }

    $cleaned += $present
}

Write-Host "Transcribe done. Writing cleaned-transcript.txt"
$cleaned | Out-File "$rootDir/$processName-cleaned-transcript.txt"

# Download Speech CLI - not used now, because it's part of the Docker image
# Write-Host "Downloading Speech CLI."
# cd $rootDir
# New-Item "CLI" -ItemType Directory
# Invoke-WebRequest $speechCliUrl -OutFile "speech-cli.zip"
# Add-Type -Assembly System.IO.Compression.FileSystem
# [System.IO.Compression.ZipFile]::ExtractToDirectory("$rootDir/speech-cli.zip", "$rootDir/CLI");
#cd $rootDir/CLI/SpeechCLI

# Config CLI
& /usr/bin/SpeechCLI/speech config set --name Build --key $speechKey --region $speechRegion --select

# Prepare ZIP and TXT for test and train datasets
Write-Host "Compiling audio and transcript files."
& /usr/bin/SpeechCLI/speech compile --audio "$rootDir/$processName-Cleaned" --transcript "$rootDir/$processName-cleaned-transcript.txt" --output "$rootDir/$processName-Compiled" --test-percentage 10

$idPattern = "(\w{8})-(\w{4})-(\w{4})-(\w{4})-(\w{12})"

# Create acoustic datasets
Write-Host "Creating acoustic datasets for training and testing."
$trainDataset = & /usr/bin/SpeechCLI/speech dataset create --name $processName --audio "$rootDir/$processName-Compiled/Train.zip" --transcript "$rootDir/$processName-Compiled/train.txt" --wait | Select-String $idPattern | % {$_.Matches.Groups[0].Value}
$testDataset = & /usr/bin/SpeechCLI/speech dataset create --name "$processName-Test" --audio "$rootDir/$processName-Compiled/Test.zip" --transcript "$rootDir/$processName-Compiled/test.txt" --wait | Select-String $idPattern | % {$_.Matches.Groups[0].Value}

# Create language dataset
#Invoke-WebRequest $sourceLanguageUrl -OutFile "$rootDir\$processName-Compiled\language.txt"
#$languageDataset = .\speech dataset create --name "$processName-Lang" --language "$rootDir\$processName-Compiled\language.txt" --wait | Select-String $idPattern | % {$_.Matches.Groups[0].Value}

# Create acoustic model with scenario "English conversational"
Write-Host "Creating acoustic model."
$model = & /usr/bin/SpeechCLI/speech model create --name $processName --locale en-us --audio-dataset $trainDataset --scenario "c7a69da3-27de-4a4b-ab75-b6716f6321e5" --wait | Select-String $idPattern | % {$_.Matches.Groups[0].Value}

# Create test
& /usr/bin/SpeechCLI/speech test create --name $processName --audio-dataset $testDataset --model $model --wait

# Create language model
#$langModel = .\speech model
$langModel = $languageModelId

# Create endpoint
& /usr/bin/SpeechCLI/speech endpoint create --name $processName --model $model --language-model $langModel --wait

Write-Host "Process done."