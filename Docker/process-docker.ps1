#
# Before running this script, change initial variables to reflect your environment.
# Run this script from an empty working folder - it will download and produce many files.
#

# TXT file with links to source WAV files. One line = one file.
#$audioFilesList = "https://<url>/<file>.txt"
$audioFilesList = $env:audioFilesList

# TXT file with links to transcription files corresponding to WAV files. One file = complete trascript of the whole WAV file (no timestamps, only text).
#$transcriptFilesList = "https://<url>/<file>.txt"
$transcriptFilesList = $env:transcriptFilesList

# TXT file with language model.
#$languageModelFile = "https://<url>/<file>.txt"
$languageModelFile = $env:languageModelFile

# ID of an already existing language model.
# If $languageModelFile is provided, this will be overwritten.
$languageModelId = $env:languageModelId

# Key to Speech API (get from Azure portal or from Speech, aka CRIS, portal).
#$speechKey = ""
$speechKey = $env:speechKey

# Region where the Speech API is deployed (get from Azure portal or from Speech portal).
#$speechRegion = "northeurope"
$speechRegion = $env:speechRegion

# GUID of speech endpoint to run the initial transcription against. 
# Better endpoint (e.g. with language model, pre-trained etc.) = better results. Suitable for multiple iterations.
# Get from Speech portal (CRIS.ai).
# If not specified, new baseline endpoint will be created.
#$speechEndpoint = ""
$speechEndpoint = $env:speechEndpoint

# How will datasets, models, tests and endpoints be named in Speech Service.
#$processName = ""
$processName = $env:processName

# (Optional) ID of the baseline model which should be used. Default is en-us "V2.5 Conversational (AM/LM adapt)".
# If provided, locale must match scenario language.
$defaultScenarioId = $env:defaultScenarioId

# (Optional) Language of models and datasets. Must be supported by the Speech service. Default: en-us
# If $defaultScenarioId is not provided, this will be set to en-us.
# So far the only tested locale is en-us.
$locale = $env:locale

# (Optional) Duration of chunks in seconds. Default = 10
$chunkLength = $env:chunkLength

# (Optional) Percentage of the source chunks that will be used to test the model. Default = 10
$testPercentage = $env:testPercentage

# (Optional) If set, the process will remove silence in source audio files. Default = $null 
$removeSilence = $env:removeSilence

# (Optional) Silence Duration in seconds. Specify a duration of silence that must exist before audio is not copied any more. Default = 1
$silenceDuration = $env:silenceDuration

# (Optional) The sample value (in dB) that should be treated as silence. Default = 50 decibels
$silenceThreshold = $env:silenceThreshold

#-----------------------------------------------------

# Required checks
if (($null -eq $audioFilesList) -or `
    ($null -eq $transcriptFilesList) -or `
    ($null -eq $speechKey) -or `
    ($null -eq $speechRegion) -or `
    ($null -eq $processName) ) 
{
    Throw "Required parameter missing."
}

# Defaults

if ($null -eq $defaultScenarioId) {
    $defaultScenarioId = "c7a69da3-27de-4a4b-ab75-b6716f6321e5" # "V2.5 Conversational (AM/LM adapt) - en-us"
    $locale = "en-us"
}

if ($null -eq $locale) {
    $locale = "en-us"
}

if ($null -eq $chunkLength) {
    $chunkLength = 10
}

if ($null -eq $testPercentage) {
    $testPercentage = 10
}

if ($null -eq $silenceDuration) {
    $silenceDuration = 1
}

if ($null -eq $silenceThreshold) {
    $silenceThreshold = 50
}

#-----------------------------------------------------

