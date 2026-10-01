[CmdletBinding()]
param(
    [string]$ToolRoot = 'D:\gmod工具',
    [string]$GModRoot = '',
    [string[]]$SteamRoots = @(),
    [string]$BlenderPath = '',
    [string]$PythonPath = '',
    [string]$CrowbarPath = '',
    [string]$SourceToolsPath = '',
    [string]$VTFCmdPath = '',
    [string]$StudioMDLPath = '',
    [string]$HLMVPath = '',
    [switch]$NoDefaultSearch,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$discoveryWarnings = New-Object System.Collections.Generic.List[string]

function Read-Directories {
    param([string]$Path)
    try { return @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction Stop) }
    catch {
        $discoveryWarnings.Add('Could not enumerate directory: ' + $Path)
        return @()
    }
}

function Find-File {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Find-Command {
    param([string]$Name)
    if ($NoDefaultSearch) { return $null }
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    return $null
}

function Get-PackageCandidates {
    param([string]$Path)
    if (-not $Path) { return @() }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $candidates = @((Join-Path $Path 'io_scene_valvesource\__init__.py'))
        if ([IO.Path]::GetFileName($Path.TrimEnd('\', '/')) -eq 'io_scene_valvesource') {
            $candidates += (Join-Path $Path '__init__.py')
        }
        return $candidates
    }
    if ([IO.Path]::GetFileName($Path) -eq '__init__.py' -and
        [IO.Path]::GetFileName((Split-Path -Parent $Path)) -eq 'io_scene_valvesource') { return @($Path) }
    return @() # A ZIP is a cache, not an installed exporter.
}

$libraries = @($SteamRoots)
$programFiles = [Environment]::GetFolderPath('ProgramFiles')
$programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
if (-not $NoDefaultSearch) {
    $libraries += @('D:\steam\Steam', 'D:\Steam', 'D:\SteamLibrary')
    foreach ($base in @($programFiles, $programFilesX86)) {
        if ($base) { $libraries += (Join-Path $base 'Steam') }
    }
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $entry = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($entry) {
            if ($entry.SteamPath) { $libraries += $entry.SteamPath }
            if ($entry.InstallPath) { $libraries += $entry.InstallPath }
        }
    }
}
foreach ($library in @($libraries | Where-Object { $_ } | Select-Object -Unique)) {
    $vdf = Join-Path $library 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
        try { $content = Get-Content -LiteralPath $vdf -Raw -ErrorAction Stop }
        catch { $discoveryWarnings.Add('Could not read Steam library file: ' + $vdf); continue }
        foreach ($match in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
            $libraries += $match.Groups[1].Value.Replace('\\', '\')
        }
    }
}
$libraries = @($libraries | Where-Object { $_ } | Select-Object -Unique)
$gameCandidates = if ($GModRoot) { @($GModRoot) } else {
    @($libraries | ForEach-Object { Join-Path $_ 'steamapps\common\GarrysMod' })
}
$resolvedGMod = $null
foreach ($candidate in $gameCandidates) {
    if ((Test-Path -LiteralPath (Join-Path $candidate 'garrysmod') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'bin') -PathType Container)) {
        $resolvedGMod = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}

$blenderCandidates = @($BlenderPath)
if (-not $BlenderPath -and -not $NoDefaultSearch) {
    $blenderCandidates += @('D:\Blender 5.2\blender.exe', (Find-Command 'blender.exe'))
    if ($programFiles) {
        $blenderBase = Join-Path $programFiles 'Blender Foundation'
        if (Test-Path -LiteralPath $blenderBase -PathType Container) {
            $blenderCandidates += @(Read-Directories $blenderBase |
                ForEach-Object { Join-Path $_.FullName 'blender.exe' })
        }
    }
}
$blender = Find-File $blenderCandidates
$pythonCandidates = @($PythonPath)
if (-not $PythonPath) {
    $pythonCandidates += @((Find-Command 'python.exe'), (Find-Command 'python3.exe')) |
        Where-Object { $_ -and $_ -notmatch '\\WindowsApps\\' }
    if ($blender) {
        $pythonCandidates += @(Read-Directories (Split-Path -Parent $blender) |
            Where-Object { $_.Name -match '^\d+\.\d+$' } |
            ForEach-Object { Join-Path $_.FullName 'python\bin\python.exe' })
    }
}
$python = Find-File $pythonCandidates

# Bounded portable-tool discovery: root and two directory levels, excluding caches/backups.
$toolDirs = @()
if (Test-Path -LiteralPath $ToolRoot -PathType Container) {
    $toolDirs += (Resolve-Path -LiteralPath $ToolRoot).Path
    $levelOne = @(Read-Directories $ToolRoot |
        Where-Object { $_.Name -notmatch '(?i)^(_downloads|.*backup.*)$' })
    $toolDirs += @($levelOne | ForEach-Object { $_.FullName })
    foreach ($dir in $levelOne) {
        $toolDirs += @(Read-Directories $dir.FullName |
            Where-Object { $_.Name -notmatch '(?i)^(_downloads|.*backup.*)$' } |
            ForEach-Object { $_.FullName })
    }
}
$crowbarCandidates = if ($CrowbarPath) { @($CrowbarPath) } else {
    @((Find-Command 'Crowbar.exe')) + @($toolDirs | ForEach-Object { Join-Path $_ 'Crowbar.exe' })
}
$vtfCandidates = if ($VTFCmdPath) { @($VTFCmdPath) } else {
    @((Find-Command 'VTFCmd.exe')) + @($toolDirs | ForEach-Object { Join-Path $_ 'VTFCmd.exe' })
}
$sourceCandidates = if ($SourceToolsPath) { @(Get-PackageCandidates $SourceToolsPath) } else {
    @($toolDirs | ForEach-Object { Get-PackageCandidates $_ })
}
if (-not $SourceToolsPath -and -not $NoDefaultSearch -and $env:APPDATA) {
    $blenderSettings = Join-Path $env:APPDATA 'Blender Foundation\Blender'
    if (Test-Path -LiteralPath $blenderSettings -PathType Container) {
        foreach ($dir in @(Read-Directories $blenderSettings)) {
            $sourceCandidates += (Join-Path $dir.FullName 'scripts\addons\io_scene_valvesource\__init__.py')
        }
    }
}
$crowbar = Find-File $crowbarCandidates
$vtfCmd = Find-File $vtfCandidates
$sourceTools = Find-File $sourceCandidates
$cachedArchives = @()
if (Test-Path -LiteralPath $ToolRoot -PathType Container) {
    $cachedArchives = @(Get-ChildItem -LiteralPath $ToolRoot -File -Recurse -Depth 3 -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)(source[_ -]?tools|blender[_ -]?source)' } |
        ForEach-Object { $_.FullName })
}

