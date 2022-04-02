param (
    [string]
    $ImageFolderPath
)

function Parse-JsonTimestamp([int]$UnixTime) {
    [DateTimeOffset]::FromUnixTimeSeconds($UnixTime)
}

function Parse-Geo($GeoData) {
    if (-not $GeoData) {
        return $null
    }

    if (-not $GeoData.latitude -or -not $GeoData.longitude) {
        return $null
    }

    @{ Lat = $GeoData.latitude ; Lon = $GeoData.longitude }
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
        Write-Warning "Failed to parse photo taken time for $FilePath - $($JsonInfo.photoTakenTime.timestamp) - $($_)"
        return
    }
    
    $ExifDateStr = $DateTimeTaken.ToString("yyyy\:MM\:dd HH\:mm\:sszzz")

    if ($ExifInfo.FileType -eq "PNG") {
        if (-not $ExifInfo.CreationTime) {
            Invoke-ExifTool -Filepath $FilePath -Command "-PNG:CreationTime=$ExifDateStr"
        }
    } else {
        if (-not $ExifInfo.CreateDate) {
            Invoke-ExifTool -Filepath $FilePath -Command "-AllDates=$ExifDateStr"
        }
    }
}

function Ensure-Location($FilePath, $ExifInfo, $JsonInfo) {
    $Geo = Parse-Geo -GeoData $JsonInfo.geoData

    if (-not $ExifInfo.GPSPosition -and $Geo) {
        Invoke-ExifTool -Filepath $FilePath -Command "-GPSLatitude=$($Geo.Lat) -GPSLongitude=$($Geo.Lon)"
    }
}

function Get-JsonFile($FilePath) {
    $FileItem = Get-ChildItem -Path $FilePath
    $DirectoryPath = $FileItem.Directory.FullName
    $BaseName = $FileItem.BaseName
    $Extension = $FileItem.Extension

    $JsonFile = $null

    if ($FilePath -match "(\(\d+\))") {        
        # Naming convention 1: File name contains numbered parenthesis, which is shifted just before the .json extension e.g.
        # IMG_2687(1).PNG =>
        # IMG_2687.PNG(1).json
        $Parenthesis = $Matches[0]
        $TrimBaseName = $BaseName.Replace($Parenthesis, "")
        $JsonFile = Get-ChildItem `
            -Path $DirectoryPath `
            -Filter "$TrimBaseName$($Extension)$Parenthesis.json"
    }

    if (-not $JsonFile) {
        # Naming convention 2: Same as file name but suffixed .json e.g.
        # 20220205_204848.jpg =>
        # 20220205_204848.jpg.json
        $JsonFile = Get-ChildItem `
            -Path $DirectoryPath `
            -Filter "$BaseName$($Extension).json"
    }

    if (-not $JsonFile) {
        # Naming convention 3: Same as file name but max. 46 chars and suffixed .json and without the image file extension e.g.
        # 01-07-2020_D7A9A6E0-7C3B-48F8-B590-21F4F08D60A0.jpg =>
        # 01-07-2020_D7A9A6E0-7C3B-48F8-B590-21F4F08D60A.json
        $JsonFile = Get-ChildItem `
            -Path $DirectoryPath `
            -Filter "$($BaseName.Substring(0, [Math]::Min($BaseName.Length, 46)))*.json"
    }

    return $JsonFile
}

$ImageFiles = Get-ChildItem `
    -Path $ImageFolderPath `
    -Include "*.jpg", "*.jpeg", "*.png" `
    -Recurse

$ImagesProcessed = 0

$ImageFiles | ForEach-Object { 

    $FilePath = $_.FullName
    Write-Host "Processing $FilePath"

    $PercentComplete = [Math]::Floor(($ImagesProcessed++ / $ImageFiles.Count) * 100)
    Write-Progress `
        -Activity "Google Photos JSON to image metadata import" `
        -Status "$PercentComplete% Complete:" `
        -PercentComplete $PercentComplete
    
    $JsonFile = Get-JsonFile -FilePath $FilePath
    if (-not $JsonFile) {
        Write-Warning "Skipping $FilePath - no JSON file found" 
        return
    }

    $JsonFilePath = $JsonFile.FullName
    try {
        $JsonInfo = Get-Content -Path $JsonFilePath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Failed to load JSON file $JsonFilePath - $($_)"
        return
    }

    $ExifInfo = exiftool $FilePath -json | ConvertFrom-Json

    Ensure-DateTaken -FilePath $FilePath -ExifInfo $ExifInfo -JsonInfo $JsonInfo
    Ensure-Location -FilePath $FilePath -ExifInfo $ExifInfo -JsonInfo $JsonInfo
}