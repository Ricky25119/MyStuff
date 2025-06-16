# Step 1: Login to Azure
Connect-AzAccount

# Step 2: Set variables
$resourceGroupName = "<your-resource-group>"
$storageAccountName = "<your-storage-account-name>"

# Step 3: Get storage account key
$accountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName)[0].Value

# Step 4: Create storage context
$context = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $accountKey

# Step 5: Get all tables
$tables = Get-AzStorageTable -Context $context

# Step 6: Iterate through tables and get latest Timestamp
foreach ($table in $tables) {
    Write-Host "Checking table: $($table.Name)"

    try {
        # Get table reference
        $cloudTable = $table.CloudTable

        # Create query to get top 1 entity sorted by Timestamp descending
        $query = New-Object Microsoft.Azure.Cosmos.Table.TableQuery
        $query.TakeCount = 1
        $query.SelectColumns = @("Timestamp")

        # Execute query and sort in descending order manually
        $results = $cloudTable.ExecuteQuery($query) | Sort-Object Timestamp -Descending | Select-Object -First 1

        if ($results) {
            Write-Output "Table: $($table.Name) | Last Modified (Entity Timestamp): $($results.Timestamp)"
        } else {
            Write-Output "Table: $($table.Name) | No entities found."
        }
    } catch {
        Write-Output "Error reading table $($table.Name): $_"
    }
}
