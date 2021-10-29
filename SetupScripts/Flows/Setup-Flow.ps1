<#
    Author: John Kerski
    Description: This script:
        1) Checks for dependencies (Azure CLI, Python)
        2) Creates Service Principal in Azure
        3) Adds Custom Connector to Power Automate

    Dependencies: 
    1) Azure CLI installed
    2) Python > 3.5
    3) Script should be run by an administrator with ability to grant admin to api endpoints.
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
Write-Host -ForegroundColor Cyan "Step 1 of 3:  Check for install dependencies."

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

#Create Service Principal
Write-Host -ForegroundColor Cyan "Step 2 of 3:  Creating App Service Principal for Custom Connector."
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
Write-Host -ForegroundColor Cyan "Step 3 of 3:  Installing Custom Connector"
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

#Create Custom Connector
#Note #https://github.com/microsoft/PowerPlatformConnectors/issues/1113 apiProperties.json 
#has a lower-case 'a' oauthsettings as temporary workaround.
paconn create -s "settings.json" -r $CredentialResult.password

#Verify environment and settings file is set correctly.
$SettingsFile = Get-Content settings.json | ConvertFrom-Json

if(-not $SettingsFile.connectorId)
{
    Write-Error "Creation of Custom Connector did not result in the settings.json file being update.  Please check for errors in console."
    return
}

Write-Host -ForegroundColor Green "Custom Connector Installed."

#Cleanup
#az ad app delete --id $AppClientId