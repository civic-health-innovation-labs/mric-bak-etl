# Location of SQL Server Instance and port (e. g.: NAME.LOCATION.cloudapp.azure.com,1433)
$SQL_SERVER_URL = "TODO"
# Name of the SQL database on the SQL Server (typically, rio_tre)
$SQL_DATABASE_NAME = "rio_tre"
# Username to SQL Server
$SQL_USERNAME = "TODO"
# Password to access SQL Server
$SQL_PASSWORD = "TODO"
# Full URL to blob (e.g.: https://SomeStorage.blob.core.windows.net/SomeBlob)
$BLOB_URL = "TODO"
# SAS to bak storage (needs to have perms: Read, List, Immutable), starting with ?sp=....
$SAS_TOKEN = "TODO"
# Path to temporary storage folder for bak files (be aware they might contain large files, use F drive)
$PATH_TEMP_FOLDER_BAK = "TODO"
# Path to temporary storage for bak files (be aware they might be large files, use F drive)
$PATH_TEMP_BAK = "TODO"
# Path to the local database file that stores the latest imported bak (e. g. last_file.txt)
$PATH_LATEST_BAK = "TODO"
# ~~~ END OF CONFIGURATION SECTION ~~~

# === FIND AVAILABLE FILES ===
$sas_link_list = $BLOB_URL + $SAS_TOKEN
$az_list_result = azcopy list "$sas_link_list" --output-type=text

# This array contains all files with .bak in name located in blob
$blob_files_list = @()

foreach ($blob_entry in $az_list_result) {
    $split_list = $blob_entry.split(";")
    $info_str_and_filename = $split_list[0]
    if ($info_str_and_filename.Contains(".zip")) {
        # Every line looks like
        #   INFO: FileName.whatever
        #   therefore the string 'INFO: ' needs to be trimmed (length = 6)
        $blob_files_list += $info_str_and_filename.Substring(6)
    }
}
if ( $blob_files_list.Count -eq 0 ) {
    # Terminate the script if empty
    Write-Host "There is no .zip file in the blob storage"
    Exit
}
$sorted_files = $blob_files_list
if ( $blob_files_list.Count -gt 1 ) {
    # This works correctly only if the array has at least 2 elements
    $sorted_files = ($blob_files_list | Sort-Object -Descending)
    $latest_file_in_storage = $sorted_files[0]
}
else {
    # This is the name of the file with the right bak (latest version)
    $latest_file_in_storage = $sorted_files
}

Write-Host "Trying to import $latest_file_in_storage"
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# === TEST IF THE NEWEST BAK HAS NOT BEEN IMPORTED ===
$local_db_file_exist = Test-Path -Path "$PATH_LATEST_BAK"
if ($local_db_file_exist) {
    $latest_file_in_db = Get-Content -Path "$PATH_LATEST_BAK"
    if ( $latest_file_in_storage -eq $latest_file_in_db ) {
        Write-Host "Nothing to import (already imported)"
        Exit
    }
}
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# === DOWNLOAD THE LATEST FILE ===
$blob_file_path_sas = $BLOB_URL + "/" + $latest_file_in_storage + $SAS_TOKEN
azcopy copy "$blob_file_path_sas" "$PATH_TEMP_BAK"
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# === UNZIP THE FILE ===
cd -Path $PATH_TEMP_FOLDER_BAK
7z e $PATH_TEMP_BAK
# ======================


# === LIST ALL BAK FILES IN THE FOLDER ===
$path_to_bak_to_unload = ""
Get-ChildItem $PATH_TEMP_FOLDER_BAK -File | Foreach-Object {
    $fileBakName = $_.Name
    if ($fileBakName.Contains(".bak")) {
        $path_to_bak_to_unload = $fileBakName
    }
}
$FULL_PATH_TO_BAK_FILE = $PATH_TEMP_FOLDER_BAK + $path_to_bak_to_unload
# ========================================

# === UNLOAD BAK INTO THE SQL SERVER ===
# Call the DROP command to remove existing DB
sqlcmd `
    -U $SQL_USERNAME `
    -P $SQL_PASSWORD `
    -S $SQL_SERVER_URL `
    -Q "DROP DATABASE IF EXISTS $SQL_DATABASE_NAME"

# Call the bak unloading
sqlcmd `
    -U $SQL_USERNAME `
    -P $SQL_PASSWORD `
    -S $SQL_SERVER_URL `
    -Q "RESTORE DATABASE $SQL_DATABASE_NAME FROM DISK = '$FULL_PATH_TO_BAK_FILE' WITH MOVE 'LIVE' TO 'F:\DATA\RiO_TRE.mdf', MOVE 'LIVE_log' TO 'F:\DATA\RiO_TRE.ldf'"

# Add Chris Ch. as a reader
sqlcmd `
    -U $SQL_USERNAME `
    -P $SQL_PASSWORD `
    -S $SQL_SERVER_URL `
    -d rio_tre `
    -Q "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'ChristopherCheyne') BEGIN CREATE USER ChristopherCheyne FOR LOGIN [ChristopherCheyne] EXEC sp_addrolemember N'db_datareader', N'ChristopherCheyne' END;"
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# === STORE THE IMPORTED VERSION INTO LOCAL DB ===
$latest_file_in_storage | Out-File -FilePath $PATH_LATEST_BAK
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# TODO: REMOVE TEMP FILES
