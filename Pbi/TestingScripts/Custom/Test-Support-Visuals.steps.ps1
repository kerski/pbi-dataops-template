<#
  Implementation of tests to check visuals in a .pbix file.
#>
Given 'that we have the Report configuration files' {
  if ($IsFileOpen -or $IsLocal -eq $False) {

    #Get dax files in this folder
    $WorkingDir = (& pwd)
    $RptLvl_ConfigPath = "pbi\$($__PBIFileToTest.Title)\PbixProj\Report\config.json"
    $RptLvl_ReportJsonPath= "pbi\$($__PBIFileToTest.Title)\PbixProj\Report\report.json"
    $SecLvl_ConfigDir = "pbi\$($__PBIFileToTest.Title)\PbixProj\Report\sections\*\config.json" 
    $VzLvl_ConfigDir = "pbi\$($__PBIFileToTest.Title)\PbixProj\Report\sections\*\visualContainers"
    $FolderPath = "pbi\$($__PBIFileToTest.Title)\PbixProj"
    # Module Paths
    $LoadWriteIssuePath = "$($WorkingDir)\Pbi\TestingScripts\Custom\Write-Issue.psm1"
    $LoadFlattenObj = "$($WorkingDir)\Pbi\TestingScripts\Custom\ConvertTo-FlatObject.psm1"
    $LoadConfigPath = "$($WorkingDir)\Pbi\TestingScripts\Custom\Get-PBIToolsConfigurations.psm1"
    # Used for logging and not failing
    $FailuresAreSilent = $False
    # Switch to forward slash to load correct in pipeline
    if($IsLocal -eq $False)
    {
      $WorkingDir = (& pwd) -replace "\\", "/"
      $RptLvl_ConfigPath = $RptLvl_ConfigPath -replace "\\", "/"
      $RptLvl_ReportJsonPath= $RptLvl_ReportJsonPath-replace "\\", "/"
      $SecLvl_ConfigDir = $SecLvl_Config -replace "\\", "/"      
      $VzLvl_ConfigDir = $VzLvl_ConfigDir -replace "\\", "/"
      $FolderPath = $FolderPath -replace "\\", "/"
      $LoadWriteIssuePath = $LoadWriteIssuePath -replace "\\", "/"
      $LoadFlattenObj = $LoadFlattenObj -replace "\\", "/"   
      $LoadConfigPath = $LoadConfigPath -replace "\\", "/" 
    }#end devops check

    #Load Modules
    Import-Module $LoadConfigPath -Force  

    # Check if we have this cached in global
    $CachedRptSettings = Get-Variable -Name "$($__PBIFileToTest.Title)_Settings" -Scope Global -ValueOnly -ErrorAction:Ignore

    if($CachedRptSettings)
    {
        $RptSettings = $CachedRptSettings
    }
    else # Retrieve configuration
    {
        # Get Configuration
        $RptSettings = Get-PBIToolsConfigurations -FolderPath $FolderPath -FlattenObjModulePath $LoadFlattenObj
        # Save to global variable
        New-Variable -Name "$($__PBIFileToTest.Title)_Settings" -Value $RptSettings -Scope Global -Force
    }

    # Make sure we loaded the report settings
    $RptSettings | Should -Not -BeNullOrEmpty
  }
  else
  {
    #Check to make sure we handle else branch
    ($IsFileOpen -or $IsLocal -eq $False)| Should -Be $True  
  }
}

# Clean up global variables
AfterEachFeature -Tags Visual {
  #Delete Global Variables used for testing and performance
  $PBIFiles = Get-ChildItem -Path "./pbi" -Recurse | Where-Object {$_ -like "*.pbix"}

  foreach($TempFile in $PBIFiles){
      $FileNameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($TempFile.FullName) 
      Remove-Variable -Name "$($FileNameNoExt)_Settings" -Scope Global -ErrorAction:Ignore
  }#end foreach

}

<#
  VISUAL TESTS
#>

<#
  Retrieve Visual and Section Information for use in subsequent tests
