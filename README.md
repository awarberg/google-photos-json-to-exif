# Introduction
Tool for importing Google Photos JSON files as delivered by [Google Takeout](https://takeout.google.com) into their respective media files (JPEG, PNG, or MP4).

In some cases Google Photos have moved the exif metadata out of the media files, which prevents standard tools like Windows Explorer or other media organization programs from working correctly.

By using this tool the metadata can be merged back into the media file so that any exif-aware programs can work with the files as intended.

# Prerequisites
- PowerShell 5.1 or later
- The [ExifTool](https://www.exiftool.org/) must be downloaded and added to the path.  
  (To check this run: `Get-Command exiftool`.)
- If you downloaded the script, the PowerShell execution policy may need to be changed to allow execution:
  - Right-click the `.ps1` file and Unblock it from the properties
  - Run the command `Set-ExecutionPolicy RemoteSigned`
  - Read more about running scripts [here](https://devblogs.microsoft.com/powershell/running-scripts-downloaded-from-the-internet/)

# Usage

> [WARNING]  
> This tool will make changes to the media files that are contained in the provided folder path. 
Make sure to backup your files before running the tool.

The tool is run from a PowerShell command prompt with the command:  
`.\Import-GooglePhotosJson.ps1 -MediaFolderPath <path-to-media-folder>`

Optionally supply the `-IncludeFiles` parameter to provide a list of extensions to scan e.g. `-IncludeFiles "*.jpg", "*.jpeg"` to only target JPEG images.

All media files will be scanned for missing metadata that might reside in the JSON file provided by Takeout. 

If a piece of metadata is missing from the media file, but is available in the JSON file, the tool will use ExifTool to add the missing metadata to the media file.

The current metadata currently supported is:
1. Date taken (JPEG: `AllDates`, PNG: `CreationTime`, MP4: `CreateDate`)
2. GPS coordinates (`GPSLatitude`, `GPSLongitude`)
3. Comment field (`xmp-dc:description`, `UserComment`)

## Remove original files
The script below will remove the original files (those have '-edited' version). Some may use Google Photo's editing tools, which would create those 'edited' files
`.\Merge-Edited-Files.ps1 -MediaFolderPath <path-to-media-folder>`
