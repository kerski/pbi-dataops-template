<#
    Author: John Kerski
    Description: Retrieves Azure DevOps Pipeline Variables Expected.  Throws errors if a variable is missing.
#>
Function Get-DevOpsVariables { 
		[CmdletBinding()]
		Param() 
		Process { 
            Try {
                #Define Options
                $Opts = @{
                    WorkingDir = (& pwd);
                    TenantId = "${env:TENANT_ID}";
                    PbiApiUrl = "${env:PBI_API_URL}"
                    BuildGroupId = "${env:PBI_BUILD_GROUP_ID}"
                    DevGroupId = "${env:PBI_DEV_GROUP_ID}"
                    UserName = "${env:PPU_USERNAME}";
                    Password = "${env:PPU_PASSWORD}";
                    TabularEditorUrl = "${env:TAB_EDITOR_URL}";
                    #SharePoint List
                    ResultsListTitle = "${env:SP_LIST_TITLE}";
                    ResultsListSPUrl = "${env:SP_URL}";                    
                    #Get new pbix changes
                    PbixChanges = git diff --name-only --relative --diff-filter AMR HEAD^ HEAD '**/*.pbix';
                    PbixTracking = @();
                    BuildVersion = "${env:BUILD_SOURCEVERSION}";
                    TabularDLLRelPath = "\PipelineScripts\PremiumPerUser\Microsoft.AnalysisServices.Tabular.DLL";
                    SSASMSIRelPath = "\PipelineScripts\PremiumPerUser\x64_15.0.2000.770_SQL_AS_AMO.msi";
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

                if(-not $Opts.TabularEditorUrl){
                    throw "Missing or Blank Tabular Editor URL"
                }

                if(-not $Opts.ResultsListTitle){
                    throw "Missing or Blank Result List Title"
                }

                if(-not $Opts.ResultsListSPUrl){
                    throw "Missing or Blank Results List's SP URL"
                }

                if(-not (Test-Path "$($Opts.WorkingDir)$($Opts.TabularDLLRelPath)"))
                {
                    throw "Missing Analysis Services (AMO) MSI"
                }

                if(-not (Test-Path "$($Opts.WorkingDir)$($Opts.SSASMSIRelPath)"))
                {
                    throw "Missing Analysis Services (AMO) MSI"
                }

                #Return object properties
                return $Opts
            }Catch [System.Exception]{
              $ErrObj = ($_).ToString()
              Write-Host "##vso[task.logissue type=error]$($ErrObj)"
              throw $ErrObj
            }#End Try
	}#End Process
}#End Function

Export-ModuleMember -Function Get-DevOpsVariables

