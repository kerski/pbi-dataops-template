<# Note: Started to add '__' prefix for variables that are referenced in downstream tests
   Not all have been updated as of December 2022
#>

# Setup before each feature
BeforeEachFeature {
  #Install Powershell Module if Needed
  if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    #Write-Host -ForegroundColor Cyan "MicrosoftPowerBIMgmt already installed"
  } else {
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
  }
}

# Clean up global variables
AfterEachFeature {
  #Delete Global Variables used for testing and performance 
  Remove-Variable -Name "PBIFileOpened_Settings" -Scope Global -ErrorAction:Ignore
}

#region BACKGROUND steps
Given 'that we have access to the Power BI Report named "(?<PBIFile>[a-zA-Z\s].*)"' {
  param($PBIFile)

  #Check if we are running locally or in a pipeline
  $IsLocal = $False
  $IsFileOpen = $False
  $__PBIFileToTest = $Null

  if(${env:BUILD_SOURCEVERSION}) # assumes this only exists in Azure Pipelines
  {
    Write-Host -ForegroundColor Cyan "Running tests in the Azure Pipeline."
    #Compile Azure Pipeline Settings
    $Opts = @{
      TenantId = "${env:TENANT_ID}";
      PBIAPIUrl = "${env:PBI_API_URL}"
      BuildGroupId = "${env:PBI_BUILD_GROUP_ID}"
      DevGroupId = "${env:PBI_DEV_GROUP_ID}"
      UserName = "${env:PPU_USERNAME}";
      Password = "${env:PPU_PASSWORD}";
      BuildVersion = "${env:BUILD_SOURCEVERSION}";
    }

    Write-Host ($Opts | Format-Table | Out-String)    
    #Set Password as Secure String

    $Secret = $Opts.Password | ConvertTo-SecureString -AsPlainText -Force
    $Credentials = [System.Management.Automation.PSCredential]::new($Opts.UserName,$Secret)
    #Connect to Power BI
    $ConnectionStatus = Connect-PowerBIServiceAccount -Credential $Credentials 
    
    #Setup variables to be used for connections
    $__PBIFileToTest = Get-PowerBIReport -WorkspaceId $Opts.BuildGroupId -Name $PBIFile
    $BuildWS = Get-PowerBIWorkspace -Id $Opts.BuildGroupId

    #Replace https with powerbi
    $PBIEndpoint = $Opts.PBIAPIUrl.Replace("https","powerbi")

    # Add Title to property for use later
    $__PBIFileToTest | Add-Member -NotePropertyName Title -NotePropertyValue $PBIFile
    
    $__PBIFileToTest | Should -Not -BeNullOrEmpty
  }
  else #Running locally
  {    
    Write-Host -ForegroundColor Cyan "Running tests on the local machine."
    #Load Modules
    $WorkingDir = (& pwd) 
    Import-Module $WorkingDir\Pbi\TestingScripts\Custom\Get-PowerBIReportsOpenedLocally.psm1 -Force
    #Now retrieve files that are opened currently
    # Check if we have this cached in global
    $CachedFilesOpened = Get-Variable -Name "PBIFileOpened_Settings" -Scope Global -ValueOnly -ErrorAction:Ignore
    if($CachedFilesOpened)
    {
      $PBIFilesOpened = $CachedFilesOpened
    }
    else
    { 
      #get data since cache doesn't exist
      $PBIFilesOpened = Get-PowerBIReportsOpenedLocally
      # Save to global variable
      New-Variable -Name "PBIFileOpened_Settings" -Value $PBIFilesOpened -Scope Global -Force
    }
    $IsLocal = $True
    # Make sure we got files back
    $PBIFilesOpened | Should -Not -BeNullOrEmpty
    $__PBIFileToTest = $null
    #Check to see if its the right file
    foreach ($X in $PBIFilesOpened) {
      if ($X.Title -eq $PBIFile) {
        $__PBIFileToTest = $X
      }
    }
  
    # Checking to see if the file is open to conduct a test
    if ($__PBIFileToTest) {
      $IsFileOpen = $true
      $__PBIFileToTest | Should -Not -BeNullOrEmpty
    }
    {
      $IsFileOpen = $false
    }
  }#end if check for azure pipelines or locally
}

