<#
.SYNOPSIS

Performs installation of Azure and Power BI resources based on Part 20 of Bringing DataOps to Power BI

.DESCRIPTION

    Description: This script:
        1) Create Azure DevOps Project
        2) Create Resource Group
        3) Create Storage Account
        4) Create Event Grid Topic
        5) Create Azure Function App
        6) Create Azure Key Vault
        7) Update Azure Function Application Settings
        8) Create Azure Event Subscription
        9) Create Power BI Workspace and setup DataFlow Example

        Dependencies: 
            1) Azure CLI installed with version 2.37
            2) Azure DevOps Extension 0.25
            2) Power BI Powershell installed
            3) A subscription in Azure created already and your are the owner
    
    Author: John Kerski
.INPUTS

None.

.OUTPUTS

None.

.EXAMPLE

PS> .\Setup-DataFlow-Trigger.ps1

#>

### UPDATE VARIABLES HERE thru Read-Host
# Set Subscription Name
$SubName = Read-Host "Please enter the name of the subscription on Azure"
# Set Location
$Location = Read-Host "Please enter the location name of your Power BI Service (ex. eastus2)"
# Set Project Name
$ProjectName = Read-Host "Please enter the name of the Azure DevOps project you'd like to create"
# Azure PAT Token
$ADOToken = Read-Host "Please enter the PAT Token you created from Azure DevOps"
#Set Power BI WOrkspace
$BuildWSName = Read-Host "Please enter the name of the build workspace (ex. Build)"

$AzDOHostURL = "https://dev.azure.com/"
$RepoToCopy = "https://github.com/kerski/pbi-dataops-template.git"
# Append this suffix to Azure resource names to keep from naming conflicts
$RandomSuffix = Get-Random -Minimum 100 -Maximum 999
# Set Resource Group Name
$ResourceGroupName = "rgdataflowtrigger$($RandomSuffix)"
# Now hyphens because of storage account naming restrictions
$StorageName = "stdataflowtrigger$($RandomSuffix)"
$EventTopicName = "evgt-dataflow-storage-$($RandomSuffix)"
$AZFuncName = "func-dataflow-trigger-$($RandomSuffix)"
$AZKeyVaultName = "kv-dataflow-trigger-$($RandomSuffix)"

# Example download file for Azure Functions
$AzFuncFilePath = "./dataflow-func.zip"
$AzFuncURI = "https://raw.githubusercontent.com/kerski/pbi-dataops-template/part20/SetupScripts/PremiumPerUser/DataFlows/func-dataflow-trigger.zip" 
$DFFilePath = "./RawSourceExample.json"
$DFExURI = "https://raw.githubusercontent.com/kerski/pbi-dataops-template/part20/SetupScripts/PremiumPerUser/DataFlows/RawSourceExample.json"

# PowerShell DataFlow Scripts
$DFUtilsURI = "https://raw.githubusercontent.com/kerski/powerbi-powershell/master/examples/dataflows/DFUtils.psm1"
$GraphURI = "https://raw.githubusercontent.com/kerski/powerbi-powershell/master/examples/dataflows/Graph.psm1"
$ImportURI = "https://raw.githubusercontent.com/kerski/powerbi-powershell/master/examples/dataflows/ImportModel.ps1"

#Download scripts for Graph, DFUtils, and Import-Module.ps1
Invoke-WebRequest -Uri $DFUtilsURI -OutFile "./DFUtils.psm1"
Invoke-WebRequest -Uri $GraphURI -OutFile "./Graph.psm1"
Invoke-WebRequest -Uri $ImportURI -OutFile "./ImportModel.ps1"
Invoke-WebRequest -Uri $AzFuncURI -OutFile $AzFuncFilePath
Invoke-WebRequest -Uri $DFExURI -OutFile $DFFilePath 

### Now Login Into Azure
$LoginInfo = az login | ConvertFrom-Json

if(!$LoginInfo) {
    Write-Error "Unable to Login into Azure"
    return
}

# Switch to subscription
az account set --subscription $SubName
# This will throw an error is the $SubName is not accessible

