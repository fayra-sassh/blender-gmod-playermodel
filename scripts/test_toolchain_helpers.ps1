# Isolated discovery and mocked downloads only; never launches installers or the game.
[CmdletBinding()]
param([string]$OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) 'gmod-skill-helper-tests'))
$ErrorActionPreference = 'Stop'
$runRoot = Join-Path $OutputRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$detector = Join-Path $PSScriptRoot 'detect_gmod_toolchain.ps1'
$downloader = Join-Path $PSScriptRoot 'download_tool_asset.ps1'
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Pass-Case {
    param([string]$Name)
    $script:passed += 1
    Write-Host ('PASS ' + $Name)
}
function New-FixtureFile {
    param([string]$Path, [string]$Content = 'fixture')
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content)
}
function Expect-Failure {
    param([scriptblock]$Operation, [string]$Pattern)
    $caught = $null
    try { & $Operation | Out-Null } catch { $caught = $_.Exception.Message }
    Assert-True ([bool]$caught) 'Operation unexpectedly succeeded.'
    Assert-True ($caught -match $Pattern) ('Unexpected failure: ' + $caught)
}

$empty = & $detector -ToolRoot (Join-Path $runRoot 'empty') -NoDefaultSearch -Json | ConvertFrom-Json
Assert-True (-not $empty.Ready -and $empty.MissingRequired.Count -eq 7) 'Empty inventory should report all seven production file components.'
Assert-True ($empty.MissingRequired -notcontains 'HLMV') 'Optional viewer must not count as a missing production tool.'
Pass-Case 'empty inventory does not claim readiness'

$unrelated = Join-Path $runRoot 'unrelated-tool\__init__.py'
New-FixtureFile $unrelated
$unrelatedResult = & $detector -ToolRoot (Split-Path -Parent $unrelated) -NoDefaultSearch -Json | ConvertFrom-Json
Assert-True ($unrelatedResult.MissingRequired -contains 'BlenderSourceTools') 'Unrelated Python package was mistaken for the exporter.'
Pass-Case 'unrelated Python package does not count as Source Tools'

$tools = Join-Path $runRoot 'tools'
$game = Join-Path $runRoot 'library\steamapps\common\GarrysMod'
$blender = Join-Path $runRoot 'Blender\blender.exe'
$python = Join-Path $runRoot 'Blender\5.2\python\bin\python.exe'
foreach ($path in @($blender, $python, (Join-Path $tools 'Crowbar-1\Crowbar.exe'),
    (Join-Path $tools 'VTF-version\bin\VTFCmd.exe'), (Join-Path $game 'bin\studiomdl.exe'),
    (Join-Path $game 'bin\hlmv.exe'))) { New-FixtureFile $path }
New-Item -ItemType Directory -Path (Join-Path $game 'garrysmod') -Force | Out-Null
$archive = Join-Path $tools '_downloads\source-tools-v\blender_source_tools.zip'
New-FixtureFile $archive
$argsForDetector = @{ToolRoot=$tools; GModRoot=$game; BlenderPath=$blender; NoDefaultSearch=$true; Json=$true}
$archiveOnly = & $detector @argsForDetector | ConvertFrom-Json
Assert-True ($archiveOnly.MissingRequired.Count -eq 1 -and $archiveOnly.MissingRequired[0] -eq 'BlenderSourceTools') 'Archive counted as exporter install or another tool was missed.'
Assert-True ($archiveOnly.CachedSourceToolsArchives -contains $archive) 'Cached archive was not reported.'
Pass-Case 'cached ZIP is not an installed plugin; bounded versioned tools and bundled Python are found'

$package = Join-Path $tools 'SourceTools\io_scene_valvesource\__init__.py'
New-FixtureFile $package 'bl_info = {}'
$ready = & $detector @argsForDetector | ConvertFrom-Json
Assert-True ($ready.Ready -and -not $ready.AcceptanceVerified -and $ready.ReadyScope -eq 'file_discovery_only') 'Files should be found without claiming actual functionality.'
Pass-Case 'package code produces file-only readiness, not live acceptance'

