# AVD Personal Host Pool Auto Shutdown
This repo consists the AVD-PersonalAutoShutdown script which you can use to automatically shutdown Personal Azure Virtual Desktop Session Hosts, and a script to deploy an automation account to run this script. If you have an existing Automation account you can also use the script to import the AVD-PersonalAutoShutdown.ps1 script, import the required modules and to create a schedule on which the script runs.

The script will only shutdown Session Hosts without any sessions. The script cannot detect if a session is active or in an disconnected state. It is best that you configure a maximum time which a Session Host can have a disconnected session. You can do this via Group Policy; Computer Configuration > Policies > Administrative Templates > Windows Components > Remote Desktop Services > Remote Desktop Session Host > Session Time Limits. And configure the 'Set time limted for disconnected sessions'. Here you can also configure 'Set time limit for active but idle Remote Desktop Services sessions', so that idle sessions will be terminated after a period of time.

To run the script you will need a subscription and an account on which you at least has contributor rights.

## DeployAutomationAccount
The creating of the automation script is basically an slightly adjusted version of the script used by Microsoft to create an Automation Account which is documented here https://docs.microsoft.com/en-us/azure/virtual-desktop/set-up-scaling-script#create-or-update-an-azure-automation-account. There for you can reuse the automation account if you have set it up for the pooled scenario. Simple run the script and reference your existing automation account and the run book will be added.

This script does the following:
* Checks if you have the appropriate permissions
* Checks if you have the correct modules installed on your computer 
* Deploys a new resource group for the automation account (if needed)
* Deploys a new Automation Account and imports the necessary modules and runbook
* Creates an Automation Schedule which runs every 1 hour
* Connects the Runbook to the Schedule so it will start 
* ~~ ~~Validates if an Run As Account is present~~ ~~
* Creates a managed identity with the required roles

## AVD-PersonalAutoShutdown.ps1
The AVD-PersonalAutoShudown.ps1 script can run on a specific Host pool.

The script does the following:
* Checks if the host pool is set to personal, pooled is not supported
* Checks if start on Connect is enabled. Link to how to configure this https://docs.microsoft.com/en-us/azure/virtual-desktop/start-virtual-machine-connect
* Collects all the Session Hosts in the host pool
* If the Session Host is running it checks if there is an active session, if there are no active sessions the Session Host will be Deallocated
* You can exclude machines from the script by using a tag

### Download Script
To setup the script download the DeployAutomationAccount.ps1 to you local computer by running:


```PowerShell
New-Item -ItemType Directory -Path "C:\Temp" -Force
Set-Location -Path "C:\Temp"
$Uri = "https://raw.githubusercontent.com/stephanvandekruis/AVD/main/PersonalScaling/DeployAutomationAccount.ps1"
# Download the script
Invoke-WebRequest -Uri $Uri -OutFile ".\DeployAutomationAccount.ps1"
```

Also download the Custom Role Definition for the role assignments 
```PowerShell
$Uri = "https://raw.githubusercontent.com/stephanvandekruis/AVD/main/PersonalScaling/Automation-RoleDefinition.json"
# Download the script
Invoke-WebRequest -Uri $Uri -OutFile ".\Automation-RoleDefinition.json"
```

Log in to your environment
```PowerShell
Login-AzAccount
```

Run the following cmdlet to execute the script and create the Automation Account. You can fill in the values or comment them to use their defaults

```PowerShell
$Params = @{
    "AADTenantId"               = "<Azure_Active_Directory_tenant_ID>"
    "SubscriptionId"            = "<Azure_subscription_ID>" 
    "AutomationRG"              = "<ResourceGroup of the Automation Account>" # Optional. Default: rgAVDAutoShutdown
    "AutomationAccountName"     = "<Automation Account Name>" # Optional. Default: AVDAutoShutdownAutomationAccount
    "AutomationScheduleName"    = "<Automation Schedule Name>" # Optional. Default: AVDShutdownSchedule
    "AVDrg"                     = "<AVD resource group which holds the Host Pool Object>"
    "SessionHostrg"             = "<Resource group which contains the VMs of the session hosts>"
    "HostPoolName"              = "<Host pool Name>"
    "SkipTag"                   = "<Name of the tag to skip the vm from processing>" # Optional. Default: SkipAutoShutdown
    "TimeDifference"            = "<Time difference from UTC (e.g. +2:00) >" # Optional. Default: +2:00
    "Location"                  = "<Location of deployment (e.g West Europe)>" # Optional. Default: West Europe
}

.\DeployAutomationAccount.ps1 @Params
```

For other information check my blog post on: https://www.stephanvdkruis.com/2021/08/auto-shutdown-avd-personal-host-pools/