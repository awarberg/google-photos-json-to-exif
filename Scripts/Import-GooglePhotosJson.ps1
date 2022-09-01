param (
    [Parameter(Mandatory=$true)]
    [string]$MediaFolderPath,
    [string[]]$IncludeFiles = @("*.jpg", "*.jpeg", "*.png", "*.mp4")
)

# Store warning messages
$Global:warnList = @()

# Store warning files can't be processed
$Global:issueList = @()

# completely override all info in image's exif
$Global:overwriteExif = $true

function Parse-JsonTimestamp([int]$UnixTime) {
    [DateTimeOffset]::FromUnixTimeSeconds($UnixTime)
}

function Parse-Geo($GeoData) {
    if (-not $GeoData) {
        return $null
    }

    [double]$Lat = $GeoData.latitude
    [double]$Lon = $GeoData.longitude

    if ($Lat -eq 0 -and $Lon -eq 0) {
        return $null
    }

    @{ Lat = $Lat ; Lon = $Lon }
}

function Invoke-ExifTool($Filepath, $Command) {
    Write-Host "ExifTool is updating $FilePath with command: $Command"
    exiftool "$FilePath" "$Command" -overwrite_original -quiet
}

function Ensure-DateTaken($FilePath, $ExifInfo, $JsonInfo) {
    if (-not $JsonInfo.photoTakenTime) {
        return
    }

    try {
        $DateTimeTaken = Parse-JsonTimestamp $JsonInfo.photoTakenTime.timestamp
    } catch {        
        $warn = "Failed to parse photo taken time for $FilePath - $($JsonInfo.photoTakenTime.timestamp) - $($_)"
        Write-Warning $warn
        $Global:issueList += $warn
        return
    }
    
    $ExifDateStr = $DateTimeTaken.ToString("yyyy\:MM\:dd HH\:mm\:sszzz")

    switch ($ExifInfo.FileType) {
        "PNG" {
            if ((-not $ExifInfo.CreationTime) -or $Global:overwriteExif) {
                Invoke-ExifTool -Filepath $FilePath -Command "-PNG:CreationTime=$ExifDateStr"
            }
        }
        "MP4" {
            if ((-not $ExifInfo.CreateDate) -or $Global:overwriteExif) {
                Invoke-ExifTool -Filepath $FilePath -Command "-CreateDate=$ExifDateStr"
            }
        }
        Default {
            if ((-not $ExifInfo.CreateDate) -or $Global:overwriteExif) {
                Invoke-ExifTool -Filepath $FilePath -Command "-AllDates=$ExifDateStr"
            }
        }
    }
}

function Ensure-Location($FilePath, $ExifInfo, $JsonInfo) {
    $Geo = Parse-Geo -GeoData $JsonInfo.geoData

    if ($Geo -and ($Global:overwriteExif -or (-not $ExifInfo.GPSLatitude)) ) {
        Invoke-ExifTool -Filepath $FilePath -Command "-GPSLatitude=$($Geo.Lat) -GPSLongitude=$($Geo.Lon)"
    }
}

function Ensure-Comment($FilePath, $ExifInfo, $JsonInfo) {
    if (-not $JsonInfo.description) {
        return
    }

    $comment = $JsonInfo.description

    if ($comment -and ($Global:overwriteExif -or (-not $ExifInfo.comment)) ) {
        Invoke-ExifTool -Filepath $FilePath -Command "-xmp-dc:description=$($comment)"
        Invoke-ExifTool -Filepath $FilePath -Command "-UserComment=$($comment)"
    }
}

