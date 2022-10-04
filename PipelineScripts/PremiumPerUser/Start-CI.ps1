<#
    Author: John Kerski
    Description: This script runs the proof-of-concept Continuous Integration of Power BI files into a Development workspace.

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName has admin right to workspace.
#>
#Setup TLS 12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#Get Working Directory
$WorkingDir = (& pwd) -replace "\\", '/'
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Publish-PBIFileWithPPU.psm1 -Force
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Invoke-RefreshDatasetSyncWithPPU.psm1 -Force
Import-Module $WorkingDir/Pbi/TestingScripts/Pester/4.10.1/Pester.psm1 -Force
#Set Default Environment Variables 
$Opts = @{
    TenantId = "${env:TENANT_ID}";
    PbiApiUrl = "${env:PBI_API_URL}"
    BuildGroupId = "${env:PBI_BUILD_GROUP_ID}"
    DevGroupId = "${env:PBI_DEV_GROUP_ID}"
    UserName = "${env:PPU_USERNAME}";
    Password = "${env:PPU_PASSWORD}";
    #Get new pbix changes
    PbixChanges = git diff --name-only --relative --diff-filter AMR HEAD^ HEAD '**/*.pbix';
    PbixTracking = @();
    BuildVersion = "${env:BUILD_SOURCEVERSION}";
}
#Check for missing variables required for pipeline to work
if(-not $Opts.TenantId){
    throw "Missing or Blank Tenant ID"
}
if(-not $Opts.PbiApiUrl){
    throw "Missing or Blank Power BI Api URL"
}

if(-not $Opts.BuildGroupId){
    throw "Missing or Blank Build Group Id"
}

if(-not $Opts.DevGroupId){
    throw "Missing or Blank Dev Group Id"
}

if(-not $Opts.UserName){
    throw "Missing or Blank UserName"
}

if(-not $Opts.Password){
    throw "Missing or Blank Password"
}

#Iterate of Power BI Changes and get the test files
if($Opts.PbixChanges)
{
foreach ($File in $Opts.PbixChanges) {
        #If file exists and not deleted
        if($File)
        {
            #Get parent folder of this file
            $ParentFolder = Split-Path -Path $File
            #Add testing to object array
            $Temp = @([pscustomobject]@{PBIPath=$File;TestFolderPath=$ParentFolder;BuildInfo=$null;RefreshResult=$null})
            $Opts.PbixTracking += $Temp
        }#end if
}#end for-each
}
else
{
Write-Warning "Found no PBI files that have changed."
}#end if

#Install Powershell Module if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "MicrosoftPowerBIMgmt already installed"
} else {
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
}


#Iterate through Test Cases and Promote to Build Environment
$Iter = 0
foreach ($PBIPromote in $Opts.PbixTracking){
    Write-Host "File to Promote to Build Workspace: $($PBIPromote.PBIPath)"

    #Publish PBI file
    $Temp = Publish-PBIFIleWithPPU -WorkspaceId $Opts.BuildGroupId `
                     -LocalDatasetPath $PBIPromote.PBIPath `
                     -UserName $Opts.UserName `
                     -Password $Opts.Password `
                     -TenantId $Opts.TenantId `
                     -APIUrl $Opts.PbiApiUrl
   
    $Opts.PbixTracking[$Iter].BuildInfo = $Temp

    $Opts.PbixTracking[$Iter].BuildInfo
    $Iter = $Iter + 1
}#end foreach

#Now Test Refreshes
$Iter = 0
foreach($PBIPromote in $Opts.PbixTracking){
    Write-Host "Checking if file needs refreshing: $($PBIPromote.PBIPath)"

    #If DatasetId property is not null then this is a PowerBI report with a dataset needing a refresh
    if($PBIPromote.BuildInfo.DatasetId -ne $null){
        $RefreshResult = Invoke-RefreshDatasetSyncWithPPU -WorkspaceId $Opts.BuildGroupId `
                        -DatasetId $PBIPromote.BuildInfo.DatasetId `
                        -UserName $Opts.UserName `
                        -Password $Opts.Password `
                        -TenantId $Opts.TenantId `
                        -APIUrl $Opts.PbiApiUrl
    
        Write-Host $RefreshResult " refresh result"

        #If Failed to Refresh stop script
        if($RefreshResult -ne "Completed")
        {
            Write-Host "##vso[task.logissue type=error]Failed to Refresh: $($PBIPromote.PBIPath)"
            exit 1
        }
        else{       
            Write-Host "Successfully refreshed: $($PBIPromote.PBIPath)"
        }
    }#end if Power BI Report can be refreshed
    
    $Iter = $Iter + 1
}#end foreach

# Reset Failure Count
$FailureCount = 0

# Run Tests
Invoke-Gherkin -Strict -OutputFile results.xml -OutputFormat NUnitXml -ErrorVariable $ErrorCount

# Retrieve Errors
#Load into XML
[System.Xml.XmlDocument]$TempResult = Get-Content "$($WorkingDir)/results.xml"
$TempFailureCount = [int]$TempResult.'test-results'.failures
$FailureCount = $TempFailureCount + 0

Write-Host "Failed Test Cases: $($FailureCount)"

#If FailureCount is greater than 1
if($FailureCount -gt 0)
{
    Write-Host "##vso[task.logissue type=error]($FailureCount) failed test(s). Please resolve."
}
else #Promote to Development
{
    $Iter = 0
    #Find all files in working directory to promote
    $PBIsToTest = Get-ChildItem -Path "./pbi" -Recurse | Where-Object {$_ -like "*.pbix"}
    # Now promote
    foreach($PBIToDev in $PBIsToTest){
        #Get parent folder of this file
        $ParentFolder = Split-Path -Path $PBIToDev.FullName

        Write-Host "File to Promote to Development Workspace: $($PBIToDev.FullName)"

        #Publish PBI file
        $Temp = Publish-PBIFIleWithPPU -WorkspaceId $Opts.DevGroupId `
                         -LocalDatasetPath $PBIToDev.FullName `
                         -UserName $Opts.UserName `
                         -Password $Opts.Password `
                         -TenantId $Opts.TenantId `
                         -APIUrl $Opts.PbiApiUrl
        $Iter = $Iter + 1
    }#end foreach
}#end promot to development

return