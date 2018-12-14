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



** Cognitive Services

##How to use
###Data Preparation
###Upload to sotrage
###Paramneters required to start process
###

###Todo
* Add monitoring solutiuon

###Detailed description All of us


## References

This pipeline references two other repos:

* [Custom Speech Processing Pipeline](https://github.com/shanepeckham/CustomSpeech-Processing-Pipeline)
* [Azure Speech CLI](https://github.com/msimecek/Azure-Speech-CLI)

To learn how work with the trained endpoint, look at [Speech Service](https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/) in Microsoft documentation. There are SDKs and samples for UWP, C#, C++, Java, JavaScript etc.
