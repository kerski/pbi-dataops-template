<#
    Author: John Kerski
    Description: This script:
        1) Creates a test SharePoint site with lists and loads data into those lists.
        2) Creates a workspace and uploads the Power BI reports to the new workspace.

    Dependencies: 
        1) You have the rights to create Power BI workspaces and SharePoint sites. 
#>


#Set Variables
$TestWSName = Read-Host "Please enter the name of the test workspace (ex. RefreshTest)"
$TestWSDec = "Workspace to test SharePoint refreshes"
$SPBaseUrl = Read-Host "Please enter the base url of the SharePoint site (ex. https://x.sharepoint.com)"
$SPSiteName = Read-Host "Please enter the name of the SharePoint site to store low-code coverage data"

$BasePBIDownloadUrl = "https://github.com/kerski/pbi-dataops-template/blob/part17/SetupScripts/Pbi/Part17/{PBIX_NAME}.pbix?raw=true"
$PbixFiles = @("Bespoke_8_Columns","Bespoke_16_Columns")
$SPListTemplate = "https://raw.githubusercontent.com/kerski/pbi-dataops-template/part10/SetupScripts/PremiumPerUser/LowCodeCoverage.xml"

#Check Inputs
if(!$TestWSName -or !$SPBaseUrl -or !$SPSiteName)
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

#Install Powershell Module if Needed
if (Get-Module -ListAvailable -Name "PnP.PowerShell") {
    Write-Host "PnP.PowerShell already installed"
} else {
    Install-Module -Name PnP.PowerShell -Scope CurrentUser -AllowClobber -Force
}

#Upload Report
Invoke-WebRequest -Uri $SampleModelCDURL -OutFile ".\SchemaExample.pbix"
Invoke-WebRequest -Uri $SampleModelCD2URL -OutFile ".\SchemaExample.pbix"

#Upload Schema Examples to resepective workspaces
New-PowerBIReport `
   -Path "$(Get-Location)\SchemaExample.pbix" `
   -Name "SchemaExample" `
   -WorkspaceId $StagingWSObj.Id.Guid `
   -ConflictAction CreateOrOverwrite


#Login into Power BI to Create Workspaces
Connect-PowerBIServiceAccount

Write-Host -ForegroundColor Cyan "Step 1 or 2: Creating Power BI Workspace" 

#Get Premium Per User Capacity as it will be used to assign to new workspace
$Cap = Get-PowerBICapacity -Scope Individual

if(!$Cap.DisplayName -like "Premium Per User*")
{
    Write-Error "Script expects Premium Per Use Capacity."
    return
}

#Create Test Workspace
$Result = New-PowerBIWorkspace -Name $TestWSName

#Find Workspace and make sure it wasn't deleted (if it's old or you ran this script in the past)
$TestWSObj = Get-PowerBIWorkspace -Scope Organization -Filter "name eq '$($WorkspaceName)' and state ne 'Deleted'"

if($TestWSObj.Length -eq 0)
{
Throw "$($WorkspaceName) workspace was not created."
}

#Update properties
$Result = Set-PowerBIWorkspace -Description $WorkspaceDesc -Scope Organization -Id $($TestWSObj.Id.Guid)
$Result = Set-PowerBIWorkspace -CapacityId $CapacityId -Scope Organization -Id $($TestWSObj.Id.Guid) 


#Upload Reports
Foreach($File in $PbixFiles)
{
    Invoke-WebRequest -Uri $SampleModelCDURL -OutFile ".\SchemaExample.pbix"

    $DlFile = $BasePBIDownloadUrl.Replace("{PBIX_NAME}",$File)

    Write-Host -ForegroundColor Cyan "Uploading $($DlFile)..."

    #Upload Schema Examples to resepective workspaces
New-PowerBIReport `
   -Path "$(Get-Location)\SchemaExample.pbix" `
   -Name "SchemaExample" `
   -WorkspaceId $StagingWSObj.Id.Guid `
   -ConflictAction CreateOrOverwrite

}

