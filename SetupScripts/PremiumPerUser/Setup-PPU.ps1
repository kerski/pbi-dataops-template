<#
    Author: John Kerski
    Description: This script:
        1) Creates Build and Development workspaces in Power BI
        2) Assigns the service user as an admin to the workspaces
        3) Assigns to the Premium Per User capacity to the two workspaces.
        4) Setups Azure DevOps project with pipeline using example found on GitHub
        5) Upload Power BI Report

    Dependencies: 
    1) Azure CLI installed
    2) Service User must be created beforehand.
    3) Person running the script must have the ability admin rights to Power BI Tenant and at least a Pro license
    4) An existing Azure DevOps instance
#>

#Set Variables
$BuildWSName = Read-Host "Please enter the name of the build workspace (ex. Build)"
$BuildDesc = "Used to test Power BI Reports before moving to development workspaces"
$DevWSName = Read-Host "Please enter the name of the build workspace (ex. Development)"
$DevDesc = "Development environment for Power BI Reports"
$SvcUser = Read-Host "Please enter the email address (UPN) of the service account assigned premium per user"

#Get Password and convert to plain string
$SecureString = Read-Host "Please enter the password for the service account assigned premium per user" -AsSecureString
$Bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
$SvcPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($Bstr)

$ProjectName = Read-Host "Please enter the name of the Azure DevOps project you'd like to create"
$AzDOHostURL = "https://dev.azure.com/"
$PBIAPIURL = "https://api.powerbi.com/v1.0/myorg"
$RepoToCopy = "https://github.com/kerski/pbi-dataops-template.git"
$SampleModelURL = "https://github.com/kerski/pbi-dataops-template/blob/part25/Pbi/SampleModel/SampleModel.pbix?raw=true"
$PipelineName = "DataOpsCI-Part25"

#Check Inputs
if(!$BuildWSName -or !$DevWSName -or !$SvcUser -or !$SvcPwd -or !$ProjectName)
{
    Write-Error "Please make sure you entered all the required information. You will need to rerun the script."
    return
} 

#Install Powershell Module if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "MicrosoftPowerBIMgmt installed moving forward"
} else {
    #Install Power BI Module
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
}
#Login into Power BI to Create Workspaces
Login-PowerBI

Write-Host -ForegroundColor Cyan "Step 1 or 5: Creating Power BI Workspaces" 

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

#Update properties
Set-PowerBIWorkspace -Description $BuildDesc -Scope Organization -Id $BuildWSObj.Id.Guid
Set-PowerBIWorkspace -CapacityId $Cap.Id.Guid -Scope Organization -Id $BuildWSObj.Id.Guid 

#Assign service account admin rights to this workspace
Add-PowerBIWorkspaceUser -Id $BuildWSObj[$BuildWSObj.Length-1].Id.ToString() -AccessRight Admin -UserPrincipalName $SvcUser

#Create Dev Workspace
New-PowerBIWorkspace -Name $DevWSName

#Find Workspace and make sure it wasn't deleted (if it's old or you ran this script in the past)
$DevWSObj = Get-PowerBIWorkspace -Scope Organization -Filter "name eq '$($DevWSName)' and state ne 'Deleted'"

if($DevWSObj.Length -eq 0)
{
  Throw "$($DevWSName) workspace was not created."
}

#Update properties
Set-PowerBIWorkspace -Description $DevDesc -Scope Organization -Id $DevWSObj.Id.Guid
Set-PowerBIWorkspace -CapacityId $Cap.Id.Guid -Scope Organization -Id $DevWSObj.Id.Guid 

#Assign service account admin rights to this workspace
Add-PowerBIWorkspaceUser -Id $DevWSObj[$DevWSObj.Length-1].Id.ToString() -AccessRight Admin -UserPrincipalName $SvcUser

Write-Host "Build Workspace ID: $($BuildWSObj.Id.Guid)"
Write-Host "Development Workspace ID: $($DevWSObj.Id.Guid)"


### Now Setup Azure DevOps
$LogInfo = az login | ConvertFrom-Json

Write-Host -ForegroundColor Cyan "Step 2 of 5: Creating Azure DevOps project"
#Assumes organization name matches $LogInfo.name and url for Azure DevOps Service is https://dev.azure.com
$ProjectResult = az devops project create `
                --name $ProjectName `
                --description "Part 23 example of Bringing DataOps to Power BI" `
                --organization "$($AzDOHostURL)$($LogInfo.name)" `
                --source-control git `
                --visibility private `
                --open --only-show-errors

#Check result
if(!$ProjectResult) {
    Write-Error "Unable to Create Project"
    return
}

#Convert Result to JSON
$ProjectInfo = $ProjectResult | ConvertFrom-JSON

