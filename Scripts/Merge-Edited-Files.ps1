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

function Remove-EditedFile($FilePath) {
    $FileItem = Get-ChildItem -Path $FilePath
    $DirectoryPath = $FileItem.Directory.FullName
    $BaseName = $FileItem.BaseName
    $Extension = $FileItem.Extension

    # Naming convention: Same as file name but suffixed -edited e.g.
    # 20220205_204848.jpg =>
    # 20220205_204848-edited.jpg
    $editedFilePath = Join-Path $DirectoryPath "$BaseName-edited$($Extension)"
    $editedFile = Get-Item -Path $editedFilePath -ErrorAction SilentlyContinue

    # we remove the old file & rename "the edited file"
    # to save the actual work underlying when processing thousands of files
    if ($editedFile) {
        Write-Host "Processing $editedFile"
        Remove-Item $FilePath
        Rename-Item $editedFile $FilePath
    }
}

$MediaFiles = Get-ChildItem `
    -Path $MediaFolderPath `
    -Include $IncludeFiles `
    -Recurse

$FilesProcessed = 0

$MediaFiles | ForEach-Object {

    $FilePath = $_.FullName

    $PercentComplete = [Math]::Floor(($FilesProcessed++ / $MediaFiles.Count) * 100)
    Write-Progress `
        -Activity "Google Photos merging 'edited' files ($FilesProcessed/$($MediaFiles.Count))" `
        -Status "$PercentComplete% Complete:" `
        -PercentComplete $PercentComplete
    
    Remove-EditedFile -FilePath $FilePath
}

$tmpArray = $Global:issueList | Out-String
Write-Host "Issued list:" -ForegroundColor Yellow
Write-Host $tmpArray

$tmpArray = $Global:warnList | Out-String
Write-Host "Issued Files:" -ForegroundColor Red
Write-Host $tmpArray