$rootDir = (Get-Item -Path ".\" -Verbose).FullName;

. /usr/src/helpers.ps1 # include

Set-SegmentStart -Name "MainProcess" # measurements
Set-SegmentStart -Name "ToolsInit"


# Test tools.
Write-Host "Checking dependencies."
pip3 --version
python3 --version
npm --version
node --version
/usr/bin/SpeechCLI/speech --version

# Config CLI
& /usr/bin/SpeechCLI/speech config set --name Build --key $speechKey --region $speechRegion --select
$idPattern = "(\w{8})-(\w{4})-(\w{4})-(\w{4})-(\w{12})"

Write-SegmentDuration -Name "ToolsInit"

# Parse source files into arrays and remove empty lines. Each line is expected to be a file URL.
Write-Host "Downloading source files."
$sourceWavs = @()
$sourceTxts = @()

Set-SegmentStart -Name "SourceDownload"

$sourceWavs += (Invoke-WebRequest $audioFilesList -ErrorAction Stop | Select -ExpandProperty Content) -Split '\n' | ? {$_}
$sourceTxts += (Invoke-WebRequest $transcriptFilesList -ErrorAction Stop | Select -ExpandProperty Content) -Split '\n' | ? {$_}

# Download WAV files locally
New-Item $rootDir/SourceWavs -ItemType Directory -Force

# Inline syntax
#$sourceWavs | % {$i = 0} { Invoke-WebRequest $_ -OutFile .\SourceWavs\$i.wav; $i++ }

for ($i = 0; $i -lt $sourceWavs.Count; $i++) {  
    # Download WAV file locally to prevent Storage transfer errors    
    Write-Host "($($i + 1)/$($sourceWavs.Count)) Downloading source WAV locally."
    
    Set-SegmentStart -Name "FileDownload-$i.wav"
    Invoke-WebRequest $sourceWavs[$i] -OutFile ./SourceWavs/$i.wav
    Write-SegmentDuration -Name "FileDownload-$i.wav"

    New-Item ./Chunks-$i -ItemType Directory -Force

    # Run FFmpeg on source files - chunk & convert
    if (!($null -eq $removeSilence))
    {
        $audioFilters = "-af silenceremove=stop_periods=-1:stop_duration=$($silenceDuration):stop_threshold=-$($silenceThreshold)dB"
    }
    
    $command = "ffmpeg -i $rootDir/SourceWavs/$i.wav -acodec pcm_s16le -vn -ar 16000 $audioFilters -f segment -segment_time $chunkLength -ac 1 $rootDir/Chunks-$i/$i-part%03d.wav"
    Set-SegmentStart -Name "ffmpeg-$i.wav"
    Invoke-Expression -Command $command
    Write-SegmentDuration -Name "ffmpeg-$i.wav"
        
    # Download full transcript
    Invoke-WebRequest $sourceTxts[$i] -OutFile $rootDir/$processName-source-transcript-$i.txt

    [byte[]]$byte = Get-Content -ReadCount 4 -TotalCount 4 -Path "$rootDir/$processName-source-transcript-$i.txt" -AsByteStream
    if (!($byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf))
    { 
        Throw "source-transcript-$i.txt is not encoded in 'UTF-8 Signature'."
    }

    # Replace non-supported Unicode characters (above U+00A1) with ASCII variants.
    (Get-Content "$rootDir/$processName-source-transcript-$i.txt") `
        -Replace "\u2019","'" -Replace "\u201A","," `
        -Replace "\u2013","-" -Replace "\u2012","-" `
        -Replace "\u201C",'"' -Replace "\u201D",'"' `
        | Out-File "$rootDir/$processName-source-transcript-$i.txt"
}

Write-SegmentDuration -Name "SourceDownload"

# If language data provided, create language model.
if (!($null -eq $languageModelFile)) {
    Set-SegmentStart -Name "CreateLanguageModel"
    Invoke-WebRequest $languageModelFile -OutFile $rootDir/$processName-source-language.txt
    
    Write-Host "Creating language model."
    $languageDataset = & /usr/bin/SpeechCLI/speech dataset create --name $processName-Lang --locale $locale --language $rootDir/$processName-source-language.txt --wait | Select-String $idPattern | % {$_.Matches.Groups[0].Value} 
    $languageModelId = & /usr/bin/SpeechCLI/speech model create --name $processName-Lang --locale $locale -lng $languageDataset -s $defaultScenarioId --wait | Select-String $idPattern | % {$_.Matches.Groups[0].Value}

    Write-SegmentDuration -Name "CreateLanguageModel"
}


# If baseline endpoint not provided, create one with baseline models first.
if ($null -eq $speechEndpoint) {
    Set-SegmentStart -Name "CreateBaselineEndpoint"
    # Is there a language model present? If not, use the baseline model.
    if ($null -eq $languageModelFile -and $null -eq $languageModelId) {
        $languageModelId = $defaultScenarioId
    }

    # Create baseline endpoint.
    Write-Host "Creating baseline endpoint."
    $speechEndpoint = & /usr/bin/SpeechCLI/speech endpoint create -n $processName-Baseline -l $locale -m $defaultScenarioId -lm $languageModelId --wait  | Select-String $idPattern | % {$_.Matches.Groups[0].Value} 
    Write-SegmentDuration -Name "CreateBaselineEndpoint"
}

# Run Batcher, if there's no machine-transcript present
# - machine transcript creation is time consuming, this allows to skip it if the process needs to be run again
cd $rootDir/../repos/CustomSpeech-Processing-Pipeline/Batcher

Set-SegmentStart -Name "Batcher"
for ($i = 0; $i -lt $sourceWavs.Count; $i++) {
    If (!(Test-Path "$rootDir/$processName-machine-transcript-$i.txt")) {
       node batcher.js --key $speechKey --region $speechRegion --endpoint $speechEndpoint --input "$rootDir/Chunks-$i" --output "$rootDir/$processName-machine-transcript-$i.txt"
    }
}
Write-SegmentDuration -Name "Batcher"

# Run Transcriber
cd $rootDir/../repos/CustomSpeech-Processing-Pipeline/Transcriber

New-Item $rootDir/$processName-Cleaned -ItemType Directory -Force
New-Item $rootDir/$processName-Compiled -ItemType Directory -Force

Set-SegmentStart -Name "Transcriber"
$cleaned = @()
for ($i = 0; $i -lt $sourceWavs.Count; $i++) 
{
    # TODO: exclude from loop, when machine transcript empty
    Set-SegmentStart -Name "TranscriberFile-$i"

    # python transcriber.py -t '11_WTA_ROM_STEPvGARC_2018/11_WTA_ROM_STEPvGARC_2018.txt' -a '11_WTA_ROM_STEPvGARC_2018/11_WTA_ROM_STEPvGARC_OFFSET.txt' -g '11_WTA_ROM_STEPvGARC_TRANSCRIPT_testfunc2.txt'
    # -t = TRANSCRIBED_FILE = official full transcript
    # -a = audio processed file = output from batcher
    # -g = output file
    python3 transcriber.py -t "$rootDir/$processName-source-transcript-$i.txt" -a "$rootDir/$processName-machine-transcript-$i.txt" -g "$rootDir/$processName-matched-transcript-$i.txt"
    Write-SegmentDuration -Name "TranscriberFile-$i"

    # Cleanup (remove NEEDS MANUAL CHECK and files which don't have transcript)
    Set-SegmentStart -Name "CleanupFile-$i"
    $present = Get-Content -Path "$rootDir/$processName-matched-transcript-$i.txt" | Where-Object {$_ -notlike "*NEEDS MANUAL CHECK*"}
    
    ForEach ($line in $present) {
        $filename = ($line -split '\t')[0]
        Copy-Item -Path "$rootDir/Chunks-$i/$filename" -Destination "$rootDir/$processName-Cleaned/$filename" # copy all to one place
    }

    $cleaned += $present
    Write-SegmentDuration -Name "CleanupFile-$i"
}

Write-Host "Transcribe done. Writing cleaned-transcript.txt"
$cleaned | Out-File "$rootDir/$processName-cleaned-transcript.txt"
Write-SegmentDuration -Name "Transcriber"

# Prepare ZIP and TXT for test and train datasets
Write-Host "Compiling audio and transcript files."
Set-SegmentStart -Name "SpeechCompile"

if ($cleaned.Length * ($testPercentage / 100) -lt 1) {
    Write-Host "Not enough files to populate the test dataset. Only training dataset will be created."
    $testPercentage = 0
}

& /usr/bin/SpeechCLI/speech compile --audio "$rootDir/$processName-Cleaned" --transcript "$rootDir/$processName-cleaned-transcript.txt" --output "$rootDir/$processName-Compiled" --test-percentage $testPercentage
Write-SegmentDuration -Name "SpeechCompile"

# Create acoustic datasets for training
Write-Host "Creating acoustic datasets for training."
Set-SegmentStart -Name "AccousticDatasetTrain"
$trainDataset = & /usr/bin/SpeechCLI/speech dataset create --name $processName --locale $locale --audio "$rootDir/$processName-Compiled/Train.zip" --transcript "$rootDir/$processName-Compiled/train.txt" --wait | Select-String $idPattern | % {$_.Matches.Groups[0].Value}
Write-SegmentDuration -Name "AccousticDatasetTrain"

# Create acoustic model with scenario "English conversational"
Write-Host "Creating acoustic model."
Set-SegmentStart -Name "AcousticModelTrain"
$model = & /usr/bin/SpeechCLI/speech model create --name $processName --locale $locale --audio-dataset $trainDataset --scenario $defaultScenarioId --wait | Select-String $idPattern | % {$_.Matches.Groups[0].Value}
Write-SegmentDuration -Name "AcousticModelTrain"

if ($testPercentage -gt 0) {
    # Create test acoustic datasets for testing.
    Set-SegmentStart -Name "AcousticModelTest"
    $testDataset = & /usr/bin/SpeechCLI/speech dataset create --name "$processName-Test" --locale $locale --audio "$rootDir/$processName-Compiled/Test.zip" --transcript "$rootDir/$processName-Compiled/test.txt" --wait | Select-String $idPattern | % {$_.Matches.Groups[0].Value}
    Write-SegmentDuration -Name "AcousticModelTest"

    # Create test for the model.
    Set-SegmentStart -Name "Test"
    & /usr/bin/SpeechCLI/speech test create --name $processName --audio-dataset $testDataset --model $model --wait
    Write-SegmentDuration -Name "Test"
}

# Create endpoint
Set-SegmentStart -Name "Endpoint"
& /usr/bin/SpeechCLI/speech endpoint create --name $processName --locale $locale --model $model --language-model $languageModelId --wait
Write-SegmentDuration -Name "Endpoint"

Write-Host "Process done."
Write-SegmentDuration -Name "MainProcess"