# Downloads only. Caller must verify current primary release source and obtain write/network permission.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)][uri]$Url,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')][string]$Tool,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')][string]$Version,
    [Parameter(Mandatory=$true)][string]$FileName,
    [string]$DownloadRoot = 'D:\gmod工具\_downloads',
    [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256 = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Url.IsAbsoluteUri -or $Url.Scheme -ne 'https' -or $Url.UserInfo) {
    throw 'Use an absolute HTTPS release-asset URL without embedded credentials.'
}
if ($FileName -notmatch '^[A-Za-z0-9][A-Za-z0-9._ -]*\.(zip|7z|exe|msi|mcpb|whl)$' -or
    [IO.Path]::GetFileName($FileName) -ne $FileName) {
    throw 'FileName must be a simple leaf name with a supported asset extension.'
}
if (-not [IO.Path]::IsPathRooted($DownloadRoot)) { throw 'DownloadRoot must be an absolute path.' }
$root = [IO.Path]::GetFullPath($DownloadRoot).TrimEnd('\', '/')
$assetDir = [IO.Path]::GetFullPath((Join-Path $root ($Tool + '-' + $Version)))
$destination = [IO.Path]::GetFullPath((Join-Path $assetDir $FileName))
if (-not $destination.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Asset path escapes DownloadRoot.'
}
$recordPath = $destination + '.provenance.json'

function Assert-AssetHeader {
    param([string]$Path, [string]$Extension)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $bytes = New-Object byte[] 8
        $count = $stream.Read($bytes, 0, $bytes.Length)
        if ($count -lt 4) { throw 'Empty/truncated download.' }
        $hex = [BitConverter]::ToString($bytes, 0, $count).Replace('-', '')
    } finally { $stream.Dispose() }
    $valid = switch ($Extension.ToLowerInvariant()) {
        '.zip' { $hex -match '^504B(0304|0506|0708)' }
        '.mcpb' { $hex -match '^504B(0304|0506|0708)' }
        '.whl' { $hex -match '^504B(0304|0506|0708)' }
        '.7z' { $hex.StartsWith('377ABCAF271C') }
        '.exe' { $hex.StartsWith('4D5A') }
        '.msi' { $hex.StartsWith('D0CF11E0A1B11AE1') }
        default { $false }
    }
    if (-not $valid) { throw 'Asset signature does not match extension (possibly HTML or an error response).' }
}

$extension = [IO.Path]::GetExtension($FileName)
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $recordPath)) {
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
        -not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
        throw 'Existing asset/record is incomplete; inspect it instead of overwriting.'
    }
    $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($record.RequestedUrl -ne $Url.AbsoluteUri -or $record.Version -ne $Version -or
        $record.Tool -ne $Tool -or $record.Sha256 -ne $hash -or
        ($ExpectedSha256 -and $ExpectedSha256 -ne $hash)) {
        throw 'Existing asset provenance/hash differs; will not overwrite or reuse.'
    }
    Assert-AssetHeader $destination $extension
    [pscustomobject]@{Status='reused'; Path=$destination; RecordPath=$recordPath; Sha256=$hash}
    return
}
if (-not $PSCmdlet.ShouldProcess($destination, ('Download verified release asset from ' + $Url.AbsoluteUri))) {
    [pscustomobject]@{Status='planned_only'; Path=$destination; RecordPath=$recordPath}
    return
}
New-Item -ItemType Directory -Path $assetDir -Force | Out-Null
$partial = $destination + '.' + [guid]::NewGuid().ToString('N') + '.partial'
try {
    $response = Invoke-WebRequest -Uri $Url.AbsoluteUri -OutFile $partial -UseBasicParsing -PassThru
    Assert-AssetHeader $partial $extension
    $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
    if ($ExpectedSha256 -and $ExpectedSha256 -ne $hash) { throw 'SHA-256 does not match expected release hash.' }
    $finalUrl = $null
    if ($response -and $response.BaseResponse) {
        if ($response.BaseResponse.ResponseUri) { $finalUrl = $response.BaseResponse.ResponseUri.AbsoluteUri }
        elseif ($response.BaseResponse.RequestMessage -and $response.BaseResponse.RequestMessage.RequestUri) {
            $finalUrl = $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
        }
    }
    if ($finalUrl -and ([uri]$finalUrl).Scheme -ne 'https') { throw 'Final response downgraded from HTTPS.' }
    $signature = 'not_applicable'
    $signer = $null
    if ($extension -in @('.exe', '.msi')) {
        $signatureInfo = Get-AuthenticodeSignature -LiteralPath $partial
        $signature = [string]$signatureInfo.Status
        if ($signatureInfo.SignerCertificate) { $signer = $signatureInfo.SignerCertificate.Subject }
        if ($signature -in @('HashMismatch', 'NotTrusted')) { throw ('Invalid installer signature: ' + $signature) }
    }
    # File.Move fails if a concurrent writer creates this destination; do not overwrite.
    [IO.File]::Move($partial, $destination)
    $record = [ordered]@{
        Tool=$Tool; Version=$Version; RequestedUrl=$Url.AbsoluteUri
        FinalResponseUrl=$finalUrl; FinalResponseUrlVerified=[bool]$finalUrl
        Path=$destination; Sha256=$hash; ExpectedSha256=$ExpectedSha256
        SizeBytes=(Get-Item -LiteralPath $destination).Length
        AuthenticodeStatus=$signature; Signer=$signer
        DownloadedUtc=[DateTime]::UtcNow.ToString('o'); Executed=$false
    }
    # Sidecar is create-new, not a blanket rewrite of an existing shared manifest.
    $json = $record | ConvertTo-Json -Depth 4
    $writer = New-Object IO.StreamWriter([IO.File]::Open($recordPath, [IO.FileMode]::CreateNew), (New-Object Text.UTF8Encoding($false)))
    try { $writer.Write($json) } finally { $writer.Dispose() }
    [pscustomobject]@{Status='downloaded'; Path=$destination; RecordPath=$recordPath; Sha256=$hash; AuthenticodeStatus=$signature}
} catch {
    throw ('Download failed: ' + $_.Exception.Message + '. Inspect any retained .partial or asset at ' + $assetDir + '; nothing was executed.')
}
