<#
    .SYNOPSIS
    Retrieves Schema for Dataset

    .DESCRIPTION
    This function calls Tabular Editor to retrieve the schema settings for the dataset

    .PARAMETER Workspace
    Name of the workspace in the service

    .PARAMETER DatasetName
    Name of the dataset in the service

    .PARAMETER UserName
    Service Account's UserName

    .PARAMETER Password
    Service Account's Password

    .PARAMETER Tenant ID
    App Service Principal's Tenant ID

    .PARAMETER APIUrl
    Url EndPoint for Power BI API (ex. https://api.powerbi.com/v1.0/myorg)

    .PARAMETER ScriptFileLocation
    Location of GetSchema.cs.  This is parameterized for testing and if folder taxonomy changes.

    .PARAMETER TabularEditorPath
    Location of TabularEditor.exe

    .OUTPUTS
    Array of objects with Name, ObjectType, Parent, FormatString, and DataType detailing schema information about the dataset

    .EXAMPLE
    PS> $X = Get-DatasetSchemaFromLocal -WorkspaceName "Build" -DatasetName "SampleModel" -ClientId "xxxx" -ClientSecret "xxxx" -TenantId "xxxx" -APIUrl "https://api.powerbigov.us/v1.0/myorg" -ScriptFileLocation ".\PipelineScripts\Premium\GetSchema.cs" -TabularEditorPath ".\Pbi\TestingScripts\TabularEditor\TabularEditor.2.17.1\TabularEditor.exe"
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
Function Get-DatasetSchemaFromService { 
    [CmdletBinding()]
    Param( 
		[Parameter(Position = 0, Mandatory = $true)][String]$WorkspaceName, 
		[Parameter(Position = 1, Mandatory = $true)][String]$DatasetName,
        [Parameter(Position = 2, Mandatory = $true)][String]$UserName,
        [Parameter(Position = 3, Mandatory = $true)][String]$Password,
        [Parameter(Position = 4, Mandatory = $true)][String]$TenantId,
        [Parameter(Position = 5, Mandatory = $true)][String]$APIUrl,
        [Parameter(Position = 6, Mandatory = $true)][String]$ScriptFileLocation,
        [Parameter(Position = 7, Mandatory = $true)][String]$TabularEditorPath
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

        #Replace https with powerbi
        $PBIEndpoint = $APIUrl.Replace("https","powerbi")

        $ScriptArg = "`"Provider=MSOLAP;Data Source=$($PBIEndpoint)/$($WorkspaceName);Connect Timeout=120;User ID=$($Username);Password=$($Password)`" `"$($DatasetName)`" -S `"$($ScriptFileLocation)`" "
        #Execute Script
        $ProcessResult = Start-Process -Verbose -FilePath $TabularEditorPath -Wait -NoNewWindow -PassThru `
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

Export-ModuleMember -Function Get-DatasetSchemaFromService