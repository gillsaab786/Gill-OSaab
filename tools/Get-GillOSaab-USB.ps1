# Gill(OS): get the USB image ready on Windows.
#   1. Put this script in the folder with the downloaded parts (gill-osaab-core-usb.img.xz.part-00, -01, ...)
#      and SHA256SUMS, or let it download them (it asks).
#   2. Right-click > Run with PowerShell.
# It joins the parts, checks the image is exactly the one published (SHA-256), and opens balenaEtcher
# (or tells you where to get it) to write it to a USB stick of 32 GB or more.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
$name = "gill-osaab-core-usb.img.xz"
$release = "https://github.com/gillsaab786/Gill-OSaab/releases/download/core-usb"

$parts = Get-ChildItem -Filter "$name.part-*" | Sort-Object Name
if (-not $parts -or -not (Test-Path SHA256SUMS)) {
    $answer = Read-Host "Parts not found here. Download them now (about 4 GB)? [y/n]"
    if ($answer -ne "y") { exit 1 }
    $api = Invoke-RestMethod "https://api.github.com/repos/gillsaab786/Gill-OSaab/releases/tags/core-usb"
    foreach ($a in $api.assets) {
        Write-Host "Downloading $($a.name)..."
        Invoke-WebRequest -Uri $a.browser_download_url -OutFile $a.name
    }
    $parts = Get-ChildItem -Filter "$name.part-*" | Sort-Object Name
}

Write-Host "Joining $($parts.Count) parts into $name ..."
$out = [System.IO.File]::Create((Join-Path $here $name))
try {
    foreach ($p in $parts) {
        $in = [System.IO.File]::OpenRead($p.FullName)
        try { $in.CopyTo($out) } finally { $in.Close() }
    }
} finally { $out.Close() }

Write-Host "Checking the image (SHA-256)..."
$want = ((Get-Content SHA256SUMS | Select-String $name).ToString() -split '\s+')[0].ToLower()
$got = (Get-FileHash -Algorithm SHA256 $name).Hash.ToLower()
if ($want -ne $got) {
    Write-Host "The image is damaged or not the published one. Delete the parts and download them again." -ForegroundColor Red
    exit 2
}
Write-Host "Image OK." -ForegroundColor Green

$etcher = @("$env:LOCALAPPDATA\Programs\balena-etcher\balenaEtcher.exe", "$env:ProgramFiles\balenaEtcher\balenaEtcher.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if ($etcher) {
    Write-Host "Opening balenaEtcher: choose 'Flash from file' > $name, then your USB stick."
    Start-Process $etcher
} else {
    Write-Host "Install balenaEtcher (https://etcher.balena.io), then flash $name to a USB stick (32 GB+)."
    Start-Process "https://etcher.balena.io"
}
Write-Host "Then boot from the stick (ROG Ally/GPD: hold Volume Down + Power), sign in as gill / gill and open"
Write-Host "'Install Gill(OS)' to put it on the PC, encrypted."
Read-Host "Press Enter to close"
