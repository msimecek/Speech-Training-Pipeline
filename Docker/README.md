# Speech Training Pipeline for Docker

![Background view of the speech processing pipeline](../_images/pipeline-background-view.png)

## Prerequisites

Before building the image run `install.ps1` first to download Speech CLI locally.

## Usage

To use this pipeline and get a trained speech endpoint in the end, you have to:

1. prepare data
2. run it

### 1. Data preparation

> **Important:** Keep on mind that all TXT files should be encoded as UTF-8 BOM and should not contain any UTF-8 characters above U+00A1 in the [Unicode characters table](http://www.utf8-chartable.de/). These are typically `–`, `‘`, `‚`, `“` etc.

**Prepare source audio/video recordings.** We usually use WAVs, but technically they can be any audio/video files as long as *ffmpeg* is able to process them. You can use multiple files and each of them can be hours long. We recommend total length no less than 4-5 hours.

**Prepare source transcripts as TXT files.** Each audio/video recording should have a corresponding transcript file. This text file contains everything that is said on the recording in a raw format (no timestamps, no special marks). If multiple recordings repeat the same text, only one TXT is needed.

**Prepare language dataset as TXT file.** Language datasets are easy to prepare and improve recognition significantly, that's why we require you to provide a language datasets for this pipeline. Language data structure is [described in the Docs](https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/how-to-customize-language-model#prepare-the-data).

> We're currently testing a script which would generate the language dataset automatically, based on transcript files.

**Upload your files to a location accessible from the internet (URL, to be precise).** We recommend Azure Blob Storage, because it supports *SAS URLs*, which means that your files don't have to be public in order to use them.

**Prepare lists of your source files.** These are two TXT files:

* list of URLs of source audio/video recordings,
* list of URLs of source transcript TXTs.

*sample-wavs.txt*

```
https://pokus.blob.core.windows.net/speech/01.wav
https://pokus.blob.core.windows.net/speech/02.wav?st=2018-10-05T09%3A34%3A30Z&se=2018-11-06T08%3A34%3A00Z&sp=rwl&sv=2018-03-28&sr=c&sig=X0g1HeF0abcde4NaZbaasds39yytpMkQwRdcasdxLyE0%3D
https://pokus.blob.core.windows.net/speech/03.wav
```

*sample-transcripts.txt*

```
https://pokus.blob.core.windows.net/speech/01.txt
https://pokus.blob.core.windows.net/speech/03.txt
https://pokus.blob.core.windows.net/speech/02.txt
```

*(Files are matched on filename, so order doesn't matter, but filename - without extension - does.)*

**Upload list files to an accessible location too.** The process will download them.

### 2. Running the process

The process itself is a PowerShell script and runs on Windows, Mac or Linux (thanks to PowerShell Core).

It is configured with environmental variables.

| Name                  | Expected type | Description                                                  | Example                                      |
| --------------------- | ------------- | ------------------------------------------------------------ | -------------------------------------------- |
| `processName`         | string        | Custom name - for better orientation, will be used by different parts of the process. Should not contain spaces and special characters. | Iteration1                                   |
| `audioFilesList`      | URL string    | TXT file containing a list of source WAV file URLs. One file per line. | https://sample.net/test/sourceWav.txt        |
| `transcriptFilesList` | URL string    | TXT file containing a list of transcript TXT files. One file per line. Order matters (should correspond with WAV files. | https://sample.net/test/sourceTranscript.txt |
| `languageModelFile`   | URL string    | TXT file with the language dataset.                          | https://sample.net/test/language.txt         |
| `languageModelId`     | GUID string   | ID of a pre-trained language model. If `languageModelFile` is provided, this **will be overwritten**! | cc6835cc-ddbb-4a1f-8fbb-bca0dd04ddb1         |
| `speechEndpoint`      | GUID string   | (Optional) ID of a baseline endpoint from the Speech service. If not provided, new endpoint will be created. | cc6835cc-ddbb-4a1f-8fbb-bca0dd04ddb1         |
| `speechKey`           | string        | Speech service subscription key.                             | acc1cabbbbeb4aaa8311477b05ab2236             |
| `speechRegion`        | string        | Speech service region.                                       | northeurope                                  |
| `chunkLength`         | int           | (Optional) Duration of the samples (in seconds) that will be created from source files. Default = 10. | 10                                           |
| `testPercentage`      | int           | (Optional) How many percent of samples will be used for testing. Default = 10. | 10                                           |
| `removeSilence`       | string        | (Optional) If specified, the process will try to remove silence from original audio. Default = $null | "true"                                       |
| `silenceDuration`     | int           | (Optional) Duration of silence (in seconds) that must exist before audio is not copied any more. Default = 1 | 1                                            |
| `silenceThreshold`    | int           | (Optional) Sample value that should be treated as silence (in dB). Default = 50 decibels. | 50                                           |
| `webhookUrl`    | string           | (Optional) URL of an endpoint to be called when the process finishes with a POST request. | https://sample.net/done                                     |
| `webhookContent`    | string           | (Optional) Custom content to be added to the webhook call. This value will be in the `Content` property of JSON object. | "Hello"                                           |

There are currently three ways of running the process.

#### Docker

Most convenient. Use Docker locally or [Azure Container Instances](https://azure.microsoft.com/en-us/services/container-instances/).

*Locally:*

```
docker run -e languageModelId='<GUID>' -e processName='DockerPipeline' -e audioFilesList='https://pokus.blob.core.windows.net/speech/sample-wavs.txt' -e transcriptFilesList='https://pokus.blob.core.windows.net/speech/source-transcripts.txt' -e languageModelFile='https://pokus.blob.core.windows.net/speech/language.txt' -e speechKey='<KEY>' -e speechRegion='<REGION>' msimecek/speech-pipeline:0.18-full 
```

*Azure Container Instances:*

```
az group create -n SpeechPipeline -l northeurope

az container create --resource-group SpeechPipeline --name speechjob --cpu 2 --memory 3.5 --image msimecek/speech-pipeline:0.18-full --restart-policy Never --environment-variables "languageModelId"="<GUID>" "processName"="DockerPipeline" "audioFilesList"="https://pokus.blob.core.windows.net/speech/sample-wavs.txt" "transcriptFilesList"="https://pokus.blob.core.windows.net/speech/source-transcripts.txt" "languageModelFile"="https://pokus.blob.core.windows.net/speech/language.txt" "speechKey"="<KEY>" "speechRegion"="<REGION>"

az container attach -n speechjob -g SpeechPipeline
```

#### PowerShell

Since it's still a PowerShell script, you can run it manually, but make sure to have all dependencies installed on the machine. Namely:

* python 3.7 + pip
* nodejs + npm
* git
* PowerShell Core (for non-Windows systems)

#### Azure DevOps

First iteration of this pipeline was actually ran in Azure DevOps and although it's super cool, Docker is more convenient option. But it works - you just have to connect your own build machine (because the process takes a looong time) and provide environmental variables as Pipeline variables in Azure DevOps. Then simply start the PowerShell script as one of the build steps.
