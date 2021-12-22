<#
.SYNOPSIS
  The script can be used to shut down Azure Virtual Desktop Personal Session Hosts which have no active sessions. 
.DESCRIPTION
The script does the following:
* Checks if the host pool is set to personal, pooled is not supported
* Checks if start on Connect is enabled. Link to how to configure this https://docs.microsoft.com/en-us/azure/virtual-desktop/start-virtual-machine-connect
* Collects all the Session Hosts in the host pool
* If the Session Host is running it checks if there is an active session, if there are no active sessions the Session Host will be Deallocated

Required Powershell modules:
	'Az.Accounts'
	'Az.Compute'
	'Az.Resources'
	'Az.Automation'
	'Az.DesktopVirtualization'

.PARAMETER AADTenantId
    The tenant ID of the tenant you want to deploy this script in
.PARAMETER SubscriptionId
    Subscription ID of where the Session Hosts are hosted
.PARAMETER AVDrg
    The resource group where the Azure Virtual Desktop object (e.g. the host pool) is located
.PARAMETER SessionHostrg
    The resource group where the Virtual Machines that are connected to the Host Pool are located
.PARAMETER HostPoolName
    The host pool name you want to auto shutdown
.PARAMETER SkipTag
    The name of the tag, which will exclude the VM from scaling. The default value is SkipAutoShutdown
.PARAMETER TimeDifference
    The time diference with UTC (e.g. +2:00)                    
.NOTES
  Version:        1.0
  Author:         Stephan van de Kruis
  Creation Date:  19/08/2021
  Purpose/Change: Initial script development

  29-10-2021
  Version:         1.1
  Purpose/Change:   Improvements
  
#>

param(
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

)

[array]$RequiredModules = @(
	'Az.Accounts'
	'Az.Compute'
	'Az.Resources'
	'Az.Automation'
	'Az.DesktopVirtualization'
)


[string[]]$TimeDiffHrsMin = "$($TimeDifference):0".Split(':')
#Functions

function Write-Log {
    # Note: this is required to support param such as ErrorAction
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$Err,

        [switch]$Warn
    )

    [string]$MessageTimeStamp = (Get-LocalDateTime).ToString('yyyy-MM-dd HH:mm:ss')
    $Message = "[$($MyInvocation.ScriptLineNumber)] $Message"
    [string]$WriteMessage = "$MessageTimeStamp $Message"

    if ($Err) {
        Write-Error $WriteMessage
        $Message = "ERROR: $Message"
    }
    elseif ($Warn) {
        Write-Warning $WriteMessage
        $Message = "WARN: $Message"
    }
    else {
        Write-Output $WriteMessage
    }

}

	# Function to return local time converted from UTC
function Get-LocalDateTime {
    return (Get-Date).ToUniversalTime().AddHours($TimeDiffHrsMin[0]).AddMinutes($TimeDiffHrsMin[1])
}

# Authenticating

try
{


    Write-log "Logging in to Azure..."
    $connecting = Connect-AzAccount -identity 

}
catch {
        Write-Error -Message $_.Exception
        Write-log "Unable to sign in, terminating script.."
        throw $_.Exception

}

#starting script
Write-Log 'Starting AVD Personal Host Pool auto shutdown script'


Write-Log 'Checking if required modules are installed in the Automation Account'
# Checking if required modules are present 
foreach ($ModuleName in $RequiredModules) {
    if (Get-Module -ListAvailable -Name $ModuleName) {
        Write-Log "$($ModuleName) is present"
    } 
    else {
        Write-Log "$($ModuleName) is not present. Make sure to import the required modules in the Automation Account. Check the desription"
        #throw
    }
}

Write-Log 'Getting Host Pool information'
$Hostpool = Get-AzWvdHostPool -SubscriptionId $SubscriptionId -Name $HostPoolName -ResourceGroupName $AVDrg

#check if host pool is set to personal and Start On Connect is enabled
if($Hostpool.HostPoolType -eq 'Personal'){
    Write-Log 'The host pool type is Personal'
} else {
    Write-log 'The hostpool type is not set to personal. Pooled host pools are not supported by this script.'
    throw 
}
if($Hostpool.StartVMOnConnect -eq 'True'){
    Write-Log 'Start on Connect is enabled for hostpool'
} else {
    Write-Log 'Start on Connect is not enabled, save money and enable this feature'
    }


#Getting Session hosts information
Write-Log 'Getting all session hosts'
$SessionHosts = @(Get-AzWvdSessionHost -ResourceGroupName $SessionHostrg  -HostPoolName $HostPoolName)
if (!$SessionHosts) {
    Write-Log "There are no session hosts in the Hostpool $($HostPool.Name). Ensure that hostpool has session hosts"
    Write-Log 'End'
    return
}

#Evaluate eacht session hosts
foreach ($SessionHost in $Sessionhosts) {
    $Domain,$SessionHostName = $SessionHost.Name.Split("/")
    $VMinstance,$DomainName,$ToplevelDomain = $SessionHostName.Split(".")
    #Gathering information about the running state
    $VMStatus = (Get-AzVM -ResourceGroupName $SessionHostrg -Name $VMinstance -Status).Statuses[1].Code
    #Gathering information about tags
    $VMSkip = (Get-AzVm -ResourceGroupName $SessionHostrg -Name $VMinstance).Tags.Keys

    # If VM is Deallocated we can skip    
    if($VMStatus -eq 'PowerState/deallocated'){
        Write-Log "$SessionHostName is in a deallocated state, processing next session hosts"
        continue
    }
    # If VM has skiptag we can skip
    if ($VMSkip -contains $SkipTag) {
        Write-Log "VM '$SessionHostName' contains the skip tag and will be ignored"
        continue
    }


    #for running vms
    if($VMStatus -eq 'PowerState/running'){
        Write-Log "$SessionHostName is running, checking for active sessions"
        #vm is running and has an active session, no action required
        if ($Sessionhost.Session -eq '1'  -and $Sessionhost.Status -eq 'Available'){
            Write-Log "$SessionHostName is running and has an active session, not taking action."
        }
        #VM is running but has no active session, time to deallocate VM
        if ($Sessionhost.Session -eq '0'  -and $Sessionhost.Status -eq 'Available'){
            Write-Log "$SessionHostName is running, but has no active sessions."
            Write-Log "Trying to deallocate $SessionHostName."
            $StopVM = Stop-AzVM -Name $VMinstance -ResourceGroupName $SessionHostrg -Force
            Write-Log "Stopping $SessionhostName ended with status: $($StopVM.Status)"
            #Create Extra check
        }   
    }  
}
Write-Log 'All VMs are processed'
Write-Log 'Disconnecting AZ Session'
#disconnect
$DisconnectInfo = Disconnect-AzAccount

Write-Log 'End'
