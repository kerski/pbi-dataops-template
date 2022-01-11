<#
    Author: John Kerski
    Description: This script:
        1) Creates Build, Development, Staging, and Production workspaces in Power BI
        2) Assigns the service user as an admin to the workspaces
        3) Assigns to the Premium Per User capacity to the four workspaces.
        4) Setups Azure DevOps project with pipeline using example found on GitHub
        5) Upload Power BI Report

    Dependencies: 
    1) Azure CLI installed
    2) Service User must be created beforehand.
    3) Person running the script must have the ability admin rights to Power BI Tenant and at least a Pro license
    4) An existing Azure DevOps instance
#>

Import-Module .\Add-PBIWorkspaceWithPPU.psm1 -Force
Import-Module .\Add-AzureDevOpsVariable.psm1 -Force

#Set Variables
$BuildWSName = Read-Host "Please enter the name of the build workspace (ex. Build)"
$BuildDesc = "Used to test Power BI Reports before moving to development workspaces"
$DevWSName = Read-Host "Please enter the name of the development workspace (ex. Development)"
$DevDesc = "Development environment for Power BI Reports"
$StagingWSName = Read-Host "Please enter the name of the staging workspace (ex. Staging)"
$StagingDesc = "Staging environment for Power BI Reports"
$ProdWSName = Read-Host "Please enter the name of the production workspace (ex. Production)"
$ProdDesc = "Production environment for Power BI Reports"
$SvcUser = Read-Host "Please enter the email address (UPN) of the service account assigned premium per user"


#Get Password and convert to plain string
$SecureString = Read-Host "Please enter the password for the service account assigned premium per user" -AsSecureString
$Bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
$SvcPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($Bstr)#>

#Set Azure DevOps and SharePoint information
$ProjectName = Read-Host "Please enter the name of the Azure DevOps project you'd like to create"
$SPBaseUrl = Read-Host "Please enter the base url of the SharePoint site (ex. https://x.sharepoint.com)"
$SPSiteName = Read-Host "Please enter the name of the SharePoint site to store low-code coverage data"
$AzDOHostURL = "https://dev.azure.com/"
$PBIAPIURL = "https://api.powerbi.com/v1.0/myorg"
$RepoToCopy = "https://github.com/kerski/pbi-dataops-template.git"
$SampleModelURL = "https://github.com/kerski/pbi-dataops-template/blob/part14/Pbi/SampleModel/SampleModel.pbix?raw=true"
$SampleModelCDURL = "https://github.com/kerski/pbi-dataops-template/blob/part14/SetupScripts/Pbi/SchemaExample.pbix?raw=true"
$SampleModelCD2URL = "https://github.com/kerski/pbi-dataops-template/blob/part14/SetupScripts/Pbi/SchemaExamplePlusNewColumn.pbix?raw=true"
$SPListTemplate = "https://raw.githubusercontent.com/kerski/pbi-dataops-template/part10/SetupScripts/PremiumPerUser/LowCodeCoverage.xml"
#Download URL for Tabular Editor:
$TabularEditorUrl = "https://github.com/otykier/TabularEditor/releases/download/2.16.1/TabularEditor.Portable.zip"

$PipelineName = "DataOpsCD-Part14"

