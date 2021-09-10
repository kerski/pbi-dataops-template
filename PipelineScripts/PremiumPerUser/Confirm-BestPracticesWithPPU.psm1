<#
    Author: John Kerski
    Description: This script installs and runs Best Practice Analzyer using Tabular Editor.  
    It then logs the results to Azure DevOps

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName has 
    admin right to workspace.
#>
Function Confirm-BestPracticesWithPPU { 
		[CmdletBinding()]
		Param( 
				[Parameter(Position = 0, Mandatory = $true)][String]$WorkspaceName, 
				[Parameter(Position = 1, Mandatory = $true)][String]$DatasetName,
                [Parameter(Position = 2, Mandatory = $true)][String]$UserName,
                [Parameter(Position = 3, Mandatory = $true)][String]$Password,
                [Parameter(Position = 4, Mandatory = $true)][String]$TabularEditorUrl,
                [Parameter(Position = 5, Mandatory = $true)][String]$APIUrl,
                [Parameter(Position = 6, Mandatory = $true)][String]$BPAUrl,
                [Parameter(Position = 7, Mandatory = $true)][String]$OutputFile
		) 
		Process { 
            Try {
                #Install Tabular Editor if Needed
                if (Test-Path TabularEditor.exe -PathType Leaf) {
                    Write-Host "TabularEditor is installed."
                } else {
                    # Download destination (root of PowerShell script execution path):
                    $DownloadDestination = join-path (get-location) "TabularEditor.zip"

                    # Download from GitHub:
                    Invoke-WebRequest -Uri $TabularEditorUrl -OutFile $DownloadDestination

                    # Unzip Tabular Editor portable, and then delete the zip file:
                    Expand-Archive -Path $DownloadDestination -DestinationPath (get-location).Path
                    Remove-Item $DownloadDestination
                }

                #Replace https with powerbi
                $PBIEndpoint = $APIUrl.Replace("https","powerbi")

                #Define Parameters to pass to bat file
                #NOTE: Change parameters here if you want to change how errors and warnings are treated.
                $BPAArg = "TabularEditor.exe """"Provider=MSOLAP;Data Source=$($PBIEndpoint)/$($WorkspaceName);User ID=$($Username);Password=$($Password)"""" """"$($DatasetName)"""" -A """"$($BPAUrl)"""" -E -W -V -T """"$($OutputFile)""""" 

                #I use the BAT file approach because running the tabular editor command using Powershell has not worked
                #The BAT file approach consistently runs during my testing
                $BATFileLocation = Get-ChildItem -Path "./" -Recurse | Where-Object {$_ -like "BPA.bat"}

                if($BATFileLocation.length -eq 0)
                {
                    Throw "Unable to find BPA.bat"
                }#end if

                #Execute BPA.bat
                cmd.exe /c $BATFileLocation.FullName "$BPAArg"

            }Catch{
              Write-Host "##vso[task.logissue type=error]Unable to check best practices."
            }#End Try
	}#End Process
}#End Function

Export-ModuleMember -Function Confirm-BestPracticesWithPPU 