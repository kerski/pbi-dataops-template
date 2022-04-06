<#
    Author: John Kerski
    Description: This script:
        1) Creates a Test SharePoint site with lists and loads data into those lists.    
        2) Creates a workspace and uploads the Power BI reports to the new workspace.
        
    Dependencies: 
        1) You have the rights to create Power BI workspaces and SharePoint sites. 
#>
#Setup TLS1.2
$TLS12Protocol = [System.Net.SecurityProtocolType] 'Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $TLS12Protocol

#Set Variables
<#$TestWSName = Read-Host "Please enter the name of the test workspace (ex. RefreshTest)"
$TestWSDesc = "Workspace to test SharePoint refreshes"
$SPBaseUrl = Read-Host "Please enter the base url of the SharePoint site (ex. https://x.sharepoint.com)"
$SPSiteName = Read-Host "Please enter the name of the SharePoint site to setup refresh test"#>

$TestWSName = "Refresh4_6"
$SPBaseUrl = "https://kerski.sharepoint.com"
$SPSiteName = "Refresh4_6"

#Set Variables
$ListName8 = '8ColumnBigList'
$ListName16 = '16ColumnBigList'
$SampleData = 'SampleData.csv'

#Download Variable URLs
$BasePBIDownloadUrl = "https://github.com/kerski/pbi-dataops-template/blob/part17/SetupScripts/Pbi/Part17/{PBIX_NAME}.pbix?raw=true"
$PbixFiles = @("Bespoke_8_Columns",
               "Bespoke_16_Columns",
               "Bespoke_Multi_Sources",
               "OData_8_Columns",
               "OData_16_Columns",
               "OData_Multi_Sources",
               "SP_Connector_V1_8_Columns",
               "SP_Connector_V1_16_Columns",
               "SP_Connector_V1_Multi_Sources"
               "SP_Connector_V2_8_Columns",
               "SP_Connector_V2_16_Columns",
               "SP_Connector_V2_Multi_Sources"               
               )
$PbixFileIds = @()
$SPListTemplate8 = "https://raw.githubusercontent.com/kerski/pbi-dataops-template/part17/SetupScripts/Pbi/Part17/8ColumnBigList.xml?raw=true"
$SPListTemplate16 = "https://raw.githubusercontent.com/kerski/pbi-dataops-template/part17/SetupScripts/Pbi/Part17/16ColumnBigList.xml?raw=true"
$SPCSVData = "https://raw.githubusercontent.com/kerski/pbi-dataops-template/part17/SetupScripts/Pbi/Part17/SampleData.csv?raw=true"

#Check Inputs
if(!$TestWSName -or !$SPBaseUrl -or !$SPSiteName)
{
    Write-Error "Please make sure you entered all the required information. You will need to rerun the script."
    return
} 

#Install Powershell Module if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host -ForegroundColor Cyan "MicrosoftPowerBIMgmt installed moving forward..."
} else {
    #Install Power BI Module
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
}

#Install Powershell Module if Needed
if (Get-Module -ListAvailable -Name "PnP.PowerShell") {
    Write-Host -ForegroundColor Cyan "PnP.PowerShell already installed, moving forward..."
} else {
    Install-Module -Name PnP.PowerShell -Scope CurrentUser -AllowClobber -Force
}

#Create SharePoint site and lists
Write-Host -ForegroundColor Cyan "Step 1 or 2: Creating SharePoint site and lists" 

#Create PnP Site
Connect-PnPOnline -Url $SPBaseUrl -Interactive
New-PnPSite -Type TeamSiteWithoutMicrosoft365Group -Title $SPSiteName -Url "$($SPBaseUrl)/sites/$($SPSiteName)"
Disconnect-PnPOnline

#Connect to new SharePoint Online site
Connect-PnPOnline -Url "$($SPBaseUrl)/sites/$($SPSiteName)" -Interactive

#Retrieve templates and CSVs
Invoke-WebRequest -Uri $SPListTemplate8 -OutFile ".\8ColumnBigList.xml"
Invoke-WebRequest -Uri $SPListTemplate16 -OutFile ".\16ColumnBigList.xml"
Invoke-WebRequest -Uri $SPCSVData -OutFile ".\SampleData.csv"

#Delete List
Remove-PnPList -Identity $ListName8 -Force
Remove-PnPList -Identity $ListName16 -Force

#Create List
Invoke-PnPSiteTemplate -Path "$($ListName8).xml"
Invoke-PnPSiteTemplate -Path "$($ListName16).xml"

#Get list information
$ListObj_8 = Get-PnPList -Identity $ListName8
$ListObj_16 = Get-PnPList -Identity $ListName16
    
$CSVData = Import-CsV -Path $SampleData

