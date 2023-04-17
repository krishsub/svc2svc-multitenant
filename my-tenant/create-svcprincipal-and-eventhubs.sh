#!/bin/bash
tenantId="<my-tenant-id>"
appIdFromPartnerTenant="<app-id-from-partner-tenant>"

# Location & Resource Group in Azure for subscription under my-tenant.com
location="westeurope"
resourceGroup="my-resources"

eventHubNamespacePrefix="my-eh-ns-"
eventHubNamePrefix="my-eh-"
randomString=$(openssl rand -hex 8)

eventHubNamespace="$eventHubNamespacePrefix$randomString"
eventHubName="$eventHubNamePrefix$randomString"

# Built-in Azure AD role 
eventHubDataSenderRoleName="Azure Event Hubs Data Sender"

# Login to my-tenant.com
az login --tenant $tenantId

# Create a service principal in this tenant (my-tenant.com) based on a
# multi-tenant app registration (appId) defined in another tenant.
az ad sp create --id $appIdFromPartnerTenant

# Create the resource group
az group create --location $location \
                --name $resourceGroup
            
# Create an event hub namespace and an event hub
az eventhubs namespace create --name $eventHubNamespace \
                              --resource-group $resourceGroup

az eventhubs eventhub create --name $eventHubName \
                             --namespace-name $eventHubNamespace \
                             --resource-group $resourceGroup

# Get the service principal object id that was just created.
servicePrincipalObjId=$(az ad sp list --filter "appId eq '$appIdFromPartnerTenant'" --query [].id -o tsv)

# Add role assignment, give permissions to send data to the event hub
az role assignment create --role "$eventHubDataSenderRoleName" \
                          --assignee-object-id $servicePrincipalObjId \
                          --assignee-principal-type ServicePrincipal \
                          --scope "//subscriptions/$(az account show --query id -o tsv)/resourceGroups/$resourceGroup/providers/Microsoft.EventHub/namespaces/$eventHubNamespace"