#>
Given 'that we have the (?<VisualType>[0-9a-zA-Z_].*) with the ID (?<VisualID>[0-9a-zA-Z].*) located in section: (?<Section>[a-zA-Z\s].*). Config Path: (?<ConfigPath>(\\[^\/]+))'{
  param($VisualType, $VisualID, $Section, $ConfigPath)
  # Get global variable with settings
  $__CachedRptSettings = Get-Variable -Name "$($__PBIFileToTest.Title)_Settings" -Scope Global -ValueOnly

  # Get Section, use two underscores to signify saving for use in downstream
  $__Section = @($__CachedRptSettings.Report.Sections | Where-Object { $_.Settings.displayName -eq $Section})
  # Get Visual
  $__Visual = $__Section.Visuals | Where-Object { $_.Config.name -eq $VisualID}

  # Check to make sure the sections and visuals exists
  $__Section.Length | Should -Be 1
  $__Visual | Should -Not -BeNullOrEmpty
}

<#
Make sure every visual has a title for accessibility
#>
Then 'the visual should have a title. Config Path: (?<ConfigPath>(\\[^\/]+))'{
  # Default that title doesn't exist
  $HasTitle = $False

  #if group visual check different property path
  if($__Visual.Config.singleVisualGroup)
  {
      if($__Visual.Config.singleVisualGroup.displayName -ne "''"){
          $HasTitle = $True
      }#end empty string test
  }
  else{
      #Check for the vcObjects.title properties
      if(($__Visual.Config.singleVisual.vcObjects.title.properties.text.expr.Literal.Value `
      -and $__Visual.Config.singleVisual.vcObjects.title.properties.text.expr.Literal.Value -ne "''") `
      -or $__Visual.Config.singleVisual.vcObjects.title.properties.text.expr.Aggregation `
      -or $__Visual.Config.singleVisual.vcObjects.title.properties.text.expr.Measure){
          $HasTitle = $True
      }
  }#end check for single visual group

  $HasTitle | Should -Be $True
}

<#
Ensure alt text is added to all non-decorative visuals on the page.
#>
And 'ensure alt text is added to the visual if it is a non-decorative visual. Config Path: (?<ConfigPath>(\\[^\/]+))'{
  param($VisualType, $VisualID)

  # Check if decoroative
  # Decorative visuals have a tab order less than zero (e.g., -999000) 
  # Also make sure non group visual
  $IsDecor = $__Visual.Config | Where-Object { [int]$_.layouts.position.tabOrder -lt 0 `
                                                  -or $_.singleVisualGroup }     
                  
  If($IsDecor) # Decorative
  {
      $IsDecor | Should -Not -BeNullOrEmpty
  }
  else 
  {
      # Check for the altText properties
      # Text is should not be '' wrapped in double quotes
      # Assume presence of expr.Aggregation or expr.Measure means calculation will return text 
      $VzWithAltText = @($__Visual.Config | Where-Object { ($_.singleVisual.vcObjects.general.properties.altText.expr.Literal `
                     -and $_.singleVisual.vcObjects.general.properties.altText.expr.Literal.Value -ne "''") `
                     -or $_.singleVisual.vcObjects.general.properties.altText.expr.Aggregation `
                     -or $_.singleVisual.vcObjects.general.properties.altText.expr.Measure})

      
      $VzWithAltText.Length | Should -Be 1
  
  }#end check for decor
}

<#
  And all visual level filters are hidden or locked in the filter pane
  This helps reduce confusion with report-level or page-level filters in the filter pane
  Note: Default fields in visuals will not display in filters.json if not explicitly filtered, locked or hidden
  Therefore this test only works for testing actively filtered fields
#>
And 'all visual level filters for the visual are hidden or locked in the filter pane. Config Path: (?<ConfigPath>(\\[^\/]+))'{    
  # Short cut if filter pane is not visible
  # config --> outspacePane.properties.visible.expr.Literal.Value
  if($__CachedRptSettings.Report.Config.objects.outspacePane.properties.visible.expr.Literal.Value -eq $false)
  {
      $__CachedRptSettings.Report.Config.objects.outspacePane.properties.visible.expr.Literal.Value | Should -Be "false"
  }
  else 
  {
    # Check to make sure all visual level filters are locked or hidden altText properties
    # Note: Visuals without filters have empty array and don't produce a json file
    $ExposedVzs = @()
    $VzF = $__Visual.Filters
    if($VzF)
    {
      # Now look for all implicit measures if they have been explicitly defined
      $AllImplicitFiltersExplicityDefined = $True
      foreach($Imp in $VzF._ImplicitFilters){
          $IsFound = $False
          #Write-Host $Imp
          foreach($Exp in $VzF._ExplicitFilters)
          {
          #Check if implicit column/measure name exists
              $Match = $Imp -match $Exp

              if($Match)
              {
              $IsFound = $True
              #Write-Host "Match E($($Exp)) in I($($Imp))"
              }
          }#end Explicit Filters

          if($IsFound -eq $False) #if here, break but we don't have all implicits, explicity defined 
          {
          $AllImplicitFiltersExplicityDefined = $False
          break;
          }
      }#end Implicit iteration

      if($AllImplicitFiltersExplicityDefined -eq $False) # We don't have all implicits, explicity defined 
      {
          $ExposedVzs += $VzF 
      }
      else{ #if here they explicit filters match implicit, so we need to double check hidden and locked for each element
          foreach($F in $VzF.Settings)
          {
              $TestExposure = $F | Where-Object { (-not $_.isHiddenInViewMode -or $_.isHiddenInViewMode -eq $False) `
                                                  -and (-not $_.isLockedInViewMode -or $_.isLockedInViewMode -eq $False) }
              if($TestExposure)
              {
              $ExposedVzs += $VzF
              break;
              }#end check for exposure
          }#end foreach filters
      }#$AllImplicitFiltersExplicityDefined -eq $False
    }
    else{
      $ExposedVzs += $VzF
    }# end if _Filters exist check
    @($ExposedVzs).Count | Should -Be 0
  }# end check if filter pane has been hidden
  
}   

<#
  SECTION TESTS
#>
Given 'that we have the section: (?<Section>[a-zA-Z\s].*)'{
  param($Section)
  # Get global variable with settings
  $__CachedRptSettings = Get-Variable -Name "$($__PBIFileToTest.Title)_Settings" -Scope Global -ValueOnly

  # Get Section, use two underscores to signify saving for use in downstream
  $__Section = @($__CachedRptSettings.Report.Sections | Where-Object { $_.Settings.displayName -eq $Section})

  # Check to make sure the sections and visuals exists
  $__Section.Length | Should -Be 1
}

<#
Make sure the sections (tabs) are using a background image to enforce branding.
#>
Then 'the section has their (?<BackgroundSetting>(canvas|wallpaper)) set with the background image named "(?<BackgroundImg>[\w\s].*)"'{
  param($BackgroundSetting, $BackgroundImg)

  # Assume tests to fail
  if($BackgroundSetting -eq "wallpaper"){
    # Check if the wallpaper image has the background image supplied
    if($__Section.Config.objects.outspace.properties.image.image.name.expr.Literal -and `
       ($__Section.Config.objects.outspace.properties.image.image.name.expr.Literal.Value -eq "$($BackgroundImg)" -or `
        $__Section.Config.objects.outspace.properties.image.image.name.expr.Literal.Value -eq "'$($BackgroundImg)'"))
    {
        $PassesBackgroundSetting = $True
    }
  }
  else # canvas
  {
    # Check if the canvas has the background image supplied
    if($__Section.Config.objects.background.properties.image.image.name.expr.Literal -and `
       ($__Section.Config.objects.background.properties.image.image.name.expr.Literal.Value -eq "$($BackgroundImg)" -or `
        $__Section.Config.objects.background.properties.image.image.name.expr.Literal.Value -eq "'$($BackgroundImg)'"))
    {
        $PassesBackgroundSetting = $True
    }
  }#end check canvas or wallpaper

  $PassesBackgroundSetting | Should -Be $True
}