#Load New to 8 Column and 16 Column List
$Batch8 = New-PnPBatch
$Batch16 = New-PnPBatch

Write-Host -ForegroundColor Cyan "Loading Data into SharePoint lists. THIS WILL TAKE A WHILE"
#Iterate in 100 row counts
For($I = 0; $I -lt $CSVData.Count; $I += 200)
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
Write-Host -ForegroundColor Cyan "Loaded Data to SharePoint lists."

#Login into Power BI to Create Workspaces
Connect-PowerBIServiceAccount

Write-Host -ForegroundColor Cyan "Step 2 or 2: Creating Power BI Workspace" 

#Create Test Workspace
New-PowerBIWorkspace -Name $TestWSName

#Find Workspace and make sure it wasn't deleted (if it's old or you ran this script in the past)
$TestWSObj = Get-PowerBIWorkspace -Scope Organization -Filter "name eq '$($TestWSName)' and state ne 'Deleted'"

if($TestWSObj.Length -eq 0)
{
    Throw "$($TestWSName) workspace was not created."
}

#Update properties
Set-PowerBIWorkspace -Description $TestWSDesc -Scope Organization -Id $($TestWSObj.Id.Guid)

#Upload Reports
$PbixFileIds = @()
Foreach($File in $PbixFiles)
{
    #Build download URL
    $DlFile = $BasePBIDownloadUrl.Replace("{PBIX_NAME}",$File)

    #Download file
    Invoke-WebRequest -Uri $Dlfile -OutFile ".\$($File).pbix"

    Write-Host -ForegroundColor Cyan "Publishing $($File).pbix..."

    #Upload example to respective workspace
    $NewRpt = New-PowerBIReport `
       -Path "$(Get-Location)\$($File).pbix" `
       -Name $File `
       -WorkspaceId $TestWSObj.Id.Guid `
       -ConflictAction CreateOrOverwrite
    
    $Temp = Get-PowerBIReport -Id $NewRpt.Id -WorkspaceId $TestWSObj.Id.Guid

    #Add ids to array
    $PbixFileIds += $Temp

    Write-Host -ForegroundColor Cyan "Published $($File).pbix. ID: $($Temp.DatasetId.toString())"
}

#Setup Parameters for updating
$SharePointURLParams = '{
  "updateDetails": [
    {
        "name": "{NAME}",
        "newValue": "{NEW_VALUE}"
      }
  ]}'
$SharePointURLParams_Two = '{
    "updateDetails": [
      {
          "name": "{NAME}",
          "newValue": "{NEW_VALUE}"
      },
      {
        "name": "{NAME2}",
        "newValue": "{NEW_VALUE2}"
      }
    ]
  }'

$SharePointURLParams_Three = '{
    "updateDetails": [
      {
          "name": "{NAME}",
          "newValue": "{NEW_VALUE}"
      },
      {
        "name": "{NAME2}",
        "newValue": "{NEW_VALUE2}"
      },
      {
        "name": "{NAME3}",
        "newValue": "{NEW_VALUE3}"
      }
    ]
  }'

