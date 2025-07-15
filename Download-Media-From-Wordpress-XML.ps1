<#
.SYNOPSIS
    Extracts media URLs from a WordPress XML export and downloads them to disk.

.DESCRIPTION
    This script reads a WordPress export `.xml` file, finds all <wp:attachment_url> entries, 
    and downloads the referenced media files. If the expected XML file is not found, 
    it prompts the user to enter the correct file path interactively.

.REQUIREMENTS
    - PowerShell 5.0 or newer
    - Internet access
    - A WordPress export XML file (from Tools > Export)

.INPUTS
    The script will prompt for the XML file path if `wordpress_export.xml` is not found.

.OUTPUTS
    - [basename]_media/        → All media files saved locally
    - download_log_*.txt       → Success and skipped file log
    - download_errors_*.txt    → Errors and failed downloads

.USAGE
    1. Export your WordPress site using Tools > Export (choose "All content" or "Media").
    2. Save the XML file locally.
    3. Place this script in the same folder or run it from anywhere.
    4. Run it in PowerShell:
           .\Download-Media-From-XML.ps1
    5. If prompted, paste the full path to your `.xml` file.

.NOTES
    You can rerun this script anytime to resume or retry. Already downloaded files are skipped.
#>

# --------------------------------------
# Configuration
# --------------------------------------

$DefaultXmlFile = "wordpress_export.xml"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$allowedExtensions = @(".jpg", ".jpeg", ".png", ".gif", ".svg", ".webp", ".mp4", ".mp3", ".pdf", ".zip")

# --------------------------------------
# Step 1: Resolve XML file path
# --------------------------------------

if (-Not (Test-Path $DefaultXmlFile)) {
    Write-Host "Default XML file '$DefaultXmlFile' not found." -ForegroundColor Yellow
    $XmlFile = Read-Host "Please enter the full path to your WordPress export .xml file"
    if (-Not (Test-Path $XmlFile)) {
        Write-Host "Error: File not found at '$XmlFile'. Please check the path and try again." -ForegroundColor Red
        exit 1
    }
} else {
    $XmlFile = $DefaultXmlFile
}

# Get base name from input file to create output folder
$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($XmlFile)
$OutDir = "$BaseName`_media"
$LogFile = "download_log_$timestamp.txt"
$ErrFile = "download_errors_$timestamp.txt"

# --------------------------------------
# Step 2: Prepare directories and logs
# --------------------------------------

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# --------------------------------------
# Step 3: Load and parse XML file
# --------------------------------------

try {
    [xml]$xml = Get-Content $XmlFile
}
catch {
    Write-Host "Failed to parse XML file: $XmlFile" -ForegroundColor Red
    exit 1
}

$nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$nsMgr.AddNamespace("wp", "http://wordpress.org/export/1.2/")

# Extract URLs as plain strings
$attachmentNodes = $xml.SelectNodes("//wp:attachment_url", $nsMgr)
Write-Host "Found $($attachmentNodes.Count) attachment_url nodes." -ForegroundColor Cyan

$rawUrls = @()
foreach ($node in $attachmentNodes) {
    if ($node.InnerText) {
        $rawUrls += $node.InnerText
    }
}

Write-Host "Extracted $($rawUrls.Count) raw URLs from nodes." -ForegroundColor Cyan

if ($rawUrls.Count -eq 0) {
    Write-Host "No <wp:attachment_url> entries found in the XML file." -ForegroundColor Yellow
    exit 1
}

# --------------------------------------
# Step 4: Filter by allowed file extensions
# --------------------------------------

$urls = $rawUrls | Where-Object {
    if ($_ -and ($_ -is [string])) {
        $ext = [System.IO.Path]::GetExtension($_).ToLower()
        return $allowedExtensions -contains $ext
    }
    return $false
}

Write-Host "After filtering: $($urls.Count) URLs with supported extensions." -ForegroundColor Cyan

if ($urls.Count -eq 0) {
    Write-Host "No media files with supported extensions found." -ForegroundColor Yellow
    Write-Host "Allowed extensions: $($allowedExtensions -join ', ')" -ForegroundColor Yellow
    exit 1
}

# --------------------------------------
# Function: Retryable download
# --------------------------------------

function Download-With-Retry {
    param (
        [string]$Url,
        [string]$Destination
    )

    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -ErrorAction Stop
        return $true
    }
    catch {
        Start-Sleep -Seconds 2
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Destination -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }
}

# --------------------------------------
# Step 5: Download each media file with progress
# --------------------------------------

$total = $urls.Count
$count = 0

foreach ($url in $urls) {
    $count++
    $fileName = Split-Path $url -Leaf
    $destination = Join-Path $OutDir $fileName

    Write-Progress -Activity "Downloading media files..." `
                   -Status "${count} of ${total}: $fileName" `
                   -PercentComplete (($count / $total) * 100)

    Write-Host "Downloading: $fileName"

    if (-Not (Test-Path $destination)) {
        if (Download-With-Retry -Url $url -Destination $destination) {
            Add-Content -Path $LogFile -Value "Success: $fileName"
        } else {
            $errorMessage = "Failed (after retry): $fileName"
            Write-Host $errorMessage -ForegroundColor Yellow
            Add-Content -Path $ErrFile -Value $errorMessage
        }
    } else {
        Add-Content -Path $LogFile -Value "Skipped (already exists): $fileName"
    }
}

# --------------------------------------
# Step 6: Completion summary
# --------------------------------------

Write-Host ""
Write-Host "Download complete." -ForegroundColor Green
Write-Host "Downloaded files are in: $OutDir"
Write-Host "Success log: $LogFile"
Write-Host "Errors logged in: $ErrFile"

# --------------------------------------
# Optional: Pause if run in console
# --------------------------------------

if ($Host.Name -eq "ConsoleHost") {
    Write-Host ""
    Read-Host "Press Enter to exit"
}