$argsForDetector.SourceToolsPath = $archive
$explicitZip = & $detector @argsForDetector | ConvertFrom-Json
Assert-True ($explicitZip.MissingRequired -contains 'BlenderSourceTools') 'Explicit ZIP must not fall back to an installed package.'
$argsForDetector.SourceToolsPath = (Split-Path -Parent $package)
$explicitPackage = & $detector @argsForDetector | ConvertFrom-Json
Assert-True $explicitPackage.Ready 'Explicit exporter package directory was not resolved.'
Pass-Case 'explicit Source Tools path is authoritative and supports a package directory'

$argsForDetector.CrowbarPath = Join-Path $runRoot 'absent\Crowbar.exe'
$badOverride = & $detector @argsForDetector | ConvertFrom-Json
Assert-True ($badOverride.MissingRequired -contains 'Crowbar') 'Bad explicit executable path silently fell back.'
$argsForDetector.Remove('CrowbarPath')
$argsForDetector.GModRoot = Join-Path $runRoot 'not-a-game'
New-Item -ItemType Directory -Path $argsForDetector.GModRoot -Force | Out-Null
$badGame = & $detector @argsForDetector | ConvertFrom-Json
Assert-True ($badGame.MissingRequired -contains 'GarrysMod') 'Arbitrary directory was accepted as game.'
Pass-Case 'invalid explicit executable/game paths stay missing'

$steam = Join-Path $runRoot 'steam-main'
$library = Join-Path $runRoot 'library'
New-FixtureFile (Join-Path $steam 'steamapps\libraryfolders.vdf') ('"libraryfolders" { "1" { "path" "' + $library.Replace('\', '\\') + '" } }')
$argsForDetector.Remove('GModRoot')
$argsForDetector.SteamRoots = @($steam)
$viaLibrary = & $detector @argsForDetector | ConvertFrom-Json
Assert-True ($viaLibrary.GModRoot -eq $game -and $viaLibrary.Ready) 'Steam libraryfolders discovery failed.'
Pass-Case 'additional Steam library is resolved from libraryfolders.vdf'

$customCompiler = Join-Path $runRoot 'custom-sdk\studiomdl.exe'
$customViewer = Join-Path $runRoot 'custom-viewer\hlmv.exe'
New-FixtureFile $customCompiler
New-FixtureFile $customViewer
$argsForDetector.StudioMDLPath = $customCompiler
$argsForDetector.HLMVPath = $customViewer
$customSourceTools = & $detector @argsForDetector | ConvertFrom-Json
Assert-True ((@($customSourceTools.Components | Where-Object Name -eq 'StudioMDL')[0]).Path -eq $customCompiler -and
    (@($customSourceTools.Components | Where-Object Name -eq 'HLMV')[0]).Path -eq $customViewer) 'Explicit Source executable paths were not respected.'
$argsForDetector.HLMVPath = Join-Path $runRoot 'absent\hlmv.exe'
$missingViewer = & $detector @argsForDetector | ConvertFrom-Json
Assert-True ($missingViewer.Ready -and $missingViewer.MissingRequired -notcontains 'HLMV') 'Missing optional viewer incorrectly blocked production.'
$viewerComponent = @($missingViewer.Components | Where-Object Name -eq 'HLMV')[0]
Assert-True (-not $viewerComponent.Found -and -not $viewerComponent.Required) 'Invalid viewer override silently fell back or remained required.'
Assert-True ($missingViewer.LiveChecksRequired -notcontains 'HLMV visible inspection' -and
    $missingViewer.LiveChecksRequired -notcontains 'GMod runtime' -and
    $missingViewer.LiveChecksRequired -notcontains 'VTF reopen' -and
    $missingViewer.LiveChecksRequired -contains 'Actual VTF conversion output and errors' -and
    $missingViewer.LiveChecksRequired -contains 'Official Blender MCP live scene read' -and
    $missingViewer.UserChecksSuggested.Count -eq 2) 'Production checks and user acceptance were not separated.'
Pass-Case 'compiler/viewer support authoritative paths; absent optional viewer does not block production'

# Function shadows Invoke-WebRequest only within this test's inherited scope.
$downloadMock = [pscustomobject]@{Calls=0; Bytes=[byte[]](0x50,0x4B,0x03,0x04,0,0,0,0,1,2,3,4); FinalUrl='https://release.example/asset.zip'}
function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing, [switch]$PassThru)
    $downloadMock.Calls += 1
    [IO.File]::WriteAllBytes($OutFile, $downloadMock.Bytes)
    [pscustomobject]@{BaseResponse=[pscustomobject]@{ResponseUri=[uri]$downloadMock.FinalUrl}}
}
$signatureMock = [pscustomobject]@{Status='Valid'; Calls=0}
function Get-AuthenticodeSignature {
    param([string]$LiteralPath)
    $signatureMock.Calls += 1
    [pscustomobject]@{Status=$signatureMock.Status; SignerCertificate=[pscustomobject]@{Subject='fixture signer'}}
}
$downloads = Join-Path $runRoot 'downloads'
$downloadArgs = @{Url='https://release.example/asset.zip'; Tool='source-tools'; Version='test-v1'; FileName='source_tools.zip'; DownloadRoot=$downloads}
$planned = & $downloader @downloadArgs -WhatIf
Assert-True ($planned.Status -eq 'planned_only' -and $downloadMock.Calls -eq 0 -and -not (Test-Path -LiteralPath $downloads)) 'WhatIf wrote files or used network.'
Pass-Case 'WhatIf has no network or filesystem writes'

