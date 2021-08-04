<#
    Author: John Kerski
    Description: This script issues a DAX query (identified by the InputFile path) via XMLA to the Workspace and Dataset.

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName has admin right to workspace.
#>
Function Send-XMLAWithPPU { 
		[CmdletBinding()]
		Param( 
				[Parameter(Position = 0, Mandatory = $true)][String]$WorkspaceName, 
				[Parameter(Position = 1, Mandatory = $true)][String]$DatasetName,
                [Parameter(Position = 2, Mandatory = $true)][String]$UserName,
                [Parameter(Position = 3, Mandatory = $true)][String]$Password,
                [Parameter(Position = 4, Mandatory = $true)][String]$TenantId,
                [Parameter(Position = 5, Mandatory = $true)][String]$APIUrl,
                [Parameter(Position = 6, Mandatory = $true)][String]$InputFile
		) 
		Process { 
            Try {
                #Install Powershell Module if Needed
                if (Get-Module -ListAvailable -Name "SqlServer") {
                    Write-Host "SqlServer module already installed"
                } else {
                    Install-Module -Name SqlServer
                }
                #Set Client Secret as Secure String
                $Secret = $Password | ConvertTo-SecureString -AsPlainText -Force
                $Credentials = [System.Management.Automation.PSCredential]::new($UserName,$Secret)
                #Replace https with powerbi
                $PBIEndpoint = $APIUrl.Replace("https","powerbi")
                #Connect to Power BI and run DAX Query
                $Result = Invoke-ASCmd -Server "$($PBIEndpoint)/$($WorkspaceName)" `
                            -Database $DatasetName `
                            -InputFile $InputFile `
                            -Credential $Credentials `
                            -TenantId $TenantId

                #Remove unicode chars for brackets and spaces from XML node names
                $Result = $Result -replace '_x[0-9A-z]{4}_','';

                #Load into XML and return
                [System.Xml.XmlDocument]$XmlResult = New-Object System.Xml.XmlDocument
                $XmlResult.LoadXml($Result)

                return $XmlResult
            }Catch [System.Exception]{
              $ErrObj = ($_).ToString()
              Write-Host "##vso[task.logissue type=error]$($ErrObj)"
            }#End Try
	}#End Process
}#End Function

Export-ModuleMember -Function Send-XMLAWIthPPU

