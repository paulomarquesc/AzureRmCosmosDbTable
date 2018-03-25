#requires -runasadministrator

#Loading Cosmos DB dependencies support

# Download nuget
Write-Verbose "Downloading nuget.exe" -Verbose
$nugetFilename = "nuget.exe"
$webclient = New-Object System.Net.WebClient
$url = "https://dist.nuget.org/win-x86-commandline/latest/$nugetFilename"
$file = Join-Path $PSScriptRoot $nugetFilename
$webclient.DownloadFile($url,$file)

# Executing nuget to get necessary packages
Write-Verbose "Executing nuget to get necessary packages" -Verbose
.\nuget install Microsoft.Azure.CosmosDB.Table -Prerelease
.\nuget install Microsoft.Azure.Storage.Common -prerelease

# Removing lder version of Microsoft.Azure.Storage
rmdir .\Microsoft.Azure.Storage.Common.8.6.0-preview -Recurse

# Required assembles
$dotNetVersion = "net45"
$requiredDlls = Get-ChildItem -Path . -Depth 3 | Where-Object { $_.fullname.contains("dll") -and $_.fullname.contains($dotNetVersion)}
$requiredDlls += Get-ChildItem -Path "DocumentDB.Spatial.Sql.dll" -Recurse
$requiredDlls += Get-ChildItem -Path "Microsoft.Azure.Documents.ServiceInterop.dll" -Recurse

# Copying assembly files to root of module folder
Write-Verbose "Copying assembly files to root of module folder" -Verbose

$dllList = @()
foreach ($dll in $requiredDlls)
{
    Write-Verbose "Copying assembly $($dll.FullName) to $PSScriptRoot" -Verbose
    Copy-Item $dll.FullName $PSScriptRoot -Force

    if ((-not $dllList.Contains($dll.Name)) -and ($dll.Name -ne "Microsoft.Azure.Documents.ServiceInterop.dll") -and ($dll.Name -ne "DocumentDB.Spatial.Sql.dll"))
    #if ((-not $dllList.Contains($dll.Name)) -and ($dll.Name -ne "Microsoft.Azure.Documents.ServiceInterop.dll"))
    {
        $dllList += $dll.Name
    }
}

# Removing assembly folders
Write-Verbose "Removing assembly folders" -Verbose
foreach ($dll in $requiredDlls)
{
    $assemblyRelativeRootPath = $dll.FullName.Replace("$PSScriptRoot\","")
    $assemblyRootLevel = Join-Path $PSScriptRoot $assemblyRelativeRootPath.Split("\")[0]

    Write-Verbose "Removing folder  $assemblyRootLevel" -Verbose
    Remove-Item $assemblyRootLevel -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Verbose "Writting dll dependency list file" -Verbose
$dllList | Out-File .\dependencies.txt -Force
