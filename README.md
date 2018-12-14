# Speech Training Pipeline

We've built this pipeline to simplify the process of preparing and training a speech to text (STT) models for the [Speech Service](https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/overview), which is part of [Microsoft Azure](https://azure.microsoft.com/en-us/).

The goal is to simplify data preparation and lower the barrier of entry overall. With this pipeline developers have to provide only full audio files and full transcripts, along with Speech Service keys, and wait for custom speech model to be created. Additional improvements in quality can be achieved by running multiple iterations.

![Developer's view](_images/pipeline-developer-view.png)


##Installation

* Requirements

###Run script - resource group and service principal (Shane) **** get logic endpoint

###Deploy button and ARM parameters (Craig)
* Required parameters - Deplyment, storage, 

###Components and in depth description (Martin function/container, Craig submit, Speaker Enrol and Id)
* Storage and blobs
* Logic Apps
   ** Submit
    ** Enrol
    ** Identify

####  Function App (Pipeline Manager)

Pipeline container is provisioned on-demand when the process is initiated and after input files are processed. Container provisioning is represented by an HTTP POST call to an Azure Function, which is deployed [from GitHub repo](https://github.com/msimecek/Pipeline-Manager).

This Function App is fairly simple - it uses Azure Management NuGet package (`Microsoft.Azure.Management.Fluent`) to create and remove Container Groups in the same Resource Group where the whole process runs.

**Configuration**

> **Note:** All of these settings are filled automatically when deploying  with Azure Resource Manager.

In addition to standard Function App settings (`AzureWebJobsStorage` etc.) these environment variables / application settings are required:

* `PrincipalAppId`: Application/Client ID of the service principal you use.
* `PrincipalAppSecret`: Password/secret of the service principal application.
* `AzureTenantId`: This value is returned by the `subscription().tenantId` statement in Resource Manager. Or you can get it from the Subscription section in the Azure portal.
* `ResourceGroupName`: In which Resource Group is the pipeline container supposed to run.
* `Location`: In which region is the pipeline container supposed to run.

**Functions:**

| Function    | Trigger   | Expected inputs                                              |
| ----------- | --------- | ------------------------------------------------------------ |
| Start       | HTTP POST | JSON request body with `containerImage`, `pipeline.processName` and any of the pipieline settings (see example below). |
| StartWorker | Queue     | Storage Queue message with `ContainerName`, `Location`, `ResourceGroup`, `ContainerImage` and `Env`. |
| Remove      | HTTP POST | JSON request body with `ProcessName`.                        |

`Start` input parameters are parsed first - all values starting with `pipeline.` are passed as ENV variables to the contaier (without the *pipeline.* part).

Becuase `Start` is designed to return as fast as possible, it enqueues a message with all parameters and then returns HTTP 202 Accepted. `StartWorker` then takes on and uses Azure Management SDK to provision the container.

```csharp
var containerGroup = azure.ContainerGroups.Define(startmessage.ContainerName)
    .WithRegion(startmessage.Location)
    .WithExistingResourceGroup(startmessage.ResourceGroup)
    .WithLinux()
    .WithPublicImageRegistryOnly()
    .WithoutVolume()
    .DefineContainerInstance("pipeline")
    	.WithImage(startmessage.ContainerImage)
    	.WithoutPorts()
    	.WithCpuCoreCount(2)
    	.WithMemorySizeInGB(3.5)
    	.WithEnvironmentVariables(startmessage.Env)
    	.Attach()
    	.WithRestartPolicy(ContainerGroupRestartPolicy.Never)
    	.Create();
```

Our test runs show that optimal amount of container RAM is 3.5 GB with CPU count 2.

**Examples:**

*POST /api/Start*

```json
{
  "containerImage": "msimecek/speech-pipeline:0.16-full",
  "pipeline.processName": "mujproces",
  "pipeline.audioFilesList": "https://storageacc.blob.core.windows.net/files/text/language.txt?sv=..saskey",
  "pipeline.transcriptFilesList": "https://storageacc.blob.core.windows.net/files/text/textInput.txt?sv=..saskey",
  "pipeline.languageModelFile": "https://storageacc.blob.core.windows.net/files/text/language.txt?sv=..saskey",
  "pipeline.languageModelId": "",
  "pipeline.speechEndpoint": "",
  "pipeline.speechKey": "44564654keykey5465456",
  "pipeline.speechRegion": "northeurope",
  "pipeline.chunkLength": "",
  "pipeline.testPercentage": "",
  "pipeline.removeSilence": "true",
  "pipeline.silenceDuration": "",
  "pipeline.silenceThreshold": "",
  "pipeline.webhookUrl": "",
  "pipeline.webhookContent": ""
}
```

*POST /api/Remove*

```json
{
	"ProcessName": "mujproces",
	"Errors": null,
	"Content": null
}
```

#### Cognitive Services

As the name suggests the speech training pipeline works with speech-related services. Specifically [Speech](https://azure.microsoft.com/en-us/services/cognitive-services/speech-to-text/) service and [Speaker Recognition](https://azure.microsoft.com/en-us/services/cognitive-services/speaker-recognition/) service. Both are part of [Azure Cognitive Services](https://azure.microsoft.com/en-us/services/cognitive-services/?v=18.44b), a set of RESTful APIs which are easy to integrate into any application.

> **Note:** If you search for Azure Speech service, you may find several offerings (Custom Speech, Bing Speech etc.). We're using the unified Speech service which replaces them all.

We recommend using the **Standard (S0)** tier for both services, because the pipeline process is quite intensive on API calls and Free tier usually hits its limit. Our ARM template uses **S0** by default.

Once you create your services, you can manage your Speech entities using a web portal or unofficial CLI tool.

**Portal**

First get your Speech key from the Azure Portal

![Azure Portal, speech keys](_images/portal-key.png)

Then navigate to https://cris.ai, sign in and connect your subscription. If your Speech service wasn't provisioned in the US, add your region to the URL (such as https://northeurope.cris.ai).

![Connect existing subscription to CRIS](_images/cris-connect.png)

If the connection passes, you will be able to see and manage all of the resources created by the training pipeline.

**CLI**

To get the unofficial Speech CLI tool, go to the [GitHub repo](https://github.com/msimecek/Azure-Speech-CLI), open **Releases** and download a ZIP archive of a version for your operating system (Windows, Mac or Linux).

Configure it with your Speech key and region:

```
speech config set --name Pipeline --key 44564654keykey5465456 --region northeurope --select
```

Then you can work with datasets, models, tests, endpoints or transcripts:

```
speech dataset list
speech model list
speech test list
speech endpoint list
speech transcript list
etc.
```

TODO: speaker recognition

##How to use



###Data Preparation

The training process uses audio samples along with their respective transcripts to create a speech to text model. Before you run start the training process you will need two sets of data:

* Audio - should be full audio recordings that you want to use for training. 
  * can be multiple files (for example several sports matches)
  * can be in any of the common formats (WAV, MP3, MP4...)
  * can be audio-only or with video (visual part will be ignored during the process)
  * should represent the audio environment in which the model will be used (that is with background noise, difficult accents etc.)
  * recommended total length is no less than 3 hours
* Transcripts - should be full transcript of each of the audio files.
  * needs to be plain text (TXT)
  * needs to be encoded as UTF-8 BOM
  * should not contain any UTF-8 characters above U+00A1 in the [Unicode characters table](http://www.utf8-chartable.de/), typically `–`, `‘`, `‚`, `“` etc. (curly characters produced by Microsoft Word)
  * should have the same filename as respective audio file

###Upload to storage

The ARM deployment has created a **Storage Account** in Azure for you. What you need to do next is:

* create an `audio` folder and upload all your audio files to it
* create a `text` folder and upload all transcript files to it

> **Hint**: Use [Azure Storage Explorer](https://azure.microsoft.com/en-us/features/storage-explorer/) too manage storage accounts and upload/download files.

###Parameters required to start process
##

###Todo
* Add monitoring solutiuon

###Detailed description All of us


## References

This pipeline references two other repos:

* [Custom Speech Processing Pipeline](https://github.com/shanepeckham/CustomSpeech-Processing-Pipeline)
* [Azure Speech CLI](https://github.com/msimecek/Azure-Speech-CLI)

To learn how work with the trained endpoint, look at [Speech Service](https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/) in Microsoft documentation. There are SDKs and samples for UWP, C#, C++, Java, JavaScript etc.
