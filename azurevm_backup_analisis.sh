#!/bin/bash

# Output CSV header
echo "VMName,BackupEnabled,SubscriptionName,DiskName,DiskSizeGB"

# Get the list of subscription IDs and names
subscriptions=$(az account list --query "[].{id:id,name:name,state:state}" -o json | jq -r '.[] | select(.state == "Enabled") | "\(.id),\(.name)"')

IFS=$'\n'
for subscription in $subscriptions; do
    subscription_id=$(echo "$subscription" | cut -d',' -f1)
    subscription_name=$(echo "$subscription" | cut -d',' -f2)

    # Set the current subscription context
    az account set --subscription "$subscription_id"

    # Get a list of all resource groups in the current subscription
    resourceGroups=$(az group list --query '[].name' --output tsv)

    while read -r resourceGroup; do
        # Get a list of all VMs in the current resource group
        vms=$(az vm list --resource-group "$resourceGroup" --query '[].name' --output tsv)

        while read -r vmName; do
            # Get the VM's service principal, if available
            servicePrincipalId=$(az vm show --resource-group "$resourceGroup" --name "$vmName" --query 'identity.principalId' --output tsv)

            # Check if the VM has the necessary permission to perform backup status action
            if [ -n "$servicePrincipalId" ]; then
                hasBackupPermission=$(az role assignment list --assignee "$servicePrincipalId" --scope "/subscriptions/$subscription_id/resourceGroups/$resourceGroup/providers/Microsoft.RecoveryServices/locations/backupStatus" --query '[].roleDefinitionName' --output tsv)
            else
                hasBackupPermission=""
            fi

            # Initialize variable to track backup status
            backupEnabled="false"
            if [ -n "$hasBackupPermission" ]; then
                backupEnabled="true"
            fi

            # Get the list of disks (both OS and data disks) attached to the VM
           disks=$(az vm show --resource-group "$resourceGroup" --name "$vmName" --query "{osDisk: storageProfile.osDisk, dataDisks: storageProfile.dataDisks[]}" --output json | jq -r '.osDisk | "\(.name),\(.diskSizeGb)" , (.dataDisks[]? | "\(.name),\(.diskSizeGb)")')

            # Check if there are no disks attached
            if [ -z "$disks" ]; then
                # Print VM info without disks if none are attached
                echo "$vmName,$backupEnabled,$subscription_name,N/A,N/A"
            else
                # Iterate through each disk and print VM and disk info
                while IFS= read -r disk; do
                    diskName=$(echo "$disk" | cut -d',' -f1)
                    diskSize=$(echo "$disk" | cut -d',' -f2)
                    echo "$vmName,$backupEnabled,$subscription_name,$diskName,$diskSize"
                done <<< "$disks"
            fi
        done <<< "$vms"
    done <<< "$resourceGroups"
    done | grep -E '^[^,]+,(true|false),.+,.+,.+'