#!/bin/bash

# Output CSV header
echo "VMName,BackupEnabled,SubscriptionName"

# Get the list of subscription IDs and names
subscriptions=$(az account list --query "[].{id:id,name:name,state:state}" -o json | jq -r '.[] | select(.state == "Enabled") | "\(.id),\(.name)"')

# Iterate over each subscription
IFS=$'\n'
for subscription in $subscriptions; do
    subscription_id=$(echo "$subscription" | cut -d',' -f1)
    subscription_name=$(echo "$subscription" | cut -d',' -f2)

    # Set the current subscription context
    az account set --subscription "$subscription_id"

    # Get a list of all resource groups in the current subscription
    resourceGroups=$(az group list --query '[].name' --output tsv)

    # Iterate through each resource group
    while read -r resourceGroup; do
        # Get a list of all VMs in the current resource group
        vms=$(az vm list --resource-group "$resourceGroup" --query '[].name' --output tsv)

        # Iterate through each VM
        while read -r vmName; do
            # Get the VM's service principal, if available
            servicePrincipalId=$(az vm show --resource-group "$resourceGroup" --name "$vmName" --query 'identity.principalId' --output tsv)

            # Check if the VM has the necessary permission to perform backup status action
            if [ -n "$servicePrincipalId" ]; then
                hasBackupPermission=$(az role assignment list --assignee "$servicePrincipalId" --scope "/subscriptions/$subscription_id/resourceGroups/$resourceGroup/providers/Microsoft.RecoveryServices/locations/backupStatus" --query '[].roleDefinitionName' --output tsv)
            else
                hasBackupPermission=""
            fi

            if [ -n "$hasBackupPermission" ]; then
                echo "$vmName,true,$subscription_name"
            else
                echo "$vmName,false,$subscription_name"
            fi
        done <<< "$vms"
    done <<< "$resourceGroups"
done | sed '/^\s*$/d' # Remove empty lines