<#
    Author: John Kerski
    Description: This script publishes RDL to workspace indentified by WorkspaceId parameter

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName has admin right to workspace.
#>
Function Publish-RDLFileWithPPU { 
		[CmdletBinding()]
		Param( 
				[Parameter(Position = 0, Mandatory = $true)][String]$WorkspaceId, 
				[Parameter(Position = 1, Mandatory = $true)][String]$LocalDatasetPath,
                [Parameter(Position = 2, Mandatory = $true)][String]$UserName,
                [Parameter(Position = 3, Mandatory = $true)][String]$Password,
                [Parameter(Position = 4, Mandatory = $true)][String]$TenantId,
                [Parameter(Position = 5, Mandatory = $true)][String]$APIUrl
		) 
		Process { 
            Try {
                #Install Powershell Module if Needed
                if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
                    Write-Host "MicrosoftPowerBIMgmt already installed"
                } else {
                    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
                }
                #Set Client Secret as Secure String
                $Secret = $Password | ConvertTo-SecureString -AsPlainText -Force
                $Credentials = [System.Management.Automation.PSCredential]::new($UserName,$Secret)
                #Connect to Power BI
                Connect-PowerBIServiceAccount -Credential $Credentials

                #Get File Name using .Net
                $FileName = [io.path]::GetFileNameWithoutExtension($LocalDatasetPath)   

                #RDL only supports "Abort" or "Overwrite" and will fail with anything else
                $RDLReportCheck = Get-PowerBIReport -WorkspaceId $WorkspaceId -Name "$($FileName)"

                #Default to new report
                $Conflict = 'Abort'             

                if($RDLReportCheck) #if exists overwrite
                {
                    $Conflict = "Overwrite"
                }#end if
                
                #Promote file
                $Result = New-PowerBIReport -Path $LocalDatasetPath -Name "$($FileName).rdl" -WorkspaceId $WorkspaceId -ConflictAction $Conflict

                return $Result

            }Catch [System.Exception]{
              $ErrObj = ($_).ToString()
              Write-Host "##vso[task.logissue type=error]$($ErrObj)"
              exit 1
            }#End Try
	}#End Process
}#End Function

Export-ModuleMember -Function Publish-RDLFileWithPPU