#Check Inputs
if(!$BuildWSName -or !$DevWSName -or !$StagingWSName -or !$ProdWSName -or `
   !$SvcUser -or !$SvcPwd -or !$ProjectName)
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
Connect-PowerBIServiceAccount

Write-Host -ForegroundColor Cyan "Step 1 or 5: Creating Power BI Workspaces" 

#Get Premium Per User Capacity as it will be used to assign to new workspace
$Cap = Get-PowerBICapacity -Scope Individual

if(!$Cap.DisplayName -like "Premium Per User*")
{
    Write-Error "Script expects Premium Per Use Capacity."
    return
}

#Create Build Workspace
$BuildWSObj = Add-PBIWorkspaceWithPPU -WorkspaceName $BuildWSName `
                           -WorkspaceDesc $BuildDesc `
                           -CapacityId $Cap.Id.Guid `
                           -SvcUser $SvcUser

Write-Host "Build Workspace ID: $($BuildWSObj.Id.Guid)"

#Create Development Workspace
$DevWSObj = Add-PBIWorkspaceWithPPU -WorkspaceName $DevWSName `
                           -WorkspaceDesc $DevDesc `
                           -CapacityId $Cap.Id.Guid `
                           -SvcUser $SvcUser                           

Write-Host "Development Workspace ID: $($DevWSObj.Id.Guid)"

#Create Staging Workspace
$StagingWSObj = Add-PBIWorkspaceWithPPU -WorkspaceName $StagingWSName `
                                            -WorkspaceDesc $StagingDesc `
                                            -CapacityId $Cap.Id.Guid `
                                            -SvcUser $SvcUser                           
                                            
Write-Host "Staging Workspace ID: $($StagingWSObj.Id.Guid)"
#Create Production Workspace
$ProdWSObj = Add-PBIWorkspaceWithPPU  -WorkspaceName $ProdWSName `
                                            -WorkspaceDesc $ProdDesc `
                                            -Capacity $Cap.Id.Guid `
                                            -SvcUser $SvcUser                           

Write-Host "Production Workspace ID: $($ProdWSObj.Id.Guid)"


### Now Setup Azure DevOps
$LogInfo = az login | ConvertFrom-Json

Write-Host -ForegroundColor Cyan "Step 2 of 5: Creating Azure DevOps project"
#Assumes organization name matches $LogInfo.name and url for Azure DevOps Service is https://dev.azure.com
$ProjectResult = az devops project create `
                --name $ProjectName `
                --description "Part 14 example of Bringing DataOps to Power BI" `
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
                --description "Part 14 example pipeline of Bringing DataOps to Power BI" `
                --org "$($AzDOHostURL)$($LogInfo.name)" `
                --project $ProjectName `
                --repository $ProjectName `
                --branch "main" `
                --yaml-path "DataOps-CD.yml" --skip-first-run --only-show-errors | ConvertFrom-Json

#Check Result
if(!$PipelineResult) {
    Write-Error "Unable to setup Pipeline"
    return
}

Write-Host -ForegroundColor Cyan "Step 4 of 5: Creating Pipeline in Azure DevOps project"
# Variable 'PBI_API_URL' was defined in the Variables tab
# Assumes commericial environment
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "PBI_API_URL" `
                        -VariableValue $PBIAPIURL `
                        -IsSecret $FALSE

# Variable 'TENANT_ID' was defined in the Variables tab
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "TENANT_ID" `
                        -VariableValue $LogInfo.tenantId `
                        -IsSecret $FALSE

# Variable 'PPU_USERNAME' was defined in the Variables tab
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "PPU_USERNAME" `
                        -VariableValue $SvcUser `
                        -IsSecret $FALSE

# Variable 'PPU_PASSWORD' was defined in the Variables tab
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "PPU_PASSWORD" `
                        -VariableValue $SvcPwd `
                        -IsSecret $TRUE

# Variable 'PBI_BUILD_GROUP_ID' was defined in the Variables tab
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "PBI_BUILD_GROUP_ID" `
                        -VariableValue $BuildWSObj.Id.Guid `
                        -IsSecret $FALSE

# Variable 'PBI_DEV_GROUP_ID' was defined in the Variables tab
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "PBI_DEV_GROUP_ID" `
                        -VariableValue $DevWSObj.Id.Guid `
                        -IsSecret $FALSE

# Variable 'PBI_STAGING_GROUP_ID' was defined in the Variables tab
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "PBI_STAGING_GROUP_ID" `
                        -VariableValue $StagingWSObj.Id.Guid `
                        -IsSecret $FALSE

# Variable 'PBI_PROD_GROUP_ID' was defined in the Variables tab
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "PBI_PROD_GROUP_ID" `
                        -VariableValue $ProdWSObj.Id.Guid `
                        -IsSecret $FALSE

# Variable 'TAB_EDITOR_URL' was defined in the Variables tab
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "TAB_EDITOR_URL" `
                        -VariableValue $TabularEditorUrl `
                        -IsSecret $FALSE

# Variable 'SP_URL' was defined in the Variables tab
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "SP_URL" `
                        -VariableValue "$($SPBaseUrl)/sites/$($SPSiteName)" `
                        -IsSecret $FALSE

# Variable 'SP_LIST_TITLE' was defined in the Variables tab
Add-AzureDevOpsVariable -AzDOHostURL $AzDOHostURL `
                        -OrgName $LogInfo.name `
                        -PipelineName $PipelineName `
                        -ProjectName $ProjectName `
                        -VariableName "SP_LIST_TITLE" `
                        -VariableValue "Low-Code Coverage" `
                        -IsSecret $FALSE

Write-Host -ForegroundColor Cyan "Step 5 of 5: Uploading SchemaExample.pbix to Staging and Production Workspaces"
#Upload Report
Invoke-WebRequest -Uri $SampleModelCDURL -OutFile ".\SchemaExample.pbix"
Invoke-WebRequest -Uri $SampleModelCD2URL -OutFile ".\SchemaExamplePlusNewColumn.pbix"

#Upload Schema Examples to resepective workspaces
New-PowerBIReport `
   -Path "$(Get-Location)\SchemaExample.pbix" `
   -Name "SchemaExample" `
   -WorkspaceId $StagingWSObj.Id.Guid `
   -ConflictAction CreateOrOverwrite

New-PowerBIReport `
   -Path "$(Get-Location)\SchemaExamplePlusNewColumn.pbix" `
   -Name "SchemaExample" `
   -WorkspaceId $ProdWSObj.Id.Guid `
   -ConflictAction CreateOrOverwrite

Write-Host -ForegroundColor Green "Azure DevOps Project $($ProjectName) created with pipeline $($PipelineName) at $($AzDOHostURL)$($LogInfo.name)"

#Clean up
<#
az devops project delete --id $ProjectInfo.id --organization "https://dev.azure.com/$($LogInfo.name)" --yes
Invoke-PowerBIRestMethod -Url "groups/$($DevWSObj.Id.Guid)" -Method Delete 
Invoke-PowerBIRestMethod -Url "groups/$($BuildWSObj.Id.Guid)" -Method Delete
Invoke-PowerBIRestMethod -Url "groups/$($StagingWSObj.Id.Guid)" -Method Delete
Invoke-PowerBIRestMethod -Url "groups/$($ProdWSObj.Id.Guid)" -Method Delete
#>