Write-Host -ForegroundColor Cyan "Step 3 of 5: Creating Repo in Azure DevOps project"
#Import Repo for kerski's GitHub
$RepoResult = az repos import create --git-source-url $RepoToCopy `
            --org "$($AzDOHostURL)$($LogInfo.name)" `
            --project $ProjectName `
            --repository $ProjectName --only-show-errors | ConvertFrom-Json

#Check Result
if(!$RepoResult) {
    Write-Error "Unable to Import Repository"
    return
}

#Service connection required for non Azure Repos can be optionally provided in the command to run it non interatively
$PipelineResult = az pipelines create --name $PipelineName --repository-type "tfsgit" `
                --description "Part 23 example pipeline of Bringing DataOps to Power BI" `
                --org "$($AzDOHostURL)$($LogInfo.name)" `
                --project $ProjectName `
                --repository $ProjectName `
                --branch "main" `
                --yaml-path "DataOps-CI.yml" --skip-first-run --only-show-errors | ConvertFrom-Json

#Check Result
if(!$PipelineResult) {
    Write-Error "Unable to setup Pipeline"
    return
}

Write-Host -ForegroundColor Cyan "Step 4 of 5: Creating Pipeline in Azure DevOps project"
# Variable 'PBI_API_URL' was defined in the Variables tab
# Assumes commericial environment
$VarResult = az pipelines variable create --name "PBI_API_URL" --only-show-errors `
             --allow-override true --org "$($AzDOHostURL)$($LogInfo.name)" `
             --pipeline-id $PipelineResult.id `
             --project $ProjectName --value $PBIAPIURL

#Check Result
if(!$VarResult) {
    Write-Error "Unable to create pipeline variable PBI_API_URL"
    return
}


# Variable 'TENANT_ID' was defined in the Variables tab
$VarResult = az pipelines variable create --name "TENANT_ID" --only-show-errors `
            --allow-override true --org "$($AzDOHostURL)$($LogInfo.name)" `
            --pipeline-name $PipelineName `
            --project $ProjectName --value $LogInfo.tenantId

#Check Result
if(!$VarResult) {
    Write-Error "Unable to create pipeline variable TENANT_ID"
    return
}
# Variable 'PPU_USERNAME' was defined in the Variables tab
$VarResult = az pipelines variable create --name "PPU_USERNAME" --only-show-errors `
            --allow-override true --org "$($AzDOHostURL)$($LogInfo.name)" `
            --pipeline-name $PipelineName `
            --project $ProjectName --value $SvcUser

#Check Result
if(!$VarResult) {
    Write-Error "Unable to create pipeline variable PPU_USERNAME"
    return
}

# Variable 'PPU_PASSWORD' was defined in the Variables tab
$VarResult = az pipelines variable create --name "PPU_PASSWORD" --only-show-errors `
            --allow-override true --org "$($AzDOHostURL)$($LogInfo.name)" `
            --pipeline-name $PipelineName `
            --project $ProjectName --value $SvcPwd --secret $TRUE

#Check Result
if(!$VarResult) {
    Write-Error "Unable to create pipeline variable PPU_PASSWORD"
    return
}
# Variable 'PBI_BUILD_GROUP_ID' was defined in the Variables tab
$VarResult = az pipelines variable create --name "PBI_BUILD_GROUP_ID" --only-show-errors `
            --allow-override true --org "$($AzDOHostURL)$($LogInfo.name)" `
            --pipeline-name $PipelineName `
            --project $ProjectName --value $BuildWSObj.Id.Guid
#Check Result
if(!$VarResult) {
    Write-Error "Unable to create pipeline variable PBI_BUILD_GROUP_ID"
    return
}

# Variable 'PBI_DEV_GROUP_ID' was defined in the Variables tab
$VarResult = az pipelines variable create --name "PBI_DEV_GROUP_ID" --only-show-errors `
            --allow-override true --org "$($AzDOHostURL)$($LogInfo.name)" `
            --pipeline-name $PipelineName `
            --project $ProjectName --value $DevWSObj.Id.Guid

#Check Result
if(!$VarResult) {
    Write-Error "Unable to create pipeline variable PBI_DEV_GROUP_ID"
    return
}

Write-Host -ForegroundColor Cyan "Step 5 of 5: Uploading SampleModel.pbix to Build Workspace"
#Upload Report
Invoke-WebRequest -Uri $SampleModelURL -OutFile "./SampleModel.pbix"

#Upload Example to Build Workspace
New-PowerBIReport `
   -Path "$(Get-Location)\SampleModel.pbix" `
   -Name "SampleModel" `
   -WorkspaceId $BuildWSObj.Id.Guid `
   -ConflictAction CreateOrOverwrite

Write-Host -ForegroundColor Green "Azure DevOps Project $($ProjectName) created with pipeline $($PipelineName) at $($AzDOHostURL)$($LogInfo.name)"

#Clean up
#az devops project delete --id $ProjectInfo.id --organization "https://dev.azure.com/$($LogInfo.name)" --yes
#Invoke-PowerBIRestMethod -Url "groups/$($DevWSObj.Id.Guid)" -Method Delete 
#Invoke-PowerBIRestMethod -Url "groups/$($BuildWSObj.Id.Guid)" -Method Delete
