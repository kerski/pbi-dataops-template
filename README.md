# Part 20 of "Bringing DataOps to Power BI" this branch serves to provides templates for applying DataOps principles.

These instructions are a continuation from <a href="https://www.kerski.tech/bringing-dataops-to-power-bi-part20/" target="_blank">Part 20 of Bringing DataOps to Power BI</a>.  The steps below describe how to setup a DevOps project with Azure resources that will automatically save Power BI dataflow code in Git.

> ***Important Note #1**: This guide is customized to Power BI for U.S. Commercial environment. If you are trying to set this up for another Microsoft cloud environment (like U.S. Gov Cloud), please check Microsoft's documentation for the appropriate URLs. They will be different from the U.S. Commercial environment.*

> ***Important Note #2**: This guide uses scripts that I built and tested on environments I have access to. Please review all scripts if you plan for production use, as you are ultimately responsible for the code that runs in your environment.*

## Table of Contents

1. [Prerequisites](#Prerequisites)
1. [Installation Steps](#Installation-Steps)
1. [Checking the dataflow pushed to Azure DevOps
](#Checking-the-dataflow-pushed-to-Azure-DevOps)

## Prerequisites

### Power BI and Azure
-   Power BI Premium Per User license. If you do not have a Premium Per User license, use the "Buy Now" feature on <a href="https://docs.microsoft.com/en-us/power-bi/admin/service-premium-per-user-faq" target="_blank">Microsoft's site</a> or if you don't have access to do that, please contact your administrator (be nice!).

-  Identify the location of your Power BI Service. Please see instructions <a href="https://docs.microsoft.com/en-us/power-bi/admin/service-admin-where-is-my-tenant-located" target="_blank">at this link</a>.  You'll need to convert the readable name to Azure name when prompted to enter the location.  For example, West US 2 would be 'westus2'.

-   Azure subscription created and you have Owner rights to the subscription.

- A PAT token generated with Code "Read, Write, Manage" Permissions  Please see instructions <a href="https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=Windows#create-a-pat" target="_blank">at this link</a>.

    ![Example to PAT Token](./images/part20-PAT.PNG)

### Desktop

-  <a href="https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" target="_blank">Azure CLI</a> version 2.37 installed.

-  <a href="https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2" target="_blank">PowerShell 7</a> installed.  If you are using Windows 10 or 11, this should be installed already. For the purposes of the instructions I'm going to use PowerShell ISE to run a PowerShell script. 

### Azure DevOps

-  Signed up for <a href="https://docs.microsoft.com/en-us/azure/devops/user-guide/sign-up-invite-teammates?view=azure-devops" target="_blank">Azure DevOps</a>.

- For Azure DevOps you must be a member of the Project Collection Administrators group, the Organization Owner, or have the Create new projects permission set to Allow. 

## Installation Steps

1. Open PowerShell Version 7 and enter the following script:
    > Invoke-WebRequest -Uri "https://raw.githubusercontent.com/kerski/pbi-dataops-template/part20/SetupScripts/PremiumPerUser/DataFlows/Setup-Dataflow-PPU.ps1" -OutFile "./Setup-Dataflow-PPU.ps1"
    
1. This will download the setup scripts to the current folder.  Run ".\Setup-Dataflow-PPU.ps1" in PowerShell.

1. During the install process you will be prompted to enter the following information:

    - The name of the subscription you have in Azure.
    - The location of your Power BI service (see Prequisites)
    - The name of the project you wish to create in Azure DevOps. 
    - The PAT Token (see Prequisites)
    - The name of the Power BI workspace you wish to create.

1. During the course of the install you will be prompted to enter your Microsoft 365 credentials. Depending on your environment you may have a browser tab appear to sign-in. After signing in you can return to the PowerShell window. In addition, if you don't have the Power BI Management Shell or Azure DevOps CLI package installed, you will be asked to install.  Please affirm you wish to install those packages if prompted.

    ![Prompt to install azure devops cli](./images/part5-devops-cli-install.PNG)

1. Near the end of the installation you will see the message that starts with "NEED ASSISTANCE".

    ![Screenshot of manual step required](./images/part20-help-please.PNG)

As of June 2022, you can not easily script connect a workspace to an Azure Gen2 Data Lake, so please navigate to the newly created workspace and <a href="https://docs.microsoft.com/en-us/power-bi/transform-model/dataflows/dataflows-azure-data-lake-storage-integration#prerequisites" target="_blank">follow these instructions</a> to make the connection.

   ![Screenshot of linking workspace to Azure storage](./images/part20-connect-workspace.PNG)


***Important Note #3**: I have seen that permission settings in the storage account can take up to 10-15 minutes to take affect.  Consequently, this causes you to get an Access Denied message during this step.  Try a few times (rule of thumb 3).*

6. If the script runs successfully you will be presented with a message similar in the image below. 

    ![Example of successful install](./images/part20-success-install.PNG)

## Checking the Dataflow pushed to Azure DevOps

With the [Installation Steps](#Installation-Steps) complete, the Azure resource should have automatically picked up on the new dataflow and pushed it to Git. Please navigate to the Repos section of the Azure DevOps project.  Switch to the 'part20' branch in the Repo and you should see a 'DataFlows' folder that contains the newly pushed 'model.json' file that represents the dataflow.  The image below is an example. 

![Example of successfully saved file to Git](./images/part20-saved-model.PNG)