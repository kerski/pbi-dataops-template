<#
    Author: John Kerski
    Description: This downloads a file from Power BI based on the WorkspaceID and ReportID.  
    This file is then uploaded to SharePoint based on the SiteUrl and DocumentLib settings.
#>

#PLEASE SET VARIABLES
$ReportID = "<REPORT ID>"
$WorkspaceID = "<WORKSPACE ID>"
$SiteUrl = "<SITE URL>"
$DocumentLib = "<LIBRARY NAME>"

Try
{
    #STEP 1: Check Dependencies
    Write-Host -ForegroundColor Cyan "Step 1 of 4: Check for Dependencies"
    #Install Powershell Module if Needed
    if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
        Write-Host "MicrosoftPowerBIMgmt already installed. check for updates."
    } else {
        Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
    }
    #Install Powershell Module if Needed
    if (Get-Module -ListAvailable -Name "PnP.PowerShell") {
        Write-Host "PnP.PowerShell already installed. Check for updates."
    } else {
        Install-Module -Name PnP.PowerShell -Scope CurrentUser -AllowClobber -Force
    }

    #STEP 2: Get Dataset Information
    Write-Host -ForegroundColor Cyan "Step 2 of 4: Getting Report Information"
    #Script will prompt you to login to Power BI and SharePoint Online
    Connect-PowerBIServiceAccount
    Connect-PnPOnline -Url $SiteUrl -Interactive

    $ReportInfo = Get-PowerBIReport -Id $ReportID -WorkspaceId $WorkspaceID
    #Check if report found
    if(-not $ReportInfo)
    {
        throw  "Unable to find report. Please check the Report ID and Workspace ID variables."
    }
    
    #Setup BackupFile Name
    $DatePrefix = Get-Date -Format "yyyyMMddHHmm"
    $BackupFileName = "$($ReportInfo.Name)_$($DatePrefix).pbix"
    #Only take 255 characters because Power BI file name limit is 255
    if($BackupFileName.length -gt 250)
    {
        $BackupFileName = $BackupFileName.Substring(0,250)
    }

    #STEP 3: Export File
    Write-Host -ForegroundColor Cyan "Step 3 of 4: Exporting File to current folder as $($BackupFileName)"
    
    Export-PowerBIReport -WorkspaceId $WorkspaceID -Id $ReportID -OutFile ".\$($BackupFileName)" -Verbose

    #STEP 4: Update to SharePoint
    Write-Host -ForegroundColor Cyan "Step 4 of 4: Uploading $($BackupFileName) to SharePoint."
    Add-PnPFile -Path ".\$($BackupFileName)" -Folder "Shared Documents" -ErrorAction Stop

    #Clean up local file
    Remove-Item ".\$($BackupFileName)"

    Write-Host -ForegroundColor Green "Backup completed."

    Disconnect-PowerBIServiceAccount
}Catch [System.Exception]{
    $ErrObj = ($_).ToString()
    Write-Host "$($ErrObj)"
    Disconnect-PowerBIServiceAccount
}#End Try