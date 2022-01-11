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
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/CD/SchemaCheck/Get-DatasetSchemaWithPPU.psm1 -Force

#Get Default Environment Variables 
$Opts = Get-DevOpsVariables
#Install PBI Powershell Module if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "MicrosoftPowerBIMgmt already installed"
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
    Write-Host "File to check in Staging Workspace: $($PBICheck)"

    #Power BI file without pbix extension
    $PBIName = [io.path]::GetFileNameWithoutExtension($PBICheck)

    # Get Dataset Id
    $ReportInfo = Get-PowerBIReport -WorkspaceId $Opts.ProdGroupId -Name $PBIName

    #If Report exists in Production, assume we got it in Staging
    if($ReportInfo){
        #If DatasetId property is null then this is a PowerBI report with a dataset needing a refresh
        if(!$ReportInfo.DatasetId -ne $null){ 
            Write-Host "Refreshing in Staging Workspace: $($PBICheck)"

            $RefreshResult = Refresh-DatasetSyncWithPPU -WorkspaceId $Opts.StagingGroupId `
                            -DatasetId $ReportInfo.DatasetId `
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
                    Write-Host "Successfully refreshed: $($PBICheck) in $($StagingWS.Name)"
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
            else{
                Write-Host "No schema issues found for $($PBICheck)"
                Write-Host "Refreshing in Production Workspace: $($PBICheck)"
                #Now Refresh Production
                $RefreshResult = Refresh-DatasetSyncWithPPU -WorkspaceId $Opts.ProdGroupId `
                -DatasetId $ReportInfo.DatasetId `
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
                    Write-Host "Successfully refreshed: $($PBICheck) in $($StagingWS.Name)"
                }
            }#end if schema comparison

            #Run Tests
            <#Get parent folder of this file
            $ParentFolder = Split-Path -Path $PBICheck.FullName

            Write-Host $ParentFolder
            #Get dax files in this folder
            $DaxFilesInFolder = Get-ChildItem -Path "$($ParentFolder)\CD" | Where-Object {$_ -like "*.*dax"}    
            
            Write-Host $DaxFilesInFolder
            
            Write-Host "Attempting to run tests for: $($PBICheck)"
            #>
            #Output Results

            #If pass publish production
        }
    }#end if report info
        $Iter = $Iter + 1
}#end foreach
return