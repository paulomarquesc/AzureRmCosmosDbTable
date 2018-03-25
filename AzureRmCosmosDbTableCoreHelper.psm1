
<#
.SYNOPSIS
	AzureRmCosmosDbTableCoreHelper.psm1 - PowerShell Module that contains all functions related to manipulating Azure Storage Table rows/entities.
.DESCRIPTION
  	AzureRmCosmosDbTableCoreHelper.psm1 - PowerShell Module that contains all functions related to manipulating Azure Storage Table rows/entities.
.NOTES
	Make sure the latest Azure PowerShell module is installed since we have a dependency on Microsoft.WindowsAzure.Storage.dll and 
    Microsoft.WindowsAzure.Commands.Common.Storage.dll.

	If running this module from Azure Automation, please make sure you check out this blog post for more information:
	https://blogs.technet.microsoft.com/paulomarques/2017/01/17/working-with-azure-storage-tables-from-powershell/
	
	Requirements:

	AzureRm.Profile
	AzureRm.Storage
	AzureRM.Resources
#>

#Requires -Modules AzureRm.Profile, AzureRM.Resources

# Loading required assemblies
[System.Reflection.Assembly]::LoadFile((join-path $PSScriptRoot  'Microsoft.Azure.Documents.Client.dll'))
[System.Reflection.Assembly]::LoadFile((join-path $PSScriptRoot  'Microsoft.Azure.Storage.Common.dll'))
[System.Reflection.Assembly]::LoadFile((join-path $PSScriptRoot  'Microsoft.Data.Edm.dll'))
[System.Reflection.Assembly]::LoadFile((join-path $PSScriptRoot  'Microsoft.Data.OData.dll'))
[System.Reflection.Assembly]::LoadFile((join-path $PSScriptRoot  'Microsoft.Data.Services.Client.dll'))
[System.Reflection.Assembly]::LoadFile((join-path $PSScriptRoot  'Microsoft.OData.Edm.dll'))
[System.Reflection.Assembly]::LoadFile((join-path $PSScriptRoot  'Microsoft.Spatial.dll'))
[System.Reflection.Assembly]::LoadFile((join-path $PSScriptRoot  'Newtonsoft.Json.dll'))
[System.Reflection.Assembly]::LoadFile((join-path $PSScriptRoot  'System.Spatial.dll'))
[System.Reflection.Assembly]::LoadFile((join-path $PSScriptRoot  'Microsoft.Azure.CosmosDB.Table.dll'))

# Module Functions

# Assembly Resolve Event Handler
$newtonSoft = [Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot  "Newtonsoft.Json.dll"))
$storageCommon = [Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot  "Microsoft.Azure.Storage.Common.dll"))

$onAssemblyResolveEventHandler = [System.ResolveEventHandler] {
	param($sender, $e)
		
	# Specific versions
	if ($e.Name.StartsWith("Newtonsoft.Json"))
	{
	  return $newtonSoft
	}

	if ($e.Name.StartsWith("Microsoft.Azure.Storage.Common"))
	{
	  return $storageCommon
	}

	foreach($assembly in [System.AppDomain]::CurrentDomain.GetAssemblies())
	{
	  if ($assembly.FullName -eq $e.Name)
	  {
			return $assembly
	  }
	}

	return $null
  }
[System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolveEventHandler)



function Test-AzureCosmosDbTableEmptyKeys
{
	[CmdletBinding()]
	param
	(
		[string]$partitionKey,
        [String]$rowKey
	)
    
    $cosmosDBEmptyKeysErrorMessage = "Cosmos DB table API does not accept empty partition or row keys when using CloudTable.Execute operation, because of this we are disabling this capability in this module and it will not proceed." 

    if ([string]::IsNullOrEmpty($partitionKey) -or [string]::IsNullOrEmpty($rowKey))
    {
        Throw $cosmosDBEmptyKeysErrorMessage
    }
}

