<#
    .SYNOPSIS
        Creates Azure DevOps Variable for Pipeline

    .DESCRIPTION
        Dependencies: Assumes logged in with azure cli installed and logged in already.

    .PARAMETER AzDOHostURL
        Base URL for Azure DevOps trailing with forward slash

    .PARAMETER OrgName
        Organization Name for the Azure DevOps instance

    .PARAMETER PipelineName
        Name of the pipeline to associate the variable

    .PARAMETER ProjectName
        Name of the project in Azure DevOps

    .PARAMETER VariableName
        Variable's name to save to the pipeline   

    .PARAMETER VariableValue
        Variable's value to save to the pipeline        

    .PARAMETER IsSecret
        True if to treat the variable as a secret. False otherwise

    .NOTES
        Author: John Kerski
#>
Function Add-AzureDevOpsVariable { 
		[CmdletBinding()]
		Param( 
                [Parameter(Position = 0, Mandatory = $true)][String]$AzDOHostURL,
                [Parameter(Position = 1, Mandatory = $true)][String]$OrgName,
                [Parameter(Position = 2, Mandatory = $true)][String]$PipelineName,
                [Parameter(Position = 3, Mandatory = $true)][String]$ProjectName,
                [Parameter(Position = 4, Mandatory = $true)][String]$VariableName,
                [Parameter(Position = 5, Mandatory = $true)][String]$VariableValue,
                [Parameter(Position = 6, Mandatory = $true)][Boolean]$IsSecret
		) 
		Process { 
            Try {
                    # Variable to be defined in the Variables tab
                    $VarResult = az pipelines variable create --name $($VariableName) --only-show-errors `
                                --allow-override true --org "$($AzDOHostURL)$($OrgName)" `
                                --pipeline-name $PipelineName `
                                --project $ProjectName --value $VariableValue --secret $IsSecret

                    #Check Result
                    if(!$VarResult) {
                        Write-Error "Unable to create pipeline variable $($VariableName)"
                        return
                    }

            }Catch [System.Exception]{
              $ErrObj = ($_).ToString()
              Throw $ErrObj
            }#End Try
	}#End Process
}#End Function


Export-ModuleMember -Function Add-AzureDevOpsVariable