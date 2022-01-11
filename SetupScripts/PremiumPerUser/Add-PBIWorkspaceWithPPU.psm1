<#
    Author: John Kerski
    Description: Creates Power BI Workspace

    Dependencies: 
        1) Already Logged into Power BI with PowerShell
#>
Function Add-PBIWorkspaceWithPPU { 
		[CmdletBinding()]
		Param( 
                [Parameter(Position = 0, Mandatory = $true)][String]$WorkspaceName,
                [Parameter(Position = 1, Mandatory = $true)][String]$WorkspaceDesc,
                [Parameter(Position = 2, Mandatory = $true)][String]$CapacityId,
                [Parameter(Position = 3, Mandatory = $true)][String]$SvcUser
		) 
		Process { 
            Try {
          
                #Create Workspace Name
                $Result = New-PowerBIWorkspace -Name $WorkspaceName

                #Find Workspace and make sure it wasn't deleted (if it's old or you ran this script in the past)
                $WSObj = Get-PowerBIWorkspace -Scope Organization -Filter "name eq '$($WorkspaceName)' and state ne 'Deleted'"

                if($WSObj.Length -eq 0)
                {
                Throw "$($WorkspaceName) workspace was not created."
                }

                #Update properties
                $Result = Set-PowerBIWorkspace -Description $WorkspaceDesc -Scope Organization -Id $($WSObj.Id.Guid)
                $Result = Set-PowerBIWorkspace -CapacityId $CapacityId -Scope Organization -Id $($WSObj.Id.Guid) 

                #Assign service account admin rights to this workspace
                $Result = Add-PowerBIWorkspaceUser -Id $WSObj[$WSObj.Length-1].Id.ToString() -AccessRight Admin -UserPrincipalName $SvcUser

                #Return Workspace Object
                return $WSObj

            }Catch [System.Exception]{
              $ErrObj = ($_).ToString()
              Throw $ErrObj
            }#End Try
	}#End Process
}#End Function


Export-ModuleMember -Function Add-PBIWorkspaceWithPPU