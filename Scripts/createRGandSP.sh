#!/usr/bin/env bash

# First run az login 
echo Enter Resource Group name
read RESOURCE_GROUP
echo Enter Resource Group location - note: not all services in this solution are available in all regions - we recommend westeurope or westus
read LOCATION
az group create --name $RESOURCE_GROUP --location $LOCATION
#Create Service Principal
SUBSCRIPTIONKEY=$(az account list --query "[?isDefault].id" --output tsv --all)
SCOPE="/subscriptions/"$SUBSCRIPTIONKEY"/resourceGroups/"$RESOURCE_GROUP 
echo Created resource group $RESOURCE_GROUP
PRINCIPAL=( $(az ad sp create-for-rbac --role contributor --scopes $SCOPE --query [appId,password] --output tsv) )

echo Service principal created. Make note of the following information, it will not be shown again.
echo - AppId: ${PRINCIPAL[0]}
echo - AppSecret: ${PRINCIPAL[1]}