function Get-AzureCosmosDbTableTable
{
	<#
	.SYNOPSIS
		Gets a Table object from Azure Cosmos DB.
	.DESCRIPTION
		Gets a Table object from Cosmos DB.
	.PARAMETER resourceGroup
        Resource Group where Cosmos DB Account is located
    .PARAMETER tableName
        Name of the table to retrieve
    .PARAMETER cosmosDbAccount
        CosmosDB account name where the table lives
	.EXAMPLE
		# Getting Cosmos DB table object
		$resourceGroup = "myResourceGroup"
		$databaseName = "myCosmosDbName"
		$tableName = "table01"
		$table01 = Get-AzureCosmosDbTabletable -resourceGroup $resourceGroup -tableName $tableName -cosmosDbAccount $databaseName
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		[string]$resourceGroup,
		
		[Parameter(Mandatory=$true)]
        [String]$tableName,

		[Parameter(Mandatory=$true)]
		[Alias("databaseName")]
        [String]$cosmosDbAccount
	)

    $nullTableErrorMessage = [string]::Empty

	$dllDependenciesFile = Join-Path $PSScriptRoot "dependencies.txt"
	if (-not (Test-Path $dllDependenciesFile))
	{
		throw "Required dependencies to work with Cosmos DB not downloaded.`nPlease open an elevated PowerShell prompt, change folder to $PSScriptRoot and execute Install-CosmosDbinstallPreReqs.ps1 script to download and install necessary dependencies."
	}

	$keys = Invoke-AzureRmResourceAction -Action listKeys -ResourceType "Microsoft.DocumentDb/databaseAccounts" -ApiVersion "2015-04-08" -ResourceGroupName $resourceGroup -Name $cosmosDbAccount -Force

	if ($keys -eq $null)
	{
		throw "Cosmos DB Database $cosmosDbAccount didn't return any keys."
	}

	$connString = [string]::Format("DefaultEndpointsProtocol=https;AccountName={0};AccountKey={1};TableEndpoint=https://{0}.table.cosmosdb.azure.com",$cosmosDbAccount,$keys.primaryMasterKey)
	[Microsoft.Azure.Storage.CloudStorageAccount]$cosmosDbAcct = [Microsoft.Azure.Storage.CloudStorageAccount]::Parse($connString)
	[Microsoft.Azure.CosmosDB.Table.CloudTableClient]$tableClient = [Microsoft.Azure.CosmosDB.Table.CloudTableClient]::new($cosmosdbacct.TableEndpoint,$cosmosdbacct.Credentials)
	[Microsoft.Azure.CosmosDB.Table.CloudTable]$table = [Microsoft.Azure.CosmosDB.Table.CloudTable]$tableClient.GetTableReference($tableName)

	$table.CreateIfNotExists() | Out-Null

	$nullTableErrorMessage = "Table $tableName could not be retrieved from Cosmos DB database name $cosmosDbAccount on resource group $resourceGroupName"

    # Checking if there a table got returned
    if ($table -eq $null)
    {
        throw $nullTableErrorMessage
    }
	
	# Cosmos DB GA Version
	return [Microsoft.Azure.CosmosDB.Table.CloudTable]$table
}

function Add-AzureCosmosDbTableRow
{
	<#
	.SYNOPSIS
		Adds a row/entity to a specified table
	.DESCRIPTION
		Adds a row/entity to a specified table
	.PARAMETER Table
		Table object of type Microsoft.Azure.CosmosDB.Table.CloudTable where the entity will be added
	.PARAMETER PartitionKey
		Identifies the table partition
	.PARAMETER RowKey
		Identifies a row within a partition
	.PARAMETER Property
		Hashtable with the columns that will be part of the entity. e.g. @{"firstName"="Paulo";"lastName"="Marques"}
	.EXAMPLE
		# Adding a row
		$table = Get-AzureCosmosDbTableTable -resourceGroup storageAndtables-rg -tableName table01 -cosmosDbAccount pmccosmosdb01
		$partitionKey = "testpartition"
		Add-AzureCosmosDbTableRow -table $table -partitionKey $partitionKey -rowKey ([guid]::NewGuid().tostring()) -property @{"firstName"="Paulo";"lastName"="Costa";"role"="presenter"}
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		$table,
		
		[Parameter(Mandatory=$true)]
        [String]$partitionKey,

		[Parameter(Mandatory=$true)]
        [String]$rowKey,

		[Parameter(Mandatory=$false)]
        [hashtable]$property
	)
	
	# Creates the table entity with mandatory partitionKey and rowKey arguments
	$entity = New-Object -TypeName "Microsoft.Azure.CosmosDB.Table.DynamicTableEntity" -ArgumentList $partitionKey, $rowKey
    
    # Adding the additional columns to the table entity
	foreach ($prop in $property.Keys)
	{
		if ($prop -ne "TableTimestamp")
		{
			$entity.Properties.Add($prop, $property.Item($prop))
		}
	}
    
	# Adding the dynamic table entity to the table
	
	$table.Execute([Microsoft.Azure.CosmosDB.Table.TableOperation]::Insert($entity)) | Out-Null

}

