<#
    Author: John Kerski
    .SYNOPSIS
        Generate Feature files for testing

    .DESCRIPTION
        Generate Feature files for testing
        
    .PARAMETER FileName
        The name of the Power BI file 
        
        Example: 
            -FileName SampleModel

    .PARAMETER Type
        Acceptable values are Visuals

        Example:
            -Type Visuals

    .EXAMPLE
        ./Generate-Tests.ps1 -FileName "SampleModel" -Type Visuals
    #>
param([String]$FileName, [String]$Type)

#Setup TLS 12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#Import Appropriate Modules
$WorkingDir = (& pwd) 
Import-Module $WorkingDir\Pbi\TestingScripts\Pester\4.10.1\Pester.psm1 -Force
Import-Module $WorkingDir\Pbi\TestingScripts\Custom\Get-PBIToolsConfigurations.psm1 -Force
$LoadFlattenObj = "$($WorkingDir)\Pbi\TestingScripts\Custom\ConvertTo-FlatObject.psm1"

# Get Power BI Files
$PBIFiles = Get-ChildItem -Path "./pbi" -Recurse | Where-Object {$_ -like "*.pbix"}

# Check to make sure the FileName exists
$TestFile = $null

if($FileName)
{
    $TestFile = $PBIFiles | Where-Object {$_.Name -like "$($FileName).pbix" -or $_.Name -like $FileName}
    # Check if TestFile has been found
    if(-not $TestFile)
    {
        Write-Host -ForegroundColor Red "$($FileName) could not be found in any of the folders under 'pbi'. If the filename has spaces, please place within double quotes (ex. ""Sample Model"")."
        return
    }
}
else
{
    Write-Host -ForegroundColor Red "FileName not supplied."
    return
}
#end FileName check

#Check Type
if($Type)
{
    $AcceptedValues = @("Visuals")

    if(-not ($AcceptedValues -Contains $Type))
    {
        Write-Host -ForegroundColor Red "Type value: ""$($Type)"" not acceptable value."
        return        
    }
}
else
{
    Write-Host -ForegroundColor Red "Type value not supplied"
    return    
}#end Type Check

#Now generate Visuals
if($Type -eq "Visuals"){

    $PbixProjPath = "$($TestFile.DirectoryName)\PbixProj"
    $Input_VisualTemplatePath = ".\Pbi\TestingScripts\Custom\Templates\Visuals.feature.template"
    $Input_VisualStepsPath = ".\Pbi\TestingScripts\Custom\Templates\Visuals.steps.ps1.template"
    $Output_TemplatePath = "$($TestFile.DirectoryName)\Visuals.feature"
    $Output_StepsPath = "$($TestFile.DirectoryName)\Visuals.steps.ps1"
    $FileNameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($TestFile.VersionInfo.FileName) 
    $Tab = [char]9
    $WorkingDir = (& pwd)

    if((Test-Path $PbixProjPath) -eq $false) # PbixProj folder doesn't exist
    {
        Write-Host -ForegroundColor Red "PbixProj folder does not exist in subfolder 'Pbi\$($FileName)'.  Please run Watch-PBI.ps1 for this Power BI file."
        return        
    }#end PbixProj path test

    # Get Configuration
    $RptSettings = Get-PBIToolsConfigurations -FolderPath $PbixProjPath `
                                              -FlattenObjModulePath $LoadFlattenObj    

    # Build Section Array
    $SecArray = @()
    $VzArray = @()

    foreach($Sec in $RptSettings.Report.Sections)
    {
        # Get Section, use two underscores to signify saving for use in downstream
        $TempSecStr = "$($Tab)|$($Sec.Settings.displayName)|"
        $SecArray += ($TempSecStr)

        foreach($Vz in $Sec.Visuals)
        {
            # Get Visual Information
            # For Visual Type show group or visual type
            $TempVzStr = "$($Tab)|$($Sec.Settings.displayName)|$($Vz.Config.singleVisualGroup.displayName + $Vz.Config.singleVisual.visualType)|$($Vz.Config.name)|$($Vz.Config._Path.SubString($WorkingDir.Path.Length))|"
            $VzArray += ($TempVzStr)
        }#end foreach
    }#end foreach section

    # Get Contents of Template                                              
    $TemplateContent = Get-Content -Path $Input_VisualTemplatePath
    $StepsContent = Get-Content -Path $Input_VisualStepsPath

    # Replace placeholders in template
    $TemplateContent = $TemplateContent -replace '{PBI_FILE}', $FileNameNoExt;
    $TemplateContent = $TemplateContent -replace '{SECTIONS}', ($SecArray -join "`n") 
    $TemplateContent = $TemplateContent -replace '{VISUALS}', ($VzArray -join "`n")

    # Write Filled Out Template to model's folder 
    Out-File -FilePath $Output_TemplatePath -Force -InputObject $TemplateContent
    Out-File -FilePath $Output_StepsPath -Force -InputObject $StepsContent

}#end generate visual file
