# Speech Training Pipeline

We've built this pipeline to simplify the process of preparing and training a speech to text (STT) models for the [Speech Service](https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/overview), which is part of [Microsoft Azure](https://azure.microsoft.com/en-us/).

The goal is to simplify data preparation and lower the barrier of entry overall. With this pipeline developers have to provide only full audio files and full transcripts, along with Speech Service keys, and wait for custom speech model to be created. Additional improvements in quality can be achieved by running multiple iterations.

![Developer's view](_images/pipeline-developer-view.png)


## Installation

*Requirements
To run the deployment script to create the Resource Group and Service Principal required for this solution, you will need to have the az cli installed - see [Azure Speech CLI](https://github.com/msimecek/Azure-Speech-CLI)

### Create Resource Group and Service Principal 
In this we will be creating the Resource Group and the Service Principal that has the rights to create Azure resources within the provisioned Resource Group. 

1) Log in to the az cli
2) Run script [createRGandSP.sh](https://github.com/msimecek/Speech-Training-Pipeline/blob/shane-doc/Scripts/createRGandSP.sh)
3) Copy the values output by the script as you will need them in the ARM deploy step

The output should look like the following:

```
{
  "id": "/subscriptions/**************************/resourceGroups/speech16",
  "location": "westeurope",
  "managedBy": null,
  "name": "speech16",
  "properties": {
    "provisioningState": "Succeeded"
  },
  "tags": null
}
Created resource group speech16
Retrying role assignment creation: 1/36
Retrying role assignment creation: 2/36
Created SP with appid 6b84e051-*****************
SP key 62a************************
```

If at any time you need to get the values of the Service Principal, you can simply run the script [SpeechPipelineUtils.sh](https://github.com/msimecek/Speech-Training-Pipeline/blob/shane-doc/Scripts/SpeechPipelineUtils.sh) although this is best run after the Deploy from ARM step.

### Deploy button and ARM parameters (Craig)
<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fshanepeckham%2FCustomSpeech-Processing-Pipeline%2Fmaster%2FDeploy%2FSpeechPipeline.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fshanepeckham%2FCustomSpeech-Processing-Pipeline%2Fmaster%2FDeploy%2FSpeechPipeline.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

The <b>deploy button</b> above automatically provisions the needed Azure services for the Custom Speech processing pipeline from an ARM template. The <b>visualise button</b> above displays a visual representation of the services that are to be provisioned from the template.

Upon provisioning the deployment - the settings of the services can be edited to better reflect meaningful identifiers within your specific use case. 

* `Deployment Name`: If multiple instances planned, change to indicate the specific pipeline. This will dynamically change subsequently generated service names to mitigate naming conflicts.

### Components and in depth description (Martin function/container, Craig submit, Speaker Enrol and Id)
* Storage and blobs

#### Logic Apps
 #### The Submit Logic App
 
 This Logic App handles the model deployment and generates URIs for the files in blob storage.
 
 ![Submit Logic App](_images/submit-la.png)
 
 When called from the specified endpoint with given parameters, the logic app generates a URI for the items in blob storage specified with the `audioBlobLocation` and `textBlobLocation` parameters. The logic app then passes the URI alongside various other environment variables to the container, spinning up the process.
 
 *Inputs*
 ```
 {
    "properties": {
        "audioBlobLocation": {
            "type": "string"
        },
        "chunkLength": {
            "type": "string"
        },
        "cleanUpKey": {
            "type": "string"
        },
        "containerImage": {
            "type": "string"
        },
        "languageModelId": {
            "type": "string"
        },
        "location": {
            "type": "string"
        },
        "processName": {
            "type": "string"
        },
        "removeSilence": {
            "type": "string"
        },
        "resourceGroup": {
            "type": "string"
        },
        "silenceDuration": {
            "type": "string"
        },
        "silenceThreshold": {
            "type": "string"
        },
        "speechEndpoint": {
            "type": "string"
        },
        "speechKey": {
            "type": "string"
        },
        "subscriptionKey": {
            "type": "string"
        },
        "testPercentage": {
            "type": "string"
        },
        "textBlobLocation": {
            "type": "string"
        }
    },
    "type": "object"
}
```
 *Outputs*
 
 A POST request which initialises the container with the audio files and process name.
 
 #### The Enroll Logic App
 
 This Logic App will enroll a speaker by using a short clip of their voice. See [Speaker Recognition](https://azure.microsoft.com/en-us/services/cognitive-services/speaker-recognition/) for more information
 
![enroll](https://github.com/msimecek/Speech-Training-Pipeline/blob/shane-doc/_images/enrolllogicapp.png)
 
The enrollment service will return a GUID upon successful registration and the Logic App will write a file to blob storage that will reference the speaker's name to the enrolled voice. This is simply an example implementation, a more efficient implementation would be to export and run this model locally in a container and store the speaker GUID to speaker name in memory for more real time speaker identification.

*Inputs*
```
    "properties": {
        "fileURL": { 'This is the url of the voice file you want to enroll
            "type": "string"
        },
        "jobName": { 'This is the name of the process so that you can monitor it
            "type": "string"
        },
        "shortAudio": { 'Instruct the service to waive the recommended minimum audio limit needed for enrollment. Set value to “true” to force enrollment using any audio length (min. 1 second).
            "type": "string"
        },
        "speakerName": { 'The name of the person you want to enroll
            "type": "string"
        },
        "speakerURL": { 'The endpoint for the Speaker Cognitive Service - see https://westus.dev.cognitive.microsoft.com/docs/services/563309b6778daf02acc0a508/operations/5645c3271984551c84ec6797
            "type": "string"
        },
        "speechKey": { 'Your Speaker Recognition Cognitive Services key
            "type": "string"
        }
    },
    "type": "object"
}
```


*Outputs*
 
 The logic app will output the GUID from the enrollment service and write a GUID/Speaker reference blob to storage.
 
#### The Recognise Logic App

 This Logic App will recognise a speaker by using a short clip of a voice. See [Speaker Recognition](https://azure.microsoft.com/en-us/services/cognitive-services/speaker-recognition/) for more information  
 
 ![RecogniseLogicApp](https://github.com/msimecek/Speech-Training-Pipeline/blob/shane-doc/_images/recogniselogicapp.png)
  
The recongise service will return a GUID upon successful identification and the Logic App will read a file from blob storage that will retrieve the reference to the speaker's name. This is simply an example implementation, a more efficient implementation would be to export and run this model locally in a container and store the speaker GUID to speaker name in memory for more real time speaker identification.

*Inputs*
```
{
    "properties": {
        "fileURL": {
            "type": "string"
        },
        "identificationProfileIds": { 'These are the GUIDS of all the candidate speakers currently enrolled
            "type": "string"
        },
        "shortAudio": { 'Instruct the service to waive the recommended minimum audio limit needed for enrollment. Set value to “true” to force enrollment using any audio length (min. 1 second).
            "type": "string"
        },
        "speakerURL": { 'The endpoint for the Speaker Cognitive Service - see https://westus.dev.cognitive.microsoft.com/docs/services/563309b6778daf02acc0a508/operations/5645c523778daf217c292592
            "type": "string"
        },
        "speechKey": { 'Your Speaker Recognition Cognitive Services key
            "type": "string"
        }
    },
    "type": "object"
}
```
*Outputs*

The name of the speaker as retrieved from the blob storage file matching the speaker GUID

* Function App
** Methods - remove
** start

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
