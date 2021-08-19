# Read Me
This repo consists the AVD-PersonalAutoShutdown script which you can use to automatically shutdown Personal Azure Virtual Desktop Session Hosts, and a script to deploy an automation account to run this script. If you have an existing automation account you can also use the script to import the AVD-PersonalAutoShutdown.ps1 script, import the required modules and to create a schedule on which the script runs.

The AVD-PersonalShutdown script will check if

To run the script you will need a subscription and an account on which you atleast has contributer rights

## DeployAutomationAccount
This script does the following:
* Checks if you have the apporopiate permissions
* Checks if you have the correct modules installed on your computer 
* Deploys a new resource group for the automation account (if needed)
* Deploys a new Automation Account and import the neccessary modules and runbook
* Creates an Automation Schedule which runs every hour
* Connects the Runbook to the Schedule so it will start 

## AVD-PersonalAutoShutdown.ps1


### Download Script
To use the AVD personal scaling script

New-Item -ItemType Directory -Path "C:\Temp" -Force
Set-Location -Path "C:\Temp"
$Uri = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/wvd-templates/wvd-scaling-script/CreateOrUpdateAzAutoAccount.ps1"
# Download the script
Invoke-WebRequest -Uri $Uri -OutFile ".\CreateOrUpdateAzAutoAccount.ps1"

param(
	[Parameter(mandatory = $false)]
	[string]$AADTenantId = '385d54f0-70d2-4728-bd56-3fe93e0fd296',
	
	[Parameter(mandatory = $false)]
	[string]$SubscriptionId = '3e738a78-cead-4895-b39b-0aaee988a0bd',
	
	[Parameter(mandatory = $false)]
	[string]$AutomationRG = "AVDAutoShutdownDEV",

	[Parameter(mandatory = $false)]
	[string] $AutomationAccountName = "AutoAVDAutoShutdown",

	[Parameter(mandatory = $false)]
	[string] $AutomationScheduleName = "AVDShutdownSchedule",

	[Parameter(mandatory = $false)]
	[string]$AVDrg = 'AVD-AADjoin',

	[Parameter(mandatory = $false)]
	[string]$SessionHostrg = 'AVD-AADjoin',

	[Parameter(mandatory = $false)]
	[string]$HostPoolName = 'AADjoin',

	[Parameter(mandatory = $false)]
	[string]$SkipTag = "SkipAutoShutdown",
    
    [Parameter(mandatory = $false)]
	[string]$TimeDifference = "+2:00" ,

	[Parameter(mandatory = $false)]
	[string]$Location = "West Europe"
)