#Get Configuration Files
And "we have the following properties"{
  param($Data)

  $Config = $Data | ConvertFrom-Json

  $Config.TabularEditorPath | Should -Not -BeNullOrEmpty
  $Config.SchemaScriptPath | Should -Not -BeNullOrEmpty
}


#region SCENARIO steps
# Retrieve test files
Given 'we have the (?<TestFile>[a-zA-Z\s].*) file' {
  param($TestFile)
  if ($IsFileOpen -or $IsLocal -eq $False) {
    #Get dax files in this folder
    $FilePathToTest = "pbi\$($__PBIFileToTest.Title)"
    if($IsLocal -eq $False)
    {
      $FilePathToTest = "pbi/$($__PBIFileToTest.Name)"
    }#end devops check

    $DaxFilesInFolder = Get-ChildItem -Path $FilePathToTest | Where-Object { $_ -like "*.*dax" }
    #Write-Host ($DaxFilesInFolder | Format-Table | Out-String)    
    #See if we can find the test file amongst those in the folder  
    $FileToTest = $DaxFilesInFolder | Where-Object { $_.BaseName -eq $TestFile }
    $FileToTest | Should -Not -BeNullOrEmpty 
  }#end if file open check

  #Check to make sure we handle else branch
  ($IsFileOpen -or $IsLocal -eq $False)| Should -Be $True
}

# Run through test files
Then 'the (?<TestFile>[a-zA-Z\s].*) file should pass its tests' {
  param($TestFile)
  #Load Modules
  if($IsLocal)
  {
    $WorkingDir = (& pwd)
    Import-Module $WorkingDir\Pbi\TestingScripts\Custom\Write-Issue.psm1 -Force    
  }
  else
  {
    $WorkingDir = (& pwd) -replace "\\", '/'
    Import-Module $WorkingDir/Pbi/TestingScripts/Custom/Write-Issue.psm1 -Force
  }

  #Run if the file is open locally or when are in the Azure Pipelines
  if ($IsFileOpen -or $IsLocal -eq $False) {
    #Set Failure count to zero
    $FailureCount = 0
    if ($TestFile) {
      Write-Host -ForegroundColor Cyan "Running Tests within $($TestFile)"
    
      #Connect to Power BI and run DAX Query
      if($IsLocal)
      {
        $Result = Invoke-ASCmd -Server "localhost:$($__PBIFileToTest.Port)" `
        -Database $__PBIFileToTest.DatabaseName `
        -InputFile $FileToTest.FullName
      }
      else
      {
        $Result = Invoke-ASCmd -Server "$($PBIEndpoint)/$($BuildWS.Name)" `
        -Database $__PBIFileToTest.Name `
        -InputFile $FileToTest.FullName `
        -Credential $Credentials `
        -TenantId $Opts.TenantId
      }

      #Remove unicode chars for brackets and spaces from XML node names
      $Result = $Result -replace '_x[0-9A-z]{4}_', '';

      #Load into XML and return
      [System.Xml.XmlDocument]$XmlResult = New-Object System.Xml.XmlDocument
      $XmlResult.LoadXml($Result)

      #Get Node List
      [System.Xml.XmlNodeList]$Rows = $XmlResult.GetElementsByTagName("row")

      #Check if Row Count is 0, no test results.
      if ($Rows.Count -eq 0) {
        $FailureCount += 1
        Write-Issue -IsLocal $IsLocal -Type "error" -Message "Query in test file $($Test.FullName) returned no results."
        $Rows.Count | Should -Not -Be 0
      }#end check of results

      #Iterate through each row of the query results and check test results
      foreach ($Row in $Rows) {
        #Expects Columns TestName, Expected, Actual Columns, Passed
        if ($Row.ChildNodes.Count -ne 4) {
          $FailureCount += 1
          Write-Issue -IsLocal $IsLocal -Type "error" -Message "Query in test file $($Test.FullName) returned no results that did not have 4 columns (TestName, Expected, and Actual, Passed)."
          $Row.ChildNotes.Count | Should -Not -Be 4
        }
        else {
          #Extract Values
          $TestName = $row.ChildNodes[0].InnerText
          $ExpectedVal = $row.ChildNodes[1].InnerText
          $ActualVal = $row.ChildNodes[2].InnerText
          #Compute whether the test passed
          $Passed = ($ExpectedVal -eq $ActualVal) -and ($ExpectedVal -and $ActualVal)

          if (-not $Passed) {
            $FailureCount += 1
            Write-Issue -IsLocal $IsLocal -Type "error" -Message "FAILED!: Test $($TestName). Expected: $($ExpectedVal) != $($ActualVal)"          }
          else {
            Write-Host -ForegroundColor Green "Test $($TestName) passed. Expected: $($ExpectedVal) == $($ActualVal)"
          }

          # After writing to terminal now test that this individual test case passed
          $Passed | Should -Be $True
        }
      }#end foreach row
    }

    #No failures
    $FailureCount | Should -Be 0
  }#end if file open check

  #Check to make sure we handle else branch
  ($IsFileOpen -or $IsLocal -eq $False)| Should -Be $True
}

