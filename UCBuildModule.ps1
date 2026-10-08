param(
    [string]$Version
)

#Getting module name from the current script path
$ModuleName = Split-Path $PSScriptRoot -Leaf

$ModuleSourcePath = [System.IO.Path]::Combine($PSScriptRoot, "Source")
$ModuleOutputPath = [System.IO.Path]::Combine($PSScriptRoot, "Output", $ModuleName)

if (!$Version) {
    #Get the lastest version of the module available in the PSGallery.
    $PSGalleryModuleInfo = Find-Module -Name $ModuleName -Repository PSGallery -ErrorAction SilentlyContinue
    $PSGalleryVersion = $PSGalleryModuleInfo.Version

    #In PowerShell 7, the version is returned as String, we need to convert it to System.Version.
    if ($PSGalleryVersion -is [string]) {
        $PSGalleryVersion = [System.Version]::Parse($PSGalleryVersion)
    }

    #For Minor we need to know if the current number of functions changed compared to the lastest version in PSGallery, if there is a change we will update the minor version, otherwise we will update the build number.
    $ModulePublicFunctions = Get-ChildItem -Path ([System.IO.Path]::Combine($ModuleSourcePath, "Public")) -Filter *.ps1

    $MinorVersion = $PSGalleryVersion.Minor
    $BuildVersion = $PSGalleryVersion.Build + 1
    if ($ModulePublicFunctions.Count -ne $PSGalleryModuleInfo.Includes.Function.Count) {
        $MinorVersion++
        $BuildVersion = $PSGalleryVersion.Build
    }
    $Version = [Version]::new($PSGalleryVersion.Major, $MinorVersion, $BuildVersion)
    Write-Host "Building $ModuleName version $Version, previous version in PSGallery is $($PSGalleryModuleInfo.Version)..." -ForegroundColor Green
}

#Check if Output path exists, if so deletes previous files.
if (!(Test-Path -Path $ModuleOutputPath)) {
    New-Item -Path $ModuleOutputPath -ItemType Directory | Out-Null
}
else {
    Remove-Item ([System.IO.Path]::Combine($ModuleOutputPath, "*.*")) -Recurse -Force
}

#Region Copy Readme and Format file if exists.
if (Test-Path -Path ([System.IO.Path]::Combine($PSScriptRoot, "README.md"))) {
    Copy-Item -Path ([System.IO.Path]::Combine($PSScriptRoot, "README.md")) -Destination ([System.IO.Path]::Combine($ModuleOutputPath, "README.md"))
}

if (Test-Path -Path ([System.IO.Path]::Combine($ModuleSourcePath, "$ModuleName.format.ps1xml"))) {
    Copy-Item -Path ([System.IO.Path]::Combine($ModuleSourcePath, "$ModuleName.format.ps1xml")) -Destination ([System.IO.Path]::Combine($ModuleOutputPath, "$ModuleName.format.ps1xml"))
}
#endregion

#Region Create Module 
$outModuleContent = ""
$FunctionsToExport = "@("

Get-ChildItem -Path ([System.IO.Path]::Combine($ModuleSourcePath, "Private")) -Filter *.ps1 | ForEach-Object { $outModuleContent += [System.IO.File]::ReadAllText($_.FullName) + [Environment]::NewLine + [Environment]::NewLine }

$ModulePublicFunctions | ForEach-Object { $outModuleContent += [System.IO.File]::ReadAllText($_.FullName) + [Environment]::NewLine + [Environment]::NewLine; $FunctionsToExport += "'" + $_.BaseName + "'," }

[System.IO.File]::WriteAllText([System.IO.Path]::Combine($ModuleOutputPath, "$ModuleName.psm1"), $outModuleContent, [System.Text.Encoding]::UTF8)
$FunctionsToExport = $FunctionsToExport.Substring(0, $FunctionsToExport.Length - 1) + ")"
#endregion

#Region Update and copy Module Manifest
if (Test-Path -Path ([System.IO.Path]::Combine($PSScriptRoot, "Source", "$ModuleName.psd1"))) {
    $ModuleManifest = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($PSScriptRoot, "Source", "$ModuleName.psd1"))

    $ModuleManifest = $ModuleManifest -replace '#%ModuleVersion%', ("""$Version""")
    $ModuleManifest = $ModuleManifest -replace '#%FunctionsToExport%', $FunctionsToExport

    [System.IO.File]::WriteAllText([System.IO.Path]::Combine($ModuleOutputPath, "$ModuleName.psd1"), $ModuleManifest, [System.Text.Encoding]::UTF8)

}
else {
    Write-Warning "Missing Manifest file: $ModuleName.psd1"
}
#endregion

Write-Host ("Module built successfully at: " + [Environment]::NewLine + "$ModuleOutputPath") -ForegroundColor Cyan
Import-Module -Name $ModuleOutputPath -Force
