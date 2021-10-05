<#
    Author: John Kerski
    Description: This script runs the proof-of-concept Continuous Integration of Power BI files 
    into a Development workspace.

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
#Install SQL Powershell Module if Needed
if (Get-Module -ListAvailable -Name "SqlServer") {
    Write-Host "SqlServer module already installed"
} else {
    Install-Module -Name SqlServer
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

    #If DatasetId property is null then this is a PowerBI report with a dataset needing a refresh
    if(!$PBIPromote.BuildInfo.DatasetId -ne $null){ 
        $RefreshResult = Refresh-DatasetSyncWithPPU -WorkspaceId $Opts.BuildGroupId `
                        -DatasetId $PBIPromote.BuildInfo.DatasetId `
                        -UserName $Opts.UserName `
                        -Password $Opts.Password `
                        -TenantId $Opts.TenantId `
                        -APIUrl $Opts.PbiApiUrl
        
        #If Failed to Refresh stop script
        if($RefreshResult -ne "Completed")
        {
            Write-Host "##vso[task.logissue type=error]Failed to refresh: $($PBIPromote.PBIPath)"
            exit 1
        }
        else
        {
            Write-Host "Successfully refreshed: $($PBIPromote.PBIPath)"
        }
    }#end if Power BI Report can be refreshed

    $Iter = $Iter + 1
}#end foreach


#Run Tests regardless of changes

#Find all files in working directory
$PBIsToTest = Get-ChildItem -Path "./pbi" -Recurse | Where-Object {$_ -like "*.pbix"}

#Set Client Secret as Secure String
$Secret = $Opts.Password | ConvertTo-SecureString -AsPlainText -Force
$Credentials = [System.Management.Automation.PSCredential]::new($Opts.UserName,$Secret)
#Connect to Power BI
Connect-PowerBIServiceAccount -Credential $Credentials

#Get Workspace Information to make sure we get the right Workspacename for XMLA
$BuildWS = Get-PowerBIWorkspace -Id $Opts.BuildGroupId 

#Setup Failed Test Counts and Results Array
$FailureCount = 0
$TestResults = @()

$Iter = 0
foreach($PBITest in $PBIsToTest){
    #Get the Report Information
    $TempRpt = Get-PowerBIReport -WorkspaceId $Opts.BuildGroupId -Name $PBITest.BaseName
    $TempOptFile = "$($WorkingDir)/$($TempRpt.Name).xml"
    
    #Best Practices
    Write-Host "Attempting to run best practice analyzer for: $($PBITest)"
    
    #Run Analyze and will output errors and failed the build is best practices are not followed
    #NOTE: BPAUrl is hard code but you can and should change for your own needs/guidelines
    Confirm-BestPracticesWithPPU -WorkspaceName $BuildWS.Name `
                        -DatasetName $TempRpt.Name `
                        -UserName $Opts.UserName `
                        -Password $Opts.Password `
                        -TabularEditorUrl $Opts.TabularEditorUrl `
                        -APIUrl $Opts.PbiApiUrl `
                        -BPAUrl "https://raw.githubusercontent.com/TabularEditor/BestPracticeRules/master/BPARules-PowerBI.json" `
                        -OutputFile $TempOptFile

    #Run Tests
    #Get parent folder of this file
    $ParentFolder = Split-Path -Path $PBITest.FullName
    #Get dax files in this folder
    $DaxFilesInFolder = Get-ChildItem -Path $ParentFolder | Where-Object {$_ -like "*.*dax"}    
    Write-Host "Attempting to run tests for: $($PBITest)"

    foreach($Test in $DaxFilesInFolder)
    {
        Write-Host "Running Tests found in $($Test.FullName)"

        $QueryResults = Send-XMLAWithPPU -WorkspaceName $BuildWS.Name `
                        -DatasetName $TempRpt.Name `
                        -UserName $Opts.UserName `
                        -Password $Opts.Password `
                        -TenantId $Opts.TenantId `
                        -APIUrl $Opts.PbiApiUrl `
                        -InputFile $Test.FullName     
                        
        #Get Node List
        [System.Xml.XmlNodeList]$Rows = $QueryResults.GetElementsByTagName("row")

        #Check if Row Count is 0, no test results.
        if($Rows.Count -eq 0){
            $FailureCount += 1
            Write-Host "##vso[task.logissue type=warning]Query in test file $($Test.FullName) returned no results."
        }#end check of results

        #Iterate through each row of the query results and check test results
        foreach($Row in $Rows)
        {
            #Expects Columns TestName, Expected, Actual Columns, Passed
            if($Row.ChildNodes.Count -ne 4)
            {
                $FailureCount +=1
                Write-Host "##vso[task.logissue type=error]Query in test file $($Test.FullName) returned no results that did not have 4 columns (TestName, Expected, and Actual)."
            }
            else
            {
                #Extract Values
                $TestName = $row.ChildNodes[0].InnerText
                $ExpectedVal = $row.ChildNodes[1].InnerText
                $ActualVal = $row.ChildNodes[2].InnerText
                #Compute whether the test passed
                $Passed = ($ExpectedVal -eq $ActualVal) -and ($ExpectedVal -and $ActualVal)

                if(-not $Passed)
                {
                    $FailureCount +=1
                    Write-Host "##vso[task.logissue type=error]FAILED!: Test $($TestName). Expected: $($ExpectedVal) != $($ActualVal)"
                }
                else
                {
                    Write-Host "Test $($TestName) passed. Expected: $($ExpectedVal) == $($ActualVal)"
                }
            }
        }#end foreach row
    }#end iterating over test files
    $Iter = $Iter + 1
}#end foreach PBI files


#If FailureCount is greater than 1
if($FailureCount -gt 0)
{
    Write-Host "##vso[task.logissue type=error]$($FailureCount) failed test(s). Please resolve"
    exit 1
}
else #Promote to Development
{
    $Iter = 0
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