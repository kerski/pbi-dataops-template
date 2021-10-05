<#
    Author: John Kerski
    Description: This script:
        1) Creates Agent Pools in DevOps
        2) Create Resource Group in Azure Portal
        3) Creates Azure Container Registry (ACR)
        4) Builds and Uploads Docker Image to ACR
        5) Create Container Instances

    Dependencies: 
    1) Azure CLI installed
    2) Docker installed
    3) A subscription in Azure created already and your are the owner
    4) Administrator of Agent Pools or Administrator Rights to Azure DevOps instance
    4) An existing Azure DevOps instance with PAT create (https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page#create-a-pat)

    NOTE: As of Sept. 2021, generating a PAT requires creating another app to grant access to get the token via an API.  Seems like a lot of overhead, so manually setting up the token is easier.
    PAT permissions: Agent Pools (read, manage)
#>

### UPDATE VARIABLES HERE thru Read-Host
# Set Subscription Name
$SubName = Read-Host "Please enter the name of the subscription on Azure"
# Set Location
$Location = Read-Host "Please enter the location name of your Azure Service (ex. centralus)"
# The URL of the Azure DevOps or Azure DevOps Server instance.
$AZP_URL = 	Read-Host "Please enter the base url of the Azure DevOps instance (ex. https://dev.azure.com/{org})"
# Personal Access Token (PAT) with Agent Pools (read, manage) scope, created by a user who has permission to configure agents, at AZP_URL.
$AZP_TOKEN = Read-Host "Please enter the Personal Access Token"
# Base64 encode for Azure DevOps.  Prepared with semicolon or it won't work with Azure DevOps API
$AZP_TOKEN_Base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(":" + $AZP_TOKEN))
$AZP_Basic_Auth = "Basic $($AZP_TOKEN_Base64)"
# Generate GUID for unique pool creation
$GuidX = New-Guid
# Resource Names
$ResourceGroupName = "rg-pbi-dataops"
# Registry name must be alphanumerics only
$RegistryName = "acrpbidataops"
$ContainerName = "container-pbi-dataops"
$AgentName7GB2CPU = "$($AgentName)-7gb-2cpu"
$AgentName10_5GB3CPU = "$($AgentName)-10-5gb-3cpu"

# Agent pool name (default value: Default).	
$AZP_POOL7GB2CPU = "7GB2CPU_$($GuidX.Guid)"
$AZP_POOL10_5GB3CPU = "10_5GB3CPU_$($GuidX.Guid)"

### Now Login Into Azure
$LoginInfo = az login | ConvertFrom-Json

if(!$LoginInfo) {
    Write-Error "Unable to Login into Azure"
    return
}

# Switch to subscription
az account set --subscription $SubName
# This will throw an error is the $SubName is not accessible


### Step 1 - Create Agent Pools
Write-Host -ForegroundColor Cyan "Step 1 of 5: Create Agent Pools in Azure DevOps"

#Thanks to https://davidhamann.de/2019/04/12/powershell-invoke-webrequest-by-example/
#Create Pools via Azure DevOps API
#Create Agent Pool with 7GB 2CPU
$PoolReq1 = Invoke-WebRequest "$($AZP_URL)/_apis/distributedtask/pools?api-version=6.0" `
                  -Method Post `
                  -ContentType "application/json" `
                  -Headers @{ 'Authorization' = $AZP_Basic_Auth } `
                  -Body "{ 'isHosted': false, 'name': '$($AZP_POOL7GB2CPU)'}" -Verbose

if($PoolReq1.StatusCode -ne 200)
{
    Write-Error "Unable to Create Agent Pool"
    return
}


#Create Agent Pool with 10.5GB 3CPU
$PoolReq2 = Invoke-WebRequest "$($AZP_URL)/_apis/distributedtask/pools?api-version=6.0" `
                  -Method Post `
                  -ContentType "application/json" `
                  -Headers @{ 'Authorization' = $AZP_Basic_Auth } `
                  -Body "{ 'isHosted': false, 'name': '$($AZP_POOL10_5GB3CPU)'}" -Verbose

                  
