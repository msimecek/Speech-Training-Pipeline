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

# (Optional) TXT file with language model.
#$languageModelFile = "https://<url>/<file>.txt"
$languageModelFile = $env:languageModelFile

# (Optional) ID of an already existing language model.
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

# (Optional) URL to an endpoint where the process will POST when finished.
# Contains process name, error list and Content.
$webhookUrl = $env:webhookUrl

# (Optional) Custom content to be added to the webhook message.
$webhookContent = $env:webhookContent

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
/usr/bin/SpeechCLI/speech --version

# Config CLI
/usr/bin/SpeechCLI/speech config set --name Build --key $speechKey --region $speechRegion --select

Write-SegmentDuration -Name "ToolsInit"

Set-SegmentStart -Name "LocaleCheck"
# Before downloading, check if the requested locale is valid.
$availableLocales = /usr/bin/SpeechCLI/speech model locales --type acoustic --simple
if (!$availableLocales.ToLower().Contains($locale.ToLower())) {
    Throw "Locale $locale is not supported with custom speech models."
}
Write-SegmentDuration -Name "LocaleCheck"

# Parse source files into arrays and remove empty lines. Each line is expected to be a file URL.
Write-Host "Downloading source files."
Set-SegmentStart -Name "SourceDownload"

# TODO: convert CRLF
$sourceWavs = @{}
(Invoke-WebRequest $audioFilesList -ErrorAction Stop | Select -ExpandProperty Content) -Split '\n' | Where-Object {$_} | % { $sourceWavs.Add([System.IO.Path]::GetFileNameWithoutExtension($_), $_) }

$sourceTxts = @{}
(Invoke-WebRequest $transcriptFilesList -ErrorAction Stop | Select -ExpandProperty Content) -Split '\n' | Where-Object {$_} | % { $sourceTxts.Add([System.IO.Path]::GetFileNameWithoutExtension($_), $_) }

# Download WAV files locally
New-Item $rootDir/SourceWavs -ItemType Directory -Force
foreach ($wav in $sourceWavs.Keys) 
{
    if (!($sourceTxts.ContainsKey($wav)))
    {
        Throw "The transcript file for $wav was not found in the list. Audio and transcript files are matched by filename (without extension)."
    }
    
    # Download WAV file locally to prevent Storage transfer errors    
    Write-Host "($wav) Downloading source media locally."
    
    Set-SegmentStart -Name "FileDownload-$wav"
    Invoke-WebRequest $sourceWavs[$wav] -OutFile $rootDir/SourceWavs/$wav # extension omitted - doesn't have to be WAV at this point
    Write-SegmentDuration -Name "FileDownload-$wav"

    New-Item $rootDir/Chunks-$wav -ItemType Directory -Force

    # Run FFmpeg on source files - chunk & convert
    if (!($null -eq $removeSilence))
    {
        $audioFilters = "-af silenceremove=stop_periods=-1:stop_duration=$($silenceDuration):stop_threshold=-$($silenceThreshold)dB"
    }
    
    $command = "ffmpeg -i $rootDir/SourceWavs/$wav -acodec pcm_s16le -vn -ar 16000 $audioFilters -f segment -segment_time $chunkLength -ac 1 $rootDir/Chunks-$wav/$wav-part%03d.wav"
    Set-SegmentStart -Name "ffmpeg-$wav"
    Invoke-Expression -Command $command
    Write-SegmentDuration -Name "ffmpeg-$wav"
        
    # Download full transcript
    Invoke-WebRequest $sourceTxts[$wav] -OutFile $rootDir/$processName-source-transcript-$wav.txt
    Confirm-BOMStatus -File "$rootDir/$processName-source-transcript-$wav.txt"

    # Replace non-supported Unicode characters (above U+00A1) with ASCII variants.
    (Get-Content "$rootDir/$processName-source-transcript-$wav.txt") `
        -Replace "\u2019","'" -Replace "\u201A","," `
        -Replace "\u2013","-" -Replace "\u2012","-" `
        -Replace "\u201C",'"' -Replace "\u201D",'"' `
        | Out-File "$rootDir/$processName-source-transcript-$wav.txt"
}

Write-SegmentDuration -Name "SourceDownload"

# Identify baseline model for given locale
$scenarios = (/usr/bin/SpeechCLI/speech model list-scenarios --locale $locale --simple) -Split '\n'
$defaultScenarioId = $scenarios[0]
Write-Host "Selected base model (scenario): $defaultScenarioId"

# If languageModelId provided, we'll just use that.
if (!($null -eq $languageModelId)) 
{
    Write-Host "Language model ID provided. No need to create new language model."
} else
{
    Set-SegmentStart -Name "CreateLanguageModel"
    # If there's prepopulated language model file, we'll use it to create new language model.
    if (!($null -eq $languageModelFile)) 
    {
        Write-Host "Creating language model from provided language file."
        Invoke-WebRequest $languageModelFile -OutFile $rootDir/$processName-source-language.txt
        Confirm-BOMStatus -File $rootDir/$processName-source-language.txt
    } else
    {
        # Otherwise we try to extract language model automatically from transcript and create new language model.
        Write-Host "Generating new language file."
        # merge transcript files for individual WAVs and store to file $rootDir/$processName-full-transcript.txt
        Get-ChildItem $rootDir -Filter "$processName-source-transcript-*.txt" | ForEach-Object { Get-Content $_; "" } | Out-File "$rootDir/$processName-full-transcript.txt"

        # run generateLanguageModel.py
        python3 /usr/src/repos/CustomSpeech-Processing-Pipeline/LanguageModel/GenerateLanguageModel.py -i "$rootDir/$processName-full-transcript.txt" -o "$rootDir/$processName-source-language.txt"
        Write-Host "Language file generated."
    }
    
    Write-Host "Creating language model."
    $languageDataset = /usr/bin/SpeechCLI/speech dataset create --name $processName-Lang --locale $locale --language $rootDir/$processName-source-language.txt --wait | Get-IdFromCli
    Write-Host "Language dataset ID: $languageDataset" -ForegroundColor Green
    $languageModelId = /usr/bin/SpeechCLI/speech model create --name $processName-Lang --locale $locale -lng $languageDataset -s $defaultScenarioId --wait | Get-IdFromCli
    Write-Host "Language model ID: $languageModelId" -ForegroundColor Green

    Write-SegmentDuration -Name "CreateLanguageModel"
}

