<#
    .SYNOPSIS
    Publish PBI file to workspace using Premium Per User

    .DESCRIPTION
     Dependencies: Premium Per User license purchased and assigned to UserName and UserName has admin right to workspace.

    .PARAMETER WorkspaceId
    GUID representing workspace in the service

    .PARAMETER LocalDatasetPath
    File path to the .pbix file

    .PARAMETER UserName
    Service Account's UserName

    .PARAMETER Password
    Service Account's Password

    .PARAMETER Tenant ID
    App Service Principal's Tenant ID

    .PARAMETER APIUrl
    Url EndPoint for Power BI API (ex. https://api.powerbi.com/v1.0/myorg)

    .OUTPUTS
    Microsoft.PowerBI.Common.Api.Reports.Report

    .EXAMPLE
    $Temp = Publish-PBIFIleWithPPU -WorkspaceId $BuildGroupId `
                     -LocalDatasetPath $PBIPath `
                     -UserName $UserName `
                     -Password $Password `
                     -TenantId $TenantId `
                     -APIUrl $PbiApiUrl

#>
Function Publish-PBIFileWithPPU { 
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
                #Set Password as Secure String
                $Secret = $Password | ConvertTo-SecureString -AsPlainText -Force
                $Credentials = [System.Management.Automation.PSCredential]::new($UserName,$Secret)
                #Connect to Power BI
                Connect-PowerBIServiceAccount -Credential $Credentials
          
                #Get File Name using .Net
                $FileName = [io.path]::GetFileNameWithoutExtension($LocalDatasetPath)

                #Promote Report and overwrite if it already exists
                $Result = New-PowerBIReport -Path $LocalDatasetPath -Name $FileName -WorkspaceId $WorkspaceId -ConflictAction CreateOrOverwrite -Timeout 5000 -Verbose

                #Note the DatasetId is blank for newly published reports (possibly a timing issue) so request for the dataset id
                $ReportInfo = Get-PowerBIReport -WorkspaceId $WorkspaceId -Id $Result.Id -Verbose

                return $ReportInfo

            }Catch [System.Exception]{
              $ErrObj = ($_).ToString()
              Write-Host "##vso[task.logissue type=error]$($ErrObj)"
              exit 1
            }#End Try
	}#End Process
}#End Function



Export-ModuleMember -Function Publish-PBIFileWithPPU