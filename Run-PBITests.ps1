<#
    Author: John Kerski
    Description: Runs test cases for files that are opened locally

    Dependencies: PowerShell < 5 so is can run Invoke-AsCmd
#>
#Setup TLS 12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#Check Powershell version to make sure it's compatible for Invoke-AsCmd
if($PSVersionTable.PSVersion.Major -ne 5)
{
    Write-Host -ForegroundColor Red "The current terminal is running the wrong version of Powershell, please type in 'Powershell -NoExit' in the terminal."
    return
}

#Import Appropriate Modules
$WorkingDir = (& pwd) 
Import-Module $WorkingDir\Pbi\TestingScripts\Custom\Get-PowerBIReportsOpenedLocally.psm1 -Force
Import-Module $WorkingDir\Pbi\TestingScripts\Pester\4.10.1\Pester.psm1 -Force

#Clean up any old test results
Get-ChildItem -Path "$($WorkingDir)\Pbi\TestingScripts\" *.xml | foreach { Remove-Item -Path $_.FullName}

#Get opened files
$PBIFilesOpened = Get-PowerBIReportsOpenedLocally

#Rest failed test case count
$FailedTestCases = 0

foreach ($Temp in $PBIFilesOpened) {

    #Get dax files in this folder
    $FolderPathToTest = "pbi\$($Temp.Title)"
    
    #Check if current project has a pbi folder for the opened Power BI file in desktop
    if (Test-Path -Path $FolderPathToTest) {
        Write-Host -Foreground Cyan "Running Tests for PBI file: $($Temp.Title)"

        #Create Temp File
        $TempFile = "$($WorkingDir)\Pbi\TestingScripts\$((New-Guid).Guid).xml"

        #Now run tests
        Invoke-Gherkin -Path $FolderPathToTest -OutputFile $TempFile -Strict

      #Load into XML
      [System.Xml.XmlDocument]$TempResult = Get-Content $TempFile
      $TempFailureCount = [int]$TempResult.'test-results'.failures
    
      $FailedTestCases += $TempFailureCount + 0

      #Display Failed Cases
      $FailedXml = Select-Xml -Path $TempFile -XPath "//test-case[@result='Failure']"

      if($TempFailureCount -ne 0)
      {
        Write-Host -ForegroundColor Red "The following are the failed test case(s) for $($Temp.Title):"
        $FailedXml.Node | Select-Object name | Format-Table
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
