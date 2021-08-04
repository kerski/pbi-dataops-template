<#
    Author: John Kerski
    Description: This script publishes PBI to workspace indentified by WorkspaceId parameter

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName has admin right to workspace.
#>
Function Publish-PBIFIleWithPPU { 
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

                #Promote Report and overwrite if it already exists
                $Result = New-PowerBIReport -Path $LocalDatasetPath -Name $FileName -WorkspaceId $WorkspaceId -ConflictAction CreateOrOverwrite -Timeout 500

                #Note the DatasetId is blank for newly published reports (possibly a timing issue) so request for the dataset id
                $ReportInfo = Get-PowerBIReport -Filter "state ne 'Deleted'" -WorkspaceId $WorkspaceId -Id $Result.Id

                return $ReportInfo

            }Catch{
              Write-Host "##vso[task.logissue type=error]Failure to promote $($LocalDatasetPath) to Workspace $($WorkspacedId)."
              exit 1
            }#End Try
	}#End Process
}#End Function



Export-ModuleMember -Function Publish-PBIFIleWithPPU