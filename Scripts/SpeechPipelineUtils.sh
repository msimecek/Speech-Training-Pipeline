#!/usr/bin/env bash

# First run az login 
echo Enter Resource Group
read RESOURCE_GROUP
FUNCTIONSTART=$(az functionapp list --resource-group speech --query "[?defaultHostName].defaultHostName" --output tsv)
FUNCTIONSTARTURL="https://$FUNCTIONSTART/api/start"
echo Azure Function App start url is $FUNCTIONSTARTURL
SPEECHNAME=$(az cognitiveservices list -g $RESOURCE_GROUP --query "[?kind=='SpeechServices'].name" --output tsv) 
SPEAKERNAME=$(az cognitiveservices list -g $RESOURCE_GROUP --query "[?kind=='SpeakerRecognition'].name" --output tsv) 
SPEECHKEY=$(az cognitiveservices account keys list -g $RESOURCE_GROUP -n $SPEECHNAME --query "[key1]" --output tsv)
echo Speech Cognitive Service key1 is $SPEECHKEY
SPEAKERKEY=$(az cognitiveservices account keys list -g $RESOURCE_GROUP -n $SPEAKERNAME --query "[key1]" --output tsv)
echo Speaker Recognition Cognitive Service key1 is $SPEAKERKEY
SPEECHREGION=$(az cognitiveservices list -g $RESOURCE_GROUP --query "[?kind=='SpeechServices'].location" --output tsv) 
SPEAKERREGION=$(az cognitiveservices list -g $RESOURCE_GROUP --query "[?kind=='SpeakerRecognition'].location" --output tsv) 
SPEECHENDPOINT=$(az cognitiveservices list -g $RESOURCE_GROUP --query "[?kind=='SpeechServices'].endpoint" --output tsv)
echo Speech Cognitive Services Endpoint is $SPEECHENDPOINT
SUBMITLOGICAPP=$(az resource list --resource-group $RESOURCE_GROUP --resource-type "Microsoft.Logic/workflows" --query "[?contains(name, 'submit')].name" --output tsv)
echo Submit logic app is $SUBMITLOGICAPP
SUBSCRIPTIONKEY=$(az account list --query "[?isDefault].id" --output tsv --all)
TENANT=$(az account list --query "[?isDefault].tenantId" --output tsv --all)
echo AD Tenant $TENANT
SPAPPID=$(az ad sp list --display-name $RESOURCE_GROUP --query "[?appId].appId" --output tsv)
echo Service Principal AppId $SPAPPID