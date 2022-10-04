<#
    .SYNOPSIS
    Retrieves Schema for Dataset

    .DESCRIPTION
    This function calls Tabular Editor to retrieve the schema settings for the dataset

    .PARAMETER PBIPort
    Local port number for SSAS

    .PARAMETER PBIDatsetID
    GUID for the local database instance of the Power BI dataset

    .PARAMETER ScriptFileLocation
    Location of GetSchema.cs.  This is parameterized for testing and if folder taxonomy changes.

    .PARAMETER TabularEditorPath
    Location of TabularEditor.exe

    .OUTPUTS
    Array of objects with Name, ObjectType, Parent, FormatString, and DataType detailing schema information about the dataset

    .EXAMPLE
    PS> $X = Get-DatasetSchemaFromLocal -PBIPort "55278" -PBIDatasetID "f6a7a89a-7a04-4d6d-876c-f8affc93dea7" -ScriptFileLocation ".\PipelineScripts\Premium\GetSchema.cs" -TabularEditorPath ".\Pbi\TestingScripts\TabularEditor\TabularEditor.2.17.1\TabularEditor.exe"
    PS> $X | Format-List
    PS> 
    Object       : Model.T.AlignmentDim.C.AlignmentKey
    Name         : AlignmentKey
    ObjectType   : Column
    Parent       : Model.T.AlignmentDim
    Description  : 
    FormatString : 
    DataType     : String
    Expression   : 

#>
Function Get-DatasetSchemaFromLocal { 
    [CmdletBinding()]
    Param( 
        [Parameter(Position = 0, Mandatory = $true)][String]$PBIPort,
        [Parameter(Position = 1, Mandatory = $true)][String]$PBIDatasetID,
        [Parameter(Position = 2, Mandatory = $true)][String]$ScriptFileLocation,
        [Parameter(Position = 3, Mandatory = $true)][String]$TabularEditorPath
    ) 
    Process { 
        #Install Tabular Editor if Needed
        if (-not (Test-Path $TabularEditorPath -PathType Leaf)) {
            Throw "Please include TabularEditor in your project"
        }

        $SchemaFile = "model.tsv"

        #Remove file before running script
        if (Test-Path -Path $SchemaFile) {
            $RemoveResult = Remove-Item $SchemaFile -ErrorAction Continue
        }#end if

        $ScriptArg = "`"Provider=MSOLAP;Data Source=localhost:$($PBIPort);Connect Timeout=120`" `"$($DatasetName)`" -S `"$($ScriptFileLocation)`" "
    
        #Execute Script
        $ProcessResult = Start-Process -FilePath $TabularEditorPath -Wait -NoNewWindow -PassThru `
            -ArgumentList "$ScriptArg"

        #Now Import Schema
        $Schema = Import-Csv -Delimiter "`t" -Path $SchemaFile

        #Remove file before running script
        if (Test-Path -Path $SchemaFile) {
            $RemoveResult = Remove-Item $SchemaFile -ErrorAction Continue
        }#end if

        #Create custom object that removes some of the internal jargon
        $SchemaObjs = @()

        foreach ($Temp in $Schema) {
            $Props = @{
                # Remove dot notation to get table name
                Table        = $Temp.Parent.SubString($Temp.Parent.LastIndexOf(".") + 1 )
                Name         = $Temp.Name
                ObjectType   = $Temp.ObjectType
                Description  = $Temp.Description
                DataType     = $Temp.DataType
                FormatString = $Temp.FormatString 
            }

            $Obj = New-Object PsObject -Property $Props 

            $SchemaObjs += $Obj

        }#end foreach

        return $SchemaObjs
    }#end process
}#end function


Export-ModuleMember -Function Get-DatasetSchemaFromLocal