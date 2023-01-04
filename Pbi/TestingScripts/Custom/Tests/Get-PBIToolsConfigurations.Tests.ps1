# Note Pester 3 is preinstalled on many Windows 10/11 machines.
# Unistall Pester 3 with this script: https://gist.github.com/nohwnd/5c07fe62c861ee563f69c9ee1f7c9688
Describe 'Get-PBIToolsConfigurations' {
    BeforeAll { 
        Import-Module ..\Get-PBIToolsConfigurations.psm1 -Force

        $BadFolderPath = "..\Fake\File\Path"
        $FolderPath = ".\PbixProj"
        $FolderPathNoReport = "..\.."
        
        $FlattenObjModulePath = "..\ConvertTo-FlatObject.psm1"
        $BadFlattenObjModulePath = "..\Fake\File\Path\ConvertTo-FlatObject.psm1"

        $TestObj = Get-PBIToolsConfigurations -FolderPath $FolderPath `
                                              -FlattenObjModulePath $FlattenObjModulePath        
    }

    #Clean up
    AfterAll {

    }

    #Check if File Exists
    It 'Module should exist' {
        $IsInstalled = Get-Command Get-PBIToolsConfigurations
        $IsInstalled | Should -Not -BeNullOrEmpty
    }

    It 'Should Throw Error when FolderPath cannot be accessed' {
        {Get-PBIToolsConfigurations -FolderPath $BadFolderPath `
                                    -FlattenObjModulePath $FlattenObjModulePath} | Should -Throw
    }

    It 'Should Throw Error when FolderPath does not have the Report subfolder' {
        {Get-PBIToolsConfigurations -FolderPath $FolderPathNoReport `
                                    -FlattenObjModulePath $FlattenObjModulePath} | Should -Throw
    }

    It 'Should Throw Error when ConvertTo-FlatObject cannot be accessed' {
        {Get-PBIToolsConfigurations -FolderPath $FolderPath `
                                    -FlattenObjModulePath $BadFlattenObjModulePath} | Should -Throw
    }

    It 'Should Not Throw Error when FolderPath and ConvertTo-FlatObject can be accessed' {
        {Get-PBIToolsConfigurations -FolderPath $FolderPath `
                                    -FlattenObjModulePath $FlattenObjModulePath} | Should -Not -Throw
    }

    It 'Should Have Report.Config with activeSectionIndex' {
         $TestObj.Report.Config | Should -Not -BeNullOrEmpty
         #Should Be a Number
         $TestObj.Report.Config.activeSectionIndex | Should -Match "\d"
    }

    It 'Reports Should Have Filters property' {
        $TestObj.Report.Filters.GetType().toString() | Should -Be "System.Object[]"
    }

    It 'Reports Should Have ReportConfig property' {
        $TestObj.Report.ReportConfig | Should -Not -BeNullOrEmpty
    }

    It 'Reports Should Have Sections property' {
        $TestObj.Report.Sections | Should -Not -BeNullOrEmpty
    }

    It 'Reports Should Have Sections property with at least 2 items' {
        $TestObj.Report.Sections.Length | Should -BeGreaterOrEqual 2
    }  
 
    It 'Reports.Sections[0].Config Should Have _Path and _Directory property' {
        $PathInfoCheck = $TestObj.Report.Sections[0].Config | Where-Object { $_._Path -and $_._Directory }

        $TestObj.Report.Sections[0].Config.Length | Should -Be $PathInfoCheck.Length
    }

    It 'Reports.Sections[0].Settings Should Have _Path and _Directory property' {
        $PathInfoCheck = $TestObj.Report.Sections[0].Settings | Where-Object { $_._Path -and $_._Directory }
        $TestObj.Report.Sections[0].Settings.Length | Should -Be $PathInfoCheck.Length
    }
    
    It 'Reports.Sections[0].Settings Should Have displayName property' {
        $TestObj.Report.Sections[0].Settings.displayName | Should -Not -BeNullOrEmpty
    }    

    It 'Reports.Sections Should Have Visuals property' {
        $TestObj.Report.Sections.Visuals | Should -Not -BeNullOrEmpty
    }

    It 'Reports.Sections[0].Visuals should have at least 10 items' {
        $TestObj.Report.Sections[0].Visuals.Length | Should -BeGreaterOrEqual 10
    }    

    It 'Reports.Sections[1].Visuals[0].Config Should Have _Path and _Directory property' {        
        $PathInfoCheck = $TestObj.Report.Sections[1].Visuals[0].Config | Where-Object {  $_._Path -and $_._Directory }
        $TestObj.Report.Sections[1].Visuals.Length | Should -BeGreaterOrEqual 1
    }    

    It 'Reports.Sections[0].Visuals[0] Should Have Filters property' {
        $TestObj.Report.Sections[0].Visuals[0].Filters | Should -Not -BeNullOrEmpty
    }  

    It 'Reports.Sections[0].Visuals.Config[0] Should Have name and layouts property' {
        $TestObj.Report.Sections[0].Visuals.Config[0].name | Should -Not -BeNullOrEmpty
        $TestObj.Report.Sections[0].Visuals.Config[0].layouts | Should -Not -BeNullOrEmpty
    }        

    It 'Reports.Sections[0].Visuals[0].Filters Should Have ImplicitFilters property' {
        $TestObj.Report.Sections[0].Visuals[0].Filters._ImplicitFilters | Should -Not -BeNullOrEmpty
    }    

    It 'Reports.Sections[0].Visuals[0].Filters Should Have _ExplicitFilters property' {
        $TestObj.Report.Sections[0].Visuals[0].Filters._ExplicitFilters | Should -Not -BeNullOrEmpty
    }

    It 'Reports.Sections[0].Visuals[0].Filters Should Have Settings property' {
        $TestObj.Report.Sections[0].Visuals[0].Filters.Settings | Should -Not -BeNullOrEmpty
    }

    It 'Reports.Sections[0].Visuals[0].Filters Should Have ImplicitFilters property with 3 items' {
        $TestObj.Report.Sections[0].Visuals[0].Filters._ImplicitFilters.Length | Should -Be 3
    }         

    It 'Reports.Sections[0].Visuals.Filters[0] Should Have ExplicitFilters property with 4 items' {
        $TestObj.Report.Sections[0].Visuals.Filters[0]._ExplicitFilters.Length | Should -Be 4
    }  
    
    It 'Reports.Sections[0].Visuals[0].Filters Should Have Settings property with 3 items' {
        $TestObj.Report.Sections[0].Visuals[0].Filters.Settings.Length | Should -Be 4
    }    

    #TODO before updating SampleModel make sure to save PbixProj contents
}