# Setup before each feature
BeforeEachFeature{
  
  # Make sure Az Module is installed
  if(Get-Module -ListAvailable -Name "Az"){
    Write-Host "Az module already installed" -ForegroundColor Cyan
  }else{
    Install-Module az -Force -AllowClobber -Scope CurrentUser
  }     

  # Create Folder
  New-Item -Path 'DataFlowsTesting' -ItemType Directory -Force

}

# Make sure to delete 
AfterEachFeature{
  Remove-Item 'DataFlowsTesting' -Force -Recurse
}

# Setup Subscription
Given 'we have access to the Azure Subscription named (?<Subscription>\S*)'{
    param($Subscription)
    $X = Get-AzSubscription -SubscriptionName $Subscription
    $X | Should -Not -BeNullOrEmpty
}

# Storage Account
And 'we have access to the Storage Account named (?<StorageAccountName>\S*)'{
  param($StorageAccountName)
  $SC = New-AzStorageContext -StorageAccountName $StorageAccountName
  $SC | Should -Not -BeNullOrEmpty
}

# model.json
And 'we have the (?<ModelFilePath>\S*) file'{
  param($ModelFilePath)
  Test-Path "$(Get-Location)$ModelFilePath" | Should -Be $True
}

# Check Entity
Given 'we have an entity called (?<EntityName>\S*)'{
  param($EntityName)
  $Data = Get-Content "$(Get-Location)$ModelFilePath" | ConvertFrom-Json
  $Entity = $Data.entities | Where-Object -FilterScript { $_.name -eq $EntityName }
  $Entity | Should -Not -BeNullOrEmpty
}

# Should be contain or match for the parameter
Then 'it should (?<ContainOrMatch>\S*) the schema defined as follows:'{
  param($ContainOrMatch, $Table)
  foreach($Row in $Table)
  {
    Write-Host -ForegroundColor Cyan "Checking for $($Row.Name) or $($Row.Type) exists."
    #Check Name and Type
    $Check = $Entity.attributes | Where-Object -FilterScript { $_.name -eq $Row.Name -and $_.datatype -eq $Row.Type }
    $Check | Should -Not -BeNullOrEmpty
  }# end foreach
  
  # if 'match' then at this point make sure no additional columns
  if($ContainOrMatch -eq 'match')
  {
    #Number of Columns should match
    $Table.Count | Should -Be $Entity.attributes.Count
  }
}

# Retrieve the data file from Azure Storage
And 'we have a data file called (?<Filename>\S*)'{
  param($Filename)
  # Retrieve partitions
  $Partitions = $Entity.partitions

  # Make sure partition exists
  $Partitions | Should -Not -BeNullOrEmpty  
  
  # Make sure no issue building relative URL
  $BlobUrl = $Partitions[0].location
  $PowerBIStr = "/powerbi/"
  $Ind = $BlobUrl.IndexOf($PowerBIStr)

  # Run test that path is valid
  $Ind | Should -Not -Be -1

  # Set Relative Path to File
  $RelUrl = $BlobUrl.SubString($ind + $PowerBIStr.Length).Trim()

  # Set File for use later
  $CSVFilePath = ".\DataFlowsTesting\$($Filename)"

  # Download file
  Get-AzDataLakeGen2ItemContent -Context $SC `
                                -FileSystem "powerbi" `
                                -Destination $CSVFilePath `
                                -Path $RelUrl `
                                -Force  

  # Make sure file exists now
  Test-Path $CSVFilePath | Should -Be $True

  # Setup CSV Content as Object to future tests
  # Get headers
  $Headers = $Entity.attributes.name
  # Convert to Object
  $CSVContent = Get-Content $CSVFilePath | ConvertFrom-Csv -Header $Headers
}

# Row Count Check
Then 'there should be (?<ExpectedCount>\S*) entities returned'{
  param($ExpectedCount)
  #Convert parameter to integer
  $ExpectedCount = [int]$ExpectedCount

  # Get count stat from CSV Content
  $ActualCount = ($CSVContent | Measure-Object)

  # Minus one for headers
  [int]$ActualCount.Count - 1 | Should -Be $ExpectedCount
}

# Unique Count Check
And 'the unique count of (?<ColumnName>\S*) is (?<ExpectedCount>\S*)'{
  param($ColumnName, $ExpectedCount)
  #Convert parameter to integer
  $ExpectedCount = [int]$ExpectedCount

  # Get unique count from column
  $UniqueCount = $CSVContent | Select-Object $ColumnName `
                            | Sort-Object $ColumnName -Unique `
                            | Measure-Object
  # Minus one for headers
  [int]$UniqueCount.Count-1 | Should -Be $ExpectedCount                            
}

# Min/Max Check
And 'the (?<MaxOrMin>\S*) value of (?<ColumnName>\S*) is (?<ExpectedCount>\S*)'{
  param($MaxOrMin, $ColumnName, $ExpectedCount)
 
  # Retrieve array of values for Column
  $ColValues = $CSVContent | Select-Object -Expand $ColumnName

  # Check if we do maximum or minimum check
  if($MaxOrMin -imatch "^(Maximum|Max|maximum|max)$")
  {
    $Stats = $ColValues | Measure-Object -Maximum
    $ActualValue = $Stats.Maximum
  }else{
    $Status = $ColValues | Measure-Object -Minimum
    $ActualValue = $Status.Minimum
  }# end if

  # Run test
  [int]$ActualValue | Should -Be $ExpectedCount
}

# Column Regex
And 'the values of (?<ColumnName>\S*) matches this regex: "(?<Regex>\S*)"'{
  param($ColumnName, $Regex)
  # Retrieve array of values for Column
  $ColValues = $CSVContent | Select-Object -Expand $ColumnName

  # Check if any of the values don't pass the regex
  $NoMatches = $ColValues -notmatch $Regex
  
  # Run test
  $NoMatches.Count | Should -Be 0
}