<#
    Author: John Kerski
    Description: Queries the RegexHealth table, evalutes the regex against the values in the table, 
    and logs any errors to Azure DevOps.  

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName has 
    admin right to workspace.
#>
Function Confirm-RegexPassesWithPPU { 
		[CmdletBinding()]
        [OutputType([Int])]
		Param(  
				[Parameter(Position = 0, Mandatory = $true)][String]$DatasetId,
                [Parameter(Position = 1, Mandatory = $true)][String]$UserName,
                [Parameter(Position = 2, Mandatory = $true)][String]$Password,
                [Parameter(Position = 3, Mandatory = $true)][String]$APIUrl
		) 
		Process { 
            Try {
                #Install PBI Powershell Module if Needed
                if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
                    Write-Host "##[debug]MicrosoftPowerBIMgmt already installed"
                } else {
                    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
                }

                #Set Client Secret as Secure String
                $Secret = $Password | ConvertTo-SecureString -AsPlainText -Force
                $Credentials = [System.Management.Automation.PSCredential]::new($UserName,$Secret)
                #Connect to Power BI
                $ConnectResult = Connect-PowerBIServiceAccount -Credential $Credentials                

                #Setup Regex Failure Counter
                $RegexFailCount = 0

                $RegexQueryUrl = "$($APIUrl)/datasets/$($DatasetId)/executeQueries"

                #Template json to issue DAX query using executeQueries endpoint
                $DaxQueryTemplate = @"
                {
                    "queries": [
                      {
                        "query": "{_QUERY_}"
                      }
                    ],
                    "serializerSettings": {
                      "includeNulls": true
                    }
                }
"@
                #Get Regex Table
                $RegexQueryResult = Invoke-PowerBIRestMethod -Url "$($RegexQueryUrl)" `
                                                             -Method Post `
                                                             -Body ($DaxQueryTemplate -replace "{_QUERY_}", "EVALUATE RegexHealth")`
                                                             -ErrorAction Ignore
                
                if($RegexQueryResult) # Query got results
                {
                    # Convert From Json to Object
                    $TempResult = $RegexQueryResult | ConvertFrom-Json
                    foreach($Row in $TempResult.results.tables.rows)
                    {
                        # Now get Table, Column Name, and Regex Expression
                        $TblName = $Row."RegexHealth[Table]"
                        $ColName = $Row."RegexHealth[Column]"
                        $RegexTest = $Row."RegexHealth[Regex]"

                        $ValQuery = "EVALUATE SELECTCOLUMNS ( '$($TblName)', \`"Values\`", '$($TblName)'`[$($ColName)`])"
                        
                        $ValQueryResult = Invoke-PowerBIRestMethod -Url "$($RegexQueryUrl)" `
                                                                   -Method Post `
                                                                   -Body ($DaxQueryTemplate -replace "{_QUERY_}", "$($ValQuery)")`
                                                                   -Verbose

                        if($ValQueryResult) #Query got results
                        {
                            $TempVals = ($ValQueryResult | ConvertFrom-Json).results.tables.rows

                            #Get what doesn't match
                            $TempNoMatches = $TempVals."[Values]" -notmatch $RegexTest

                            #Get Unique Values
                            $TempNoMatches = $TempNoMatches | Sort-Object | Get-Unique

                            #Increment counter if regex test fails
                            if($TempNoMatches.Count -gt 0)
                            {
                                $RegexFailCount +=1
                            }

                            #Log errors
                            foreach($NoMatch in $TempNoMatches)
                            {
                                # Regex 
                                Write-Host "##vso[task.logissue type=error]DatasetId $($DatasetId) has failed with value '$($NoMatch)' against regex: '$($RegexTest)'"
                            }
                        }
                    }#end foreach
                }
                else {
                    # No Regex to check
                    Write-Host "##vso[task.logissue type=warning]No RegexHealth table found for DatasetId $($DatasetId)"
                }#end check if on EVALUATE RegexHealth

                # Return counter
                Write-Host "RegexFailCount $($RegexFailCount)"

                return $RegexFailCount

            }Catch [System.Exception]{
                $ErrObj = ($_).ToString()
                Write-Host "##vso[task.logissue type=error]$($ErrObj)"
                exit 1
            }#End Try
	}#End Process
}#End Function

Export-ModuleMember -Function Confirm-RegexPassesWithPPU 