function Get-PSObjectFromEntity
{
	# Internal function
	# Converts entities output from the ExecuteQuery method of table into an array of PowerShell Objects

	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		$entityList
	)

	$returnObjects = @()

	if (-not [string]::IsNullOrEmpty($entityList))
	{
		foreach ($entity in $entityList)
		{
			$entityNewObj = New-Object -TypeName psobject
			$entity.Properties.Keys | ForEach-Object {Add-Member -InputObject $entityNewObj -Name $_ -Value $entity.Properties[$_].PropertyAsObject -MemberType NoteProperty}

			# Adding table entity other attributes
			Add-Member -InputObject $entityNewObj -Name "PartitionKey" -Value $entity.PartitionKey -MemberType NoteProperty
			Add-Member -InputObject $entityNewObj -Name "RowKey" -Value $entity.RowKey -MemberType NoteProperty
			Add-Member -InputObject $entityNewObj -Name "TableTimestamp" -Value $entity.Timestamp -MemberType NoteProperty
			Add-Member -InputObject $entityNewObj -Name "Etag" -Value $entity.Etag -MemberType NoteProperty

			$returnObjects += $entityNewObj
		}
	}

	return $returnObjects

}

function Get-AzureCosmosDbTableRowAll
{
	<#
	.SYNOPSIS
		Returns all rows/entities from a storage table - no filtering
	.DESCRIPTION
		Returns all rows/entities from a storage table - no filtering
	.PARAMETER Table
		Table object of type Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageTable to retrieve entities
	.EXAMPLE
		# Getting all rows
		Get-AzureStorageTableRowAll -table $table
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		$table
	)

	$tableQuery = New-Object -TypeName "Microsoft.Azure.CosmosDB.Table.TableQuery"
	
	[Collections.Generic.IEnumerable[Microsoft.Azure.CosmosDB.Table.DynamicTableEntity]]$result = $table.ExecuteQuery($tableQuery)
		
	return (Get-PSObjectFromEntity -entityList $result)

}

function Get-AzureStorageTableRowByPartitionKey
{
	<#
	.SYNOPSIS
		Returns one or more rows/entities based on Partition Key
	.DESCRIPTION
		Returns one or more rows/entities based on Partition Key
	.PARAMETER Table
		Table object of type Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageTable to retrieve entities
	.PARAMETER PartitionKey
		Identifies the table partition
	.EXAMPLE
		# Getting rows by partition Key
		Get-AzureStorageTableRowByPartitionKey -table $table -partitionKey $newPartitionKey
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		$table,

		[Parameter(Mandatory=$true)]
		[string]$partitionKey
	)

		$tableQuery = New-Object -TypeName "Microsoft.Azure.CosmosDB.Table.TableQuery"

		[string]$filter = `
		 	[Microsoft.Azure.CosmosDB.Table.TableQuery]::GenerateFilterCondition("PartitionKey",`
		 		[Microsoft.Azure.CosmosDB.Table.QueryComparisons]::Equal,$partitionKey)

		$tableQuery.FilterString = $filter

  	    $result = $table.ExecuteQuery($tableQuery)

	   return (Get-PSObjectFromEntity -entityList $result)
}