$studioCandidates = @()
$hlmvCandidates = @()
$vpkCandidates = @()
$gmadCandidates = @()
if ($resolvedGMod) {
    $studioCandidates += (Join-Path $resolvedGMod 'bin\studiomdl.exe')
    $hlmvCandidates += (Join-Path $resolvedGMod 'bin\hlmv.exe')
    $vpkCandidates += (Join-Path $resolvedGMod 'bin\vpk.exe')
    $gmadCandidates += (Join-Path $resolvedGMod 'bin\gmad.exe')
}
foreach ($library in $libraries) {
    $sdkBin = Join-Path $library 'steamapps\common\Source SDK Base 2013 Multiplayer\bin'
    $studioCandidates += (Join-Path $sdkBin 'studiomdl.exe')
    $hlmvCandidates += (Join-Path $sdkBin 'hlmv.exe')
    $vpkCandidates += (Join-Path $sdkBin 'vpk.exe')
}
if ($StudioMDLPath) { $studioCandidates = @($StudioMDLPath) }
else { $studioCandidates += @((Find-Command 'studiomdl.exe')) + @($toolDirs | ForEach-Object { Join-Path $_ 'studiomdl.exe' }) }
if ($HLMVPath) { $hlmvCandidates = @($HLMVPath) }
else { $hlmvCandidates += @((Find-Command 'hlmv.exe')) + @($toolDirs | ForEach-Object { Join-Path $_ 'hlmv.exe' }) }
$studioMdl = Find-File $studioCandidates
$hlmv = Find-File $hlmvCandidates
$vpk = Find-File $vpkCandidates
$gmad = Find-File $gmadCandidates
$vtfGui = Find-File @($toolDirs | ForEach-Object { Join-Path $_ 'VTFEdit Reloaded.exe'; Join-Path $_ 'VTFEdit.exe' })
$gmpublisher = Find-File (@((Find-Command 'gmpublisher.exe')) + @($toolDirs | ForEach-Object { Join-Path $_ 'gmpublisher.exe' }))
$mcpConfig = $null
$mcpConfigured = $false
if (-not $NoDefaultSearch -and $env:USERPROFILE) {
    $mcpConfig = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (Test-Path -LiteralPath $mcpConfig -PathType Leaf) {
        $mcpConfigured = [bool](Select-String -LiteralPath $mcpConfig -Pattern '^\[mcp_servers\.blender\]$' -Quiet)
    }
}