<#
Make sure the sections have a certain dimension.
#>
And 'the section has a width of (?<Width>\d+px) and a height of (?<Height>\d+px)'{
  param($Width, $Height)

  # Get numbers from width and height
  $W_Size = [int]$Width.Substring(0,$Width.Length-2)
  $H_Size = [int]$Height.Substring(0,$Height.Length-2)

  # Check width and height now
  [int]$__Section.Settings.width | Should -Be $W_Size
  [int]$__Section.Settings.height | Should -Be $H_Size
}

<#
  REPORT TESTS
#>

<#
  Validate we have report level settings
#>
Given 'that we have the report settings'{
  # Get global variable with settings
  $__CachedRptSettings = Get-Variable -Name "$($__PBIFileToTest.Title)_Settings" -Scope Global -ValueOnly

  $__CachedRptSettings | Should -Not -BeNullOrEmpty
}

<#
Make sure that a specific tab in the Power BI Report is shown by default
when someone opens the report
#>
Then 'the default section is the (?<Order>\d{1,2}(?:st|nd|rd|th)) section' {
  param($Order)
  
  # Remove last two characters and substract by 1 to get zero based order
  $OrderNum = [int]$Order.SubString(0,$Order.Length-2) - 1
   
  # Active Section comparison increases by 1 because people are not familiar with zero based start.
  ([int]$__CachedRptSettings.Report.Config.activeSectionIndex) + 1 | Should -Be ($OrderNum + 1)
}

