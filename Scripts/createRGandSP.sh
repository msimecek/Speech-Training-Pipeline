#!/usr/bin/env bash

# First run az login 
echo Enter Resource Group
read RESOURCE_GROUP
echo enter Location - note not all services in this solution are available in all regions - we recommend westeurope or westus
read LOCATION
az group create --name $RESOURCE_GROUP --location $LOCATION
#Create Service Principal
SUBSCRIPTIONKEY=$(az account list --query "[?isDefault].id" --output tsv --all)
SCOPE="/subscriptions/"$SUBSCRIPTIONKEY"/resourceGroups/"$RESOURCE_GROUP 
echo Created resource group $RESOURCE_GROUP
SPAPPID=$(az ad sp create-for-rbac --role contributor --scopes $SCOPE --query appId --output tsv)
echo Created SP with appid $SPAPPID
SPAPPKEY=$(az ad sp credential list --id $SPAPPID --query "[?keyId].keyId" --output tsv)
echo SP key $SPAPPKEY
