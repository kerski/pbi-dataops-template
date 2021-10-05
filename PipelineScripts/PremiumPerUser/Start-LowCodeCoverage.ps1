<#
    Author: John Kerski
    Description: This script runs the proof-of-concept to run Low-Code Coverage processes.

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName 
    has admin right to workspace.
#>
#Setup TLS 12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#Get Working Directory
$WorkingDir = (& pwd) -replace "\\", '/'
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Get-DevOpsVariables.psm1 -Force
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Find-LowCodeCoverageForPBIWithPPU.psm1 -Force
Import-Module $WorkingDir/PipelineScripts/PremiumPerUser/Add-ResultToSPWithPPU.psm1 -Force
#Get Default Environment Variables 
$Opts = Get-DevOpsVariables
#Install PBI Powershell Module if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "MicrosoftPowerBIMgmt already installed"
} else {
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
}
#Install SQL Powershell Module if Needed
if (Get-Module -ListAvailable -Name "SqlServer") {
    Write-Host "SqlServer module already installed"
} else {
    Install-Module -Name SqlServer
}

#Check if Tabular object exists

#Get Major Version of Tabular Version
#Reference: https://dscottraynsford.wordpress.com/2018/09/10/list-global-assembly-cache-using-powershell/
try{
    $CheckDrive = Get-PSDrive -Name HKCR
}
catch #if drive does not exist this fails so create drive
{
    $CheckDrive = New-PSDrive -Name HKCR -PSProvider 'Microsoft.PowerShell.Core\Registry' -Root HKEY_CLASSES_ROOT
}
# Get Global Assembly Cache
$GACList = Get-ItemProperty -Path 'HKCR:\Installer\Assemblies\Global' | Get-Member -MemberType NoteProperty 
# Now check if the version is 15 or later
$Version15Check = $GACList.Where({ [string]($_.Definition) -like '*Microsoft.AnalysisServices.Tabular*version="15.*'})

Write-Host "Count of Version 15 Libraries Instances: $($Version15Check.Count)"

# If greater than 0, version 15 exists, if not, we need to install version 15
if($Version15Check.Count -eq 0)
{
    try{
        #Install SSAS DLLs
        $MSIFile = "$($Opts.WorkingDir)$($Opts.SSASMSIRelPath)"
        Write-Host "Installing $($Opts.SSASMSIRelPath)"

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
    }
    catch
    {
        $_.Exception.LoaderExceptions | % {
        Write-Error $_.Message
        }
        exit 1
    }#end catch
}
else
{
    Write-Host "Tabular Object installed."
}
#end if

#Iterate of Power BI Changes and get the pbix files
#Find all files in working directory
$PBIsToTest = Get-ChildItem -Path "./pbi" -Recurse | Where-Object {$_ -like "*.pbix"}

#Set Client Secret as Secure String
$Secret = $Opts.Password | ConvertTo-SecureString -AsPlainText -Force
$Credentials = [System.Management.Automation.PSCredential]::new($Opts.UserName,$Secret)
#Connect to Power BI
Connect-PowerBIServiceAccount -Credential $Credentials

#Get Workspace Information to make sure we get the right Workspacename for XMLA
$BuildWS = Get-PowerBIWorkspace -Id $Opts.BuildGroupId 

$Iter = 0
foreach($PBITest in $PBIsToTest){
    #Get the Report Information
    $TempRpt = Get-PowerBIReport -WorkspaceId $Opts.BuildGroupId -Name $PBITest.BaseName
    
    #Get parent folder of this file
    $ParentFolder = Split-Path -Path $PBITest.FullName
    #Get dax files in this folder
    $DaxFilesInFolder = Get-ChildItem -Path $ParentFolder | Where-Object {$_ -like "*.*dax"}    
    Write-Host "Attempting to run calculate low-code coverage: $($PBITest)"

    #Define array
    $DaxQueries = @()

    #Iterate Through List and format tests
    foreach($Test in $DaxFilesInFolder)
    {
        $X = [pscustomobject]@{
            TestName = [io.path]::GetFileNameWithoutExtension($Test.FullName)
            Path = $Test.FullName
            Content = Get-Content -Path $Test.FullName -Encoding String
            }
            #Make sure DEFINE is removed
            #Make sure EVALUATE is switched to RETURN
            #This is case insensitive
            $TempExp = $X.Content -replace "^DEFINE\s*", ""
            $TempExp = $TempExp -replace "\bEVALUATE", "RETURN"
            $TempExp = $TempExp.Trim()
            $X.Content = $TempExp

            #Add to Array
            $DaxQueries += $X
    }#end foreach test files

    #Get Coverage information (Calculation Dependencies, Measures, Calculated Columns and Tables)
    $TestCoverageResult = Find-LowCodeCoverageForPBIWithPPU -WorkspaceName $BuildWS.Name `
                -LocalDatasetPath $PBITest.FullName `
                -UserName $Opts.UserName `
                -Password $Opts.Password `
                -TenantId $Opts.TenantId `
                -APIUrl $Opts.PbiApiUrl `
                -DaxQueries $DaxQueries `
                -BuildId $Opts.BuildVersion               
    
        
    #Save to SharePoint
    Add-ResultToSPWithPPU -SiteUrl $Opts.ResultsListSPUrl`
            -ListTitle $Opts.ResultsListTitle`
            -UserName $Opts.UserName `
            -Password $Opts.Password `
            -ContentTypeName "Item" `
            -Values $TestCoverageResult

    $Iter = $Iter + 1
}#end foreach PBI files

return