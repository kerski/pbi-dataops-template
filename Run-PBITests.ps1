<#
    Author: John Kerski
    .SYNOPSIS
        Runs test cases for Power BI files that are opened locally

    .DESCRIPTION
        Runs test cases for Power BI files that are opened locally

        If no parameters are passed all tests will be ran

        Dependencies: PowerShell < 5 so is can run Invoke-AsCmd
    .PARAMETER FileName
        The name of the Power BI file 
        
        Example: 
            -FileName SampleModel

    .PARAMETER Feature
        The name of the feature file to test

        Example:
            -Feature SampleModelVisuals

    .EXAMPLE
        ./Run-PBITests.ps1
        ./Run-PBITests.ps1  -FileName "SampleModel" -Feature "SampleModelVisuals"
    #>
param([String]$FileName, [String]$Feature)

#Setup TLS 12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#Import Appropriate Modules
$WorkingDir = (& pwd) 
Import-Module $WorkingDir\Pbi\TestingScripts\Custom\Get-PowerBIReportsOpenedLocally.psm1 -Force
Import-Module $WorkingDir\Pbi\TestingScripts\Pester\4.10.1\Pester.psm1 -Force

#Check Powershell version to make sure it's compatible for Invoke-AsCmd
if($PSVersionTable.PSVersion.Major -ne 5)
{
    Write-Host -ForegroundColor Red "The current terminal is running the wrong version of Powershell, please type in 'Powershell -NoExit' in the terminal."
    return
}

# Get Power BI Files
$PBIFiles = Get-ChildItem -Path "./pbi" -Recurse | Where-Object {$_ -like "*.pbix"}

# Check to make sure the FileName exists
$TestFile = $null
$TestFeatureFile = $null
$ShouldTestOneFeature = $false
if($FileName)
{
    $TestFile = $PBIFiles | Where-Object {$_.Name -like "$($FileName).pbix" -or $_.Name -like $FileName}
    # Check if TestFile has been found
    if(-not $TestFile)
    {
        Write-Host -ForegroundColor Red "$($FileName) could not be found in any of the folders under 'pbi'. If the filename has spaces, please place within double quotes (ex. ""Sample Model"")."
        return
    }

    #Check if specifc features need to be tested
    if($Feature)
    {    
        $TestFeatureFile = Get-ChildItem -Path $TestFile.DirectoryName -Filter "$($Feature).feature"

        if(-not $TestFeatureFile)
        {
            Write-Host -ForegroundColor Red "$($Feature).feature could not be found in the directory: $($TestFile.DirectoryName)"
            return
        }

        #Change flag to make sure we test one feature
        $ShouldTestOneFeature = $true
    }
}#end FileName check

#Clean up any old test results
Get-ChildItem -Path "$($WorkingDir)\Pbi\TestingScripts\" *.xml | foreach { Remove-Item -Path $_.FullName}

#Get opened files
$PBIFilesOpened = Get-PowerBIReportsOpenedLocally

if($TestFile) # Then just filter to just the filename
{
    #Get Name with no extension
    $FileNameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($TestFile.VersionInfo.FileName) 
    $PBIFilesOpened = $PBIFilesOpened | Where-Object {$_.Title -eq $FileNameNoExt }
    
    if($PBIFilesOpened.Count -eq 0)
    {
        Write-Host -ForegroundColor Red "$($TestFile) could not be found opened."
        return        
    }# end check to see if specific file exists
}# end filter

#Rest failed test case count
$FailedTestCases = 0

foreach ($Temp in $PBIFilesOpened) {
    #Get dax files in this folder
    if($ShouldTestOneFeature -eq $true)
    {
        #Assign to Feature File to test
        $FolderPathToTest = $TestFeatureFile.VersionInfo.FileName
    }
    else
    {
        #Assigne directory of feature files to test
        $FolderPathToTest = "pbi\$($Temp.Title)"
    }# end check which feature files to test

    #Check if current project has a pbi folder for the opened Power BI file in desktop
    if (Test-Path -Path $FolderPathToTest) {
        Write-Host -Foreground Cyan "Running Tests for PBI file: $($Temp.Title)"

        #Create Temp File
        $TempFile = "$($WorkingDir)\Pbi\TestingScripts\$((New-Guid).Guid).xml"

        #Now run tests
        Invoke-Gherkin -Path $FolderPathToTest -OutputFile $TempFile -Show  Failed,Summary

      #Load into XML
      [System.Xml.XmlDocument]$TempResult = Get-Content $TempFile
      $TempFailureCount = [int]$TempResult.'test-results'.failures
    
      $FailedTestCases += $TempFailureCount + 0

      #Display Failed Cases
      $FailedXml = Select-Xml -Path $TempFile -XPath "//test-case[@result='Failure']"

      if($TempFailureCount -ne 0)
      {
        Write-Host -ForegroundColor Red "The following are the failed test case(s) for $($Temp.Title):"
        $FailedOutput = $FailedXml.Node | Select-Object name

        # Output list of failures
        $X = 1
        foreach($F in $FailedOutput){
        Write-Host -ForegroundColor Red "$X) $($F.name) `n"
        $X +=1
        }#end foreach
      }

    }#end if
}

#Output results
if ($PBIFilesOpened.Length -eq 0)
{
    Write-Host -ForegroundColor Yellow "WARNING:  No test cases ran."
}
elseif ($FailedTestCases -eq 0) {
    Write-Host -ForegroundColor Green "SUCCESS: All test cases passed."
}
else {
    Write-Host -ForegroundColor Red "Failed: $($FailedTestCases) test case(s) failed."
}#end check number of failures

#Clean up test results
Get-ChildItem -Path "$($WorkingDir)\Pbi\TestingScripts\" *.xml | ForEach-Object { Remove-Item -Path $_.FullName}