$fetched = & $downloader @downloadArgs
Assert-True ($fetched.Status -eq 'downloaded' -and $downloadMock.Calls -eq 1) 'Mock asset download failed.'
$record = Get-Content -LiteralPath $fetched.RecordPath -Raw | ConvertFrom-Json
Assert-True ($record.Sha256 -eq (Get-FileHash -LiteralPath $fetched.Path -Algorithm SHA256).Hash -and
    -not $record.Executed -and $record.FinalResponseUrlVerified -and $record.FinalResponseUrl -eq $downloadMock.FinalUrl) 'Provenance is incomplete.'
$reused = & $downloader @downloadArgs
Assert-True ($reused.Status -eq 'reused' -and $downloadMock.Calls -eq 1) 'Reuse should verify hashes without a second download.'
Pass-Case 'download records provenance and reuses only unchanged verified bytes'

[IO.File]::WriteAllBytes($fetched.Path, [byte[]](1,2,3,4))
Expect-Failure { & $downloader @downloadArgs } 'provenance/hash differs'
Assert-True ($downloadMock.Calls -eq 1) 'Tampered existing asset triggered a replacement download.'
Pass-Case 'tampered asset is neither reused nor overwritten'

$downloadArgs.Version = 'test-html'
$downloadMock.Bytes = [Text.Encoding]::UTF8.GetBytes('<html>error page</html>')
Expect-Failure { & $downloader @downloadArgs } 'signature does not match'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $downloads 'source-tools-test-html\source_tools.zip'))) 'HTML was saved as a final ZIP.'
Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $downloads 'source-tools-test-html') -Filter '*.partial').Count -eq 1) 'Failed response was not retained as a non-executable partial.'
Pass-Case 'HTML masquerading as ZIP fails validation and stays partial'

$downloadArgs.Version = 'test-hash'
$downloadMock.Bytes = [byte[]](0x50,0x4B,0x03,0x04,0,0,0,0)
Expect-Failure { & $downloader @downloadArgs -ExpectedSha256 ('0' * 64) } 'SHA-256 does not match'
Pass-Case 'expected release hash mismatch is blocking'