#Create SharePoint site and lists
Write-Host -ForegroundColor Cyan "Step 2 or 2: Creating SharePoint site" 

#Create PnP Site
Connect-PnPOnline -Url $SPBaseUrl -Interactive
New-PnPSite -Type TeamSiteWithoutMicrosoft365Group -Title $SPSiteName -Url "$($SPBaseUrl)/sites/$($SPSiteName)"
Disconnect-PnPOnline

#Connect to new SharePoint Online site
Connect-PnPOnline -Url "$($SPBaseUrl)/sites/$($SPSiteName)" -Interactive

#Retrieve local template
Invoke-WebRequest -Uri $SPListTemplate -OutFile "./LowCodeCoverageTemplate.xml"
$TemplateFile = "./LowCodeCoverageTemplate.xml"

#Create list based on template
Invoke-PnPSiteTemplate -Path $TemplateFile

$ConSite=Connect-PnPOnline -Url 'https://kerski.sharepoint.com/sites/please' -Interactive

#Set Variables
$ListName8 = '8ColumnBigList'
$ListName16 = '16ColumnBigList'
$SampleData = 'SampleData.csv'
#Delete List
Remove-PnPList -Identity $ListName8 -Force
Remove-PnPList -Identity $ListName16 -Force

Invoke-PnPSiteTemplate -Path "$($ListName8).xml"
Invoke-PnPSiteTemplate -Path "$($ListName16).xml"

$ListObj_8 = Get-PnPList -Identity $ListName8
$ListObj_16 = Get-PnPList -Identity $ListName16
    
$CSVData = Import-CsV -Path $SampleData

#Load New to 8 Column and 16 Column List
$Batch8 = New-PnPBatch
$Batch16 = New-PnPBatch

Write-Host "Loading Data into SharePoint lists."
#Iterate in 100 row counts
For($I = 0; $I -lt $CSVData.Count-19000; $I += 200)
{
    #Create array to load into list
    $Subset = @()
    if(($CSVData.Count - $I) -gt 199)
    {
        $Subset = $CSVData[$I..($I + 199)]
    }
    else {
        $Subset = $CSVData[$I..($CSVData.Count - 1)]   
    }

    #Load Data
    ForEach ($Row in $Subset)
    { 
         #Add List Items - Map with Internal Names of the Fields
         Add-PnPListItem -List $ListName8 -Batch $Batch8 -Values @{"Title" = $($Row.'firstname');
                                                   "field_0" = $($Row.'id');
                                                   "field_2" = $($Row.'lastname');
                                                   "field_3" = $($Row.'gender');
                                                   "field_4" = $($Row.'ipaddress');
                                                   "field_5" = $($Row.'when');
                                                   "field_6" = $($Row.'sentence');
                                                   "field_7" = $($Row.'bool');
                                                  };
        Add-PnPListItem -List $ListName16 -Batch $Batch16 -Values @{"Title" = $($Row.'firstname');
                                               "field_0" = $($Row.'id');
                                               "field_2" = $($Row.'lastname');
                                               "field_3" = $($Row.'gender');
                                               "field_4" = $($Row.'ipaddress');
                                               "field_5" = $($Row.'when');
                                               "field_6" = $($Row.'sentence');
                                               "field_7" = $($Row.'bool');
                                               "field_8" = $($Row.'extra column');
                                               "field_9" = $($Row.'extra column 2');
                                               "field_10" = $($Row.'extra column 3');
                                               "field_11" = $($Row.'extra column 4');
                                               "field_12" = $($Row.'extra column 5');
                                               "field_13" = $($Row.'extra column 6');
                                               "field_14" = $($Row.'extra column 7');
                                               "field_15" = $($Row.'extra column 8');
                                              };

    }
    #Load in Batch
    Invoke-PnPBatch -Batch $Batch8
    Invoke-PnPBatch -Batch $Batch16
    
    Write-Host "Loaded $($I+200) of $($CSVData.Count) items."

}#end for
Write-Host "Loaded Data to SharePoint lists."