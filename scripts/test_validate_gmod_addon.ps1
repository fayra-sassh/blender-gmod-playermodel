# Isolated static package fixtures only; never launches software or writes a game addon.
[CmdletBinding()]
param([string]$OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) 'gmod-addon-validator-tests'))

$ErrorActionPreference = 'Stop'
$runRoot = Join-Path $OutputRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$validator = Join-Path $PSScriptRoot 'validate_gmod_addon.ps1'
$passed = 0
$fixtureChecksum = 15837642

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Pass-Case([string]$Name) {
    $script:passed += 1
    Write-Host ('PASS ' + $Name)
}
function Write-FixtureText([string]$Path, [string]$Content) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content)
}
function Write-FamilyFile([string]$ModelBase, [string]$Suffix, [int]$Checksum = $fixtureChecksum) {
    $bytes = New-Object byte[] 128
    switch ($Suffix) {
        '.mdl' {
            [Text.Encoding]::ASCII.GetBytes('IDST').CopyTo($bytes, 0)
            [BitConverter]::GetBytes([int]48).CopyTo($bytes, 4)
            [BitConverter]::GetBytes($Checksum).CopyTo($bytes, 8)
        }
        '.vvd' {
            [Text.Encoding]::ASCII.GetBytes('IDSV').CopyTo($bytes, 0)
            [BitConverter]::GetBytes($Checksum).CopyTo($bytes, 8)
        }
        '.phy' {
            [BitConverter]::GetBytes($Checksum).CopyTo($bytes, 12)
        }
        default {
            [BitConverter]::GetBytes([int]7).CopyTo($bytes, 0)
            [BitConverter]::GetBytes($Checksum).CopyTo($bytes, 16)
        }
    }
    [IO.File]::WriteAllBytes(($ModelBase + $Suffix), $bytes)
}
function New-PackageFixture([string]$Name, [string]$ModelRel, [string[]]$Suffixes, [string]$Lua) {
    $addonRoot = Join-Path $runRoot $Name
    $modelBase = Join-Path $addonRoot ($ModelRel.Substring(0, $ModelRel.Length - 4).Replace('/', '\'))
    New-Item -ItemType Directory -Path (Split-Path -Parent $modelBase) -Force | Out-Null
    foreach ($suffix in $Suffixes) { Write-FamilyFile $modelBase $suffix }
    Write-FixtureText (Join-Path $addonRoot 'addon.json') '{"title":"static fixture","type":"model"}'
    Write-FixtureText (Join-Path $addonRoot 'lua\autorun\fixture.lua') $Lua
    Write-FixtureText (Join-Path $addonRoot 'materials\models\fixture\texture.vmt') '"VertexLitGeneric" { "$basetexture" "models/fixture/texture" }'
    $vtfBytes = New-Object byte[] 84
    [Text.Encoding]::ASCII.GetBytes("VTF`0").CopyTo($vtfBytes, 0)
    [BitConverter]::GetBytes([uint32]7).CopyTo($vtfBytes, 4)
    [BitConverter]::GetBytes([uint32]80).CopyTo($vtfBytes, 12)
    [BitConverter]::GetBytes([uint16]1).CopyTo($vtfBytes, 16)
    [BitConverter]::GetBytes([uint16]1).CopyTo($vtfBytes, 18)
    [IO.File]::WriteAllBytes((Join-Path $addonRoot 'materials\models\fixture\texture.vtf'), $vtfBytes)
    return [pscustomobject]@{Root=$addonRoot; Model=$ModelRel; Base=$modelBase; Lua=(Join-Path $addonRoot 'lua\autorun\fixture.lua')}
}
function Read-PackageReport($Fixture, [string]$Kind = '') {
    $arguments = @{AddonRoot=$Fixture.Root; ModelRelativePath=$Fixture.Model; Json=$true}
    if ($Kind) { $arguments.ModelKind = $Kind }
    return (& $validator @arguments | ConvertFrom-Json)
}

$playerPath = 'models/player/fixture/fixture.mdl'
$playerLua = "local modelPath = '$playerPath'`nlist.Set('PlayerOptionsModel', 'Fixture', modelPath)`nplayer_manager.AddValidModel('Fixture', modelPath)"
$player = New-PackageFixture 'player-default' $playerPath @('.mdl', '.vvd', '.dx90.vtx', '.phy') $playerLua
$defaultPlayer = Read-PackageReport $player
$explicitPlayer = Read-PackageReport $player 'PlayerModel'
Assert-True ($defaultPlayer.Valid -and $explicitPlayer.Valid -and $defaultPlayer.ModelKind -eq 'PlayerModel') 'Default player model validation changed.'
Assert-True (-not (Test-Path -LiteralPath ($player.Base + '.dx80.vtx'))) 'Player fixture accidentally depended on DX80.'
Pass-Case 'PlayerModel default retains PHY and player registration contract without requiring DX80'

Remove-Item -LiteralPath ($player.Base + '.phy')
$playerNoPhy = Read-PackageReport $player
Assert-True (-not $playerNoPhy.Valid -and $playerNoPhy.Failed -contains 'model.phy') 'Default player model stopped requiring PHY.'
Write-FamilyFile $player.Base '.phy'
Write-FixtureText $player.Lua "player_manager.AddValidModel('Fixture', '$playerPath')"
$playerNoList = Read-PackageReport $player
Assert-True (-not $playerNoList.Valid -and $playerNoList.Failed -contains 'PlayerOptionsModel registration') 'Default player selector registration requirement changed.'
Write-FixtureText $player.Lua $playerLua
Pass-Case 'PlayerModel missing PHY or selector registration still fails'

$handsPath = 'models/weapons/c_arms_fixture.mdl'
$handsLua = "local handsPath = '$handsPath'`nplayer_manager.AddValidHands('Fixture', handsPath, 0, '0000000')"
$hands = New-PackageFixture 'hands-variable' $handsPath @('.mdl', '.vvd', '.dx90.vtx', '.dx80.vtx') $handsLua
$handsGood = Read-PackageReport $hands 'Hands'
Assert-True ($handsGood.Valid -and $handsGood.ModelKind -eq 'Hands') 'Hands with handsPath registration failed.'
Assert-True (-not (Test-Path -LiteralPath ($hands.Base + '.phy')) -and
    $handsGood.Checks.Name -notcontains 'PlayerOptionsModel registration' -and
    $handsGood.Checks.Name -notcontains 'AddValidModel registration') 'Hands incorrectly required player model assets or registration.'
Pass-Case 'Hands accepts a standalone hand family and handsPath registration without PHY or PM registration'

Write-FixtureText $hands.Lua "player_manager.AddValidHands('Fixture', '$handsPath', 0, '0000000')"
$handsDirect = Read-PackageReport $hands 'Hands'
Assert-True $handsDirect.Valid 'Hands direct literal registration failed.'
Pass-Case 'Hands accepts a direct model-path literal'

Remove-Item -LiteralPath ($hands.Base + '.dx80.vtx')
$handsMissingDX80 = Read-PackageReport $hands 'Hands'
Assert-True (-not $handsMissingDX80.Valid -and $handsMissingDX80.Failed -contains 'model.dx80.vtx') 'Hands missing DX80 was accepted.'
Write-FamilyFile $hands.Base '.dx80.vtx'
Pass-Case 'Hands requires DX80 as well as DX90'

Write-FixtureText $hands.Lua "local handsPath = '$handsPath'`nplayer_manager.AddValidHands('Fixture', 'models/weapons/c_arms_wrong.mdl', 0, '0000000')"
$handsWrongPath = Read-PackageReport $hands 'Hands'
Assert-True (-not $handsWrongPath.Valid -and $handsWrongPath.Failed -contains 'AddValidHands registration') 'Exact expected path outside the registration falsely satisfied Hands registration.'
Write-FixtureText $hands.Lua "-- player_manager.AddValidHands('Fixture', '$handsPath', 0, '0000000')`nplayer_manager.AddValidModel('Fixture', '$handsPath')"
$handsCommentOnly = Read-PackageReport $hands 'Hands'
Assert-True (-not $handsCommentOnly.Valid -and $handsCommentOnly.Failed -contains 'AddValidHands registration') 'A commented hands call or AddValidModel substituted for AddValidHands.'
Write-FixtureText $hands.Lua $handsLua
Pass-Case 'Hands rejects wrong-path registration and commented or player-only registration'

foreach ($suffix in @('.vvd', '.dx90.vtx', '.dx80.vtx')) {
    Write-FamilyFile $hands.Base $suffix ($fixtureChecksum + 1)
    $mixedCompile = Read-PackageReport $hands 'Hands'
    Assert-True (-not $mixedCompile.Valid -and $mixedCompile.Failed -contains 'Model family checksum') ('Hands accepted a mismatched ' + $suffix + ' checksum.')
    Write-FamilyFile $hands.Base $suffix
}
Pass-Case 'Hands rejects mixed-compile VVD, DX90 and DX80 checksums'

foreach ($suffix in @('.dx90.vtx', '.dx80.vtx')) {
    $bytes = [IO.File]::ReadAllBytes($hands.Base + $suffix)
    [BitConverter]::GetBytes([int]6).CopyTo($bytes, 0)
    [IO.File]::WriteAllBytes(($hands.Base + $suffix), $bytes)
    $wrongVtxVersion = Read-PackageReport $hands 'Hands'
    Assert-True (-not $wrongVtxVersion.Valid -and $wrongVtxVersion.Failed -contains ($suffix + ' header')) ('Hands accepted an invalid ' + $suffix + ' header.')
    Write-FamilyFile $hands.Base $suffix
}
Pass-Case 'Hands checks both VTX header versions'

$finalHands = Read-PackageReport $hands 'Hands'
$finalPlayer = Read-PackageReport $player
Assert-True ($finalHands.Valid -and $finalPlayer.Valid) 'Restored positive fixtures no longer passed.'
[pscustomobject]@{Passed=$passed; FixtureRoot=$runRoot; LaunchedPrograms=0; ModifiedGameAddons=0} | ConvertTo-Json
