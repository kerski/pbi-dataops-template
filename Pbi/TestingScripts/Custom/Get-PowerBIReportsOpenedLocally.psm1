    <#
        .SYNOPSIS
        Identifies all the Power BI Reports opened on the current machine and identifies the ports.

        .DESCRIPTION
        This function iterates through each opened Power BI process and identifies the report and port that is opened.

        .PARAMETER Name
        Get-PowerBIReportsOpenedLocally

        .OUTPUTS
        Array of objects with process id (Id), port number (Port), database name (DatabaseName) and name of the report (Title)

        .EXAMPLE
        PS> $X = Get-PowerBIReportsOpenedLocally
        PS> $X[0] | Format-List
        PS> 
        Name  : Port
        Value : 63402

        Name  : Title
        Value : Sample Report

        Name  : Id
        Value : 24480

        Name  : DatabaseName
        Value : f88de9a5-9849-4085-a3a2-5656cb42850f
    #>
    Function Get-PowerBIReportsOpenedLocally { 
        [CmdletBinding()]
        Param() 
        Process {
            #Install Powershell Module if Needed
            if (Get-Module -ListAvailable -Name "SqlServer") {
                #Write-Host "SqlServer module already installed"
            } else {
                Install-Module -Name SqlServer -Scope CurrentUser -AllowClobber -Force
            }

        #Check to see if the type already exists
        if("UserWindows" -as [type])
        {
            #already exists
        }
        else {
            <# Action when all if and elseif conditions are false #>
        
        Add-Type -IgnoreWarnings @"
using System;
using System.Runtime.InteropServices;
public class UserWindows {
[DllImport("user32.dll")]
public static extern IntPtr GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
}
"@
    }#end if
            #Get windows title and process ids for opened Power BI files
            $stringbuilder = New-Object System.Text.StringBuilder 256
    
            $pbifile_processids = @()
            $counter = 0
            $x = Get-Process | ForEach-Object {
                
                $count = [UserWindows]::GetWindowText($_.MainWindowHandle, $stringbuilder, 256)
    
                if (0 -lt $count -and $_.Product -eq "Microsoft Power BI Desktop") {
                    $temp_model = $_.MainWindowTitle.Substring(0, $_.MainWindowTitle.LastIndexOf('-') - 1)
                    $pbifile_processids += [pscustomobject]@{Id = $_.Id; Title = $temp_model; Port = 0; DatabaseName=0; Index = $counter } 
                    $counter++;  
                }
            }
            
    
            #Gets a list of teh ProcessIDs for all Open Power BI Desktop files
            $processids = $null
            try{
                $processids = Get-Process msmdsrv -ErrorAction Stop | Select-Object -ExpandProperty id 
            }
            catch [System.SystemException]{
                Write-Host -ForegroundColor Red "No instances of Power BI are running on this machine."
            }
            
            #Loops through each ProcessIDs, gets the diagnostic port for each file, and finally generates the connection that can be use when connecting to the Vertipaq model.
            if ($processids) {
                foreach ($processid in $processids) {
                    
                    $pbidiagnosticport = Get-NetTCPConnection | ? { ($_.State -eq "Listen") -and ($_.RemoteAddress -eq "0.0.0.0") -and ($_.OwningProcess -eq $processid) } | Select-Object -ExpandProperty LocalPort
                    
                    #Get Parent Process Id
                    $parentid = (Get-CimInstance -ClassName Win32_Process | ? processid -eq $processid).parentprocessid
                    
                    $index = ($pbifile_processids | Where-Object { $_.Id -eq $parentid }).Index
                    
                    if ($index -ge 0) {
                        $pbifile_processids[$index].Port = $pbidiagnosticport

                        #Now Also get the database name
                        $Result = Invoke-ASCmd -Server:"localhost:$($pbidiagnosticport)" -Query "<Discover xmlns='urn:schemas-microsoft-com:xml-analysis'><RequestType>DBSCHEMA_CATALOGS</RequestType><Restrictions /><Properties /></Discover>"

                        #Remove unicode chars for brackets and spaces from XML node names
                        $Result = $Result -replace '_x[0-9A-z]{4}_','';
                        
                        #Load into XML and return
                        [System.Xml.XmlDocument]$XmlResult = New-Object System.Xml.XmlDocument
                        $XmlResult.LoadXml($Result)
                        
                        [System.Xml.XmlNodeList]$Rows = $XmlResult.GetElementsByTagName("row")
                        #We expect one row with the catalog name
                        $pbifile_processids[$index].DatabaseName = $Rows.CATALOG_NAME                        
                    }
                } 
            }
            #Return array of objects with information about Power BI files opened
            return $pbifile_processids
            
    
        }#End Process
    }#End Function
    #Get-PowerBIReportsOpenedLocally
    Export-ModuleMember -Function Get-PowerBIReportsOpenedLocally