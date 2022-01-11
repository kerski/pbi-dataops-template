#Note Pester 3 is preinstalled on many Windows 10/11 machines.
#Unistall Pester 3 with this script: https://gist.github.com/nohwnd/5c07fe62c861ee563f69c9ee1f7c9688
Describe 'Get-DatasetSchemaWithPPU' {
    BeforeAll { 
        Import-Module .\Get-DatasetSchemaWithPPU.psm1 -Force

        $Test = @{
            WorkspaceName = "Build";
            DatasetName = "Base-PlusNewColumn";
            UserName = "X";
            Password = "******";
            APIUrl = "https://api.powerbi.com/v1.0/myorg";
            TabEditorUrl = "https://github.com/otykier/TabularEditor/releases/download/2.16.1/TabularEditor.Portable.zip";
            ScriptFile = ".\\GetSchema.cs"
        }
    }

    #Clean up Tabular Editor Installs
    AfterAll {
        #Thanks to for work around on OneDrive delete
        #https://evotec.xyz/remove-item-access-to-the-cloud-file-is-denied-while-deleting-files-from-onedrive/
        if(test-path ".\TabEditor")
        {
              $Items = Get-ChildItem -LiteralPath ".\TabEditor" -Recurse
              foreach ($Item in $Items) {
                  Remove-Item -LiteralPath $Item.Fullname
              }
              $Items = Get-Item -LiteralPath ".\TabEditor"
              $Items.Delete($true)
        }
    }

    #Check if File Exists
    It 'Module should exist' {
        $IsInstalled = Get-Command Get-DatasetSchemaWithPPU

        $IsInstalled | Should -Not -BeNullOrEmpty
    }

    It 'Check if Script Runs' {

        Get-DatasetSchemaWithPPU -WorkspaceName $Test.WorkspaceName `
                                 -DatasetName $Test.DatasetName `
                                 -UserName $Test.UserName `
                                 -Password $Test.Password `
                                 -APIUrl $Test.APIUrl `
                                 -TabularEditorUrl $Test.TabEditorUrl `
                                 -ScriptFile $Test.ScriptFile
        
        Test-Path "documentation.tsv" | Should -Be $True
    }
}