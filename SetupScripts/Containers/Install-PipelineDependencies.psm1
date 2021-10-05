<#
    Author: John Kerski
    Description: This script installs libraries and PowerShell modules for pipline.

    Dependencies: PowerShell 5.0
#>
Function Install-PipelineDependencies { 
		[CmdletBinding()]
		Param( 
		) 
		Process { 
            #Setup TLS 12
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            #Check for instances of Microsoft.AnalysisServices.Tabular
            $TabInstance = Get-ChildItem -Path "C:\\Windows\\Microsoft.NET\\assembly\\GAC_MSIL\\" -Recurse | Where-Object {$_ -like "Microsoft.AnalysisServices.Tabular*"}
            # Output for debugging
            $TabInstance.FullName

            #Install SSAS Tabular DLLs
            $MSIFile = "x64_15.0.2000.770_SQL_AS_AMO.msi"
            Write-Host "Installing Tabular SSAS Libraries with $($MSIFile)"
            
            #Setup Arguments for Install
            #Thanks Kevin Marquette: https://powershellexplained.com/2016-10-21-powershell-installing-msi-files/
            $DataStamp = get-date -Format yyyyMMddTHHmmss
            $LogFile = '{0}-{1}.log' -f $MSIFile,$DataStamp
            $MSIArguments = @(
                "/i"
                ('"{0}"' -f $MSIFile)
                "/qn"
                "/norestart"
                "/L*v"
                $LogFile
            )
            Start-Process "msiexec.exe" -ArgumentList $MSIArguments -Wait -NoNewWindow -Verbose

            #Find versions of the AnalysisServices Tabular dll
            $TabInstance = Get-ChildItem -Path "C:\\Windows\\Microsoft.NET\\assembly\\GAC_MSIL\\" -Recurse | Where-Object {$_ -like "Microsoft.AnalysisServices.Tabular*"}

            #Output for debugging
            $TabInstance.FullName

            #Setup Nuget
            Write-Host "Installing Nuget Package Provider"
            Install-PackageProvider -Name NuGet -Force -Verbose

            # Install Power BI Module
            Write-Host "Installing Power BI Module"
            Install-Module -Name MicrosoftPowerBIMgmt -Force -Verbose

            # Install SharePoint PnP Module
            Write-Host "Installing SharePoint PnP Module"
            Install-Module -Name PnP.PowerShell -Force -Verbose

            # Install Sql Server Libraries
            Write-Host "Installing Sql Server Libraries"
            Install-Module -Name SqlServer -Force -Verbose

            # Install Tabular Editor
            $TabularEditorUrl = "https://github.com/otykier/TabularEditor/releases/download/2.16.1/TabularEditor.Portable.zip"

            # Download destination (root of PowerShell script execution path):
            $DownloadDestination = join-path (get-location) "TabularEditor.zip"

            # Download from GitHub:
            Invoke-WebRequest -Uri $TabularEditorUrl -OutFile $DownloadDestination

            # Unzip Tabular Editor portable, and then delete the zip file:
            Expand-Archive -Path $DownloadDestination -DestinationPath (get-location).Path
            Remove-Item $DownloadDestination

            if (Test-Path TabularEditor.exe -PathType Leaf) {
                Write-Host "TabularEditor is installed."
            }
	}#End Process
}#End Function

Export-ModuleMember -Function Install-PipelineDependencies