# If baseline endpoint not provided, create one with baseline models first (in order to utilize the language model).
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
    Write-Host "Baseline endpoint ID: $speechEndpoint" -ForegroundColor Green
    Write-SegmentDuration -Name "CreateBaselineEndpoint"
}

# Run Batcher
# - machine transcript creation is time consuming
Set-SegmentStart -Name "Batcher"
cd $rootDir/../repos/CustomSpeech-Processing-Pipeline/Batcher-Py
foreach ($wav in $sourceWavs.Keys) 
{
    # endpoint doesnt work yet
    #python3 batcher.py --key $speechKey --region $speechRegion --endpoint $speechEndpoint --input "$rootDir/Chunks-$wav" --output "$rootDir/$processName-machine-transcript-$wav.txt"
    python3 batcher.py --key $speechKey --region $speechRegion --input "$rootDir/Chunks-$wav/" --output "$rootDir/$processName-machine-transcript-$wav.txt"
}
Write-SegmentDuration -Name "Batcher"

# Run Transcriber
cd $rootDir/../repos/CustomSpeech-Processing-Pipeline/Transcriber

New-Item $rootDir/$processName-Cleaned -ItemType Directory -Force
New-Item $rootDir/$processName-Compiled -ItemType Directory -Force

Set-SegmentStart -Name "Transcriber"
$cleaned = @()
foreach ($wav in $sourceWavs.Keys)
{
    # TODO: exclude from loop, when machine transcript empty
    Set-SegmentStart -Name "TranscriberFile-$wav"

    # Encoding cleanup - otherwise transcriber fails on certain characters
    Get-Content "$rootDir/$processName-source-transcript-$wav.txt" | Set-Content -Encoding UTF8 "$rootDir/$processName-source-transcript-$wav-utf8.txt"

    # python transcriber.py -t '11_WTA_ROM_STEPvGARC_2018/11_WTA_ROM_STEPvGARC_2018.txt' -a '11_WTA_ROM_STEPvGARC_2018/11_WTA_ROM_STEPvGARC_OFFSET.txt' -g '11_WTA_ROM_STEPvGARC_TRANSCRIPT_testfunc2.txt'
    # -t = TRANSCRIBED_FILE = official full transcript
    # -a = audio processed file = output from batcher
    # -g = output file
    python3 transcriber.py -t "$rootDir/$processName-source-transcript-$wav-utf8.txt" -a "$rootDir/$processName-machine-transcript-$wav.txt" -g "$rootDir/$processName-matched-transcript-$wav.txt"
    Write-SegmentDuration -Name "TranscriberFile-$wav"

    # Cleanup (remove NEEDS MANUAL CHECK and files which don't have transcript)
    Set-SegmentStart -Name "CleanupFile-$wav"
    $present = Get-Content -Path "$rootDir/$processName-matched-transcript-$wav.txt" | Where-Object {$_ -notlike "*NEEDS MANUAL CHECK*"}
    
    foreach ($line in $present) 
    {
        $filename = ($line -split '\t')[0]
        Copy-Item -Path "$rootDir/Chunks-$wav/$filename" -Destination "$rootDir/$processName-Cleaned/$filename" # copy all to one place
    }

    $cleaned += $present
    Write-SegmentDuration -Name "CleanupFile-$wav"
}

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
Write-Host "Training dataset ID: $trainDataset" -ForegroundColor Green
Write-SegmentDuration -Name "AccousticDatasetTrain"

# Create acoustic model with selected base model.
Write-Host "Creating acoustic model."
Set-SegmentStart -Name "AcousticModelTrain"
$model = /usr/bin/SpeechCLI/speech model create --name $processName --locale $locale --audio-dataset $trainDataset --scenario $defaultScenarioId --wait | Get-IdFromCli
Write-Host "Acoustic model ID: $model" -ForegroundColor Green
Write-SegmentDuration -Name "AcousticModelTrain"

if ($testPercentage -gt 0) 
{
    # Create test acoustic datasets for testing.
    Set-SegmentStart -Name "AcousticModelTest"
    $testDataset = /usr/bin/SpeechCLI/speech dataset create --name "$processName-Test" --locale $locale --audio "$rootDir/$processName-Compiled/Test.zip" --transcript "$rootDir/$processName-Compiled/test.txt" --wait | Get-IdFromCli
    Write-Host "Testing dataset ID: $testDataset" -ForegroundColor Green
    Write-SegmentDuration -Name "AcousticModelTest"

    # Create test for the model.
    Set-SegmentStart -Name "Test"
    /usr/bin/SpeechCLI/speech test create --name $processName --audio-dataset $testDataset --model $model --language-model $languageModelId --wait
    Write-SegmentDuration -Name "Test"
}

# Create endpoint
Set-SegmentStart -Name "Endpoint"
$newEndpointId = /usr/bin/SpeechCLI/speech endpoint create --name $processName --locale $locale --model $model --language-model $languageModelId --wait | Get-IdFromCli
Write-Host "Trained endpoint ID: $newEndpointId" -ForegroundColor Green
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