#Iterate and update parameters
Foreach($File in $PbixFiles)
{
    $Body = ""
    switch($File)
    {
        "OData_8_Columns" {$Body = $SharePointURLParams.Replace('{NAME}','QueryURL').Replace('{NEW_VALUE}',"$($SPBaseUrl)/sites/$($SPSiteName)/_api/web/lists/GetByTitle('8ColumnBigList')/items?$select=Author/Name,Author/Title,Id,field_2,field_4,field_6&$expand=Author/Id&$top=5000")}
        "OData_16_Columns" {$Body = $SharePointURLParams.Replace('{NAME}','QueryURL').Replace('{NEW_VALUE}',"$($SPBaseUrl)/sites/$($SPSiteName)/_api/web/lists/GetByTitle('16ColumnBigList')/items?$select=Author/Name,Author/Title,Id,field_2,field_4,field_6&$expand=Author/Id&$top=5000")}
        "OData_Multi_Sources" {
                                $Body = $SharePointURLParams_Two.Replace('{NAME}','QueryURL_8_Columns').Replace('{NEW_VALUE}',"$($SPBaseUrl)/sites/$($SPSiteName)/_api/web/lists/GetByTitle('8ColumnBigList')/items?$select=Author/Name,Author/Title,Id,field_2,field_4,field_6&$expand=Author/Id&$top=5000")
                                $Body = $Body.Replace('{NAME2}','QueryURL_16_Columns').Replace('{NEW_VALUE2}',"$($SPBaseUrl)/sites/$($SPSiteName)/_api/web/lists/GetByTitle('16ColumnBigList')/items?$select=Author/Name,Author/Title,Id,field_2,field_4,field_6&$expand=Author/Id&$top=5000")}
        "Bespoke_8_Columns" {$Body = $SharePointURLParams.Replace('{NAME}','SharePointURL').Replace('{NEW_VALUE}',"$($SPBaseUrl)/sites/$($SPSiteName)")}
        "Bespoke_16_Columns" {$Body = $SharePointURLParams.Replace('{NAME}','SharePointURL').Replace('{NEW_VALUE}',"$($SPBaseUrl)/sites/$($SPSiteName)")}
        "Bespoke_Multi_Sources" {$Body = $SharePointURLParams.Replace('{NAME}','SharePointURL').Replace('{NEW_VALUE}',"$($SPBaseUrl)/sites/$($SPSiteName)")}
        "SP_Connector_V1_8_Columns" {
                                 $Body = $SharePointURLParams_Two.Replace('{NAME2}','SharePointSiteURL').Replace('{NEW_VALUE2}',"$($SPBaseUrl)/sites/$($SPSiteName)")
                                 $Body = $Body.Replace('{NAME}','ListID').Replace('{NEW_VALUE}',$ListObj_8.Id.toString())}
        "SP_Connector_V1_16_Columns" {
                                $Body = $SharePointURLParams_Two.Replace('{NAME}','SharePointSiteURL').Replace('{NEW_VALUE}',"$($SPBaseUrl)/sites/$($SPSiteName)")
                                $Body = $Body.Replace('{NAME2}','ListID').Replace('{NEW_VALUE2}',$ListObj_16.Id.toString())}
        "SP_Connector_V1_Multi_Sources" {
                                    $Body = $SharePointURLParams_Three.Replace('{NAME}','SharePointSiteURL').Replace('{NEW_VALUE}',"$($SPBaseUrl)/sites/$($SPSiteName)")
                                    $Body = $Body.Replace('{NAME2}','ListID_16_Columns').Replace('{NEW_VALUE2}',$ListObj_16.Id.toString())
                                    $Body = $Body.Replace('{NAME3}','ListID_8_Columns').Replace('{NEW_VALUE3}',$ListObj_8.Id.toString())}
        "SP_Connector_V2_8_Columns" {
                                        $Body = $SharePointURLParams_Two.Replace('{NAME2}','SharePointSiteURL').Replace('{NEW_VALUE2}',"$($SPBaseUrl)/sites/$($SPSiteName)")
                                        $Body = $Body.Replace('{NAME}','ListID').Replace('{NEW_VALUE}',$ListObj_8.Id.toString())}
        "SP_Connector_V2_16_Columns" {
                                        $Body = $SharePointURLParams_Two.Replace('{NAME}','SharePointSiteURL').Replace('{NEW_VALUE}',"$($SPBaseUrl)/sites/$($SPSiteName)")
                                        $Body = $Body.Replace('{NAME2}','ListID').Replace('{NEW_VALUE2}',$ListObj_16.Id.toString())}
        "SP_Connector_V2_Multi_Sources" {
                                           $Body = $SharePointURLParams_Three.Replace('{NAME}','SharePointSiteURL').Replace('{NEW_VALUE}',"$($SPBaseUrl)/sites/$($SPSiteName)")
                                           $Body = $Body.Replace('{NAME2}','ListID_16_Columns').Replace('{NEW_VALUE2}',$ListObj_16.Id.toString())
                                           $Body = $Body.Replace('{NAME3}','ListID_8_Columns').Replace('{NEW_VALUE3}',$ListObj_8.Id.toString())}
       
        }#end switch

    #Get Dataset Info
    $DatasetInfo = $PbixFileIds | Where-Object {$_.Name -eq $File}

    # Update Parameters URL
    Write-Host -ForegroundColor Cyan "Updating Parameters for $($File); DatasetId: $($DatasetInfo.DatasetId)"
    $UrlUpdateParams = "groups/$($TestWSObj.Id.Guid)/datasets/$($DatasetInfo.DatasetId)/Default.UpdateParameters"
    $content = 'application/json'
    
    #Update Paramters
    Invoke-PowerBIRestMethod -Url $UrlUpdateParams `
                             -Method Post `
                             -Body $Body `
                             -Verbose
}#end foreach

Write-Host -ForegroundColor Green "Successfully setup Power BI workspace and SharePoint site.  Please continue to follow the directions on Github."

    #Invoke-PowerBIRestMethod -Url "groups/$($TestWSObj.Id.Guid)" -Method Delete
    #sharepoint online delete site collection powershell
    #Remove-PnPTenantSite -Url "$($SPBaseUrl)/sites/$($SPSiteName)" -Force