#region SCHEMA_CHECK steps
And 'we have the schema for "(?<TableName>[a-zA-Z\s].*)"' {
  param($TableName)

  $DatasetSchema = $null
  if($IsLocal) 
  {
    $WorkingDir = (& pwd) 
    Import-Module $WorkingDir\Pbi\TestingScripts\Custom\Get-DatasetSchemaFromLocal.psm1 -Force  

    $DatasetSchema = Get-DatasetSchemaFromLocal -PBIPort $__PBIFileToTest.Port `
    -PBIDatasetID $__PBIFileToTest.DatabaseName `
    -ScriptFileLocation $Config.SchemaScriptPath `
    -TabularEditorPath $Config.TabularEditorPath    
  }
  else #azure pipeline
  {
    $WorkingDir = (& pwd) -replace "\\", '/'
    Import-Module $WorkingDir/Pbi/TestingScripts/Custom/Get-DatasetSchemaFromService.psm1 -Force

    $DatasetSchema = Get-DatasetSchemaFromService -WorkspaceName $BuildWS.Name `
        -DatasetName $__PBIFileToTest.Name `
        -UserName $Opts.UserName `
        -Password $Opts.Password `
        -TenantId $Opts.TenantId `
        -APIUrl $Opts.PBIAPIUrl `
        -ScriptFileLocation ($Config.SchemaScriptPath -Replace "\\", "/") `
        -TabularEditorPath ($Config.TabularEditorPath -Replace "\\", "/")
  }#end check for local

  $DatasetSchema | Should -Not -BeNullOrEmpty
}

# Should be contain or match for the parameter
Then 'it should (?<ContainOrMatch>\S*) the schema defined as follows:'{
  param($ContainOrMatch, $Table)

  #Load Modules
  if($IsLocal)
  {
    $WorkingDir = (& pwd)
    Import-Module $WorkingDir\Pbi\TestingScripts\Custom\Write-Issue.psm1 -Force    
  }
  else
  {
    $WorkingDir = (& pwd) -replace "\\", '/'
    Import-Module $WorkingDir/Pbi/TestingScripts/Custom/Write-Issue.psm1 -Force
  }

  foreach($Row in $Table)
  {
    Write-Host -ForegroundColor Cyan "Checking for $($Row.Name) as $($Row.Type) with format: $($Row.Format) exists."
    #Check Name, Type, and Format
    $TableSchema = $DatasetSchema | Where-Object {$_.Table -eq $TableName}

    #Write-Host ($TableSchema | Format-Table | Out-String)

    #Make sure you get a schema back
    $TableSchema | Should -Not -BeNullOrEmpty

    $Check = $TableSchema | Where-Object -FilterScript { $_.Name -eq $Row.Name -and $_.DataType -eq $Row.Type -and $_.FormatString -eq $Row.Format }
    # Write Issue is format fails
    if([string]::IsNullOrEmpty($Check))
    {
      Write-Issue -IsLocal $IsLocal -Type "error" -Message "Check for $($Row.Name) as $($Row.Type) with format: $($Row.Format) failed."
    } 
    
    $Check | Should -Not -BeNullOrEmpty
  }# end foreach
  
  # if 'match' then at this point make sure no additional columns
  if($ContainOrMatch -eq 'match')
  {
    #Number of Columns should match
    $Table.Count | Should -Be $TableSchema.Length
  }
}

