<#
    Author: John Kerski
    Description: This script installs and runs Best Practice Analzyer using Tabular Editor.  
    It then logs the results to Azure DevOps

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName has 
    admin right to workspace.
#>
Function Get-DatasetSchemaWithPPU { 
		[CmdletBinding()]
		Param( 
				[Parameter(Position = 0, Mandatory = $true)][String]$WorkspaceName, 
				[Parameter(Position = 1, Mandatory = $true)][String]$DatasetName,
                [Parameter(Position = 2, Mandatory = $true)][String]$UserName,
                [Parameter(Position = 3, Mandatory = $true)][String]$Password,
                [Parameter(Position = 4, Mandatory = $true)][String]$TabularEditorUrl,
                [Parameter(Position = 5, Mandatory = $true)][String]$APIUrl,
                [Parameter(Position = 6, Mandatory = $true)][String]$ScriptFile
		) 
		Process { 
            Try {
                #Install Tabular Editor if Needed
                if (Test-Path ".\TabEditor\TabularEditor.exe" -PathType Leaf) {
                    Write-Host "TabularEditor is installed."
                } else {
                    #Add Sub Folder to install Tabular Editor
                    if(!(test-path ".\TabEditor"))
                    {
                          New-Item -ItemType Directory -Force -Path "TabEditor"
                    }

                    # Download destination (root of PowerShell script execution path):
                    $DownloadDestination = join-path (get-location) "TabEditor\TabularEditor.zip"

                    # Download from GitHub:
                    Invoke-WebRequest -Uri $TabularEditorUrl -OutFile $DownloadDestination

                    # Unzip Tabular Editor portable, and then delete the zip file:
                    Expand-Archive -Path $DownloadDestination -DestinationPath "$((get-location).Path)\TabEditor\"
                    Remove-Item $DownloadDestination
                }

                #Replace https with powerbi
                $PBIEndpoint = $APIUrl.Replace("https","powerbi")

                #Define Parameters to pass to bat file
                #NOTE: Change parameters here if you want to change how errors and warnings are treated.
                $ScriptArg = "`"Provider=MSOLAP;Data Source=$($PBIEndpoint)/$($WorkspaceName);Connect Timeout=120;User ID=$($Username);Password=$($Password)`" `"$($DatasetName)`" -S `"$($ScriptFile)`" "

                #Execute Script
                Start-Process -FilePath ".\TabEditor\TabularEditor.exe" -Wait -NoNewWindow -PassThru `
                -ArgumentList "$ScriptArg"
            }Catch [System.Exception]{
                $ErrObj = ($_).ToString()
                Write-Host "##vso[task.logissue type=error]$($ErrObj)"
                exit 1
            }#End Try
	}#End Process
}#End Function

Export-ModuleMember -Function Get-DatasetSchemaWithPPU 