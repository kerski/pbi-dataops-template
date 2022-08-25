<#
    Author: John Kerski
    Description: This script runs the proof-of-concept Continuous Integration of Dataflow files.

    Dependencies: Premium Per User license purchased and assigned to UserName and UserName has admin right to workspace.
#>
#Setup TLS 12
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#Get Working Directory
$WorkingDir = (& pwd) -replace "\\", '/'
#Set Default Environment Variables 
$Opts = @{
    TenantId = "${env:TENANT_ID}";
    PbiApiUrl = "${env:PBI_API_URL}"
    BuildGroupId = "${env:PBI_BUILD_GROUP_ID}"
    UserName = "${env:PPU_USERNAME}";
    Password = "${env:PPU_PASSWORD}";
    #Get new dataflow changes
    DFChanges = git diff --name-only --relative --diff-filter AMR HEAD^ HEAD '**/model.json';
    BuildVersion = "${env:BUILD_SOURCEVERSION}";
    BuildVersionSrcMsg = ${env:BUILD_SOURCEVERSIONMESSAGE};
    # Case insentive check to see if file starts with Revert:
    IsRevert = ${env:BUILD_SOURCEVERSIONMESSAGE} -match '^Revert:';
}

#Install Powershell Module if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "MicrosoftPowerBIMgmt already installed"
} else {
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
}
        
#Set Client Secret as Secure String
$Secret = $Opts.Password | ConvertTo-SecureString -AsPlainText -Force
$Credentials = [System.Management.Automation.PSCredential]::new($Opts.UserName,$Secret)
#Connect to Power BI
Connect-PowerBIServiceAccount -Credential $Credentials

#Get Workspace Information to make sure we get the right Workspace names
$BuildWS = Get-PowerBIWorkspace -Id $Opts.BuildGroupId 

# Check if we got a revert
if($Opts.IsRevert)
{
    <# After several attempts I was unable to implement this logic until the takeover feature 
    is made available via an API end point #>
}
else #revert didn't occur so move forward with testing
{
    #Handle Prerequisites
    $FullyQualifiedName = @{ModuleName="Pester";ModuleVersion="4.10.0.0"}

    if(Get-Module -FullyQualifiedName $FullyQualifiedName){
        Write-Host "Pester module already installed" -ForegroundColor Cyan
    }else{
        Write-Host "Installing Pester 4.10.0" -ForegroundColor Cyan
        Install-Module -Name Pester -RequiredVersion 4.10.0 -Scope CurrentUser -AllowClobber -Force
    }     

    # Make sure Az Module is installed
    if(Get-Module -ListAvailable -Name "Az.Storage"){
        Write-Host "Az module already installed" -ForegroundColor Cyan
    }else{
        Write-Host "Installing Az.Accounts and Az.Storage" -ForegroundColor Cyan
        Install-Module Az.Accounts -Force -AllowClobber -Scope CurrentUser
        Install-Module Az.Storage -Force -AllowClobber -Scope CurrentUser
    }   

    # Run Tests
    Invoke-Gherkin -Strict -OutputFile result.xml -OutputFormat NUnitXml -ErrorVariable $ErrorCount
}#end if

return