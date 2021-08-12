param(
	[Parameter(mandatory = $true)]
	[string]$AADTenantId = '385d54f0-70d2-4728-bd56-3fe93e0fd296',
	 
	[Parameter(mandatory = $true)]
	[string]$SubscriptionId = '3e738a78-cead-4895-b39b-0aaee988a0bd',
	
	[Parameter(mandatory = $true)]
	[string]$AVDrg = "AVD-AADjoin",

    [Parameter(mandatory = $true)]
	[string]$SessionHostrg = "AVD-AADjoin",

    [Parameter(mandatory = $true)]
	[string]$HostPoolName = "AADjoin",

    [Parameter(mandatory = $false)]
	[string]$SkipTag = "SkipAutoShutdown",
    
    [Parameter(mandatory = $false)]
	[string]$TimeDifference = "+2:00"

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
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    Write-log "Logging in to Azure..."
    $connecting = Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}



#starting script
Write-Log 'Starting AVD Personal Host Pool auto shutdown script'

Write-Log 'Getting Host Pool information'
$Hostpool = Get-AzWvdHostPool -SubscriptionId $SubscriptionId -Name $HostPoolName -ResourceGroupName $AVDrg

#check if host pool is set to personal and Start On Connect is enabled
if($Hostpool.HostPoolType -eq 'Personal'){
    Write-Log 'The host pool type is Personal'
} else {
    throw "The hostpool type is not set to personal. Pooled host pools are not supported by this script." 
}
if($Hostpool.StartVMOnConnect -eq 'True'){
    Write-Log 'Start on Connect is enabled for hostpool'
} else {
    throw "Start On connect is not enabled for the hostpool $($HostPool.Name)" 
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
    #Gathering information about the running state
    $VMStatus = (Get-AzVM -ResourceGroupName $SessionHostrg -Name $SessionHostName -Status).Statuses[1].Code
    #Gathering information about tags
    $VMSkip = (Get-AzVm -ResourceGroupName $SessionHostrg -Name $SessionHostName).Tags.Keys

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
            Write-Log "$SessionHostName is running and has an active session"
        }
        #VM is running but has no active session, time to deallocate VM
        if ($Sessionhost.Session -eq '0'  -and $Sessionhost.Status -eq 'Available'){
            Write-Log "$SessionHostName is running, but has no active sessions"
            Write-Log "Trying to deallocate $SessionHostName"
            $StopVM = Stop-AzVM -Name $SessionHostName -ResourceGroupName $ResourceGroupName -Force
            Write-Log "Stopping $SessionhostName ended with status: $($StopVM.Status)"
        }   
    }  

}
Write-Log 'All VMs are processed'
Write-Log 'Disconnecting AZ Session'
#disconnect
$DisconnectInfo = Disconnect-AzAccount

Write-Log 'End'

#disconnect
$DisconnectInfo = Disconnect-AzAccount
