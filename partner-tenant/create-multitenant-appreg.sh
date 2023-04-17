#!/bin/bash
partnerTenantId="<partner-tenant-id>"
appRegDisplayName="MyAppReg-123456789"
keyDisplayName="MyKey-123456789" # Not a secret, just a display name!
yearsValid=3

# Login to partner-tenant.com
az login --tenant $partnerTenantId

# Create a multi-tenant app registration
az ad app create --display-name $appRegDisplayName \
                 --sign-in-audience AzureADMultipleOrgs

# Get the app id of the application registration just created
appId=$(az ad app list --display-name $appRegDisplayName --query [].appId -o tsv)

# Create a secret. (Could also be a certificate.)
# Important: Note the password that will be auto-generated after this command.
# Password can't be queried again, only possibility is reset/create a new one.
az ad app credential reset --id $appId \
                           --display-name $keyDisplayName \
                           --years $yearsValid