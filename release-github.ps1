param(
	[switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:CreatedReleaseUrl = ''

function Invoke-CheckedTool {
	param(
		[Parameter(Mandatory = $true)][string]$Executable,
		[Parameter(Mandatory = $true)][string[]]$Arguments
	)

	$previousErrorActionPreference = $ErrorActionPreference
	try {
		$ErrorActionPreference = 'Continue'
		$commandOutput = & $Executable @Arguments 2>&1
		$exitCode = $LASTEXITCODE
	} finally {
		$ErrorActionPreference = $previousErrorActionPreference
	}

	$outputText = (($commandOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()
	if ($exitCode -ne 0) { throw "$Executable failed with exit code $exitCode.`n$outputText" }
	return $outputText
}

function Get-ArchiveEntryBytes {
	param([Parameter(Mandatory = $true)]$ArchiveEntry)

	$entryStream = $ArchiveEntry.Open()
	$memoryStream = [IO.MemoryStream]::new()
	try {
		$entryStream.CopyTo($memoryStream)
		return $memoryStream.ToArray()
	} finally {
		$memoryStream.Dispose()
		$entryStream.Dispose()
	}
}

function Get-FileSha256 {
	param([Parameter(Mandatory = $true)][string]$FilePath)

	$fileStream = [IO.File]::OpenRead($FilePath)
	$sha256 = [Security.Cryptography.SHA256]::Create()
	try {
		return ([BitConverter]::ToString($sha256.ComputeHash($fileStream))).Replace('-', '').ToLowerInvariant()
	} finally {
		$sha256.Dispose()
		$fileStream.Dispose()
	}
}

function Convert-TagToVersion {
	param([string]$TagName)

	if ([string]::IsNullOrWhiteSpace($TagName)) { return $null }
	$normalizedTag = $TagName.Trim()
	if ($normalizedTag.StartsWith('v', [StringComparison]::OrdinalIgnoreCase)) { $normalizedTag = $normalizedTag.Substring(1) }
	if ($normalizedTag -notmatch '^\d+\.\d+\.\d+$') { return $null }
	return [version]$normalizedTag
}

function Invoke-Release {
	$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
	$distPath = Join-Path $projectRoot 'dist'
	Set-Location -LiteralPath $projectRoot

	Write-Host 'Dropper - GitHub Release' -ForegroundColor Cyan
	Write-Host 'Finding the highest-version MZP in dist...'

	foreach ($requiredCommand in @('git', 'gh')) {
		if ($null -eq (Get-Command $requiredCommand -ErrorAction SilentlyContinue)) { throw "Required command was not found: $requiredCommand" }
	}
	if (-not [IO.Directory]::Exists($distPath)) { throw 'The dist directory was not found.' }

	$validPackages = @()
	$ignoredFiles = @()
	foreach ($mzpFile in @(Get-ChildItem -LiteralPath $distPath -Filter '*.mzp' -File)) {
		if ($mzpFile.Name -match '^(?<slug>[a-z0-9_-]+)@(?<version>\d+\.\d+\.\d+)@(?<guid>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.mzp$') {
			$validPackages += [pscustomobject]@{
				File = $mzpFile
				VersionText = $Matches['version']
				Version = [version]$Matches['version']
				PackageGuid = $Matches['guid'].ToLowerInvariant()
			}
		} else {
			$ignoredFiles += $mzpFile.Name
		}
	}

	if ($validPackages.Count -eq 0) { throw 'No MZP named slug@major.minor.patch@guid.mzp was found in dist.' }
	if ($ignoredFiles.Count -gt 0) {
		Write-Host 'Ignoring MZP files with invalid names:' -ForegroundColor Yellow
		foreach ($ignoredFile in $ignoredFiles) { Write-Host "  $ignoredFile" }
	}

	$highestVersion = ($validPackages | Sort-Object Version -Descending | Select-Object -First 1).Version
	$latestPackages = @($validPackages | Where-Object { $_.Version -eq $highestVersion })
	if ($latestPackages.Count -ne 1) {
		$duplicateNames = ($latestPackages | ForEach-Object { $_.File.Name }) -join [Environment]::NewLine
		throw "Several MZP files have the same highest version $highestVersion. Keep only one:`n$duplicateNames"
	}
	$selectedPackage = $latestPackages[0]
	if ($selectedPackage.File.Length -lt 1024) { throw 'The selected MZP is unexpectedly small.' }

	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$archive = [IO.Compression.ZipFile]::OpenRead($selectedPackage.File.FullName)
	try {
		$archiveEntries = @{}
		foreach ($archiveEntry in $archive.Entries) { $archiveEntries[$archiveEntry.FullName.Replace('\', '/').ToLowerInvariant()] = $archiveEntry }
		foreach ($requiredArchivePath in @('manifest.ini', 'manifest.json', 'maxpkg-changelog.ini', 'mzp.run', 'mzp.run.ms', '_install.ms', '_uninstall.ms', 'icons/icon.svg')) {
			if (-not $archiveEntries.ContainsKey($requiredArchivePath.ToLowerInvariant())) { throw "The MZP is missing a required file: $requiredArchivePath" }
		}

		$manifestJson = [Text.Encoding]::UTF8.GetString((Get-ArchiveEntryBytes $archiveEntries['manifest.json']))
		$manifest = $manifestJson | ConvertFrom-Json
		if ($manifest.version.ToString() -ne $selectedPackage.VersionText) { throw 'The version in manifest.json does not match the MZP filename.' }
		if ($manifest.packageGuid.ToString().ToLowerInvariant() -ne $selectedPackage.PackageGuid) { throw 'The GUID in manifest.json does not match the MZP filename.' }
		if ([string]::IsNullOrWhiteSpace($manifest.name.ToString())) { throw 'The package name is missing from manifest.json.' }
		$releaseChannel = $manifest.releaseChannel.ToString().ToLowerInvariant()
		if ($releaseChannel -notin @('stable', 'alpha', 'beta')) { throw "Unknown releaseChannel: $releaseChannel" }
		$manifestEntryPath = $manifest.entry.ToString().Replace('\', '/').ToLowerInvariant()
		if (-not $archiveEntries.ContainsKey($manifestEntryPath)) { throw 'The entry file from manifest.json is missing from the MZP.' }
		$packageName = $manifest.name.ToString()
	} finally {
		$archive.Dispose()
	}

	$originUrl = Invoke-CheckedTool git @('remote', 'get-url', 'origin')
	if ($originUrl -notmatch '(?i)github\.com[:/](?<repository>[^/\s]+/[^/\s]+?)(?:\.git)?/?$') { throw "The origin remote is not a GitHub repository: $originUrl" }
	$remoteRepository = $Matches['repository']
	[void](Invoke-CheckedTool gh @('auth', 'status', '--hostname', 'github.com'))
	$repositoryInfo = (Invoke-CheckedTool gh @('repo', 'view', $remoteRepository, '--json', 'nameWithOwner,url,defaultBranchRef')) | ConvertFrom-Json
	$repository = $repositoryInfo.nameWithOwner

	$releaseTagOutput = Invoke-CheckedTool gh @('api', '--paginate', "repos/$repository/releases?per_page=100", '--jq', '.[].tag_name')
	$releaseTags = @($releaseTagOutput -split '\r?\n' | Where-Object { $_ -ne '' })
	$existingReleaseTag = $null
	foreach ($releaseTagName in $releaseTags) {
		$releaseVersion = Convert-TagToVersion $releaseTagName
		if ($null -ne $releaseVersion -and $releaseVersion -eq $selectedPackage.Version) {
			$existingReleaseTag = $releaseTagName
			break
		}
	}

	if ($null -ne $existingReleaseTag) {
		$existingRelease = (Invoke-CheckedTool gh @('api', "repos/$repository/releases/tags/$existingReleaseTag")) | ConvertFrom-Json
		Write-Host ''
		Write-Host "Version $($selectedPackage.VersionText) already exists in GitHub Releases." -ForegroundColor Yellow
		Write-Host $existingRelease.html_url -ForegroundColor Cyan
		return
	}

	$remoteTagOutput = Invoke-CheckedTool gh @('api', '--paginate', "repos/$repository/tags?per_page=100", '--jq', '.[].name')
	$remoteTags = @($remoteTagOutput -split '\r?\n' | Where-Object { $_ -ne '' })
	$preferredTag = 'v' + $selectedPackage.VersionText
	if ($remoteTags -contains $preferredTag) {
		$releaseTag = $preferredTag
	} elseif ($remoteTags -contains $selectedPackage.VersionText) {
		$releaseTag = $selectedPackage.VersionText
	} else {
		$releaseTag = $preferredTag
	}

	$packageHash = Get-FileSha256 $selectedPackage.File.FullName
	Write-Host ''
	Write-Host "Valid MZP files : $($validPackages.Count)"
	Write-Host "Highest version : $($selectedPackage.VersionText)" -ForegroundColor Green
	Write-Host "File            : $($selectedPackage.File.Name)"
	Write-Host "Size            : $($selectedPackage.File.Length) bytes"
	Write-Host "SHA-256         : $packageHash"
	Write-Host "Repository      : $($repositoryInfo.url)"
	Write-Host "Release tag     : $releaseTag"
	Write-Host 'This version does not exist in GitHub Releases.' -ForegroundColor Green

	if ($CheckOnly) {
		Write-Host ''
		Write-Host 'Validation completed. Nothing was uploaded.' -ForegroundColor Yellow
		return
	}

	Write-Host ''
	$confirmation = Read-Host 'Upload the selected MZP to GitHub Releases? [Y/N]'
	if ($confirmation.Trim() -ine 'Y') {
		Write-Host 'Cancelled. Nothing was uploaded.' -ForegroundColor Yellow
		return
	}

	$releaseTitle = "$packageName $($selectedPackage.VersionText)"
	$releaseArguments = @('release', 'create', $releaseTag, $selectedPackage.File.FullName, '--repo', $repository, '--title', $releaseTitle, '--target', $repositoryInfo.defaultBranchRef.name, '--generate-notes')
	if ($releaseChannel -ne 'stable') { $releaseArguments += '--prerelease' }
	$script:CreatedReleaseUrl = "https://github.com/$repository/releases/tag/$releaseTag"
	$releaseOutput = Invoke-CheckedTool gh $releaseArguments
	if ($releaseOutput -ne '') { Write-Host $releaseOutput }

	$publishedRelease = (Invoke-CheckedTool gh @('api', "repos/$repository/releases/tags/$releaseTag")) | ConvertFrom-Json
	$uploadedAssets = @($publishedRelease.assets | Where-Object { $_.name -eq $selectedPackage.File.Name })
	if ($uploadedAssets.Count -ne 1) { throw 'The release was created, but the uploaded MZP was not found in its assets.' }
	if ([int64]$uploadedAssets[0].size -ne $selectedPackage.File.Length) { throw 'The release was created, but the uploaded MZP size differs from the local file.' }

	Write-Host ''
	Write-Host 'Release published successfully:' -ForegroundColor Green
	Write-Host $publishedRelease.html_url -ForegroundColor Cyan
}

try {
	Invoke-Release
	exit 0
} catch {
	Write-Host ''
	Write-Host 'RELEASE STOPPED' -ForegroundColor Red
	Write-Host $_.Exception.Message -ForegroundColor Red
	if ($script:CreatedReleaseUrl -ne '') {
		Write-Host 'GitHub accepted the create command. Check the release before retrying:' -ForegroundColor Yellow
		Write-Host $script:CreatedReleaseUrl -ForegroundColor Cyan
	} else {
		Write-Host 'Nothing was uploaded.' -ForegroundColor Yellow
	}
	exit 1
}