Write-Host -ForegroundColor Cyan "Step 1 of 9: Creating Azure DevOps project"
#Assumes organization name matches $LogInfo.name and url for Azure DevOps Service is https://dev.azure.com
$ProjectResult = az devops project create `
                --name $ProjectName `
                --description "Part 20 example of Bringing DataOps to Power BI Dataflows" `
                --organization "$($AzDOHostURL)$($LoginInfo.name)" `
                --source-control git `
                --visibility private `
                --open --only-show-errors | ConvertFrom-Json

#Check result
if(!$ProjectResult) {
    Write-Error "Unable to Create Project in Azure DevOps"
    return
}

#Get Repository Id
$RepoResult = az repos list --project $ProjectResult.id `
                            --organization "$($AzDOHostURL)$($LoginInfo.name)" | ConvertFrom-Json

if(!$RepoResult.Count -gt 0)
{
    Write-Error "Unable to retrieve repository information from the Azure DevOps Project"
    return 
}

#Import Repo for kerski's GitHub - this serves as to initliaze the repo
$RepoImportResult = az repos import create --git-source-url $RepoToCopy `
            --org "$($AzDOHostURL)$($LoginInfo.name)" `
            --project $ProjectName `
            --repository $ProjectName --only-show-errors | ConvertFrom-Json

#Check Result
if(!$RepoImportResult) {
    Write-Error "Unable to Import Repository"
    return
}

# Step 2
Write-Host -ForegroundColor Cyan "Step 2 of 9: Create Resource Group to host Data Flow Trigger"

# Create a resource group
$RGResult = az group create --name $ResourceGroupName --location $Location

if(!$RGResult) {
    Write-Error "Unable to create resource group"
    return
}

# Step 3
Write-Host -ForegroundColor Cyan "Step 3 of 9: Create Data Storage Account (V2)"

# Create a storage account
$SAResult = az storage account check-name --name $StorageName | ConvertFrom-Json

if(!$SAResult.nameAvailable) {
    Write-Error "Unable to create storage account in '$($StorageName)' as it already exists.  Please update script with unique storage account name"
    return
}

$STResult = az storage account create --name $StorageName --resource-group $ResourceGroupName `
                                                            --access-tier Hot `
                                                            --allow-shared-key-access true `
                                                            --assign-identity `
                                                            --enable-hierarchical-namespace true `
                                                            --kind StorageV2 `
                                                            --location $Location `
                                                            --min-tls-version TLS1_2 `
                                                            --sku Standard_RAGRS | ConvertFrom-Json

if(!$STResult) {
    Write-Error "Unable to create storage account"
    return
}

# Assign current user 'Owner', 'Storage Blob Data Reader' and 'Storage Blob Data Owner'
# This assists with Data Flow setup later
$AssignResult = az role assignment create --assignee $LoginInfo.user.name --role "Owner" --scope $STResult.id | ConvertFrom-Json

if(!$AssignResult) {
    Write-Error "Unable to assign $($LoginInfo.user.name) to 'Owner'"
    return
}

$AssignResult = az role assignment create --assignee $LoginInfo.user.name --role "Storage Blob Data Owner" --scope $STResult.id | ConvertFrom-Json

if(!$AssignResult) {
    Write-Error "Unable to assign $($LoginInfo.user.name) to 'Storage Blob Data Owner'"
    return
}

$AssignResult = az role assignment create --assignee $LoginInfo.user.name --role "Storage Blob Data Contributor"  --scope $STResult.id | ConvertFrom-Json

if(!$AssignResult) {
    Write-Error "Unable to assign $($LoginInfo.user.name) to 'Storage Blob Data Contributor'"
    return
}


$AssignResult = az role assignment create --assignee $LoginInfo.user.name --role "Storage Blob Data Reader"  --scope $STResult.id | ConvertFrom-Json

if(!$AssignResult) {
    Write-Error "Unable to assign $($LoginInfo.user.name) to 'Storage Blob Data Owner'"
    return
}

# Step 4 - Create an Event Topic
Write-Host -ForegroundColor Cyan "Step 4 of 9: Create Event Grid Topic"

