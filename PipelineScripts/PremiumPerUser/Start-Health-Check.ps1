<#
    Author: John Kerski
    Description: 

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName 
    has admin right to workspace.
#>
#Setup TLS 12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#Get Working Directory
$WorkingDir = (& pwd) -replace "\\", '/'
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Get-DevOpsVariables.psm1 -Force
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Publish-PBIFIleWithPPU.psm1 -Force
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Refresh-DatasetSyncWithPPU.psm1 -Force
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Send-XMLAWithPPU.psm1 -Force
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Confirm-BestPracticesWithPPU.psm1 -Force

#Get Default Environment Variables 
$Opts = Get-DevOpsVariables
#Install PBI Powershell Module if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "MicrosoftPowerBIMgmt already installed"
} else {
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
}

#Iterate through files in Staging Environment
$PBIsToTest = Get-ChildItem -Path "./pbi" -Recurse | Where-Object {$_ -like "*.pbix"}
$Iter = 0
foreach ($PBICheck in $PBIsToTest){
    Write-Host "File to check in Staging Workspace: $($PBICheck)"

    #Set Client Secret as Secure String
    $Secret = $Opts.Password | ConvertTo-SecureString -AsPlainText -Force
    $Credentials = [System.Management.Automation.PSCredential]::new($Opts.UserName,$Secret)
    #Connect to Power BI
    Connect-PowerBIServiceAccount -Credential $Credentials

    # Get Dataset Id
    $ReportInfo = Get-PowerBIReport -WorkspaceId -Filter "name eq '$($PBICheck)'" -Scope Organization

    #If DatasetId property is null then this is a PowerBI report with a dataset needing a refresh
    if(!$ReportInfo.DatasetId -ne $null){ 
        <#$RefreshResult = Refresh-DatasetSyncWithPPU -WorkspaceId $Opts.StagingGroupId `
                        -DatasetId $PBIPromote.BuildInfo.DatasetId `
                        -UserName $Opts.UserName `
                        -Password $Opts.Password `
                        -TenantId $Opts.TenantId `
                        -APIUrl $Opts.PbiApiUrl
            
            #If Failed to Refresh stop script
            if($RefreshResult -ne "Completed")
            {
                Write-Host "##vso[task.logissue type=error]Failed to refresh: $($PBICheck)"
                exit 1
            }
            else
            {
                Write-Host "Successfully refreshed: $($PBICheck)"
            }
        #>
        #Run Tests
        #Get parent folder of this file
        $ParentFolder = Split-Path -Path $PBITest.FullName
        #Get dax files in this folder
        $DaxFilesInFolder = Get-ChildItem -Path $ParentFolder | Where-Object {$_ -like "*.*dax"}    
        Write-Host "Attempting to run tests for: $($PBITest)"
    }
    $Iter = $Iter + 1
}#end foreach

return