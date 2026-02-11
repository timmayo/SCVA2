param(
  [Parameter(Mandatory=$true)]
  [string] $SolutionName,

  [Parameter(Mandatory=$true)]
  [string] $DevEnv,                  # e.g. https://mydev.crm.dynamics.com  (or environment id/name)

  [Parameter(Mandatory=$true)]
  [string] $TagName,                 # e.g. v1.0.0  (your "release" tag)

  [string] $CommitMessage = "",

  [string] $SrcRoot = ".\src",
  [string] $OutRoot = ".\out",

  [string] $Branch = "main"          # branch you want to push to
)

function Exec([string]$cmd) {
  Write-Host ">> $cmd"
  iex $cmd
  if ($LASTEXITCODE -ne 0) { throw "Command failed: $cmd" }
}

# ----------------------------
# Pre-flight checks (Git)
# ----------------------------
# Ensure we're in a git repo
Exec "git rev-parse --is-inside-work-tree | Out-Null"

# Ensure working tree is clean (prevents accidental tagging of mixed state)
$status = (git status --porcelain)
if ($status) {
  throw "Git working tree is not clean. Commit/stash your changes before running this script."
}

# Ensure the tag doesn't already exist (locally or remotely)
Exec "git fetch --tags"
$existingTag = (git tag -l $TagName)
if ($existingTag) {
  throw "Tag '$TagName' already exists locally. Choose a new tag name."
}
$remoteTag = (git ls-remote --tags origin $TagName)
if ($remoteTag) {
  throw "Tag '$TagName' already exists on origin. Choose a new tag name."
}

# Default commit message
if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
  $CommitMessage = "Export/unpack $SolutionName from Dev ($TagName)"
}

# ----------------------------
# PAC: authenticate to Dev
# ----------------------------
Write-Host "Authenticating to Dev environment..."
Exec "pac auth create --environment `"$DevEnv`""   # interactive user sign-in [2](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/environmentvariables-power-automate)

# ----------------------------
# PAC: export solution (unmanaged)
# ----------------------------
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$zipPath = Join-Path $OutRoot "$SolutionName`_unmanaged.zip"

Write-Host "Exporting solution '$SolutionName' to $zipPath ..."
Exec "pac solution export --name `"$SolutionName`" --path `"$zipPath`" --overwrite"  # [1](https://community.powerplatform.com/blogs/post/?postid=b94c4030-8eee-4654-83f6-123745b860ae)

# ----------------------------
# PAC: unpack to src folder
# ----------------------------
New-Item -ItemType Directory -Force -Path $SrcRoot | Out-Null
$solutionFolder = Join-Path $SrcRoot $SolutionName

if (Test-Path $solutionFolder) {
  Write-Host "Removing existing unpacked folder: $solutionFolder"
  Remove-Item -Recurse -Force $solutionFolder
}

Write-Host "Unpacking to $solutionFolder ..."
Exec "pac solution unpack --zipfile `"$zipPath`" --folder `"$solutionFolder`""        # [1](https://community.powerplatform.com/blogs/post/?postid=b94c4030-8eee-4654-83f6-123745b860ae)

# ----------------------------
# Git: add/commit/tag/push
# ----------------------------
Write-Host "Staging unpacked solution..."
Exec "git add `"$solutionFolder`""

# If nothing changed, don't create a meaningless tag
$staged = (git diff --cached --name-only)
if (-not $staged) {
  Write-Host "No changes detected in $solutionFolder. Nothing to commit; no tag created."
  exit 0
}

Write-Host "Committing..."
Exec "git commit -m `"$CommitMessage`""

Write-Host "Creating annotated tag '$TagName'..."
Exec "git tag -a $TagName -m `"$TagName`""

Write-Host "Pushing commit to origin/$Branch ..."
Exec "git push origin $Branch"

Write-Host "Pushing tag '$TagName'..."
Exec "git push origin $TagName"


Write-Host "✅ DONE"
Write-Host "Solution:  $SolutionName"
Write-Host "Tag:       $TagName"
Write-Host "Commit:    $(git rev-parse --short HEAD)"
Write-Host "Export ZIP: $zipPath"
Write-Host "Unpacked:  $solutionFolder"