$EGResult = az eventgrid system-topic create --resource-group $ResourceGroupName `
                                             --name $EventTopicName `
                                             --location $Location `
                                             --topic-type microsoft.storage.storageaccounts `
                                             --source $STResult.id | ConvertFrom-Json

if(!$EGResult) {
    Write-Error "Unable to create Event Grid Topic 'evgt-dataflow-storage' "
    return
}

# Step 5 - Create Azure Function
Write-Host -ForegroundColor Cyan "Step 5 of 9: Create Azure Function App"

$AZResult = az functionapp create --name $AzFuncName `
                                  --resource-group $ResourceGroupName `
                                  --storage-account $StorageName `
                                  --consumption-plan-location $Location `
                                  --functions-version 4 `
                                  --runtime "powershell" | ConvertFrom-Json

if(!$AZResult) {
    Write-Error "Unable to create Azure Function '$($AzFuncName)' "
    return
}

#Assign Managed Identity to Azure Function
$MIResult = az functionapp identity assign --resource-group $ResourceGroupName `
                                           --name $AZFuncName | ConvertFrom-Json

if(!$MIResult) {
    Write-Error "Unable to assignment managed identity to Azure Function '$($AzFuncName)' "
    return
}

# Make sure Managed Identity has access to the storage as Storage
$AssignResult = az role assignment create --assignee-object-id $MIResult.principalId `
                                          --role "Storage Blob Data Reader" `
                                          --assignee-principal-type ServicePrincipal `
                                          --scope $STResult.id | ConvertFrom-Json

if(!$AssignResult) {
    Write-Error "Unable to assign Managed Identity to $($STResult.name)"
    return
}


# Step 6 - Create Azure Key Vault
Write-Host -ForegroundColor Cyan "Step 6 of 9: Create Azure Key Vault"
$KVResult = az keyvault create --location $Location `
                               --name $AZKeyVaultName `
                               --resource-group $ResourceGroupName | ConvertFrom-Json

if(!$KVResult) {
    Write-Error "Unable to create azure key vault"
    return
}

# Set get policy to secret for the Azure Function's Mangaged Identity
$KVPolResult = az keyvault set-policy --name $KVResult.name `
                       --object-id $MIResult.principalId `
                       --secret-permissions get | ConvertFrom-Json

if(!$KVPolResult) {
    Write-Error "Unable to create azure key vault policy for the managed identity"
    return
}

#Create Secret Value for PAT Token
$SecResult = az keyvault secret set --name "AzureDevOpsPAT" `
                                    --vault-name $KVResult.name `
                                    --value $ADOToken | ConvertFrom-Json


if(!$SecResult) {
    Write-Error "Unable to create secret value for Azure Key Vault"
    return
}


# Step 7 - Update Azure Function Application Settings
Write-Host -ForegroundColor Cyan "Step 7 of 9: Update Azure Function Application Settings"

# Deploy Code
$FuncResult = az functionapp deployment source config-zip --name $AzFuncName `
                                                          --build-remote true `
                                                          --resource-group $ResourceGroupName `
                                                          --src $AzFuncFilePath

if(!$FuncResult) {
    Write-Error "Unable to deploy code to create Azure Function '$($AzFuncName)' "
    return
}

#Set Organization Name
$ConfigResult = az functionapp config appsettings set --name $AZFuncName `
                                      --resource-group $ResourceGroupName `
                                      --settings "OrganizationName=$($LoginInfo.name)"

if(!$ConfigResult) {
    Write-Error "Unable to update OrganizationName setting for Azure Function '$($AzFuncName)' "
    return
}

#Set AzureDevOpsProjectName
$ConfigResult = az functionapp config appsettings set --name $AZFuncName `
                                      --resource-group $ResourceGroupName `
                                      --settings "AzureDevOpsProjectName=$($ProjectResult.name)"

if(!$ConfigResult) {
    Write-Error "Unable to update AzureDevOpsProjectName setting for Azure Function '$($AzFuncName)' "
    return
}

#Set AzureDevOpsRepositoryId
$ConfigResult = az functionapp config appsettings set --name $AZFuncName `
                                      --resource-group $ResourceGroupName `
                                      --settings "AzureDevOpsRepositoryId=$($RepoResult[0].id)"

