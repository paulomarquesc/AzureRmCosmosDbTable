@{

# ID used to uniquely identify this module
GUID = '0af8c114-4209-4fc5-a732-098cb01dd2fd'

# Author of this module
Author = 'Paulo Marques (MSFT)'

# Company or vendor of this module
CompanyName = 'Microsoft Corporation'

# Copyright statement for this module
Copyright = '© Microsoft Corporation. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Sample functions to add/retrieve/update entities on Azure Cosmos DB Tables from PowerShell. It requires you to execute Install-CosmosDbInstallPreReqs.ps1 to install pre-req assemblies.'

# HelpInfo URI of this module
HelpInfoUri = 'https://blogs.technet.microsoft.com/paulomarques/2017/01/17/working-with-azure-CosmosDb-tables-from-powershell/'

# Version number of this module
ModuleVersion = '1.0.0.0'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '4.0'

# Minimum version of the common language runtime (CLR) required by this module
CLRVersion = '2.0'

# Script module or binary module file associated with this manifest
#ModuleToProcess = ''

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
NestedModules = @('AzureRmCosmosDbTableCoreHelper.psm1')

FunctionsToExport = @(  'Add-AzureCosmosDbTableRow',
                        'Get-AzureCosmosDbTableRowAll',
                        'Get-AzureCosmosDbTableRowByPartitionKey',
                        'Get-AzureCosmosDbTableRowByColumnName',
                        'Get-AzureCosmosDbTableRowByCustomFilter',
                        'Update-AzureCosmosDbTableRow',
                        'Remove-AzureCosmosDbTableRow',
                        'Get-AzureCosmosDbTableTable'
                        )

VariablesToExport = ''

}