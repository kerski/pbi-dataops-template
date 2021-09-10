<#
    Author: John Kerski
    Description: This script:
        1) Loads the Tabular DLL
        2) Connects to the Dataset
        3) Export and copies the dataset
        4) Add the tests (DaxQueries)
        5) Runs Calculation Dependencies
        6) Delete the copied dataset
        7) Return the results as an XML object

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName has admin right to workspace.
#>
Function Find-TestCoverageForPBIWithPPU { 
		[CmdletBinding()]
		Param( 
				[Parameter(Position = 0, Mandatory = $true)][String]$WorkspaceName, 
				[Parameter(Position = 1, Mandatory = $true)][String]$LocalDatasetPath,
                [Parameter(Position = 2, Mandatory = $true)][String]$UserName,
                [Parameter(Position = 3, Mandatory = $true)][String]$Password,
                [Parameter(Position = 4, Mandatory = $true)][String]$TenantId,
                [Parameter(Position = 5, Mandatory = $true)][String]$APIUrl,
                [Parameter(Position = 7, Mandatory = $true)][Object[]]$DaxQueries,
                [Parameter(Position = 8, Mandatory = $true)][String]$BuildId
		) 
		Process { 
            Try {
                   #Install Powershell Module if Needed
                   if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
                       Write-Host "MicrosoftPowerBIMgmt already installed"
                   } else {
                       Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
                   }

                   #Install Powershell Module if Needed
                   if (Get-Module -ListAvailable -Name "SqlServer") {
                       Write-Host "SqlServer module already installed"
                   } else {
                       Install-Module -Name SqlServer
                   }

                   #Add Microsoft Analysis Services library
                   $LoadTabResult = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.AnalysisServices.Tabular")

                   #Copy Power BI Dataset
                   #Set Client Secret as Secure String
                   $Secret = $Password | ConvertTo-SecureString -AsPlainText -Force
                   $Credentials = [System.Management.Automation.PSCredential]::new($UserName,$Secret)
                   #Connect to Power BI
                   $ConnectResult = Connect-PowerBIServiceAccount -Credential $Credentials

                   #Get Workspace Info for use later
                   $WorkspaceInfo = Get-PowerBIWorkspace -Filter "name eq '$($WorkspaceName)' and state ne 'Deleted'"

                   #Get Dataset Name from file path
                   $TempFilePath = [io.path]::GetFullPath($LocalDatasetPath)
                   $DatasetName = [io.path]::GetFileNameWithoutExtension($TempFilePath)

                   #Copy Report to create Test Coverage
                   $TestCoverageFile = "$($DatasetName)$($BuildId)"
                   #Only take 255 characters because Power BI file name limit is 255
                   if($TestCoverageFile.length -gt 250)
                   {
                    $TestCoverageFile = $TestCoverageFile.Substring(0,250)
                   }
                   $TestFileName = $TestCoverageFile
                   $TestCoverageFile = "$($TestCoverageFile).pbix"
                   $CopyResult = Copy-Item -Path $TempFilePath -Destination "$($TestCoverageFile)"                 
                   $TestCoverageFile = [io.path]::GetFullPath($TestCoverageFile)
                   $TestCoverageFile = $TestCoverageFile -replace "\\", '/'

                   Write-Host "Uploading Test Report $($TestCoverageFile)"
                   #Promote Report and overwrite if it already exists
                   $TestCovRptInfo = New-PowerBIReport -Path "$($TestCoverageFile)" -Name $TestFileName -WorkspaceId $WorkspaceInfo.Id -ConflictAction CreateOrOverwrite -Timeout 500
                   Start-Sleep -Seconds 15 #sleep wait seconds before running again. I noticed there is a delay, may need to be updated or while loop added.
                   $TestCovRptInfo = Get-PowerBIReport -WorkspaceId $WorkspaceInfo.Id -Name $TestFileName
                   #Replace https with powerbi
                   $PBIEndpoint = $APIUrl.Replace("https","powerbi")

                   #Connect to PowerBI
                   Write-Host "Connect to Power BI dataset $($TestFileName)"
                   $Server = New-Object Microsoft.AnalysisServices.Tabular.Server
                   $Server.Connect("Provider=MSOLAP;Data Source=$($PBIEndpoint)/$($WorkspaceName);initial catalog=$($TestFileName);User Id=$($UserName);Password=$($Password)")
                   $Dbs = $Server.databases
                   
                   #Retrieve Test Coverage File
                   $TempDb = $Dbs.GetByName($TestFileName)

                   #With Test Coverage Created, now we need to add the measures
                   #Add Tests as Calculated Table
                   foreach($Test in $DaxQueries)
                   {               
                    Write-Host "Adding $($Test.TestName) to model for Test Coverage"
                    $TempCPS= New-object Microsoft.AnalysisServices.Tabular.CalculatedPartitionSource
                    $TempCPS.Expression=Out-String -InputObject $Test.Content
                    $TempPar= New-Object Microsoft.AnalysisServices.Tabular.Partition                    
                    #Create partition name based on test.name
                    $TempParName = "TestCoverage_Par_"
                    $TempParName += Out-String -InputObject $Test.TestName
                    #Assign new name to table
                    $TempPar.Name=$TempParName 
                    $TempPar.Source=$TempCPS
                    $TempTbl=new-object Microsoft.AnalysisServices.Tabular.Table
                    #Create table name based on test.name
                    $TempTblName="TestCoverage_Tbl_"
                    $TempTblName+= Out-String -InputObject $Test.TestName
                    #Assign new name to table
                    $TempTbl.Name=$TempTblName
                    $TempTbl.Partitions.Add($TempPar)
                    $TempDB.Model.Tables.Add($TempTbl)                    
                   }#end foreach
                   #Save changes
                   $SaveChangesResult = $TempDb.Model.SaveChanges()
                   
                   #Now that updates are complete disconnect
                   $DisconnectResult = $Server.Disconnect();

                   #Now get the calculation dependencies
                   $CDResult = Invoke-ASCmd -Server "$($PBIEndpoint)/$($WorkspaceName)" `
                        -Database $TestFileName `
                        -Query "SELECT [Database_Name],
                        	   [Object_Type],
	                           [Table],
	                           [Object],
                               [Expression],
                               [Referenced_Object_type],
                               [Referenced_Table],
                               [Referenced_Object],
                               [Referenced_Expression],
                               [Query] 
                                FROM `$System.DISCOVER_CALC_DEPENDENCY" `
                        -Credential $Credentials `
                        -TenantId $TenantId

                   #Now get tables
                   $TablesResult = Invoke-ASCmd -Server "$($PBIEndpoint)/$($WorkspaceName)" `
                        -Database $TestFileName `
                        -Query "SELECT [ID],
                                [ModelID],
                                [Name],
                                [DataCategory],
                                [Description],
                                [IsHidden],
                                [TableStorageID],
                                [ModifiedTime],
                                [StructureModifiedTime],
                                [SystemFlags],
                                [ShowAsVariationsONly],
                                [IsPrivate],
                                [DefaultDetailRowsDefinitionID],
                                [AlternateSourcePrecedence],
                                [RefreshPolicyID],
                                [CalculationGroupID],
                                [ExcludeFromModelRefresh],
                                [LineageTag],
                                [SourceLineageTag]
                                FROM `$System.TMSCHEMA_TABLES" `
                        -Credential $Credentials `
                        -TenantId $TenantId

                   #Now get measures
                   $MeasuresResult = Invoke-ASCmd -Server "$($PBIEndpoint)/$($WorkspaceName)" `
                        -Database $TestFileName `
                        -Query "SELECT [ID],
                                [TableID],
                                [Name],
                                [Description],
                                [DataType],
                                [Expression],
                                [FormatString],
                                [IsHidden],
                                [State],
                                [ModifiedTime],
                                [StructureModifiedTime],
                                [KPIID],
                                [ErrorMessage],
                                [DisplayFolder],
                                [DetailRowsDefinitionID],
                                [DataCategory],
                                [LineageTag],
                                [SourceLineageTag]
                                FROM `$System.TMSCHEMA_MEASURES" `
                        -Credential $Credentials `
                        -TenantId $TenantId

                   #Now get columns
                   $ColumnsResult = Invoke-ASCmd -Server "$($PBIEndpoint)/$($WorkspaceName)" `
                        -Database $TestFileName `
                        -Query "SELECT [ID],
                                [TableID],
                                [ExplicitName],
                                [InferredName],
                                [ExplicitDataType],
                                [InferredDataType],
                                [DataCategory],
                                [Description],
                                [IsHidden],
                                [State],
                                [IsUnique],
                                [IsKey],
                                [IsNullable],
                                [Alignment],
                                [TableDetailPosition],
                                [IsDefaultLabel],
                                [IsDefaultImage],
                                [SummarizeBy],
                                [ColumnStorageID],
                                [Type],
                                [SourceColumn],
                                [ColumnOriginID],
                                [Expression],
                                [FormatString],
                                [IsAvailableInMDX],
                                [SortByColumnID],
                                [AttributeHierarchyID],
                                [ModifiedTime],
                                [StructureModifiedTime],
                                [RefreshedTime],
                                [SystemFlags],
                                [KeepUniqueRows],
                                [DisplayOrdinal],
                                [ErrorMessage],
                                [SourceProviderType],
                                [DisplayFolder],
                                [EncodingHint],
                                [RelatedColumnDetailsID],
                                [AlternateOfID],
                                [LineageTag],
                                [SourceLineageTag]
                        		FROM `$System.TMSCHEMA_COLUMNS" `
                        -Credential $Credentials `
                        -TenantId $TenantId


                    #Remove unicode chars for brackets and spaces from XML node names
                    $CDResult = $CDResult -replace '_x[0-9A-z]{4}_','';
                    $MeasuresResult = $MeasuresResult -replace '_x[0-9A-z]{4}_','';
                    $TablesResult = $TablesResult -replace '_x[0-9A-z]{4}_','';
                    $ColumnsResult = $ColumnsResult -replace '_x[0-9A-z]{4}_','';               
                    
                    #Create object for test coverage data
                    $Temp = @{
                        Title = $BuildId;
                        CalculationDependencies = $CDResult;
                        Tables = $TablesResult
                        Measures = $MeasuresResult;
                        Columns = $ColumnsResult;
                    }

                    #Setup Refresh Endpoint
                    $DeleteUrl = "$($APIUrl)/groups/$($WorkspaceInfo.Id)/datasets/$($TestCovRptInfo.DatasetId)"
                    #Issue Dataset deletion
                    $DeleteResult = Invoke-PowerBIRestMethod -Url "$($DeleteUrl)" -Method DELETE

                    #Return XML representation of the calculation dependencies
                    Return $Temp

            }Catch [System.Exception]{
              $ErrObj = ($_).ToString()
              Write-Host "##vso[task.logissue type=error]$($ErrObj)"
              throw "Unable to Find Test Coverage."
            }#End Try
	}#End Process
}#End Function

Export-ModuleMember -Function Find-TestCoverageForPBIWithPPU
