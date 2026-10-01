[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AddonRoot,
    [Parameter(Mandatory=$true)][string]$ModelRelativePath,
    [ValidateSet('PlayerModel', 'Hands')][string]$ModelKind = 'PlayerModel',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $AddonRoot).Path
$modelRel = $ModelRelativePath.Replace('/', '\').TrimStart('\')
if ($modelRel -notmatch '(?i)^models\\.+\.mdl$' -or $modelRel -match '(^|\\)\.\.(\\|$)') {
    throw 'ModelRelativePath must be an addon-relative models/... .mdl path without parent traversal'
}
$modelFull = [IO.Path]::GetFullPath((Join-Path $root $modelRel))
if (-not $modelFull.StartsWith(($root.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ModelRelativePath escapes AddonRoot'
}
$modelBase = $modelFull.Substring(0, $modelFull.Length - 4)

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$name, [bool]$ok, [string]$detail) {
    $checks.Add([pscustomobject]@{ Name=$name; OK=$ok; Detail=$detail })
}

function Test-VtfHeader([string]$path) {
    # Basic desktop VTF 7.x sanity only; not a decoder or proof of pixel correctness.
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $stream = $null
    try {
        $stream = [IO.File]::OpenRead($path)
        if ($stream.Length -lt 64) { return $false }
        $header = New-Object byte[] 20
        if ($stream.Read($header, 0, $header.Length) -ne $header.Length) { return $false }
        $magic = [Text.Encoding]::ASCII.GetString($header, 0, 4)
        $headerSize = [BitConverter]::ToUInt32($header, 12)
        return $magic -eq "VTF`0" -and [BitConverter]::ToUInt32($header, 4) -eq 7 -and
            $headerSize -ge 64 -and $headerSize -lt $stream.Length -and
            [BitConverter]::ToUInt16($header, 16) -gt 0 -and [BitConverter]::ToUInt16($header, 18) -gt 0
    } catch { return $false }
    finally { if ($stream) { $stream.Dispose() } }
}

Add-Check 'addon.json' (Test-Path -LiteralPath (Join-Path $root 'addon.json') -PathType Leaf) 'Addon metadata'
$familySuffixes = if ($ModelKind -eq 'Hands') { @('.mdl', '.vvd', '.dx90.vtx', '.dx80.vtx') } else { @('.mdl', '.vvd', '.dx90.vtx', '.phy') }
foreach ($suffix in $familySuffixes) {
    $path = $modelBase + $suffix
    Add-Check ('model' + $suffix) (Test-Path -LiteralPath $path -PathType Leaf) $path
}
if (Test-Path -LiteralPath ($modelBase + '.mdl') -PathType Leaf) {
    $bytes = [IO.File]::ReadAllBytes($modelBase + '.mdl')
    Add-Check 'MDL header' ($bytes.Length -ge 128 -and [Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(4, $bytes.Length)) -eq 'IDST') 'Expected Source MDL IDST header'
}
if (Test-Path -LiteralPath ($modelBase + '.vvd') -PathType Leaf) {
    $bytes = [IO.File]::ReadAllBytes($modelBase + '.vvd')
    Add-Check 'VVD header' ($bytes.Length -ge 64 -and [Text.Encoding]::ASCII.GetString($bytes, 0, [Math]::Min(4, $bytes.Length)) -eq 'IDSV') 'Expected Source VVD IDSV header'
}
$vtxSuffixes = if ($ModelKind -eq 'Hands') { @('.dx90.vtx', '.dx80.vtx') } else { @('.dx90.vtx') }
foreach ($suffix in $vtxSuffixes) {
    if (Test-Path -LiteralPath ($modelBase + $suffix) -PathType Leaf) {
        $bytes = [IO.File]::ReadAllBytes($modelBase + $suffix)
        $checkName = if ($ModelKind -eq 'Hands') { $suffix + ' header' } else { 'VTX header' }
        Add-Check $checkName ($bytes.Length -ge 64 -and [BitConverter]::ToInt32($bytes, 0) -eq 7) 'Expected Source VTX version 7'
    }
}
if ($ModelKind -eq 'PlayerModel' -and (Test-Path -LiteralPath ($modelBase + '.phy') -PathType Leaf)) {
    Add-Check 'PHY size' ((Get-Item -LiteralPath ($modelBase + '.phy')).Length -ge 128) 'Expected nonempty collision data'
}
$familyPaths = $familySuffixes | ForEach-Object { $modelBase + $_ }
if (@($familyPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -eq 4) {
    $mdlBytes = [IO.File]::ReadAllBytes($familyPaths[0])
    $vvdBytes = [IO.File]::ReadAllBytes($familyPaths[1])
    $vtxBytes = [IO.File]::ReadAllBytes($familyPaths[2])
    $fourthBytes = [IO.File]::ReadAllBytes($familyPaths[3])
    $fourthChecksumOffset = if ($ModelKind -eq 'Hands') { 16 } else { 12 }
    $checksumOK = $mdlBytes.Length -ge 12 -and $vvdBytes.Length -ge 12 -and $vtxBytes.Length -ge 20 -and $fourthBytes.Length -ge ($fourthChecksumOffset + 4)
    if ($checksumOK) {
        $expected = [BitConverter]::ToInt32($mdlBytes, 8)
        $checksumOK = $expected -eq [BitConverter]::ToInt32($vvdBytes, 8) -and
            $expected -eq [BitConverter]::ToInt32($vtxBytes, 16) -and
            $expected -eq [BitConverter]::ToInt32($fourthBytes, $fourthChecksumOffset)
    }
    $checksumDetail = if ($ModelKind -eq 'Hands') { 'MDL/VVD/DX90 VTX/DX80 VTX must belong to the same compile' } else { 'MDL/VVD/VTX/PHY must belong to the same compile' }
    Add-Check 'Model family checksum' $checksumOK $checksumDetail
}

$autorun = Join-Path $root 'lua\autorun'
$luaFiles = if (Test-Path -LiteralPath $autorun) {
    @(Get-ChildItem -LiteralPath $autorun -Filter '*.lua' -File -ErrorAction SilentlyContinue)
} else {
    @()
}
$luaText = ($luaFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
$luaText = [regex]::Replace($luaText, '(?s)--\[\[.*?\]\]', '')
$luaText = [regex]::Replace($luaText, '(?m)--[^\r\n]*', '')
$modelLuaPath = $ModelRelativePath.Replace('\', '/')
$quote = '["' + [char]39 + ']'
$quotedPath = $quote + [regex]::Escape($modelLuaPath) + $quote
$pathVariable = if ($ModelKind -eq 'Hands') { 'handsPath' } else { 'modelPath' }
$assignedPath = [regex]::IsMatch($luaText, '(?im)^\s*(?:local\s+)?' + $pathVariable + '\s*=\s*' + $quotedPath)
$pathArgument = if ($assignedPath) { '(?:' + $pathVariable + '|' + $quotedPath + ')' } else { $quotedPath }
Add-Check 'lua autorun' ($luaFiles.Count -gt 0) (($luaFiles.FullName) -join '; ')
Add-Check 'Lua exact model path' ($assignedPath -or [regex]::IsMatch($luaText, $quotedPath)) $modelLuaPath
if ($ModelKind -eq 'Hands') {
    $handsPattern = '(?is)\bplayer_manager\s*\.\s*AddValidHands\s*\(\s*[^,)]*,\s*' + $pathArgument + '\s*,\s*[^)]*\)'
    Add-Check 'AddValidHands registration' ([regex]::IsMatch($luaText, $handsPattern)) 'player_manager.AddValidHands with exact hands path'
} else {
    $listPattern = '(?is)\blist\s*\.\s*Set\s*\(\s*' + $quote + 'PlayerOptionsModel' + $quote + '\s*,\s*[^,)]*,\s*' + $pathArgument + '\s*\)'
    $managerPattern = '(?is)\bplayer_manager\s*\.\s*AddValidModel\s*\(\s*[^,)]*,\s*' + $pathArgument + '\s*\)'
    Add-Check 'PlayerOptionsModel registration' ([regex]::IsMatch($luaText, $listPattern)) 'list.Set registration with exact model path'
    Add-Check 'AddValidModel registration' ([regex]::IsMatch($luaText, $managerPattern)) 'player_manager registration with exact model path'
}

$materialsRoot = Join-Path $root 'materials'
$vmtFiles = if (Test-Path -LiteralPath $materialsRoot) {
    @(Get-ChildItem -LiteralPath $materialsRoot -Filter '*.vmt' -File -Recurse -ErrorAction SilentlyContinue)
} else {
    @()
}
foreach ($vmt in $vmtFiles) {
    $text = Get-Content -LiteralPath $vmt.FullName -Raw
    $text = [regex]::Replace($text, '(?m)//[^\r\n]*', '')
    $match = [regex]::Match($text, '(?im)"?\$basetexture"?\s+"?([^"\r\n}]+)"?')
    if ($match.Success) {
        $textureRel = $match.Groups[1].Value.Trim().Replace('/', '\') + '.vtf'
        $texture = [IO.Path]::GetFullPath((Join-Path $materialsRoot $textureRel))
        $insideMaterials = $texture.StartsWith(($materialsRoot.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)
        Add-Check ('VMT ' + $vmt.Name) ($insideMaterials -and (Test-VtfHeader $texture)) ($texture + ' [basic VTF header/data check]')
    } else {
        Add-Check ('VMT ' + $vmt.Name) $false 'Missing $basetexture'
    }
}
Add-Check 'At least one material' ($vmtFiles.Count -gt 0) ($vmtFiles.Count.ToString() + ' VMT files')

$failed = @($checks | Where-Object { -not $_.OK })
$result = [pscustomobject]@{
    Valid = ($failed.Count -eq 0)
    AddonRoot = $root
    Model = $modelLuaPath
    ModelKind = $ModelKind
    Failed = @($failed | ForEach-Object { $_.Name })
    Checks = $checks
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
} else {
    $checks | Format-Table Name, OK, Detail -AutoSize
    Write-Host ''
    if ($result.Valid) { Write-Host 'VALID' } else { Write-Host ('INVALID: ' + ($result.Failed -join ', ')) }
}

if (-not $result.Valid) { exit 2 }
