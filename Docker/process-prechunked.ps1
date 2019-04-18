
# Filesystem path to where audio chunks are located.
$audioFilesPath = $env:audioFilesPath

# Filesystem path to TXT file with transcript.
#$transcriptFilesList = "https://<url>/<file>.txt"
$transcriptFilePath = $env:transcriptFilePath

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

# (Optional) Percentage of the source chunks that will be used to test the model. Default = 10
$testPercentage = $env:testPercentage

# (Optional) URL to an endpoint where the process will POST when finished.
# Contains process name, error list and Content.
$webhookUrl = $env:webhookUrl

# (Optional) Custom content to be added to the webhook message.
$webhookContent = $env:webhookContent

#-----------------------------------------------------

# Required checks
if (($null -eq $audioFilesPath) -or `
    ($null -eq $transcriptFilePath) -or `
    ($null -eq $speechKey) -or `
    ($null -eq $speechRegion) -or `
    ($null -eq $processName) ) 
{
    Throw "Required parameter missing."
}

if (($null -eq $languageModelFile) -and ($null -eq $languageModelId)) 
{
    Throw "Either languageModelFile or languageModelId must be provided."
}

# Defaults
if ($null -eq $locale) {
    $locale = "en-us"
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
/usr/bin/SpeechCLI/speech config set --name Build --key $speechKey --region $speechRegion --select

Write-SegmentDuration -Name "ToolsInit"

Set-SegmentStart -Name "LocaleCheck"
# Before downloading, check if the requested locale is valid.
$availableLocales = /usr/bin/SpeechCLI/speech model locales --type acoustic --simple
if (!$availableLocales.ToLower().Contains($locale)) {
    Throw "Locale $locale is not supported with custom speech models."
}
Write-SegmentDuration -Name "LocaleCheck"

# Check encoding of the source transcript file
# [byte[]]$byte = Get-Content -ReadCount 4 -TotalCount 4 -Path $transcriptFilePath -AsByteStream
# if (!($byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf))
# { 
#     Throw "$transcriptFilePath is not encoded in 'UTF-8 Signature'."
# }

# Replace non-supported Unicode characters (above U+00A1) with ASCII variants.
(Get-Content $transcriptFilePath) `
    -Replace "\u2019","'" -Replace "\u201A","," `
    -Replace "\u2013","-" -Replace "\u2012","-" `
    -Replace "\u201C",'"' -Replace "\u201D",'"' `
    | Out-File $transcriptFilePath

# Identify baseline model for given locale
$scenarios = (/usr/bin/SpeechCLI/speech model list-scenarios --locale $locale --simple) -Split '\n'
$defaultScenarioId = $scenarios[0]
Write-Host "Selected base model (scenario): $defaultScenarioId"


# If language data provided, download it and create language model. Otherwise expect that $languageModelId was provided.
if (!($null -eq $languageModelFile)) 
{
    Set-SegmentStart -Name "CreateLanguageModel"
    Invoke-WebRequest $languageModelFile -OutFile $rootDir/$processName-source-language.txt
    
    Write-Host "Creating language model."
    $languageDataset = /usr/bin/SpeechCLI/speech dataset create --name $processName-Lang --locale $locale --language $rootDir/$processName-source-language.txt --wait | Get-IdFromCli
    $languageModelId = /usr/bin/SpeechCLI/speech model create --name $processName-Lang --locale $locale -lng $languageDataset -s $defaultScenarioId --wait | Get-IdFromCli

    Write-SegmentDuration -Name "CreateLanguageModel"
}

# If baseline endpoint not provided, create one with baseline models first.
if ($null -eq $speechEndpoint) 
{
    Set-SegmentStart -Name "CreateBaselineEndpoint"
    # Is there a language model present? If not, use the baseline model.
    if ($null -eq $languageModelFile -and $null -eq $languageModelId) {
        $languageModelId = $defaultScenarioId
    }

    # Create baseline endpoint.
    Write-Host "Creating baseline endpoint."
    $speechEndpoint = /usr/bin/SpeechCLI/speech endpoint create -n $processName-Baseline -l $locale -m $defaultScenarioId -lm $languageModelId --wait  | Get-IdFromCli
    Write-SegmentDuration -Name "CreateBaselineEndpoint"
}

# TODO: check if folder exists and contains any files

# Encode audio files.
New-Item $rootDir/$processName-Chunks -ItemType Directory
Get-ChildItem $audioFilesPath -Exclude *.txt | % { ffmpeg -i $_ -acodec pcm_s16le -vn -ar 16000 -ac 1 $rootDir/$processName-Chunks/$($_.Name) }

# Run Batcher
# - machine transcript creation is time consuming
cd $rootDir/../repos/CustomSpeech-Processing-Pipeline/Batcher

Set-SegmentStart -Name "Batcher"
node batcher.js --key $speechKey --region $speechRegion --endpoint $speechEndpoint --input $rootDir/$processName-Chunks --output "$rootDir/$processName-machine-transcript.txt"
Write-SegmentDuration -Name "Batcher"

# Run Transcriber
cd $rootDir/../repos/CustomSpeech-Processing-Pipeline/Transcriber

New-Item $rootDir/$processName-Cleaned -ItemType Directory -Force
New-Item $rootDir/$processName-Compiled -ItemType Directory -Force

Set-SegmentStart -Name "Transcriber"
$cleaned = @()

# Encoding cleanup - otherwise transcriber fails on certain characters
Get-Content $transcriptFilePath | Set-Content -Encoding UTF8 "$rootDir/$processName-source-transcript-utf8.txt"

# python transcriber.py -t '11_WTA_ROM_STEPvGARC_2018/11_WTA_ROM_STEPvGARC_2018.txt' -a '11_WTA_ROM_STEPvGARC_2018/11_WTA_ROM_STEPvGARC_OFFSET.txt' -g '11_WTA_ROM_STEPvGARC_TRANSCRIPT_testfunc2.txt'
# -t = TRANSCRIBED_FILE = official full transcript
# -a = audio processed file = output from batcher
# -g = output file
python3 transcriber.py -t "$rootDir/$processName-source-transcript-utf8.txt" -a "$rootDir/$processName-machine-transcript.txt" -g "$rootDir/$processName-matched-transcript.txt"

# Cleanup (remove NEEDS MANUAL CHECK and files which don't have transcript)
Set-SegmentStart -Name "CleanupFile"
$present = Get-Content -Path "$rootDir/$processName-matched-transcript.txt" | Where-Object {$_ -notlike "*NEEDS MANUAL CHECK*"}

foreach ($line in $present) 
{
    $filename = ($line -split '\t')[0]
    Copy-Item -Path "$rootDir/$processName-Chunks/$filename" -Destination "$rootDir/$processName-Cleaned/$filename" # copy all to one place
}

$cleaned += $present
Write-SegmentDuration -Name "CleanupFile"

Write-Host "Transcribe done. Writing cleaned-transcript.txt"
$cleaned | Out-File "$rootDir/$processName-cleaned-transcript.txt"
Write-SegmentDuration -Name "Transcriber"

# Prepare ZIP and TXT for test and train datasets
Write-Host "Compiling audio and transcript files."
Set-SegmentStart -Name "SpeechCompile"

# At least 1 file is needed for testing. If the percentage is too high to populate test dataset, it will be set to 0.
if ($cleaned.Length * ($testPercentage / 100) -lt 1) 
{
    Write-Host "Not enough files to populate the test dataset. Only training dataset will be created."
    $testPercentage = 0
}

/usr/bin/SpeechCLI/speech compile --audio "$rootDir/$processName-Cleaned" --transcript "$rootDir/$processName-cleaned-transcript.txt" --output "$rootDir/$processName-Compiled" --test-percentage $testPercentage
Write-SegmentDuration -Name "SpeechCompile"

# Create acoustic datasets for training.
Write-Host "Creating acoustic datasets for training."
Set-SegmentStart -Name "AccousticDatasetTrain"
$trainDataset = /usr/bin/SpeechCLI/speech dataset create --name $processName --locale $locale --audio "$rootDir/$processName-Compiled/Train.zip" --transcript "$rootDir/$processName-Compiled/train.txt" --wait | Get-IdFromCli
Write-SegmentDuration -Name "AccousticDatasetTrain"

# Create acoustic model with selected base model.
Write-Host "Creating acoustic model."
Set-SegmentStart -Name "AcousticModelTrain"
$model = /usr/bin/SpeechCLI/speech model create --name $processName --locale $locale --audio-dataset $trainDataset --scenario $defaultScenarioId --wait | Get-IdFromCli
Write-SegmentDuration -Name "AcousticModelTrain"

if ($testPercentage -gt 0) 
{
    # Create test acoustic datasets for testing.
    Set-SegmentStart -Name "AcousticModelTest"
    $testDataset = /usr/bin/SpeechCLI/speech dataset create --name "$processName-Test" --locale $locale --audio "$rootDir/$processName-Compiled/Test.zip" --transcript "$rootDir/$processName-Compiled/test.txt" --wait | Get-IdFromCli
    Write-SegmentDuration -Name "AcousticModelTest"

    # Create test for the model.
    Set-SegmentStart -Name "Test"
    /usr/bin/SpeechCLI/speech test create --name $processName --audio-dataset $testDataset --model $model --language-model $languageModelId --wait
    Write-SegmentDuration -Name "Test"
}

# Create endpoint
Set-SegmentStart -Name "Endpoint"
$newEndpointId = /usr/bin/SpeechCLI/speech endpoint create --name $processName --locale $locale --model $model --language-model $languageModelId --wait | Get-IdFromCli
Write-SegmentDuration -Name "Endpoint"

Write-Host "Process done."
Write-SegmentDuration -Name "MainProcess"

# Call webhook, if provided. $webhookContent gets injected as Content.
if (!($null -eq $webhookUrl)) 
{
    $content = @{
        ProcessName = $processName;
        Errors = $Error;
        Content = $webhookContent;
        EndpointId = $newEndpointId;
        LanguageModelId = $languageModelId;
    }

    Invoke-WebRequest -Uri $webhookUrl -Method POST -ContentType "application/json" -Body ($content | ConvertTo-Json) | Select-Object -Property StatusCode, StatusDescription

    Write-Host "Webhook triggered."
}