if($PoolReq2.StatusCode -ne 200)
{
    Write-Error "Unable to Create Agent Pool"
    return
}


# Step 2
Write-Host -ForegroundColor Cyan "Step 2 of 5: Create Resource Group to host container information"

# Create a resource group
$RGResult = az group create --name $ResourceGroupName --location $Location

if(!$RGResult) {
    Write-Error "Unable to create resource group"
    return
}

# Step 3 - Create a container registry
Write-Host -ForegroundColor Cyan "Step 3 of 5: Create Container Registry"

$CRResult = az acr create --resource-group $ResourceGroupName --name $RegistryName --sku Basic | ConvertFrom-Json

if(!$CRResult) {
    Write-Error "Unable to create container registry"
    return
}

# Step 4 - Push Docker Build
Write-Host -ForegroundColor Cyan "Step 4 of 5: Build and Push Docker Image to Registry"

# Login into the register
az acr login --name $CRResult.loginServer

# Build Docker Image
docker build --no-cache -t "$($AgentName):latest" .

# Tag 
docker tag "$($AgentName):latest" "$($CRResult.loginServer)/$($AgentName)"

#Push to Registry
docker push "$($CRResult.loginServer)/$($AgentName)"

### Create container instance (NOTE: I switch to PowerShell but I found this to be more successful in implementing)
Write-Host -ForegroundColor Cyan "Step 5 of 5: Create Container"

# Install Az.ContainerInstance Module if Needed
if (Get-Module -ListAvailable -Name "Az.Accounts") {
    Write-Host "Az.Accounts already installed"
} else {
    Install-Module -Name Az.Accounts -Scope CurrentUser -AllowClobber -Force
}

if (Get-Module -ListAvailable -Name "Az.ContainerInstance") {
    Write-Host "Az.ContainerInstance already installed"
} else {
    Install-Module -Name Az.ContainerInstance -Scope CurrentUser -AllowClobber -Force
}

if (Get-Module -ListAvailable -Name "Az.ContainerRegistry") {
    Write-Host "Az.ContainerRegistry already installed"
} else {
    Install-Module -Name Az.ContainerRegistry -Scope CurrentUser -AllowClobber -Force
}

# Connect to Azure
Connect-AzAccount

Connect-AzContainerRegistry -Name $RegistryName

# Setup port and environment variables
$Port1 = New-AzContainerInstancePortObject -Port 8080 -Protocol TCP
$Port2 = New-AzContainerInstancePortObject -Port 443 -Protocol TCP
# Setup Environment Variables
$Arg1 = New-AzContainerInstanceEnvironmentVariableObject -Name "AZP_URL" -Value $AZP_URL
$Arg2 = New-AzContainerInstanceEnvironmentVariableObject -Name "AZP_TOKEN" -Value $AZP_TOKEN
$Arg3 = New-AzContainerInstanceEnvironmentVariableObject -Name "AZP_AGENT_NAME" -Value $AgentName7GB2CPU
$Arg4 = New-AzContainerInstanceEnvironmentVariableObject -Name "AZP_POOL" -Value $AZP_POOL7GB2CPU
$EnvVars = @($Arg1,$Arg2,$Arg3,$Arg4)

# Create Instance Template
# According to https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/hosted?view=azure-devops&tabs=yaml#hardware
# The base instance for the windows machine has 7 GB or RAM and 2 virtual CPUs
# This instance will match those for testing purposes
$ContainerOne = New-AzContainerInstanceObject -Name self-host-container-one -Image "$($CRResult.loginServer)/$($AgentName)" `
                                           -RequestCpu 2 `
                                           -RequestMemoryInGb 7 `
                                           -Port @($Port1, $Port2) `
                                           -EnvironmentVariable $EnvVars

if(!$ContainerOne) {
    Write-Error "Unable to create container"
    return
}

