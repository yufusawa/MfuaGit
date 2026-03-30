param(
    [switch]$DeleteMissing
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$TeacherUrl    = "https://gitflic.ru/project/rurewa/mfua.git"
$TeacherBranch = "master"
$TargetBranch  = "main"
$RemoteName    = "teacher"

function Fail($Message) {
    Write-Error $Message
    exit 1
}

function GitOutput {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    $output = & git @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join "`n")
    }
    return $output
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail "git is not installed or not in PATH."
}

# Find repo root based on where the script is stored
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

try {
    $RepoRoot = (GitOutput -C $ScriptDir rev-parse --show-toplevel | Select-Object -First 1).Trim()
} catch {
    Fail "This script must be placed somewhere inside your local git repository."
}

Set-Location $RepoRoot

$CurrentBranch = (GitOutput rev-parse --abbrev-ref HEAD | Select-Object -First 1).Trim()
if ($CurrentBranch -ne $TargetBranch) {
    Fail "You are on '$CurrentBranch'. Switch to '$TargetBranch' first."
}

$Status = GitOutput status --porcelain
if ($Status.Count -gt 0) {
    Fail "Working tree is not clean. Commit, stash, or remove changes first."
}

$BackupBranch = "backup-before-teacher-sync-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")
GitOutput branch $BackupBranch | Out-Null
Write-Host "Created backup branch: $BackupBranch"

$RemoteExists = $true
try {
    GitOutput remote get-url $RemoteName | Out-Null
} catch {
    $RemoteExists = $false
}

if ($RemoteExists) {
    GitOutput remote set-url $RemoteName $TeacherUrl | Out-Null
} else {
    GitOutput remote add $RemoteName $TeacherUrl | Out-Null
}

Write-Host "Fetching $RemoteName/$TeacherBranch ..."
GitOutput fetch --prune $RemoteName $TeacherBranch | Out-Null

$RemoteRef = "$RemoteName/$TeacherBranch"

Write-Host "Copying tracked files from $RemoteRef into $TargetBranch ..."
GitOutput checkout $RemoteRef -- . | Out-Null

if ($DeleteMissing) {
    Write-Host "Removing tracked files that do not exist in $RemoteRef ..."

    $MineList = @(GitOutput ls-files | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $TeacherList = @(GitOutput ls-tree -r --name-only $RemoteRef | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $TeacherSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $TeacherList) {
        [void]$TeacherSet.Add($item)
    }

    $ToDelete = @()
    foreach ($item in $MineList) {
        if (-not $TeacherSet.Contains($item)) {
            $ToDelete += $item
        }
    }

    if ($ToDelete.Count -gt 0) {
        foreach ($path in $ToDelete) {
            & git rm -f -- $path
            if ($LASTEXITCODE -ne 0) {
                Fail "Failed to delete tracked file: $path"
            }
        }
    } else {
        Write-Host "No tracked files to delete."
    }
}

GitOutput add -A | Out-Null

& git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "No changes to commit."
    Write-Host "Backup branch kept at: $BackupBranch"
    exit 0
}

& git commit -m "Sync files from teacher repo ($TeacherBranch)"
if ($LASTEXITCODE -ne 0) {
    Fail "Commit failed."
}

& git push origin $TargetBranch
if ($LASTEXITCODE -ne 0) {
    Fail "Push failed."
}

Write-Host "Done."
Write-Host "Backup branch: $BackupBranch"