function Get-AzureStorageTableRowByColumnName
{
	<#
	.SYNOPSIS
		Returns one or more rows/entities based on a specified column and its value
	.DESCRIPTION
		Returns one or more rows/entities based on a specified column and its value
	.PARAMETER Table
		Table object of type Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageTable to retrieve entities
	.PARAMETER ColumnName
		Column name to compare the value to
	.PARAMETER Value
		Value that will be looked for in the defined column
	.PARAMETER Operator
		Supported comparison operator. Valid values are "Equal","GreaterThan","GreaterThanOrEqual","LessThan" ,"LessThanOrEqual" ,"NotEqual"
	.EXAMPLE
		# Getting row by firstname
		Get-AzureStorageTableRowByColumnName -table $table -columnName "firstName" -value "Paulo" -operator Equal
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		$table,

		[Parameter(Mandatory=$true)]
		[string]$columnName,

		[Parameter(ParameterSetName="byString",Mandatory=$true)]
		[AllowEmptyString()]
		[string]$value,

		[Parameter(ParameterSetName="byGuid",Mandatory=$true)]
		[guid]$guidValue,

		[Parameter(Mandatory=$true)]
		[validateSet("Equal","GreaterThan","GreaterThanOrEqual","LessThan" ,"LessThanOrEqual" ,"NotEqual")]
		[string]$operator
	)
	
	# Filtering by Partition Key

	$tableQuery = New-Object -TypeName "Microsoft.Azure.CosmosDB.Table.TableQuery"

	if ($PSCmdlet.ParameterSetName -eq "byString") {			
		[string]$filter = `
			[Microsoft.Azure.CosmosDB.Table.TableQuery]::GenerateFilterCondition($columnName,[Microsoft.Azure.CosmosDB.Table.QueryComparisons]::$operator,$value)
	}

	if ($PSCmdlet.ParameterSetName -eq "byGuid") {
		[string]$filter = `
			[Microsoft.Azure.CosmosDB.Table.TableQuery]::GenerateFilterConditionForGuid($columnName,[Microsoft.Azure.CosmosDB.Table.QueryComparisons]::$operator,$guidValue)
	}

	$tableQuery.FilterString = $filter
	$result = $table.ExecuteQuery($tableQuery)

	if (-not [string]::IsNullOrEmpty($result))
	{
		return (Get-PSObjectFromEntity -entityList $result)
	}
}

function Get-AzureStorageTableRowByCustomFilter
{
	<#
	.SYNOPSIS
		Returns one or more rows/entities based on custom filter.
	.DESCRIPTION
		Returns one or more rows/entities based on custom filter. This custom filter can be
		built using the Microsoft.WindowsAzure.Storage.Table.TableQuery class or direct text.
	.PARAMETER Table
		Table object of type Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageTable to retrieve entities
	.PARAMETER customFilter
		Custom filter string.
	.EXAMPLE
		# Getting row by firstname by using the class Microsoft.WindowsAzure.Storage.Table.TableQuery
		Get-AzureStorageTableRowByCustomFilter -table $table -customFilter $finalFilter
	.EXAMPLE
		# Getting row by firstname by using text filter directly (oData filter format)
		Get-AzureStorageTableRowByCustomFilter -table $table -customFilter "(firstName eq 'User1') and (lastName eq 'LastName1')"
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		$table,

		[Parameter(Mandatory=$true)]
		[string]$customFilter
	)
	
	# Filtering by Partition Key
	$tableQuery = New-Object -TypeName "Microsoft.Azure.CosmosDB.Table.TableQuery"

	$tableQuery.FilterString = $customFilter

	$result = $table.ExecuteQuery($tableQuery)

	if (-not [string]::IsNullOrEmpty($result))
	{
		return (Get-PSObjectFromEntity -entityList $result)
	}
}

function Update-AzureStorageTableRow
{
	<#
	.SYNOPSIS
		Updates a table entity
	.DESCRIPTION
		Updates a table entity. To work with this cmdlet, you need first retrieve an entity with one of the Get-AzureStorageTableRow cmdlets available
		and store in an object, change the necessary properties and then perform the update passing this modified entity back, through Pipeline or as argument.
		Notice that this cmdlet accepts only one entity per execution. 
		This cmdlet cannot update Partition Key and/or RowKey because it uses those two values to locate the entity to update it, if this operation is required
		please delete the old entity and add the new one with the updated values instead.
	.PARAMETER Table
		Table object of type Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageTable where the entity exists
	.PARAMETER Entity
		The entity/row with new values to perform the update.
	.EXAMPLE
		# Updating an entity
		[string]$filter = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::GenerateFilterCondition("firstName",[Microsoft.WindowsAzure.Storage.Table.QueryComparisons]::Equal,"User1")
		$person = Get-AzureStorageTableRowByCustomFilter -table $table -customFilter $filter
		$person.lastName = "New Last Name"
		$person | Update-AzureStorageTableRow -table $table
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		$table,

		[Parameter(Mandatory=$true,ValueFromPipeline=$true)]
		$entity
	)
    
    # Only one entity at a time can be updated
    $updatedEntityList = @()
    $updatedEntityList += $entity

    if ($updatedEntityList.Count -gt 1)
    {
        throw "Update operation can happen on only one entity at a time, not in a list/array of entities."
    }

	$updatedEntity = New-Object -TypeName "Microsoft.Azure.CosmosDB.Table.DynamicTableEntity" -ArgumentList $entity.PartitionKey, $entity.RowKey

	# Iterating over PS Object properties to add to the updated entity 
	foreach ($prop in $entity.psobject.Properties)
	{
		if (($prop.name -ne "PartitionKey") -and ($prop.name -ne "RowKey") -and ($prop.name -ne "Timestamp") -and ($prop.name -ne "Etag") -and ($prop.name -ne "TableTimestamp"))
		{
			$updatedEntity.Properties.Add($prop.name, $prop.Value)
		}
	}

	$updatedEntity.ETag = $entity.Etag

	$table.Execute([Microsoft.Azure.CosmosDB.Table.TableOperation]::Replace($updatedEntity)) | Out-Null
}

