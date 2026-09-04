#Requires -RunAsAdministrator
# ============================================================
# OneDrive Neutralizer — makes OneDrive inactive without
# uninstalling it (prevents Windows Update reinstall loop)
# ============================================================

#Install-Module Pester -Scope CurrentUser -Force
#Install-Module PSScriptAnalyzer -Scope CurrentUser -Force

Write-Host "=== OneDrive Neutralizer ===" -ForegroundColor Cyan

# ------------------------------------------------------------
# STEP 0: SAFETY CHECK - Detect online-only (cloud) files
# ------------------------------------------------------------
Write-Host "`n[0] Checking for cloud-only files (Files on Demand)..." -ForegroundColor Yellow

$foldersToCheck = @(
    [Environment]::GetFolderPath("Desktop"),
    [Environment]::GetFolderPath("MyDocuments"),
    [Environment]::GetFolderPath("MyPictures")
)

# 0x1000 = FILE_ATTRIBUTE_OFFLINE
# 0x400000 = FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS
$cloudFiles = Get-ChildItem $foldersToCheck -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { ($_.Attributes -band 0x1000) -or ($_.Attributes -band 0x400000) }

if ($cloudFiles) {
    $count = ($cloudFiles | Measure-Object).Count
    Write-Host "WARNING: $count online-only files found!" -ForegroundColor Red
    Write-Host "Open OneDrive → Settings → Sync and backup → Advanced settings"
    Write-Host "→ 'Download all files' FIRST, wait for completion, then re-run this script." -ForegroundColor Yellow
    $answer = Read-Host "Continue anyway? (y/N)"
    if ($answer -ne 'y') { exit 1 }
} else {
    Write-Host "✔ All files are stored locally — safe to proceed." -ForegroundColor Green
}

# ------------------------------------------------------------
# STEP 1: Stop OneDrive processes
# ------------------------------------------------------------
Write-Host "`n[1] Stopping OneDrive processes..." -ForegroundColor Yellow
$procs = Get-Process -Name "OneDrive*" -ErrorAction SilentlyContinue
if ($procs) {
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
Write-Host "✔ OneDrive processes stopped"

# ------------------------------------------------------------
# STEP 2: Disable OneDrive scheduled tasks
# ------------------------------------------------------------
Write-Host "`n[2] Disabling OneDrive scheduled tasks..." -ForegroundColor Yellow
$foundTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskPath -like "*OneDrive*" -or $_.TaskName -like "*OneDrive*" }

if ($foundTasks) {
    foreach ($task in $foundTasks) {
        Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  ✔ Disabled: $($task.TaskPath)$($task.TaskName)"
    }
} else {
    Write-Host "  ℹ No OneDrive scheduled tasks found"
}

# ------------------------------------------------------------
# STEP 3: Disable OneDrive startup entry
# ------------------------------------------------------------
Write-Host "`n[3] Disabling OneDrive autostart..." -ForegroundColor Yellow

# Startup folder shortcut
$startupShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\OneDrive.lnk"
if (Test-Path $startupShortcut) {
    Remove-Item $startupShortcut -Force
    Write-Host "  ✔ Removed startup shortcut"
}

# Registry Run keys
$runKeys = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
             "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
foreach ($rk in $runKeys) {
    if (Get-ItemProperty -Path $rk -Name "OneDrive" -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $rk -Name "OneDrive" -Force -ErrorAction SilentlyContinue
        Write-Host "  ✔ Removed OneDrive from $rk"
    }
}

# Approved Startup list (Task Manager's Startup tab)
$approvedPaths = @(
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
)
$disabledBlob = [byte[]] @(0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
foreach ($ap in $approvedPaths) {
    if (Test-Path $ap) {
        if (Get-ItemProperty -Path $ap -Name "OneDrive" -ErrorAction SilentlyContinue) {
            Set-ItemProperty -Path $ap -Name "OneDrive" -Value $disabledBlob -Type Binary -ErrorAction SilentlyContinue
            Write-Host "  ✔ Disabled OneDrive startup entry in $ap"
        }
    }
}

# ------------------------------------------------------------
# STEP 4: Unlink account + kill sync via policy (registry)
# ------------------------------------------------------------
Write-Host "`n[4] Disabling OneDrive via policy..." -ForegroundColor Yellow

$policyPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive",
    "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows\OneDrive"
)
foreach ($path in $policyPaths) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "DisableFileSyncNGSC" -Value 1 -Type DWord
}

$cuSyncPath = "HKCU:\SOFTWARE\Microsoft\OneDrive"
if (-not (Test-Path $cuSyncPath)) { New-Item -Path $cuSyncPath -Force | Out-Null }
Set-ItemProperty -Path $cuSyncPath -Name "DisablePersonalSync" -Value 1 -Type DWord
Write-Host "  ✔ Sync disabled via Group Policy and User settings"

# ------------------------------------------------------------
# STEP 5: Remove OneDrive from Explorer sidebar
# ------------------------------------------------------------
Write-Host "`n[5] Removing OneDrive from Explorer sidebar..." -ForegroundColor Yellow

$clsidRoots = @(
    "Registry::HKEY_CURRENT_USER\Software\Classes\CLSID",
    "HKLM:\SOFTWARE\Classes\CLSID",
    "HKLM:\SOFTWARE\WOW6432Node\Classes\CLSID"
)

# Known OneDrive CLSIDs
$oneDriveClsids = @("{018D5C66-4533-4307-9B53-224DE2ED1FE6}", "{04271989-C4D2-455D-8085-51D743CC2A3F}")

foreach ($root in $clsidRoots) {
    if (-not (Test-Path $root)) { continue }
    foreach ($clsid in $oneDriveClsids) {
        $targetKey = Join-Path $root $clsid
        if (Test-Path $targetKey) {
            Set-ItemProperty -Path $targetKey -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Write-Host "  ✔ Unpinned CLSID: $clsid"
        }
    }
}

# ------------------------------------------------------------
# STEP 6: Fix Known Folder Redirection
# ------------------------------------------------------------
Write-Host "`n[6] Checking for folder redirects..." -ForegroundColor Yellow

$folders = @{
    "Desktop"  = "$env:USERPROFILE\Desktop"
    "Personal" = "$env:USERPROFILE\Documents"
    "My Pictures" = "$env:USERPROFILE\Pictures"
    "{374DE290-123F-4565-9164-39C4925E467B}" = "$env:USERPROFILE\Downloads"
}

$regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
$legacyPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"

foreach ($entry in $folders.GetEnumerator()) {
    $valName = $entry.Key
    $newPath = $entry.Value
    
    # Ensure local target exists
    if (-not (Test-Path $newPath)) { 
        New-Item -Path $newPath -ItemType Directory -Force | Out-Null 
    }

    $current = (Get-ItemProperty -Path $regPath -Name $valName -ErrorAction SilentlyContinue).$valName
    if ($current -like "*OneDrive*") {
        Set-ItemProperty -Path $regPath -Name $valName -Value $newPath -Type ExpandString
        Set-ItemProperty -Path $legacyPath -Name $valName -Value $newPath -ErrorAction SilentlyContinue
        Write-Host "  ✔ Redirected '$valName' from '$current' → '$newPath'"
    }
}

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host @"
OneDrive is now neutralized.
It remains INSTALLED to prevent Windows Update reinstall loops.

To undo: Set 'DisableFileSyncNGSC' to 0 in HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive
"@ -ForegroundColor White

$restart = Read-Host "`nRestart PC now to finalize? (y/N)"
if ($restart -eq 'y') { Restart-Computer -Confirm }