$downloadArgs.Version = 'test-redirect'
$downloadMock.FinalUrl = 'http://release.example/asset.zip'
Expect-Failure { & $downloader @downloadArgs } 'downgraded from HTTPS'
Pass-Case 'HTTPS downgrade response is rejected'

$downloadArgs.Version = 'test-invalid'
$downloadArgs.Url = 'http://release.example/asset.zip'
Expect-Failure { & $downloader @downloadArgs } 'absolute HTTPS'
$downloadArgs.Url = 'https://release.example/asset.zip'
$downloadArgs.FileName = '..\asset.zip'
Expect-Failure { & $downloader @downloadArgs } 'simple leaf name'
Pass-Case 'HTTP and filename traversal are rejected before download'

$downloadArgs.Url = 'https://release.example/asset.zip'
$downloadArgs.FileName = 'source_tools.zip'
$downloadArgs.Version = 'test-matching-hash'
$downloadMock.FinalUrl = 'https://release.example/asset.zip'
$downloadMock.Bytes = [byte[]](0x50,0x4B,0x03,0x04,0,0,0,0)
$hashFixture = Join-Path $runRoot 'hash-fixture.bin'
[IO.File]::WriteAllBytes($hashFixture, $downloadMock.Bytes)
$expected = (Get-FileHash -LiteralPath $hashFixture -Algorithm SHA256).Hash
$matched = & $downloader @downloadArgs -ExpectedSha256 $expected
Assert-True ($matched.Sha256 -eq $expected) 'Matching release hash was rejected.'
Pass-Case 'matching expected release hash is accepted'

$downloadArgs.Version = 'test-orphan'
$orphan = Join-Path $downloads 'source-tools-test-orphan\source_tools.zip'
New-FixtureFile $orphan
$callsBeforeOrphan = $downloadMock.Calls
Expect-Failure { & $downloader @downloadArgs } 'Existing asset/record is incomplete'
Assert-True ($downloadMock.Calls -eq $callsBeforeOrphan -and (Get-Content -LiteralPath $orphan -Raw) -eq 'fixture') 'Orphan existing asset was overwritten.'
Pass-Case 'asset without provenance is not overwritten'

$downloadArgs.Version = 'test-installer'
$downloadArgs.FileName = 'setup.exe'
$downloadMock.Bytes = [byte[]](0x4D,0x5A,0,0,0,0,0,0)
$installer = & $downloader @downloadArgs
$installerRecord = Get-Content -LiteralPath $installer.RecordPath -Raw | ConvertFrom-Json
Assert-True ($installer.AuthenticodeStatus -eq 'Valid' -and $installerRecord.Signer -eq 'fixture signer' -and
    -not $installerRecord.Executed -and $signatureMock.Calls -eq 1) 'Installer signature metadata is missing or it was executed.'
Pass-Case 'mock installer signature is recorded but installer is never executed'

$downloadArgs.Version = 'test-untrusted-installer'
$signatureMock.Status = 'NotTrusted'
Expect-Failure { & $downloader @downloadArgs } 'Invalid installer signature'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $downloads 'source-tools-test-untrusted-installer\setup.exe'))) 'Invalid signature installer became a final asset.'
Pass-Case 'untrusted installer signature remains blocking'

