<#
    .SYNOPSIS
    Write Issue via Write-Host

    .DESCRIPTION
    Write message to host.  If IsLocal is false, it will include Azure DevOps (ex. ##vso[task.logissue type=error])

    .PARAMETER Message
    Message to Log

    .PARAMETER IsLocal
    True is running locally or False is fun in Azure Pipelines

    .PARAMETER Type
    Type can be either 'error' or 'warning'

#>
Function Write-Issue {
    [CmdletBinding()]
    Param( 
        [Parameter(Position = 0, Mandatory = $true)][String]$Message, 
        [Parameter(Position = 1, Mandatory = $true)][Boolean]$IsLocal,
        [Parameter(Position = 2, Mandatory = $true)][String]$Type       
    ) 
    Process { 
      # Check Type
      if(-Not($Type -eq 'error') -and -Not($Type -eq 'warning')){
         Throw "Type must be 'error' or 'warning'"
      }
  
      if($IsLocal)
      {
        #Set Color
        $Color = "Red"
        switch ($Type) {
          "error" { $Color = "Red" }
          "warning" { $Color = "Yellow"}
        }
  
         Write-Host -ForegroundColor $Color $Message
      }
      else {
        switch ($Type) {
          "error" { Write-Host "##vso[task.logissue type=error]$($Message)"}
          "warning" { Write-Host "##vso[task.logissue type=warning]$($Message)"}
        }
      }#endif
    }#end process
  } #End Write-Issue

  Export-ModuleMember -Function Write-Issue