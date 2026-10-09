function Build-UcPowerShellModule {
    <#
        .SYNOPSIS
        Test connection to a Service

        .DESCRIPTION
        This function will validate if the there is an active connection to a service and also if the required module is installed.

        Requirements:   MsGraph, TeamsDeviceTAC - EntraAuth PowerShell module (Install-Module EntraAuth)
                        TeamsModule - MicrosoftTeams PowerShell module (Install-Module MicrosoftTeams)

        .PARAMETER Path
        Specify the PowerShell Module Source Path.
        
        .PARAMETER Version
        By default this cmdlet uses the current version in PowerShell Galery, we can specify one with this parameter.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Version
    )

    #Getting module name from the current script path
    $ModuleName = Split-Path $Path -Leaf

    $ModuleSourcePath = [System.IO.Path]::Combine($Path, "Source")
    $ModuleOutputPath = [System.IO.Path]::Combine($Path, "Output", $ModuleName)

    $ModulePublicFunctions = Get-ChildItem -Path ([System.IO.Path]::Combine($ModuleSourcePath, "Public")) -Filter *.ps1

    if (!$Version) {
        #Get the lastest version of the module available in the PSGallery.
        $PSGalleryModuleInfo = Find-Module -Name $ModuleName -Repository PSGallery -ErrorAction SilentlyContinue
        $PSGalleryVersion = $PSGalleryModuleInfo.Version

        #In PowerShell 7, the version is returned as String, we need to convert it to System.Version.
        if ($PSGalleryVersion -is [string]) {
            $PSGalleryVersion = [System.Version]::Parse($PSGalleryVersion)
        }

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
    if (Test-Path -Path ([System.IO.Path]::Combine($Path, "README.md"))) {
        Copy-Item -Path ([System.IO.Path]::Combine($Path, "README.md")) -Destination ([System.IO.Path]::Combine($ModuleOutputPath, "README.md"))
    }

    if (Test-Path -Path ([System.IO.Path]::Combine($Path, "LICENSE"))) {
        Copy-Item -Path ([System.IO.Path]::Combine($Path, "LICENSE")) -Destination ([System.IO.Path]::Combine($ModuleOutputPath, "LICENSE"))
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
    if (Test-Path -Path ([System.IO.Path]::Combine($Path, "Source", "$ModuleName.psd1"))) {
        $ModuleManifest = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($Path, "Source", "$ModuleName.psd1"))

        $ModuleManifest = $ModuleManifest -replace '#%ModuleVersion%', ("""$Version""")
        $ModuleManifest = $ModuleManifest -replace '#%FunctionsToExport%', $FunctionsToExport

        [System.IO.File]::WriteAllText([System.IO.Path]::Combine($ModuleOutputPath, "$ModuleName.psd1"), $ModuleManifest, [System.Text.Encoding]::UTF8)

    }
    else {
        Write-Warning "Missing Manifest file: $ModuleName.psd1"
    }
    #endregion

    Write-Host ("Module ready to be imported with: " + [Environment]::NewLine) -ForegroundColor Cyan
    Write-Host ("Import-Module -Name `"$ModuleOutputPath`" -Force") -ForegroundColor DarkGreen   
}