#region REGEX steps
Given 'we have a table called "(?<TableName>[a-zA-Z\s].*)"' {
  param($TableName)

  #Build Query
  $TableQuery = "SELECT * FROM `$SYSTEM.TMSCHEMA_TABLES WHERE [Name] = '$($TableName)'"

  #Connect to Power BI and run DAX Query
  if($IsLocal)
  {
    $Result = Invoke-ASCmd -Server "localhost:$($__PBIFileToTest.Port)" `
    -Database $__PBIFileToTest.DatabaseName `
    -Query $TableQuery
  }
  else
  {
    $Result = Invoke-ASCmd -Server "$($PBIEndpoint)/$($BuildWS.Name)" `
    -Database $__PBIFileToTest.Name `
    -Query $TableQuery `
    -Credential $Credentials `
    -TenantId $Opts.TenantId
  }#end IsLocal check 

  #Remove unicode chars for brackets and spaces from XML node names
  $Result = $Result -replace '_x[0-9A-z]{4}_', '';

  #Load into XML and return
  [System.Xml.XmlDocument]$XmlResult = New-Object System.Xml.XmlDocument
  $XmlResult.LoadXml($Result)

  #Get Node List
  [System.Xml.XmlNodeList]$Rows = $XmlResult.GetElementsByTagName("row")

  $Rows.Name | Should -Be $TableName
}

# Column Regex
And 'the values of "(?<ColumnName>[a-zA-Z\s].*)" matches this regex: "(?<Regex>[\w\S].*)"' {
  param($ColumnName, $Regex)

  #Load Modules
  if($IsLocal)
  {
    $WorkingDir = (& pwd)
    Import-Module $WorkingDir\Pbi\TestingScripts\Custom\Write-Issue.psm1 -Force    
  }
  else
  {
    $WorkingDir = (& pwd) -replace "\\", '/'
    Import-Module $WorkingDir/Pbi/TestingScripts/Custom/Write-Issue.psm1 -Force
  }

  #Setup Query
  $ValQuery = "EVALUATE DISTINCT(SELECTCOLUMNS ( '$($TableName)', `"Values`", '$($TableName)'`[$($ColumnName)`]))"
  #Connect to Power BI and run DAX Query
  if($IsLocal)
  {
    $Result = Invoke-ASCmd -Server "localhost:$($__PBIFileToTest.Port)" `
    -Database $__PBIFileToTest.DatabaseName `
    -Query $ValQuery
  }
  else
  {
    $Result = Invoke-ASCmd -Server "$($PBIEndpoint)/$($BuildWS.Name)" `
    -Database $__PBIFileToTest.Name `
    -Query $ValQuery `
    -Credential $Credentials `
    -TenantId $Opts.TenantId
  }#end IsLocal check 


  #Remove unicode chars for brackets and spaces from XML node names
  $Result = $Result -replace '_x[0-9A-z]{4}_', '';

  #Load into XML and return
  [System.Xml.XmlDocument]$XmlResult = New-Object System.Xml.XmlDocument
  $XmlResult.LoadXml($Result)

  #Get Node List
  [System.Xml.XmlNodeList]$Rows = $XmlResult.GetElementsByTagName("row")

  if($Rows) #Query got results
  {
      $TempVals = $Rows.Values
  
      #Get what doesn't match
      $TempNoMatches = $TempVals -notmatch $Regex
  
      #Get Unique Values
      $TempNoMatches = $TempNoMatches | Sort-Object | Get-Unique
  
      #Increment counter if regex test fails
      if($TempNoMatches.Count -gt 0)
      {
          $RegexFailCount +=1
      }
  
      #Log errors
      foreach($NoMatch in $TempNoMatches)
      {
          # Regex 
          Write-Issue -IsLocal $IsLocal -Type "error" -Message "$($ColumnName) has failed with value '$($NoMatch)' against regex: '$($Regex)'"
      }

      #We should have no mistmatches
      $TempNoMatches.Length | Should -Be 0
  }  

  #Regex should be present
  $Regex | Should -Not -BeNullOrEmpty
}