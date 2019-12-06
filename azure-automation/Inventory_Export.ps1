<#
.SYNOPSIS  
	 Exports Azure resources in a subscription to a CSV file in blob storage

.DESCRIPTION  
	 This runbook exports Azure resources in a subscription to a CSV file in blob storage.

	 This runbook requires the Azure Automation Run-As (Service Principle) account, which must be added when creating the Azure Automation account.

.EXAMPLE  
	.\Inventory_Export.ps1 -StorageAccountName "mystorageaccount" -StorageAccountResourceGroupName "inventory-reporting-rg" -StorageAccountContainerName "export"

.PARAMETER

    - StorageAccountName                : Name of the storage account to use for export
    - StorageAccountResourceGroupName   : Name of the resource group containing the storage account
    - StorageAccountContainerName       : Name of the storage account container to be used for export
#>
Param(
[Parameter(Mandatory=$true,HelpMessage="Enter the name of the storage account to use for export")][String]$StorageAccountName,
[Parameter(Mandatory=$true,HelpMessage="Enter the name of the resource group containing the storage account to use for export")][String]$StorageAccountResourceGroupName,
[Parameter(Mandatory=$true,HelpMessage="Enter the name of the storage container for export")][string]$StorageAccountContainerName
)

# establish automation credentials
$connectionName = "AzureRunAsConnection"
$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName

Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

# settings
$defaultPath = "c:\Temp\azureresources.csv"
$csvDelimiter = ';'
  
# receive all subscriptions
$subscriptions = Get-AzureRmSubscription
$subscriptions | ft SubscriptionId, @{Name="Name";Expression={if(!$_.SubscriptionName) { $_.Name; } else { $_.SubscriptionName } } }
  
# select azure subscriptions that you want to export
$subscriptionIds = ""
  
if([String]::IsNullOrWhiteSpace($subscriptionIds)) {
    $subscriptionIds = @($subscriptions | select -ExpandProperty SubscriptionId)
}
elseif($subscriptionIds.Contains(',')) {
    $subscriptionIds = $subscriptionIds.Split(',')
}
else {
    $subscriptionIds = @($subscriptionIds)
}
  
# configure csv output
$path = $defaultPath
  
if (Test-Path $path) { 
        Remove-Item $path
}
  
"Start exporting data..."
foreach($subscriptionId in $subscriptionIds) {
    # change azure subscription
    [void](Set-AzureRmContext -SubscriptionID $subscriptionId)
    # read subscription name as we want to see it in the exported csv
    $currentSubscription = ($subscriptions | Where { $_.SubscriptionId -eq $subscriptionId })
    $subscriptionName = $currentSubscription.SubscriptionName
    if([String]::IsNullOrEmpty($subscriptionName)) {
        $subscriptionName = $currentSubscription.Name
    }
      
    $subscriptionSelector = @{ Label="SubscriptionName"; Expression={$subscriptionName} }
    $tagSelector =  @{Name="Tags";Expression={ if($_.Tags -ne $null) { $x = $_.Tags.GetEnumerator() | %{ "{ `"" + $_.Name + "`" : `"" + $_.Value + "`" }, " }; ("{ " + ([string]$x).TrimEnd(", ") + " }") } }}
    #get resources from azure subscription
    $export = Get-AzureRmResource | select *, $subscriptionSelector, $tagSelector -ExcludeProperty "Tags"
    $export | Export-CSV $path -Delimiter $csvDelimiter -Append -Force -NoTypeInformation
    "Exported " + $subscriptionId + " - " + $subscriptionName
}
  
"Export done, writing blob..."
Set-AzureRmCurrentStorageAccount -StorageAccountName $StorageAccountName -ResourceGroupName $StorageAccountResourceGroupName
Set-AzureStorageBlobContent -Container $StorageAccountContainerName -File $path -Blob resources.csv -Force
"Job complete"