<#
Make sure a specific custom theme is being used.
#>
And 'the report uses a custom theme named "(?<ThemeName>[a-zA-Z\s].*)"' {
  param($ThemeName)
  #Check if customTheme name starts with name.
  #We use starts with because pbi-tools/Microsoft add suffix (typically numbers) to the end of the name
  $UsesCustomTheme = $False
  
  if($__CachedRptSettings.Report.Config.themeCollection.customTheme -and `
      $__CachedRptSettings.Report.Config.themeCollection.customTheme.name.StartsWith($ThemeName)){
      $UsesCustomTheme = $True
  }#end check for custom theme

  $UsesCustomTheme | Should -Be $True
}

<#
  Visual Options: Hide the visual header in reading view
#>
Then 'the Visual Option "Hide the visual header in reading view" is (?<Setting>(enabled|disabled))'{
  param($Setting)

  $HideVisualContainerHeader = $__CachedRptSettings.Report.Config.settings.hideVisualContainerHeader
  if($Setting -eq 'enabled')
  {
      $HideVisualContainerHeader | Should -Be $True
  }
  else #disabled
  {
      $HideVisualContainerHeader | Should -BeIn ($False,$null)
  }
}

<#
  Visual Options: Use the modern visual header with updated styling options
#>
Then 'the Visual Option "Use the modern visual header with updated styling options" is (?<Setting>(enabled|disabled))'{
  param($Setting)

  $UseNewFilterPaneExperience = $__CachedRptSettings.Report.Config.settings.useNewFilterPaneExperience
  if($Setting -eq 'enabled')
  {
      $UseNewFilterPaneExperience | Should -Be $True
  }
  else #disabled
  {
      $UseNewFilterPaneExperience | Should -BeIn ($False,$null)
  }
}

<#
  Visual Option: Change default visual interaction from cross highlighting to cross filtering
#>
Then 'the Visual Option "Change default visual interaction from cross highlighting to cross filtering" is (?<Setting>(enabled|disabled))'{
  param($Setting)

  $DefaultFilterActionIsDataFilter = $__CachedRptSettings.Report.Config.settings.defaultFilterActionIsDataFilter
  if($Setting -eq 'enabled')
  {
      $DefaultFilterActionIsDataFilter | Should -Be $True
  }
  else #disabled
  {
      $DefaultFilterActionIsDataFilter | Should -BeIn ($False,$null)
  }
}

<#
  Persistent filters: Don't allow end user to save filters on this file in the Power BI Service
#>
Then 'the Persistent Filters setting is (?<Setting>(enabled|disabled))'{
  param($Setting)

  $PersistentFilterSetting = $__CachedRptSettings.Report.Config.settings.isPersistentUserStateDisabled

  if($Setting -eq 'enabled')
  {
      $PersistentFilterSetting | Should -Be $true
  }
  else #disabled
  {
      $PersistentFilterSetting | Should -BeIn ($false,$null)
  }
}

<#
  Export Data
  1 - Allow end users to export data with current layout and summarized data from the Power BI Service or Power BI Report Server
  2 - Allow end users to export data with current layout, summarized data and underlying data from the service or Report Server
  3 - Don't allow end users to export any data from the service or Report Server 
#>
Then 'the Export data setting is "(?<Setting>(export summarized data only|export summarized and underlying data|no export allowed))"'{
  param($Setting)

  $ExportDataMode = [int]$__CachedRptSettings.Report.Config.settings.exportDataMode
  # Use switch convert text to check integer value in config
  switch ($Setting)
  {
      "export summarized data only" {$ExportDataMode | Should -Be 1}
      "export summarized and underlying data" {$ExportDataMode | Should -Be 0}
      "no export allowed" {$ExportDataMode | Should -Be 2}
  }
}

<#
  Filtering experience: "Allow users to change filter types
#>
Then 'the Filtering experience "Allow users to change filter types" is (?<Setting>(enabled|disabled))'{
  param($Setting)

  $AllowChangeFilterTypes = $__CachedRptSettings.Report.Config.settings.allowChangeFilterTypes
  if($Setting -eq 'enabled')
  {
      $AllowChangeFilterTypes | Should -Be $True
  }
  else #disabled
  {
      $AllowChangeFilterTypes | Should -BeIn ($False,$null)
  }
}

<#
  Filtering experience: "Enable search for the filter pane"
#>
Then 'the Filtering experience "Enable search for the filter pane" is (?<Setting>(enabled|disabled))'{
  param($Setting)

  $DisableFilterPaneSearch = $__CachedRptSettings.Report.Config.settings.disableFilterPaneSearch
  if($Setting -eq 'disabled')
  {
      $DisableFilterPaneSearch | Should -Be $True
  }
  else #enabled
  {
      $DisableFilterPaneSearch | Should -BeIn ($False,$null)
  }
}


<#
 Cross-report drillthrough: "Allow visuals in this report to use drillthrough targets from other reports"
#>
Then 'the Cross-report drillthrough setting "Allow visuals in this report to use drillthrough targets from other reports" is (?<Setting>(enabled|disabled))'{
  param($Setting)

  $UseCrossReportDrillthrough = $__CachedRptSettings.Report.Config.settings.useCrossReportDrillthrough
  if($Setting -eq 'enabled')
  {
      $UseCrossReportDrillthrough | Should -Be $True
  }
  else #disabled
  {
      $UseCrossReportDrillthrough | Should -BeIn ($False,$null)
  }
}

<#
 Personalize visuals: "Allow report readers to personalize visuals to suit their needs"
#>
Then 'the Personalize visuals setting "Allow report readers to personalize visuals to suit their needs" is (?<Setting>(enabled|disabled))'{
  param($Setting)

  $AllowInlineExploration = $__CachedRptSettings.Report.Config.settings.allowInlineExploration
  if($Setting -eq 'enabled')
  {
      $AllowInlineExploration | Should -Be $True
  }
  else #disabled
  {
      $AllowInlineExploration | Should -BeIn ($False,$null)
  }
}

<#
  Developer Mode: "Turn on developer mode for custom visuals for this session"
#>
Then 'the Developer Mode setting "Turn on developer mode for custom visuals for this session" is (?<Setting>(enabled|disabled))'{
  param($Setting)

  $EnableDeveloperMode = $__CachedRptSettings.Report.Config.settings.enableDeveloperMode
  if($Setting -eq 'enabled')
  {
      $EnableDeveloperMode | Should -Be $True
  }
  else #disabled
  {
      $EnableDeveloperMode | Should -BeIn ($False,$null)
  }
}

<#
  Default summarizations: "For aggregated fields, always show the default summarization type"
#>
Then 'the Default summarizations setting "For aggregated fields, always show the default summarization type" is (?<Setting>(enabled|disabled))'{
  param($Setting)

  $UseDefaultAggregateDisplayName = $__CachedRptSettings.Report.Config.settings.useDefaultAggregateDisplayName
  if($Setting -eq 'enabled')
  {
      $UseDefaultAggregateDisplayName | Should -Be $True
  }
  else #disabled
  {
      $UseDefaultAggregateDisplayName | Should -BeIn ($False,$null)
  }
}

<#
  Make sure report-level measures have a prefix so we can distinguish with the measures in the model.
#>
Then 'all report-level measures have a prefix: "(?<Prefix>[^\.,;`:\/\\\*|?\""&%$!\+=\(\)\[\]\{\}\<\>]+)"'{
  param($Prefix)

  $RptLvl_Measures = @()

  # if properties exist then save measures to array
  if($__CachedRptSettings.Report.Config.modelExtensions.entities.measures)
  {
    $RptLvl_Measures = @($__CachedRptSettings.Report.Config.modelExtensions.entities.measures)
  }
  
  # Assume pass by default
  $AllHaveRightPrefix = $True

  foreach($M in $RptLvl_Measures){
    if($M.name.StartsWith($Prefix) -eq $False){
      $AllHaveRightPrefix = $False
      break; # because this will make sure the test fails because we found a measure that doesn't have the prefix
    }#end if
  }#end foreach

  $AllHaveRightPrefix | Should -Be $True
}