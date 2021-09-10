Function Add-ResultToSPWithPPU { 
		[CmdletBinding()]
		Param( 
				[Parameter(Position = 0, Mandatory = $true)][String]$SiteUrl, 
				[Parameter(Position = 1, Mandatory = $true)][String]$ListTitle,
                [Parameter(Position = 2, Mandatory = $true)][String]$UserName,
                [Parameter(Position = 3, Mandatory = $true)][String]$Password,
                [Parameter(Position = 3, Mandatory = $true)][String]$ContentTypeName,
                [Parameter(Position = 4, Mandatory = $true)][Object]$Values
		) 
		Process { 
            Try {
                #Install Powershell Module if Needed
                if (Get-Module -ListAvailable -Name "PnP.PowerShell") {
                    Write-Host "PnP.PowerShell already installed"
                } else {
                    Install-Module -Name PnP.PowerShell -Scope CurrentUser -AllowClobber -Force
                }

                #Set Client Secret as Secure String
                $Secret = $Password | ConvertTo-SecureString -AsPlainText -Force
                $Credentials = [System.Management.Automation.PSCredential]::new($UserName,$Secret)

                #Connect to SharePoint
                $ConnectResult = Connect-PnPOnline -Url $SiteUrl -Credentials $Credentials -ReturnConnection
 
                $ConnectResult

                #Add Test to SharePoint
                $Result = Add-PnPListItem -List $ListTitle -ContentType $ContentTypeName -Values $Values

            }Catch [System.Exception]{
              $ErrObj = ($_).ToString()
              Write-Host "##vso[task.logissue type=error]$($ErrObj)"
              Throw "Unable to add test to SharePoint list."
            }#End Try
	}#End Process
}#End Function

Export-ModuleMember -Function Add-ResultToSPWithPPU