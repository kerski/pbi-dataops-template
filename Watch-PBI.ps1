<#
    Author: John Kerski
    .SYNOPSIS
        Provide a file name searches the /Pbi file to launch the .pbix file in Power BI Desktop
        and initiates extract command with watch using pbi-tools.        

    .DESCRIPTION
        Provide a file name searches the /Pbi file to launch the .pbix file in Power BI Desktop
        and initiates extract command with watch using pbi-tools.

        Dependencies: pbi-tools
    .PARAMETER FileName
        The name of the Power BI file 
        
        Example: 
            -FileName SampleModel
    .EXAMPLE
        ./Watch-PBI.ps1  -FileName "SampleModel"
    #>
param([String]$FileName)

if(-not $FileName)
{
    Write-Host -ForegroundColor Red "Please provide a FileName to tell pbi-tools to watch"
    return   
}

# Get Power BI Files
$PBIFiles = Get-ChildItem -Path "./pbi" -Recurse | Where-Object {$_ -like "*.pbix"}

# Check to make sure the FileName exists
$TestFile = $PBIFiles | Where-Object {$_.Name -like "$($FileName).pbix" -or $_.Name -like $FileName}

if(-not $TestFile)
{
    Write-Host -ForegroundColor Red "$($FileName) could not be found in any of the folders under 'PBI'. If the filename has spaces, please place within double quotes (ex. ""Sample Model"")."
    return
}

# Also check if someone has the file open already
$FoundTheFileSession = $false
# Check to make sure this File is open using pbi-tools
$Output = pbi-tools info | ConvertFrom-Json
$Session = $Output.pbiSessions | Where-Object {$_.PbixPath -eq $TestFile}

if(-not $Session) # then the file is not open already so launch it.
{
    # Now Launch PBI
    Write-Host -ForegroundColor Cyan "Launching $($FileName) in Power BI Desktop"
    $LaunchStatus = pbi-tools launch-pbi $TestFile.FullName
    # Setup check with a limit on how long we wait for Power BI to load
    $NumberOfTries = 0
    $LimitOfTries = 10
    $Session = $null
    #And now we wait
    Do
    {
        #Wait for Power BI Desktop to Load
        Write-Host -ForegroundColor Cyan "Waiting for Power BI Desktop to load $($FileName) and then pbi-tools watch will be initiated"
        Start-Sleep -Seconds 10
        # Check to make sure this File is open using pbi-tools
        $Output = pbi-tools info | ConvertFrom-Json
        
        $Session = $Output.pbiSessions | Where-Object {$_.PbixPath -eq $TestFile.FullName}

        if($Session)
        {
            #Set to true
            $FoundTheFileSession = $true  
            #break;  
        }

        $NumberOfTries+=1
    }While ($NumberOfTries -le $LimitOfTries -and $FoundTheFileSession -ne $true)
}
else #File already open so update boolean flag
{
    Write-Host -ForegroundColor Cyan "File appears to be open already, so attempting to initiate watch."
    $FoundTheFileSession = $true
}

#Last check before we initiate watch
if($FoundTheFileSession -eq $false)
{
    Write-Host -ForegroundColor Red "$($FileName) either took longer than 30 seconds to load or Power BI Desktop had an error. Please try again."
    return
}
else #Initiate Watch
{
    Write-Host -ForegroundColor Green "Initiating Watch!"
    pbi-tools extract $TestFile.FullName -extractFolder "$($TestFile.DirectoryName)\PbixProj" -watch -pid $Session.ProcessId
}