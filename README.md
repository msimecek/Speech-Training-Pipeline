# Speech Training Pipeline

We've built this pipeline to simplify the process of preparing and training a speech to text (STT) models for the [Speech Service](https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/overview), which is part of [Microsoft Azure](https://azure.microsoft.com/en-us/).

The goal is to simplify data preparation and lower the barrier of entry overall. With this pipeline developers have to provide only full audio files and full transcripts, along with Speech Service keys, and wait for custom speech model to be created. Additional improvements in quality can be achieved by running multiple iterations.

![Developer's view](_images/pipeline-developer-view.png)


##Installation

* Requirements
To run the deployment script to create the Resource Group and Service Principal required for this solution, you will need to have the az cli installed - see [Azure Speech CLI](https://github.com/msimecek/Azure-Speech-CLI)

###Create Resource Group and Service Principal 
In this we will be creating the Resource Group and the Service Principal that has the rights to create Azure resources within the provisioned Resource Group. 

1) Log in to the az cli
2) Run script [createRGandSP](https://github.com/msimecek/Speech-Training-Pipeline/blob/shane-doc/Scripts/createRGandSP.sh)
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



###Deploy button and ARM parameters (Craig)
* Required parameters - Deplyment, storage, 

###Components and in depth description (Martin function/container, Craig submit, Speaker Enrol and Id)
* Storage and blobs
* Logic Apps
 ** Submit
 ** Enrol
 ** Identify

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
