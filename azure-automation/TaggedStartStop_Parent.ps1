<#
.SYNOPSIS  
	 Wrapper script for get all the VM's based on VM or subscription tag and then call the ScheduledStarStop_Child runbook
.DESCRIPTION  
	 This runbook is intended to start/stop ARM based VMs that are tagged with a specific tag.
		
	 This runbook requires the Azure Automation Run-As (Service Principle) account, which must be added when creating the Azure Automation account.
.EXAMPLE  
	.\TaggedStartStop_Parent.ps1 -Action "stop" -StartStopTagValue "a"

.PARAMETER
    - Action                  : Valid values are "start" and "stop". Indicates the action to perform on matching resources
    - StartStopTagValue       : Value for tag to consider resource as valid for selection on this run
   
#>

Param(
[Parameter(Mandatory=$true,HelpMessage="Enter the value for Action. Value can be either stop or start")][String]$Action,
[Parameter(Mandatory=$true,HelpMessage="Value of startStopSchedule tag to select for inclusion")][string]$StartStopTagValue
)

# establish automation credentials
$connectionName = "AzureRunAsConnection"
$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName

Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

# these variables are present in the existing Start/Stop solution
$automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
$aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'

# initialize list to build VMs that will be stopped/started
[Hashtable] $includeVms = @{}
[Hashtable] $excludeVms = @{}

$tagToInclude = @{startStopSchedule="$($StartStopTagValue)"}
$tagToExclude = @{startStopExcluded="true"}
$taggedVMList = Get-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines -Tag $tagToInclude
foreach($vmResource in $taggedVMList)
{
    Write-Output "Adding VM: " $vmResource.Name
    $key = $vmResource.ResourceGroupName + $vmResource.Name
    $resourceToAdd = @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "ResourceManager"}
    $includeVms[$key] = $resourceToAdd
}

# get child VMs of tagged resource groups here in addition to (or instead of) machine tags
$taggedResourceGroupList = Get-AzureRmResourceGroup -Tag $tagToInclude
foreach($resourceGroup in $taggedResourceGroupList)
{
    Write-Output "Adding VMs from tagged Resource Group: " $resourceGroup.ResourceGroupName
    $rgVMList = Get-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines -ResourceGroupName $resourceGroup.ResourceGroupName
    
    foreach($vmResource in $rgVMList)
    {  
        Write-Output "Adding VM: " $vmResource.Name
        $key = $vmResource.ResourceGroupName + $vmResource.Name
        $resourceToAdd = @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "ResourceManager"}
        $includeVms[$key] = $resourceToAdd
    }
}

Write-Output "Processing Exclusions"
$excludedVmList = Get-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines -Tag $tagToExclude
foreach($vmResource in $excludedVmList)
{
    Write-Output "Adding Exclusion for VM: " $vmResource.Name
    $key = $vmResource.ResourceGroupName + $vmResource.Name
    $resourceToExclude = @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "ResourceManager"}
    $excludeVms[$key] = $resourceToExclude
}
# Remove excluded VMs from the list
foreach($vmExclusionKey in $excludeVms.Keys)
{
    if($includeVms.ContainsKey($vmExclusionKey))
    {
        $includeVms.Remove($vmExclusionKey)
    }
}


foreach($vmResource in $includeVms.Values)
{
    # run the existing child runbook
    $params = @{"VMName"="$($vmResource.Name)";"Action"="$($Action.ToLower())";"ResourceGroupName"="$($vmResource.ResourceGroupName)"}
    $runbook = Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName `
        -Name "ScheduledStartStop_Child" `
        -ResourceGroupName $aroResourceGroupName `
        -Parameters $params
}