# Minimal static package fixtures, not executable game assets.
$addonValidator = Join-Path $PSScriptRoot 'validate_gmod_addon.ps1'
$addon = Join-Path $runRoot 'addon-fixture'
$modelBase = Join-Path $addon 'models\player\fixture\fixture'
New-Item -ItemType Directory -Path (Split-Path -Parent $modelBase) -Force | Out-Null
foreach ($suffix in @('.mdl', '.vvd', '.dx90.vtx', '.phy')) {
    $bytes = New-Object byte[] 128
    if ($suffix -eq '.mdl') { [Text.Encoding]::ASCII.GetBytes('IDST').CopyTo($bytes, 0) }
    if ($suffix -eq '.vvd') { [Text.Encoding]::ASCII.GetBytes('IDSV').CopyTo($bytes, 0) }
    if ($suffix -eq '.dx90.vtx') { [BitConverter]::GetBytes([int]7).CopyTo($bytes, 0) }
    [IO.File]::WriteAllBytes(($modelBase + $suffix), $bytes)
}
New-FixtureFile (Join-Path $addon 'addon.json') '{"title":"fixture","type":"model"}'
New-FixtureFile (Join-Path $addon 'lua\autorun\fixture.lua') "local modelPath = 'models/player/fixture/fixture.mdl'`nlist.Set('PlayerOptionsModel', 'Fixture', modelPath)`nplayer_manager.AddValidModel('Fixture', modelPath)"
$vmt = Join-Path $addon 'materials\models\player\fixture\texture.vmt'
$vtf = Join-Path $addon 'materials\models\player\fixture\texture.vtf'
New-FixtureFile $vmt '"VertexLitGeneric" { "$basetexture" "models/player/fixture/texture" }'
$vtfBytes = New-Object byte[] 84
[Text.Encoding]::ASCII.GetBytes("VTF`0").CopyTo($vtfBytes, 0)
[BitConverter]::GetBytes([uint32]7).CopyTo($vtfBytes, 4)
[BitConverter]::GetBytes([uint32]80).CopyTo($vtfBytes, 12)
[BitConverter]::GetBytes([uint16]1).CopyTo($vtfBytes, 16)
[BitConverter]::GetBytes([uint16]1).CopyTo($vtfBytes, 18)
[IO.File]::WriteAllBytes($vtf, $vtfBytes)
$packageArgs = @{AddonRoot=$addon; ModelRelativePath='models/player/fixture/fixture.mdl'; Json=$true}
$packageGood = & $addonValidator @packageArgs | ConvertFrom-Json
Assert-True $packageGood.Valid 'Basic positive static package fixture failed.'
Pass-Case 'basic VTF header and static package positive control'

[IO.File]::WriteAllBytes($vtf, [byte[]]@())
$packageEmpty = & $addonValidator @packageArgs | ConvertFrom-Json
Assert-True (-not $packageEmpty.Valid -and $packageEmpty.Failed -contains 'VMT texture.vmt') 'Empty VTF was accepted.'
[IO.File]::WriteAllBytes($vtf, (New-Object byte[] 84))
$packageWrongMagic = & $addonValidator @packageArgs | ConvertFrom-Json
Assert-True (-not $packageWrongMagic.Valid) 'Incorrect VTF signature was accepted.'
Pass-Case 'empty and wrong-signature VTFs are rejected'

[BitConverter]::GetBytes([uint32]1000).CopyTo($vtfBytes, 12)
[IO.File]::WriteAllBytes($vtf, $vtfBytes)
$packageTruncated = & $addonValidator @packageArgs | ConvertFrom-Json
Assert-True (-not $packageTruncated.Valid) 'VTF declaring an out-of-file header was accepted.'
Pass-Case 'truncated VTF header extent is rejected'

New-FixtureFile $vmt '"VertexLitGeneric" { "$basetexture" "models/player/fixture/directory" }'
New-Item -ItemType Directory -Path (Join-Path $addon 'materials\models\player\fixture\directory.vtf') -Force | Out-Null
$packageDirectory = & $addonValidator @packageArgs | ConvertFrom-Json
Assert-True (-not $packageDirectory.Valid) 'Directory masquerading as VTF was accepted.'
Pass-Case 'a directory cannot satisfy a VTF file check'

[pscustomobject]@{Passed=$passed; FixtureRoot=$runRoot; NetworkRequests=0; InstalledPrograms=0} | ConvertTo-Json
