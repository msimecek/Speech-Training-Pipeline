# Filesystem path to TXT file with transcript.
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

# (Optional) When the supported locales API doesn't work, this disables the check.
$bypassLocaleCheck = $env:bypassLocaleCheck

#-----------------------------------------------------

# Required checks
if (($null -eq $languageModelFile) -and ($null -eq $transcriptFilePath)) 
{
    Throw "You have to specify languageModelFile or transcriptFilePath."
}

if (($null -eq $speechKey) -or `
    ($null -eq $speechRegion) -or `
    ($null -eq $processName) ) 
{
    Throw "Required parameter missing."
}

# Defaults
if ($null -eq $locale) {
    $locale = "en-us"
}

if ($null -eq $testPercentage) {
    $testPercentage = 10
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

if ($null -eq $bypassLocaleCheck) 
{
    Set-SegmentStart -Name "LocaleCheck"
    # Before downloading, check if the requested locale is valid.
    $availableLocales = /usr/bin/SpeechCLI/speech model locales --type acoustic --simple
    if (!$availableLocales.ToLower().Contains($locale.ToLower())) {
        Throw "Locale $locale is not supported with custom speech models."
    }
    Write-SegmentDuration -Name "LocaleCheck"
}

if ($null -eq $defaultScenarioId) 
{
    # Identify baseline model for given locale
    $scenarios = (/usr/bin/SpeechCLI/speech model list-scenarios --locale $locale -p LanguageAdaptation --simple) -Split '\n'
    $defaultScenarioId = $scenarios[0]
    Write-Host "Selected base model (scenario): $defaultScenarioId"
}

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
        python3 /usr/src/repos/CustomSpeech-Processing-Pipeline/LanguageModel/GenerateLanguageModel.py -i "$transcriptFilePath" -o "$rootDir/$processName-source-language.txt"
        Write-Host "Language file generated."
    }
    
    Write-Host "Creating language model."
    $languageDataset = /usr/bin/SpeechCLI/speech dataset create --name $processName-Lang --locale $locale --language $rootDir/$processName-source-language.txt --wait | Get-IdFromCli
    Write-Host "Language dataset ID: $languageDataset" -ForegroundColor Green
    $languageModelId = /usr/bin/SpeechCLI/speech model create --name $processName-Lang --locale $locale -lng $languageDataset -s $defaultScenarioId --wait | Get-IdFromCli
    Write-Host "Language model ID: $languageModelId" -ForegroundColor Green

    Write-SegmentDuration -Name "CreateLanguageModel"
}

# Create endpoint with baseline model.
Set-SegmentStart -Name "CreateBaselineEndpoint"

Write-Host "Creating baseline endpoint."
$speechEndpoint = /usr/bin/SpeechCLI/speech endpoint create -n $processName -l $locale -m $defaultScenarioId -lm $languageModelId --wait  | Get-IdFromCli
Write-Host "Baseline endpoint ID: $speechEndpoint" -ForegroundColor Green
Write-SegmentDuration -Name "CreateBaselineEndpoint"

Write-Host "Process done."
Write-SegmentDuration -Name "MainProcess"

# Call webhook, if provided. $webhookContent gets injected as Content.
if (!($null -eq $webhookUrl)) 
{
    $content = @{
        ProcessName = $processName;
        Errors = $Error;
        Content = $webhookContent;
        EndpointId = $speechEndpoint;
        LanguageModelId = $languageModelId;
    }

    Invoke-WebRequest -Uri $webhookUrl -Method POST -ContentType "application/json" -Body ($content | ConvertTo-Json) | Select-Object -Property StatusCode, StatusDescription

    Write-Host "Webhook triggered."
}