function Get-JsonFile($FilePath) {
    $FileItem = Get-ChildItem -Path $FilePath
    $DirectoryPath = $FileItem.Directory.FullName
    $BaseName = $FileItem.BaseName
    $Extension = $FileItem.Extension

    # Naming convention 1: Same as file name but suffixed .json e.g.
    # 20220205_204848.jpg =>
    # 20220205_204848.jpg.json
    $JsonFilePath = Join-Path $DirectoryPath "$BaseName$($Extension).json"
    $JsonFile = Get-Item -Path $JsonFilePath -ErrorAction SilentlyContinue

    if (-not $JsonFile -and $FilePath -match "(\(\d+\))") {        
        # Naming convention 2: File name contains numbered parenthesis, which is shifted just before the .json extension e.g.
        # IMG_2687(1).PNG =>
        # IMG_2687.PNG(1).json
        $Parenthesis = $Matches[0]
        $TrimBaseName = $BaseName.Replace($Parenthesis, "")
        $JsonFilePath = Join-Path $DirectoryPath "$TrimBaseName$($Extension)$Parenthesis.json"
        $JsonFile = Get-Item -Path $JsonFilePath -ErrorAction SilentlyContinue
    }

    if (-not $JsonFile) {
        # Naming convention 3: Same as file name but max. 46 chars and suffixed .json and without the image file extension e.g.
        # 01-07-2020_D7A9A6E0-7C3B-48F8-B590-21F4F08D60A0.jpg =>
        # 01-07-2020_D7A9A6E0-7C3B-48F8-B590-21F4F08D60A.json
        $JsonFilePath = Join-Path $DirectoryPath "$($BaseName.Substring(0, [Math]::Min($BaseName.Length, 46)))*.json"
        $JsonFile = Get-Item -Path $JsonFilePath -ErrorAction SilentlyContinue
    }

    $differ = "-edited"
    if (-not $JsonFile -and $FilePath -match "\b$differ\b") {
        # Naming convention 4: Same as file name but has the 'edited' at the end, before the '.json'. E.g.
        # received_728318214459446-edited.jpeg =>
        # received_728318214459446.jpeg.json
        $matchedWord = $Matches[0]
        $TrimBaseName = $BaseName.Replace($matchedWord, "")
        $JsonFilePath = Join-Path $DirectoryPath "$TrimBaseName$($Extension).json"
        $JsonFile = Get-Item -Path $JsonFilePath -ErrorAction SilentlyContinue
    }

    if ($JsonFile -and $JsonFile.Count -gt 1) {        
        $warn = "Ambigous JSON file matches for $FilePath"
        Write-Warning $warn
        $Global:issueList += $warn
        return $null
    }

    return $JsonFile
}

$MediaFiles = Get-ChildItem `
    -Path $MediaFolderPath `
    -Include $IncludeFiles `
    -Recurse

$FilesProcessed = 0

$MediaFiles | ForEach-Object {

    $FilePath = $_.FullName
    Write-Host "Processing $FilePath"

    $PercentComplete = [Math]::Floor(($FilesProcessed++ / $MediaFiles.Count) * 100)
    Write-Progress `
        -Activity "Google Photos JSON metadata import ($FilesProcessed/$($MediaFiles.Count))" `
        -Status "$PercentComplete% Complete:" `
        -PercentComplete $PercentComplete
    
    $JsonFile = Get-JsonFile -FilePath $FilePath
    if (-not $JsonFile) {
        $warn = "Skipping $FilePath - no JSON file found"
        Write-Warning $warn
        $Global:warnList += $warn
        return
    }

    $JsonFilePath = $JsonFile.FullName
    try {
        $JsonInfo = Get-Content -Path $JsonFilePath -Raw | ConvertFrom-Json
    } catch {
        $warn = "Failed to load JSON file $JsonFilePath - $($_)"
        Write-Warning $warn
        $Global:warnList += $warn
        return
    }

    $ExifInfo = exiftool $FilePath -json | ConvertFrom-Json

    Ensure-DateTaken -FilePath $FilePath -ExifInfo $ExifInfo -JsonInfo $JsonInfo
    Ensure-Location -FilePath $FilePath -ExifInfo $ExifInfo -JsonInfo $JsonInfo
    Ensure-Comment -FilePath $FilePath -ExifInfo $ExifInfo -JsonInfo $JsonInfo
}

$tmpArray = $Global:issueList | Out-String
Write-Host "Issued list:" -ForegroundColor Yellow
Write-Host $tmpArray

$tmpArray = $Global:warnList | Out-String
Write-Host "Issued Files:" -ForegroundColor Red
Write-Host $tmpArray