if(!$ConfigResult) {
    Write-Error "Unable to update AzureDevOpsRepositoryId setting for Azure Function '$($AzFuncName)' "
    return
}

#Set AzureDevOpsPAT
$ConfigResult = az functionapp config appsettings set --name $AZFuncName `
                                      --resource-group $ResourceGroupName `
                                      --settings "AzureDevOpsPAT=@Microsoft.KeyVault(SecretUri=$($SecResult.id))"

if(!$ConfigResult) {
    Write-Error "Unable to update AzureDevOpsPAT setting for Azure Function '$($AzFuncName)' "
    return
}

#Set StorageAccountName
$ConfigResult = az functionapp config appsettings set --name $AZFuncName `
                                      --resource-group $ResourceGroupName `
                                      --settings "StorageAccountName=$($STResult.name)"

if(!$ConfigResult) {
    Write-Error "Unable to update StorageAccountName setting for Azure Function '$($AzFuncName)' "
    return
}

#Set AzureDevOpsBranch
$ConfigResult = az functionapp config appsettings set --name $AZFuncName `
                                      --resource-group $ResourceGroupName `
                                      --settings "AzureDevOpsBranch=refs/heads/part20"

if(!$ConfigResult) {
    Write-Error "Unable to update AzureDevOpsBranch setting for Azure Function '$($AzFuncName)' "
    return
}

# Step 8 - Create Azure Event Subscription
Write-Host -ForegroundColor Cyan "Step 8 of 9: Create Azure Event Subscription and link to Azure Function"

# Create Event Subscription
$SubResult = az eventgrid system-topic event-subscription create --name "EventGridTrigger2" `
    --resource-group $ResourceGroupName `
    --system-topic-name $EGResult.name `
    --endpoint "$($AZResult.id)/functions/EventGridTrigger1" `
    --endpoint-type azurefunction `
    --advanced-filter subject StringContains "model.json@snapshot"

if(!$SubResult) {
    Write-Error "Unable to create Event Subscription for Azure Function '$($AzFuncName)' "
    return
}

# Step 9 - Create Power BI Workspace
Write-Host -ForegroundColor Cyan "Step 9 of 9: Create Power BI Workspace and upload example Dataflow"

#Install Powershell Module if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "MicrosoftPowerBIMgmt installed moving forward"
} else {
    #Install Power BI Module
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
}
#Login into Power BI to Create Workspaces
Login-PowerBI

#Get Premium Per User Capacity as it will be used to assign to new workspace
$Cap = Get-PowerBICapacity -Scope Individual

if(!$Cap.DisplayName -like "Premium Per User*")
{
    Write-Error "Script expects Premium Per Use Capacity."
    return
}

#Create Build Workspace
New-PowerBIWorkspace -Name $BuildWSName

#Find Workspace and make sure it wasn't deleted (if it's old or you ran this script in the past)
$BuildWSObj = Get-PowerBIWorkspace -Scope Organization -Filter "name eq '$($BuildWSName)' and state ne 'Deleted'"

if($BuildWSObj.Length -eq 0)
{
  Throw "$($BuildWSName) workspace was not created."
}

# Update Paramters
Set-PowerBIWorkspace -CapacityId $Cap.Id.Guid -Scope Organization -Id $BuildWSObj.Id.Guid 

# This command sets the execution policy to bypass for only the current PowerShell session after the window is closed,
# the next PowerShell session will open running with the default execution policy.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# Upload Example Data Flow
.\ImportModel.ps1 -Workspace $BuildWSObj.name -File $DFFilePath

# If we get here, success
Write-Host -ForegroundColor Green "Installation Complete in Azure and Azure DevOps Project $($ProjecResult.name) at $($AzDOHostURL)$($LogInfo.name)"

<# Cleanup
# Delete resource group
az group delete --name $ResourceGroupName --yes
# Delete project
az devops project delete --id $ProjectResult.id --organization "$($AzDOHostURL)$($LogInfo.name)" --yes
# Delete workspace
Invoke-PowerBIRestMethod -Url "groups/$($BuildWSObj.Id.Guid)" -Method Delete
#>