$items = @(
    [pscustomobject]@{Name='GarrysMod'; Required=$true; Found=[bool]$resolvedGMod; Path=$resolvedGMod; Note='Validated directory layout; runtime unchecked'},
    [pscustomobject]@{Name='Blender'; Required=$true; Found=[bool]$blender; Path=$blender; Note='Executable discovery; version and runtime unchecked'},
    [pscustomobject]@{Name='Python'; Required=$true; Found=[bool]$python; Path=$python; Note='Check Python 3.10+ before running validators'},
    [pscustomobject]@{Name='BlenderMCPConfig'; Required=$false; Found=$mcpConfigured; Path=if($mcpConfigured){$mcpConfig}else{$null}; Note='Hint only; actual MCP live read required'},
    [pscustomobject]@{Name='BlenderSourceTools'; Required=$true; Found=[bool]$sourceTools; Path=$sourceTools; Note='Package code only; enabling and export unchecked'},
    [pscustomobject]@{Name='Crowbar'; Required=$true; Found=[bool]$crowbar; Path=$crowbar; Note='MDL decompile/compile front end'},
    [pscustomobject]@{Name='StudioMDL'; Required=$true; Found=[bool]$studioMdl; Path=$studioMdl; Note='Source compiler; branch compatibility unchecked'},
    [pscustomobject]@{Name='VTFCmd'; Required=$true; Found=[bool]$vtfCmd; Path=$vtfCmd; Note='Inspect actual texture conversion output and errors'},
    [pscustomobject]@{Name='VTFEditGUI'; Required=$false; Found=[bool]$vtfGui; Path=$vtfGui; Note='Optional texture inspection GUI'},
    [pscustomobject]@{Name='HLMV'; Required=$false; Found=[bool]$hlmv; Path=$hlmv; Note='Optional user-operated model viewer; missing viewer does not block production'},
    [pscustomobject]@{Name='VPK'; Required=$false; Found=[bool]$vpk; Path=$vpk; Note='Required only for archived reference content'},
    [pscustomobject]@{Name='GMad'; Required=$false; Found=[bool]$gmad; Path=$gmad; Note='Required only for GMA packaging'},
    [pscustomobject]@{Name='GMPublisher'; Required=$false; Found=[bool]$gmpublisher; Path=$gmpublisher; Note='Required only for requested Workshop publication'}
)
$missing = @($items | Where-Object { $_.Required -and -not $_.Found })
$result = [pscustomobject]@{
    Ready=($missing.Count -eq 0)
    ReadyScope='file_discovery_only'
    AcceptanceVerified=$false
    LiveChecksRequired=@('Official Blender MCP live scene read', 'Source Tools enabled and SMD import/export', 'Python version', 'StudioMDL compile', 'Actual VTF conversion output and errors')
    UserChecksSuggested=@('User verifies the installed model in GMod after a full restart', 'Optional user-operated HLMV appearance and sequence inspection')
    ToolRoot=$ToolRoot
    GModRoot=$resolvedGMod
    MissingRequired=@($missing | ForEach-Object { $_.Name })
    CachedSourceToolsArchives=$cachedArchives
    DiscoveryWarnings=@($discoveryWarnings.ToArray())
    Components=$items
}
if ($Json) { $result | ConvertTo-Json -Depth 5 } else {
    $items | Format-Table Name, Required, Found, Path, Note -AutoSize
    if ($result.Ready) { Write-Host 'FILES FOUND: live plugin and functional checks still required.' }
    else { Write-Host ('MISSING FILES: ' + ($result.MissingRequired -join ', ')) }
}
