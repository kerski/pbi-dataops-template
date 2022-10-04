<#
    .SYNOPSIS
    This script runs a synchronous refresh of a dataset against the WorkspaceId identified.

    .DESCRIPTION
    This script runs a synchronous refresh of a dataset against the WorkspaceId identified.
    Dependencies: Premium Per User license purchased and assigned to UserName and UserName has admin right to workspace.

    .PARAMETER WorkspaceId
    GUID representing workspace in the service

    .PARAMETER DatasetId
    GUID represnting the dataset in the service

    .PARAMETER UserName
    Service Account's UserName

    .PARAMETER Password
    Service Account's Password

    .PARAMETER Tenant ID
    App Service Principal's Tenant ID

    .PARAMETER APIUrl
    Url EndPoint for Power BI API (ex. https://api.powerbi.com/v1.0/myorg)

    .OUTPUTS
    Refresh json as defined is MS Docs: https://learn.microsoft.com/en-us/rest/api/power-bi/datasets/get-refresh-history-in-group#refresh

    .EXAMPLE
   $RefreshResult = Invoke-RefreshDatasetSyncWithPPU -WorkspaceId $BuildGroupId `
                  -DatasetId $DatasetId `
                  -UserName $UserName `
                  -Password $Password `
                  -TenantId $TenantId `
                  -APIUrl $PbiApiUrl

#>
Function Invoke-RefreshDatasetSyncWithPPU { 
		[CmdletBinding()]
		Param( 
				[Parameter(Position = 0, Mandatory = $true)][String]$WorkspaceId, 
				[Parameter(Position = 1, Mandatory = $true)][String]$DatasetId,
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
                $ConnectionStatus = Connect-PowerBIServiceAccount -Credential $Credentials
                #Setup Refresh Endpoint
                $RefreshUrl = "$($APIUrl)/groups/$($WorkspaceId)/datasets/$($DatasetId)/refreshes"
                Write-Host "Refreshing via URL: $($RefreshUrl)"
                #Issue Data Refresh
                $ResultResult = Invoke-PowerBIRestMethod -Verbose -Url "$($RefreshUrl)" -Method Post -Body "{ `"notifyOption`": `"NoNotification`"}"
                #Check for Refresh to Complete
                Start-Sleep -Seconds 10 #wait ten seconds before checking refresh first time
                $CheckRefresh = 1
                
                Do
                { 
                 $RefreshResult = Invoke-PowerBIRestMethod -Url "$($RefreshUrl)?`$top=1" -Method Get | ConvertFrom-JSON
                 #Check date timestamp and verify no issue with top 1 being old 
                 $TimeSinceRequest = New-Timespan -Start $RefreshResult.value[0].startTime -End (Get-Date)
                 if($TimeSinceRequest.Minutes > 30)
                 {
                    $CheckRefresh = 1
                 }#Check status.  Not Unknown means in progress
                 elseif($RefreshResult.value[0].status -eq "Completed")
                 {
                    $CheckRefresh = 0
                    Write-Host "Refreshed Completed"
                    return "Completed"
                 }
                 elseif($RefreshResult.value[0].status -eq "Failed")
                 {
                    $CheckRefresh = 0
                    Write-Host "Refreshed Failed"
                    return "Failed"
                 }
                 elseif($RefreshResult.value[0].status -ne "Unknown")
                 {
                    $CheckRefresh = 0
                    Write-Host "Refresh Status Unknown"
                    return "Unknown"
                 }
                 else #In Progress check, PBI uses Unknown for status
                 {
                    $CheckRefresh = 1
                    Write-Host "Refresh Still In Progress"
                    Start-Sleep -Seconds 10 #sleep wait seconds before running again
                 }
                } While ($CheckRefresh -eq 1)  
                
                return "Unknown"      
            }Catch [System.Exception]{
              $ErrObj = ($_).ToString()
              Write-Host "##vso[task.logissue type=error]$($ErrObj)"
              exit 1
            }#End Try
	}#End Process
}#End Function
                  
Export-ModuleMember -Function Invoke-RefreshDatasetSyncWithPPU