#Create container with 50% more RAM and CPU
$Arg5 = New-AzContainerInstanceEnvironmentVariableObject -Name "AZP_AGENT_NAME" -Value $AgentName10_5GB3CPU
$Arg6 = New-AzContainerInstanceEnvironmentVariableObject -Name "AZP_POOL" -Value $AZP_POOL10_5GB3CPU
$EnvVars = @($Arg1,$Arg2,$Arg5,$Arg6)

$ContainerTwo = New-AzContainerInstanceObject -Name self-host-container-two -Image "$($CRResult.loginServer)/$($AgentName)" `
                                           -RequestCpu 3 `
                                           -RequestMemoryInGb 10.5 `
                                           -Port @($Port1, $Port2) `
                                           -EnvironmentVariable $EnvVars

if(!$ContainerTwo) {
    Write-Error "Unable to create container"
    return
}

# Enable Admin settings so current user can create instance
Update-AzContainerRegistry -Name $RegistryName -ResourceGroupName $ResourceGroupName -EnableAdminUser

# Get username and password for registry credential
$AzConRegistryCredential = Get-AzContainerRegistryCredential -ResourceGroupName $ResourceGroupName -Name $RegistryName

# Setup Credential
$ImageRegistryCredential = New-AzContainerGroupImageRegistryCredentialObject -Server $CRResult.loginServer `
                                                  -Username $AzConRegistryCredential.Username `
                                                  -Password (ConvertTo-SecureString $AzConRegistryCredential.Password -AsPlainText -Force) 

# Pause so credentials work
Start-Sleep -Seconds 120

# Create First Instance
$ContainerGroupOne = New-AzContainerGroup -ResourceGroupName $ResourceGroupName `
                                       -Name "$($ContainerName)-7gb-2cpu" `
                                       -Location $Location `
                                       -Container $ContainerOne `
                                       -OsType Windows `
                                       -RestartPolicy "OnFailure" `
                                       -IpAddressType Public `
                                       -ImageRegistryCredential $ImageRegistryCredential

# Create Second Instance
$ContainerGroupTwo = New-AzContainerGroup -ResourceGroupName $ResourceGroupName `
                                       -Name "$($ContainerName)-10-5gb-3cpu" `
                                       -Location $Location `
                                       -Container $ContainerTwo `
                                       -OsType Windows `
                                       -RestartPolicy "OnFailure" `
                                       -IpAddressType Public `
                                       -ImageRegistryCredential $ImageRegistryCredential

<#
In a separate window check the status: 
az container attach --resource-group rg-pbi-dataops --name container-pbi-dataops-10-5gb-3cpu
az container attach --resource-group rg-pbi-dataops --name container-pbi-dataops-7gb-2cpu
#>

Write-Host -ForegroundColor Green "Installation Complete"
Write-Host -ForegroundColor Green "Be sure to update DataOps-CI.yml with the $($AZP_POOL7GB2CPU) and $($AZP_POOL10_5GB3CPU) pool references."

<#
Local running of container:
docker build -t agent-pbi-dataops:latest .
docker run -e AZP_URL=$AZP_URL -e AZP_TOKEN=$AZP_TOKEN -e AZP_AGENT_NAME=mydockeragent agent-pbi-dataops:latest
#>

# Cleanup
# Delete resource group
#az group delete --name $ResourceGroupName --yes
#Delete Agents
#Delete Pool 1
<#$Pool1 = $PoolReq1.Content | ConvertFrom-Json
Invoke-WebRequest "$($AZP_URL)/_apis/distributedtask/pools/$($Pool1.Id)?api-version=6.0" `
                  -Method Delete `
                  -ContentType "application/json" `
                  -Headers @{ 'Authorization' = $AZP_Basic_Auth }

#Delete Pool 2
$Pool2 = $PoolReq2.Content | ConvertFrom-Json
Invoke-WebRequest "$($AZP_URL)/_apis/distributedtask/pools/$($Pool2.Id)?api-version=6.0" `
                  -Method Delete `
                  -ContentType "application/json" `
                  -Headers @{ 'Authorization' = $AZP_Basic_Auth }

#>