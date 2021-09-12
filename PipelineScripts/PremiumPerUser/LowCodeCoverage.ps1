<#
    Author: John Kerski
    Description: This script runs the proof-of-concept to run Test Coverage processes.

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

#Try to add Tabular
$TempTabPath = "$($Opts.WorkingDir)$($Opts.TabularDLLRelPath)"

#Check if Tabular object exists
try
{
    $TestNewObj = New-Object Microsoft.AnalysisServices.Tabular.Server
}
catch
{
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
    #Try to add load assembly now after installation
    try
    {
        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.AnalysisServices.Tabular")
    }
    catch
    {
        $_.Exception.LoaderExceptions | % {
        Write-Error $_.Message
        }
        exit 1
    }
}#end catch


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
    Write-Host "Attempting to run calculate test coverage: $($PBITest)"

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

    #Get Test Coverage information (Calculation Dependencies, Measures, Calculated Columns and Tables)
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