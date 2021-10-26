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
### NOTE: NAVIGATE TO Flows folder to file path works for paconn create
$CurLoc = Get-Location
if($CurLoc.Path -match "SetupScripts\\Flows$" -eq $FALSE)
{
    cd .\SetupScripts\Flows
}
### VARIABLES ###
#App Service Principal Variables
$AppPrincipalName = "DataOpsFlowApp"
$PowerBIAppId = "00000009-0000-0000-c000-000000000000"
$DatasetReadAll = "7f33e027-4039-419b-938e-2f8ca153e68e=Scope"
$ReportReadAll = "4ae1bf56-f562-4747-b7bc-2fa0874ed46f=Scope"

#Check Dependencies
Write-Host -ForegroundColor Cyan "Step 1 of X:  Check for install dependencies."

#Check Python Version
$PythonVersion = python --version

if(-not $PythonVersion){
    throw "Python is missing. Please install at least version 3.5 and ensure it has been added to the PATH environment variable."
}

#Check Azure CLI
$AZVersion = az --version

if(-not $AZVersion){
    throw "Azure CLI is missing. Please install and ensure it has been added to the PATH environment variable."
}

#Check for PowerShell Admin
if (Get-Module -ListAvailable -Name "Microsoft.PowerApps.Administration.PowerShell") {
    Write-Host "Microsoft.PowerApps.Administration.PowerShell already installed"
} else {
    Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -AllowClobber -Force
}

#In this code we use the default, but this should be updated if using Dev/Test/Prod environments
#Get Environment Information
$AdminInfo = Get-AdminPowerAppEnvironment

if(-not $AdminInfo){
    throw "Unable to get environment information for Power Platform. Please check your access."
}


#Create Service Principal
Write-Host -ForegroundColor Cyan "Step 1 of X:  Creating App Service Principal for Custom Connector."
#Login to Azure
az login

#Grab redirectUrl from API Properties file to update App Service Principal
$ApiProps = Get-Content apiProperties.json | ConvertFrom-Json
$RedirectUrl = $ApiProps.properties.connectionParameters.token.oAuthSettings.redirectUrl

#Creates App
$AppClientId = az ad app create --display-name $AppPrincipalName --query "appId" --reply-urls $RedirectUrl | ConvertFrom-Json

if(!$AppClientId) {
    Write-Error "Unable to register an app."
    return
}

#Create service principal for the app just created
#This makes sure it is in active directory
$Output = az ad sp create --id $AppClientId

if(!$Output) {
    Write-Error "Unable to register an app as service principal."
    return
}

$AppObjId = az ad sp show --id $AppClientId --query "objectId" | ConvertFrom-Json

if(!$AppObjId) {
    Write-Error "Unable to register an app as service principal."
    return
}

#Now Add Power BI Permissions

#Add Dataset.Read.All
az ad app permission add --id $AppClientId --api $PowerBIAppId --api-permissions $DatasetReadAll

#Add Report.Read.All
az ad app permission add --id $AppClientId --api $PowerBIAppId --api-permissions $ReportReadAll

#Grant Admin Consent (requires admin rights.  Otherwise you need an adminstrator to do this for you)
$PermissionOutput = az ad app permission grant --id $AppClientId --api $PowerBIAppId

if(!$PermissionOutput) {
    Write-Error "Unable to grant admin consent for application service principal."
    return
}

#Create Credential - Expires in 1 year
#$AppClientID = "00d6d64c-f9ae-4e60-b804-42abc3dc07e7"
$CredentialResult = az ad app credential reset --id $AppClientID | ConvertFrom-Json

#Check that the password was created
if(!$CredentialResult.password)
{
    Write-Error "Unable to create client secret for application service principal."
    return
}

#Please run as administrator is possible
#Install Power Platform CLI on Python
Write-Host -ForegroundColor Cyan "Step 3 of X:  Installing Custom Connector"
pip install paconn --upgrade

#Login to Azure, you will be prompted
Write-Host -ForegroundColor Cyan "Logging into Azure with Power Platform CLI, you may prompted to enter a device code."

#Use verbose to make sure you are prompted.
paconn login

#Create Custom Connector 

#Prior to Create Custom Connector - overwrite settings.json with base file to 
#avoid environment id or customer connecter id being present
Copy-Item settings-base.json -Destination settings.json

#Update Client id in API Properties
$ApiProps.properties.connectionParameters.token.oAuthSettings.clientId = $AppClientId
$UpdatedFile = $ApiProps | ConvertTo-Json -depth 100 
Set-Content -Path .\apiProperties.json -Value $UpdatedFile

#TODO REMOVE
#$Test1 = "Default-e704d214-b5b5-4799-af96-61fa2730c289"
#$Test2 = "Zr8EQB9uqhdGKnJK_7PAIyt3yz1XxHUykF"
#paconn create -e $Test1 -s "settings.json" --secret $Test2 --debug

#Create Custom Connector
paconn create -e $AdminInfo[0].EnvironmentName -s "settings.json" --secret $CredentialResult.password

#Verify environment and settings file is set correctly.
$SettingsFile = Get-Content settings.json | ConvertFrom-Json

if(-not $SettingsFile.connectorId)
{
    Write-Error "Creation of Custom Connector did not result in the settings.json file being update.  Please check for errors in console."
    return
}

#Cleanup
#az ad app delete --id $AppClientId