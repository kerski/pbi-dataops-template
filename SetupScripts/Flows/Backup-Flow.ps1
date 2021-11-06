<#
    Author: John Kerski
    Description: This downloads a file from Power BI based on the WorkspaceID and ReportID.  
    This file is then uploaded to SharePoint based on the SiteUrl and DocumentLib settings.

    NOTE: Based on preferClientRouting issue, several steps have been made to work with small and large file sizes.
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
    $TestFileName = "Test_$($DatePrefix).pbix"
    #Only take 255 characters because Power BI file name limit is 255
    if($BackupFileName.length -gt 250)
    {
        $BackupFileName = $BackupFileName.Substring(0,250)
    }

    #STEP 3: Export File
    Write-Host -ForegroundColor Cyan "Step 3 of 4: Exporting file to current folder as $($BackupFileName)"

    #With the preferClientRouting 403 issue I need to get the local tenant url so we can get the export
    #https://devblogs.microsoft.com/scripting/powertip-use-powershell-to-save-verbose-messages-in-output-file/
    $TestURL = "https://api.powerbi.com/v1.0/myorg/groups/$($WorkspaceID)/reports/$($ReportID)/export?preferClientRouting=true"
    $Vtext = "log-file.txt"
    #Output verbose to file so we can retrieve the tenant host
    Invoke-PowerBIRestMethod -Method Get -Url $TestURL -Verbose -OutFile ".\$($TestFileName)" 4>&1 > $VText
    
    #Error may occur, but get redirect host from file
    $URLString = ((Select-String '(https)(:\/\/)([^\s,]+)' -Input $X).Matches.Value)
    [system.uri]$PBITenantHostURL = $URLString
    #Setup working URL to export
    $DownloadAPIEndpoint = "https://$($PBITenantHostURL.Host)/export/v201606/reports/$($ReportID)/pbix"
    
    #Cleanup files before testing again
    if(Test-Path -Path ".\$($TestFileName)")
    {
        Remove-Item ".\$($TestFileName)"
    }
    Remove-Item ".\$($VText)"

    #Make request using new url with endpoint that should work
    Invoke-PowerBIRestMethod -Method Get -Url $DownloadAPIEndpoint -Verbose -OutFile ".\$($TestFileName)" -TimeoutSec 600

    #Check file size because this may be a json file (pointing to where the pbix is in blob storage) or actual pbix.
    $FileSize = (Get-Item ".\$($TestFileName)").length/1KB

    if($FileSize -lt 1)
    {
        #File is too big, so Microsoft put in temporary blob storage, parse file and retrieve
        $Temp = Get-Content ".\$($TestFileName)" | ConvertFrom-Json

        #Check if url is valid
        if($Temp.url)
        {
            #Cleanup file before testing again
            Remove-Item ".\$($TestFileName)"
            #Try download file
            Invoke-WebRequest $Temp.url -Verbose -OutFile ".\$($BackupFileName)" -TimeoutSec 600
        }
        else
        {
            throw "Unable to parse json for file location."
        }

    }
    else
    {
        #File should be pbix so rename
        Rename-Item ".\$($TestFileName)" -NewName $BackupFileName
    }
    #end if
    

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