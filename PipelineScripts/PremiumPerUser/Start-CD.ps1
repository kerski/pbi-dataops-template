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
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Refresh-DatasetSyncWithPPU.psm1 -Force
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Send-XMLAWithPPU.psm1 -Force
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/CD/SchemaCheck/Get-DatasetSchemaWithPPU.psm1 -Force

#Get Default Environment Variables 
$Opts = Get-DevOpsVariables
#Install PBI Powershell Module if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "##[debug]MicrosoftPowerBIMgmt already installed"
} else {
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
}

#Set Client Secret as Secure String
$Secret = $Opts.Password | ConvertTo-SecureString -AsPlainText -Force
$Credentials = [System.Management.Automation.PSCredential]::new($Opts.UserName,$Secret)
#Connect to Power BI
Connect-PowerBIServiceAccount -Credential $Credentials

#Staging Information
$StagingWS = Get-PowerBIWorkspace -id $Opts.StagingGroupId

#Production Information
$ProdWS = Get-PowerBIWorkspace -id $Opts.ProdGroupId

#Iterate through files in Staging Environment
$PBIsToTest = Get-ChildItem -Path "./pbi" -Recurse | Where-Object {$_ -like "*.pbix"}
$Iter = 0
foreach ($PBICheck in $PBIsToTest){
    Write-Host "##[group]File to check in Staging Workspace: $($PBICheck)"

    #Power BI file without pbix extension
    $PBIName = [io.path]::GetFileNameWithoutExtension($PBICheck)

    # Get Dataset Id
    $ProdReportInfo = Get-PowerBIReport -WorkspaceId $Opts.ProdGroupId -Name $PBIName
    $StagingReportInfo = Get-PowerBIReport -WorkspaceId $Opts.StagingGroupId -Name $PBIName

    #If Report exists in Production, assume we got it in Staging
    if($ProdReportInfo){
        #If DatasetId property is null then this is a PowerBI report with a dataset needing a refresh
        if(!$ProdReportInfo.DatasetId -ne $null){ 
            Write-Host "##[section]Refreshing in Staging Workspace: $($PBICheck)"

            $RefreshResult = Refresh-DatasetSyncWithPPU -WorkspaceId $Opts.StagingGroupId `
                            -DatasetId $StagingReportInfo.DatasetId `
                            -UserName $Opts.UserName `
                            -Password $Opts.Password `
                            -TenantId $Opts.TenantId `
                            -APIUrl $Opts.PbiApiUrl
                
                #If Failed to Refresh stop script
                if($RefreshResult -ne "Completed")
                {
                    Write-Host "##vso[task.logissue type=error]Failed to refresh: $($PBICheck) in $($StagingWS.Name)"
                    exit 1
                }
                else
                {
                    Write-Host "##[debug]Successfully refreshed: $($PBICheck) in $($StagingWS.Name)"
                }

            #Run Schema Check
            # Delete files just in case
            if(Test-Path -Path "./staging.tsv")
            {
                Remove-Item -Path "./staging.tsv"
            }
            
            if(Test-Path -Path "./production.tsv")
            {
                Remove-Item -Path "./production.tsv"
            }

            # Staging
            Get-DatasetSchemaWithPPU -WorkspaceName $StagingWS.Name `
                                    -DatasetName $PBIName `
                                    -UserName $Opts.UserName `
                                    -Password $Opts.Password `
                                    -APIUrl $Opts.PbiApiUrl `
                                    -TabularEditorUrl $Opts.CD.TabEditorUrl `
                                    -ScriptFile "$($WorkingDir)/$($Opts.CD.StagingScriptFile)"
            # Production
            Get-DatasetSchemaWithPPU -WorkspaceName $ProdWS.Name `
                                    -DatasetName $PBIName `
                                    -UserName $Opts.UserName `
                                    -Password $Opts.Password `
                                    -APIUrl $Opts.PbiApiUrl `
                                    -TabularEditorUrl $Opts.CD.TabEditorUrl `
                                    -ScriptFile "$($WorkingDir)/$($Opts.CD.ProductionScriptFile)"
                
            $SchemaCompare = Compare-Object -ReferenceObject (Get-Content -Path "./staging.tsv") -DifferenceObject (Get-Content -Path "./production.tsv")

            if($SchemaCompare.length -ne 0) #Schema issue
            {
                Write-Host "##vso[task.logissue type=error]Schema Issue for $($PBICheck): $($SchemaCompare)"
                exit 1

            }
            #end if schema comparison

            ### Run Tests
            # Get parent folder of this file
            $ParentFolder = Split-Path -Path $PBICheck.FullName

            #Get dax files in this folder
            if(Test-Path -Path "$($ParentFolder)\CD")
            {
                $DaxFilesInFolder = Get-ChildItem -Path "$($ParentFolder)\CD" | Where-Object {$_ -like "*.*dax"}    
            }
            else #Default to empty array is CD folder does not exist
            {
                $DaxFilesInFolder = @()   
            }
        
            Write-Host "##[section]Attempting to run tests for: $($PBICheck) in Staging"
            
            # Reset Failure Count for each file
            $FailureCount = 0
            foreach($Test in $DaxFilesInFolder)
            {
                Write-Host "##[section]Running Tests found in $($Test.FullName)"
        
                $QueryResults = Send-XMLAWithPPU -WorkspaceName $StagingWS.Name `
                                -DatasetName $PBIName `
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
                            Write-Host "##[debug]Test $($TestName) passed. Expected: $($ExpectedVal) == $($ActualVal)"
                        }
                    }
                }#end foreach row
            }#end iterating over test files            
            
            #Output Results
            #If FailureCount is greater than 1
            if($FailureCount -gt 0)
            {
                Write-Host "##vso[task.logissue type=error]$($FailureCount) failed test(s) in Staging. Please resolve"
                exit 1
            }
            else #Refresh in Production but we encounter no issues
            {            
                Write-Host "##[debug]No schema or testing issues found for $($PBICheck)"
                Write-Host "##[section]Refreshing in Production Workspace: $($PBICheck)"
                #Now Refresh Production
                $RefreshResult = Refresh-DatasetSyncWithPPU -WorkspaceId $Opts.ProdGroupId `
                -DatasetId $ProdReportInfo.DatasetId `
                -UserName $Opts.UserName `
                -Password $Opts.Password `
                -TenantId $Opts.TenantId `
                -APIUrl $Opts.PbiApiUrl
    
                #If Failed to Refresh stop script
                if($RefreshResult -ne "Completed")
                {
                    Write-Host "##vso[task.logissue type=error]Failed to refresh: $($PBICheck) in $($ProdWS.Name)"
                    exit 1
                }
                else
                {
                    Write-Host "##[debug]Successfully refreshed: $($PBICheck) in $($ProdWS.Name)"
                }                
            }#end checking for failures
        }
    }#end if report info
        $Iter = $Iter + 1
        Write-Host "##[endgroup]"
}#end foreach
return