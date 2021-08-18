
<#
.SYNOPSIS
	This is a sample script to deploy the required resources to execute scaling script in Microsoft Azure Automation Account.
	v0.1.7
#>
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

<# temp, required parameters AVD-PersonalAutoshutdown.ps1
	[Parameter(mandatory = $true)]
	[string]$AADTenantId,
	 
	[Parameter(mandatory = $true)]
	[string]$SubscriptionId,
	
	[Parameter(mandatory = $true)]
	[string]$AVDrg,

    [Parameter(mandatory = $true)]
	[string]$SessionHostrg,

    [Parameter(mandatory = $true)]
	[string]$HostPoolName,

    [Parameter(mandatory = $false)]
	[string]$SkipTag = "SkipAutoShutdown",
    
    [Parameter(mandatory = $false)]
	[string]$TimeDifference = "+2:00"

#>


# Setting ErrorActionPreference to stop script execution when error occurs
$ErrorActionPreference = "Stop"

# Initializing variables
[string]$RunbookName = "AVDPersonalAutoShutdown"
[string]$ArtifactsURI = 'https://raw.githubusercontent.com/stephanvandekruis/AVD/main/PersonalScaling' 

# Set the ExecutionPolicy if not being ran in CloudShell as this command fails in CloudShell
if ($env:POWERSHELL_DISTRIBUTION_CHANNEL -ne 'CloudShell') {
	Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser -Force -Confirm:$false
}

# Import Az and AzureAD modules
Import-Module Az.Resources
Import-Module Az.Accounts
Import-Module Az.OperationalInsights
Import-Module Az.Automation

# Get the azure context
$AzContext = Get-AzContext
if (!$AzContext) {
	throw 'No Azure context found. Please authenticate to Azure using Login-AzAccount cmdlet and then run this script'
}

if (!$AADTenantId) {
	$AADTenantId = $AzContext.Tenant.Id
}
if (!$SubscriptionId) {
	$SubscriptionId = $AzContext.Subscription.Id
}

if ($AADTenantId -ne $AzContext.Tenant.Id -or $SubscriptionId -ne $AzContext.Subscription.Id) {
	# Select the subscription
	$AzContext = Set-AzContext -SubscriptionId $SubscriptionId -TenantId $AADTenantId

	if ($AADTenantId -ne $AzContext.Tenant.Id -or $SubscriptionId -ne $AzContext.Subscription.Id) {
		throw "Failed to set Azure context with subscription ID '$SubscriptionId' and tenant ID '$AADTenantId'. Current context: $($AzContext | Format-List -Force | Out-String)"
	}
}

# Get the Role Assignment of the authenticated user
$RoleAssignments = Get-AzRoleAssignment -SignInName $AzContext.Account -ExpandPrincipalGroups
if (!($RoleAssignments | Where-Object { $_.RoleDefinitionName -in @('Owner', 'Contributor') })) {
	throw 'Authenticated user should have the Owner/Contributor permissions to the subscription'
}

# Check if the resourcegroup exist
$ResourceGroup = Get-AzResourceGroup -Name $AutomationRG -Location $Location -ErrorAction SilentlyContinue
if (!$ResourceGroup) {
	New-AzResourceGroup -Name $AutomationRG -Location $Location -Force -Verbose
	Write-Output "Resource Group was created with name: $AutomationRG"
}

[array]$RequiredModules = @(
	'Az.Accounts'
	'Az.Compute'
	'Az.Resources'
	'Az.Automation'
	'Az.DesktopVirtualization'
)

$SkipHttpErrorCheckParam = (Get-Command Invoke-WebRequest).Parameters['SkipHttpErrorCheck']

# Function to check if the module is imported
function Wait-ForModuleToBeImported {
	param(
		[Parameter(mandatory = $false)]
		[string]$ResourceGroupName = $AutomationRG,

		[Parameter(mandatory = $true)]
		[string]$AutomationAccountName,

		[Parameter(mandatory = $true)]
		[string]$ModuleName
	)

	$StartTime = Get-Date
	$TimeOut = 30*60 # 30 min

	while ($true) {
		if ((Get-Date).Subtract($StartTime).TotalSeconds -ge $TimeOut) {
			throw "Wait timed out. Taking more than $TimeOut seconds"
		}
		$AutoModule = Get-AzAutomationModule -ResourceGroupName $AutomationRG -AutomationAccountName $AutomationAccountName -Name $ModuleName -ErrorAction SilentlyContinue
		if ($AutoModule.ProvisioningState -eq 'Succeeded') {
			Write-Output "Successfully imported module '$ModuleName' into Automation Account Modules"
			break
		}
		Write-Output "Waiting for module '$ModuleName' to get imported into Automation Account Modules ..."
		Start-Sleep -Seconds 30
	}
}


