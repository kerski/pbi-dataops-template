<#
    .SYNOPSIS
    Combines Multiple json files from Pbix Project and return as an object

    .DESCRIPTION
    Combines Multiple json files from Pbix Project and return as an object.  This module supports
    extracting and parsing json files for use in automated testing.

    .PARAMETER FolderPath
    Path to Pbix Project main folder

    .PARAMETER IsLocal
    True if running on local machine, False if running on a Build Agent

    .PARAMETER FlattenObjModulePath
    Module depends on the ability to support flatten objects.  This is the path to the ConvertTo-FlatObject module file.

    .OUTPUTS
      $Settings = [PSCustomObject]@{
        Report = [PSCustomObject]@{
          Config = {}
          Filters = {}
          ReportConfig = {}
          Sections = [PSCustomObject]@{
            Config = {}
            Filters = {}
            Visuals = {}
            Settings = {} #section.json
          }
        }
      }

    .EXAMPLE
    $TestObj = Get-PBIToolsConfigurations -FolderPath $FolderPath `
                                        -FlattenObjModulePath $FlattenObjModulePath 
#>
Function Get-PBIToolsConfigurations { 
  [CmdletBinding()]
  Param( 
  [Parameter(Position = 0, Mandatory = $true)][String]$FolderPath,
  [Parameter(Mandatory = $false)][Boolean]$IsLocal=$true,
  [Parameter(Mandatory = $false)][String]$FlattenObjModulePath=".\ConvertTo-FlatObject.psm1"
  ) 
  Process { 
      ### SETUP ###
      #Check if Folder Path is accessible
      if (-not (Test-Path -Path $FolderPath)) {
          Throw "Folder Path: $($FolderPath), cannot be reached."
      }#end if

      #Setup Directory 
      $RptLvl_ModelDir = "$($FolderPath)\Model"
      $RptLvl_ReportDir = "$($FolderPath)\Report"
      $SecLvl_ConfigDir = "$($FolderPath)\Report\sections\*\config.json"
      $SecLvl_SectionDir = "$($FolderPath)\Report\sections\*\section.json"         
      $VzLvl_ConfigDir = "\visualContainers"

      #Report Level paths
      $RptLvl_ConfigJsonPath = "$($FolderPath)\Report\config.json"
      $RptLvl_FilterJsonPath = "$($FolderPath)\Report\filters.json"        
      $RptLvl_ReportJsonPath = "$($FolderPath)\Report\report.json"


      # Switch back slash to forward slash if running in VM or Build Agent
      if($IsLocal -eq $false)
      {
        $FolderPath -replace "\\", "/"
        $RptLvl_ModelDir = $RptLvl_ModelDir -replace "\\", "/"
        $RptLvl_ReportDir = $RptLvl_ReportDir -replace "\\", "/"
        $SecLvl_ConfigDir = $SecLvl_ConfigDir -replace "\\", "/"
        $SecLvl_SectionDir = $SecLvl_SectionDir -replace "\\", "/"
        $VzLvl_ConfigDir = $VzLvl_ConfigDir -replace "\\", "/"  

        $RptLvl_ConfigJsonPath = $RptLvl_ConfigJsonPath -replace "\\", "/"  
        $RptLvl_FilterJsonPath = $RptLvl_FilterJsonPath -replace "\\", "/"         
        $RptLvl_ReportJsonPath = $RptLvl_ReportJsonPath -replace "\\", "/"           
      }

      # Make sure Report folder (which should exist with pbi-tool extract)
      if(-not (Test-Path -Path $RptLvl_ReportDir))
      {
        Throw "Folder Path: $($FolderPath), does not contain a Report folder as expected with pbi-tools."
      }       

      # Make sure you can load the module
      if(-not (Test-Path -Path $FlattenObjModulePath))
      {
        Throw "Flatten Config Module located at: $($FlattenObjModulePath) was not accessible at the path provided."
      }
      
      #Load Flatten Object Module 
      Import-Module $FlattenObjModulePath -Force  
      
      # Build Object for hydration
      $Settings = [PSCustomObject]@{
        Report = [PSCustomObject]@{
          Config = {}
          Filters = {}
          ReportConfig = {}
          Sections = [PSCustomObject]@{
            Config = {}
            Filters = {}
            Visuals = @()
            Settings = {} #section.json
          }
        }
      }

      ### END SETUP ###

      ### LOAD OBJECTS ###
      
      #REPORT LEVEL
      #Convert Report level config to object
      $Settings.Report.Config = Get-Content -Path $RptLvl_ConfigJsonPath | ConvertFrom-Json
      $Settings.Report.Config | Add-Member -NotePropertyName _Path $RptLvl_ConfigJsonPath
      $Settings.Report.ReportConfig = Get-Content -Path $RptLvl_ReportJsonPath | ConvertFrom-Json

      #Test is a chance report level fitlers doesn't exist so check
      if(Test-Path $RptLvl_FilterJsonPath)
      {
        $Settings.Report.Filters = @(Get-Content -Path $RptLvl_FilterJsonPath | ConvertFrom-Json)
      }
 
      #SECTION LEVEL
      #Retrieve Section Level Config Files
      $SecLvl_ConfigFiles = Get-ChildItem -Path $SecLvl_ConfigDir -Filter config.json
      $SecLvl_SecJsonFiles = Get-ChildItem -Path $SecLvl_SectionDir -Filter section.json

      #Convert Section Config.json and Section.Json Files to objects from json
      $SecLvl_ConfigObjs = @($SecLvl_ConfigFiles | ForEach-Object { (Get-Content -Raw $_.FullName | ConvertFrom-Json) })
      $SecLvl_SectionObjs = @($SecLvl_SecJsonFiles | ForEach-Object { (Get-Content -Raw $_.FullName | ConvertFrom-Json) })
      
      $I=0
      $SecLvl_Array = @()
      for(;$I -lt $SecLvl_ConfigObjs.Count;$I++)
      {
            #Add Path
            $SecLvl_ConfigObjs[$I] | Add-Member -NotePropertyName _Path -NotePropertyValue $SecLvl_ConfigFiles[$I].FullName
            $SecLvl_ConfigObjs[$I] | Add-Member -NotePropertyName _Directory -NotePropertyValue $SecLvl_ConfigFiles[$I].Directory              
            $SecLvl_SectionObjs[$I] | Add-Member -NotePropertyName _Path -NotePropertyValue $SecLvl_ConfigFiles[$I].FullName
            $SecLvl_SectionObjs[$I] | Add-Member -NotePropertyName _Directory -NotePropertyValue $SecLvl_ConfigFiles[$I].Directory

            $SecLvl_Array += [PSCustomObject]@{
                                                Config = $SecLvl_ConfigObjs[$I]
                                                Settings = $SecLvl_SectionObjs[$I]
                                              }
      }# end adding File Info

      #Assign Visuals to Sections
      $Settings.Report.Sections = $SecLvl_Array

      #VISUAL LEVEL
      $SecIndex = 0
      foreach($Sec in $Settings.Report.Sections.Settings){
          #Assign to Sections.Visuals
          $Settings.Report.Sections[$SecIndex] | Add-Member -NotePropertyName Visuals -NotePropertyValue {}

          #Retrieve Visual Config Files
          $VzLvl_ConfigFiles = Get-ChildItem -Path "$($Sec._Directory)$($VzLvl_ConfigDir)" -Recurse -Filter config.json
          #Convert Visual Configuration Files to objects from json          
          $VzLvl_ConfigObjs = @($VzLvl_ConfigFiles | ForEach-Object { (Get-Content -Raw $_.FullName | ConvertFrom-Json) })

          #Iterate over files and add name (unique id) to reference later
          $VzLvl_Array = @()
          $X=0
          for(;$X -lt $VzLvl_ConfigObjs.Count;$X++)
          {
              #Add Path
              $VzLvl_ConfigObjs[$X] | Add-Member -NotePropertyName _Path -NotePropertyValue $VzLvl_ConfigFiles[$X].FullName
              $VzLvl_ConfigObjs[$X] | Add-Member -NotePropertyName _Directory -NotePropertyValue $VzLvl_ConfigFiles[$X].Directory
            
              #Handle implicit and explicit filters for each visual
              # Check if visual is not elements (textbox, shape, actionButton, image, etc.)
              # Also exclude if visual container is a group
              $IsVzConfigNonElement = ($VzLvl_ConfigObjs[$X].singleVisual.visualType -ne "textbox" -and `
                                    $VzLvl_ConfigObjs[$X].singleVisual.visualType -ne "shape" -and `
                                    $VzLvl_ConfigObjs[$X].singleVisual.visualType -ne "actionButton" -and `
                                    $VzLvl_ConfigObjs[$X].singleVisual.visualType -ne "image" -and `
                                    $VzLvl_ConfigObjs[$X].singleVisual.visualType -ne "basicShape" -and `
                                    -not $VzLvl_ConfigObjs[$X].singleVisualGroup)        

              <#Write-Host $VzLvl_ConfigObjs[$X]._Path
              Write-Host $IsVzConfigNonElement#>
              
              #Setup Implicity Filters Temporary Array
              $ImplicitVals = @()        
              $ExplicitFilters = @()
              $FilterSettings = $null
              if($IsVzConfigNonElement){
                # Projects have implicit filters at the visual level identifies by queryRef
                # Flatten object to get queryRef regardless of visual type
                $TempFlatObj = @{}
                if($VzLvl_ConfigObjs[$X].singleVisual.projections)
                {
                  $TempFlatObj = ConvertTo-FlatObject $VzLvl_ConfigObjs[$X].singleVisual.projections -Include queryRef
                }#end if

                # Store ImplicitVals in Array
                foreach($Prop in $TempFlatObj.PSObject.Properties)
                {
                  $ImplicitVals += $Prop.Value 
                } #end foreach

                <#Write-Host @($ImplicitVals)
                Write-Host "---"#>            

                $VzFPath = Get-ChildItem -Path $VzLvl_ConfigObjs[$X]._Directory -Filter filters.json
                $RawText = Get-Content -Raw $VzFPath.FullName
                # We need to account for visual filters that have no settings
                # so check for that so we can have an empty json array
                $Result = $RawText
                if($RawText -eq "[]")
                {
                  $Result = "{Filters:[]}"
                }
                else{
                  $Result = "{Filters:$($RawText)}"
                }
                $JsonResult= ($Result | ConvertFrom-Json)

                $FilterSettings = $JsonResult.Filters
                #Build array of explicit filters
                foreach($F in $JsonResult.Filters)
                {
                  $TempFlatObj = ConvertTo-FlatObject $F.expression -Include Entity, Property
                  
                  $RefToElement = ""
                  $PropIndex = 0
                  # Assumes first value is the Entity and second in Measure/Column
                  foreach($Prop in $TempFlatObj.PSObject.Properties)
                  {
                    if($PropIndex -eq 0)
                    {
                      $RefToElement = "$($Prop.Value)."
                    }
                    else{ #Assume second
                      $RefToElement += $Prop.Value
                    }
                    $PropIndex += 1
                  } #end foreach Prop
                  $ExplicitFilters += $RefToElement
                }#end foreach   
              }#end IsVzConfigNonElement           

              #Add custom object to array
              $VzLvl_Array += [PSCustomObject]@{
                Config = $VzLvl_ConfigObjs[$X]
                Filters = [PSCustomObject]@{
                  _ImplicitFilters = @($ImplicitVals)
                  _ExplicitFilters = @($ExplicitFilters)
                  Settings = $FilterSettings
                }
              }#end adding object              
            }#end check is Visual Config
            
          #Add array to visuals properties
          $Settings.Report.Sections[$SecIndex].Visuals = $VzLvl_Array

          # Increment Index for Section
          $SecIndex += 1
      }#end for each section
      return $Settings
  }#end process
}#end function

Export-ModuleMember -Function Get-PBIToolsConfigurations