function Remove-AzureStorageTableRow
{
	<#
	.SYNOPSIS
		Remove-AzureStorageTableRow - Removes a specified table row
	.DESCRIPTION
		Remove-AzureStorageTableRow - Removes a specified table row. It accepts multiple deletions through the Pipeline when passing entities returned from the Get-AzureStorageTableRow
		available cmdlets. It also can delete a row/entity using Partition and Row Key properties directly.
	.PARAMETER Table
		Table object of type Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageTable where the entity exists
	.PARAMETER Entity (ParameterSetName=byEntityPSObjectObject)
		The entity/row with new values to perform the deletion.
	.PARAMETER PartitionKey (ParameterSetName=byPartitionandRowKeys)
		Partition key where the entity belongs to.
	.PARAMETER RowKey (ParameterSetName=byPartitionandRowKeys)
		Row key that uniquely identifies the entity within the partition.		 
	.EXAMPLE
		# Deleting an entry by entity PS Object
		[string]$filter1 = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::GenerateFilterCondition("firstName",[Microsoft.WindowsAzure.Storage.Table.QueryComparisons]::Equal,"Paulo")
		[string]$filter2 = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::GenerateFilterCondition("lastName",[Microsoft.WindowsAzure.Storage.Table.QueryComparisons]::Equal,"Marques")
		[string]$finalFilter = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::CombineFilters($filter1,"and",$filter2)
		$personToDelete = Get-AzureStorageTableRowByCustomFilter -table $table -customFilter $finalFilter
		$personToDelete | Remove-AzureStorageTableRow -table $table
	.EXAMPLE
		# Deleting an entry by using partitionkey and row key directly
		Remove-AzureStorageTableRow -table $table -partitionKey "TableEntityDemoFullList" -rowKey "399b58af-4f26-48b4-9b40-e28a8b03e867"
	.EXAMPLE
		# Deleting everything
		Get-AzureStorageTableRowAll -table $table | Remove-AzureStorageTableRow -table $table
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		$table,

		[Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="byEntityPSObjectObject")]
		$entity,

		[Parameter(Mandatory=$true,ParameterSetName="byPartitionandRowKeys")]
		[string]$partitionKey,

		[Parameter(Mandatory=$true,ParameterSetName="byPartitionandRowKeys")]
		[string]$rowKey
	)

	begin
	{
		$updatedEntityList = @()
		$updatedEntityList += $entity

		if ($updatedEntityList.Count -gt 1)
		{
			throw "Delete operation cannot happen on an array of entities, altough you can pipe multiple items."
		}
		
		$results = @()
	}
	
	process
	{
		if ($PSCmdlet.ParameterSetName -eq "byEntityPSObjectObject")
		{
			$partitionKey = $entity.PartitionKey
			$rowKey = $entity.RowKey
		}

        Test-AzureStorageTableEmptyKeys -PartitionKey $partitionKey -RowKey $rowKey

      	$entityToDelete = [Microsoft.Azure.CosmosDB.Table.DynamicTableEntity]($table.Execute([Microsoft.Azure.CosmosDB.Table.TableOperation]::Retrieve($partitionKey,$rowKey))).Result

		if ($entityToDelete -ne $null)
		{
			$results += $table.Execute([Microsoft.Azure.CosmosDB.Table.TableOperation]::Delete($entityToDelete))
		}
	}
	
	end
	{
		return ,$results
	}
}