# Function to add required modules to Azure Automation account
function Add-ModuleToAutoAccount {
	param(
		[Parameter(mandatory = $false)]
		[string]$ResourceGroupName = $AutomationRG,

		[Parameter(mandatory = $true)]
		[string]$AutomationAccountName,

		[Parameter(mandatory = $true)]
		[string]$ModuleName,

		# if not specified latest version will be imported
		[Parameter(mandatory = $false)]
		[string]$ModuleVersion
	)

	[string]$Url = "https://www.powershellgallery.com/api/v2/Search()?`$filter=IsLatestVersion&searchTerm=%27$ModuleName $ModuleVersion%27&targetFramework=%27%27&includePrerelease=false&`$skip=0&`$top=40"

	[array]$SearchResult = Invoke-RestMethod -Method Get -Uri $Url
	if ($SearchResult.Count -gt 1) {
		$SearchResult = $SearchResult[0]
	}

	if (!$SearchResult) {
		throw "Could not find module '$ModuleName' on PowerShell Gallery."
	}
	if ($SearchResult.Length -gt 1) {
		throw "Module name '$ModuleName' returned multiple results. Please specify an exact module name."
	}
	$PackageDetails = Invoke-RestMethod -Method Get -Uri $SearchResult.Id

	if (!$ModuleVersion) {
		$ModuleVersion = $PackageDetails.entry.properties.version
	}

	# Check if the required modules are imported
	$ImportedModule = Get-AzAutomationModule -ResourceGroupName $AutomationRG -AutomationAccountName $AutomationAccountName -Name $ModuleName -ErrorAction SilentlyContinue
	if ($ImportedModule -and $ImportedModule.Version -ge $ModuleVersion) {
		return
	}

	[string]$ModuleContentUrl = "https://www.powershellgallery.com/api/v2/package/$ModuleName/$ModuleVersion"

	# Test if the module/version combination exists
	try {
		Invoke-RestMethod $ModuleContentUrl | Out-Null
	}
	catch {
		throw [System.Exception]::new("Module with name '$ModuleName' of version '$ModuleVersion' does not exist. Are you sure the version specified is correct?", $PSItem.Exception)
	}

	# Find the actual blob storage location of the module
	$Res = $null
	do {
		$ActualUrl = $ModuleContentUrl
		if ($SkipHttpErrorCheckParam) {
			$Res = Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -UseBasicParsing -SkipHttpErrorCheck -ErrorAction Ignore
		}
		else {
			$Res = Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -UseBasicParsing -ErrorAction Ignore
		}
		$ModuleContentUrl = $Res.Headers['Location']
	} while ($ModuleContentUrl)

	New-AzAutomationModule -ResourceGroupName $AutomationRG -AutomationAccountName $AutomationAccountName -Name $ModuleName -ContentLink $ActualUrl -Verbose
	Wait-ForModuleToBeImported -ModuleName $ModuleName -ResourceGroupName $AutomationRG -AutomationAccountName $AutomationAccountName
}
# Note: the URL for the scaling script will be suffixed with current timestamp in order to force the ARM template to update the existing runbook script in the auto account if any

$ScriptURI = "$ArtifactsURI/AVD-PersonalAutoShutdown.ps1"


# Creating an automation account & runbook and publish the scaling script file
$DeploymentStatus = New-AzResourceGroupDeployment -ResourceGroupName $AutomationRG -TemplateUri "$ArtifactsURI/AutomationRunbookTemplate.json" -automationAccountName $AutomationAccountName -RunbookName $RunbookName -location $Location -scriptUri "$ScriptURI$($URISuffix)" -Force -Verbose

if ($DeploymentStatus.ProvisioningState -ne 'Succeeded') {
	throw "Some error occurred while deploying a runbook. Deployment Provisioning Status: $($DeploymentStatus.ProvisioningState)"
}




# Required modules imported from Automation Account Modules gallery for Scale Script execution
foreach ($ModuleName in $RequiredModules) {
	Add-ModuleToAutoAccount -ResourceGroupName $AutomationRG -AutomationAccountName $AutomationAccountName -ModuleName $ModuleName
}


Write-Output "Azure Automation Account Name: $AutomationAccountName"
#Write-Output "Webhook URI: $($WebhookURI.value)"

#Creating Automation Schedule
$ScheduleParams = @{
    "AutomationAccountName" = $AutomationAccountName
    "Name"  = $AutomationScheduleName
    "StartTime" = $StartTime = (Get-Date).AddHours(1)
    "ExpiryTime" = $EndTime = $StartTime.AddYears(5)
    "HourInterval" = "1"
    "ResourceGroup" = $AutomationRG
	"TimeZone" = $TimeZone = ([System.TimeZoneInfo]::Local).Id
}

$AutomationScheduleOutput = New-AzAutomationSchedule @ScheduleParams

Write-Output "Azure Automation Schedule $($AutomationScheduleOutput.Name) will first run on $($AutomationScheduleOutput.NextRun)"

##Building params for runbook

$AVDParams = @{
	"AADTenantId"		= $AADTenantId
	"SubscriptionId"	= $SubscriptionId
	"AVDrg"				= $AVDrg
	"SessionHostrg"		= $SessionHostrg
	"HostPoolName"		= $HostPoolName
	"SkipTag"			= $SkipTag
	"TimeDifference"	= $TimeDifference
}

#Connecting Runbook to Azure Automation Schedule

$RegisterParams = @{
    "AutomationAccountName" = $AutomationAccountName
    "Parameters"            =  $AVDParams
    "ResourceGroup" = $AutomationRG
    "RunbookName" = $RunbookName
    "ScheduleName" = $AutomationScheduleName
}
$RegisterScheduleOutput = Register-AzAutomationScheduledRunbook @RegisterParams

Write-Output "Azure Automation Schedule $($AutomationScheduleOutput.Name) is connected to $RunbookName will first run on $($AutomationScheduleOutput.NextRun)"
Write-Output "Do not forget to create a run as account."
Write-Output "The script has completed successfully"
Write-Output "End"