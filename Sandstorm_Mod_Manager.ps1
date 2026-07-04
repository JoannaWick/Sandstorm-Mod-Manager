<#PSScriptInfo
.VERSION 1.1.1
.AUTHOR Joanna Wick
.TAGS Sandstorm, Mods
.PROJECTURI https://github.com/JoannaWick/Sandstorm-Mod-Manager
#>

Set-Location -Path $PSScriptRoot

$Version = "1.1.1" 

$settingsPath = Join-Path $env:LOCALAPPDATA "mod.io\globalsettings.json"

if (Test-Path $settingsPath) {
    $StoragePath = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
}
else
{
    Write-Host "$settingsPath is MISSING and cannot proceed." -ForegroundColor Red
    pause
    exit
}

# Create Backup of globalsettings.json

$backupsettingsPath = Join-Path $env:LOCALAPPDATA "mod.io\globalsettings.backup"

if(-not(Test-Path "$backupsettingsPath"))
{
    Copy-Item -Path "$env:LOCALAPPDATA\mod.io\globalsettings.json" -Destination "$env:LOCALAPPDATA\mod.io\globalsettings.backup"
}

# Restore backup if json contents different

$targetFile = "$env:LOCALAPPDATA\mod.io\globalsettings.json"
$backupFile = "$env:LOCALAPPDATA\mod.io\globalsettings.backup"

# Load JSON content
$Settings_Json = Get-Content -Raw -Path $targetFile | ConvertFrom-Json
$Backup_Json = Get-Content -Raw -Path $backupFile | ConvertFrom-Json

# Compare paths (case-insensitive for directory paths)
if ($Settings_Json.RootLocalStoragePath -ne $Backup_Json.RootLocalStoragePath) {
    Write-Host "Mismatch found! Restoring backup..." -ForegroundColor Yellow
    
    # Overwrite the active file with the backup
    Copy-Item -Path $backupFile -Destination $targetFile -Force
    
    Write-Host "Restore complete." -ForegroundColor Green
    pause
}

$destination=$StoragePath.RootLocalStoragePath
$destination=$destination.Replace('/', '\')
$destination_Store=$destination
$verbose = 0
$global:forced_updates = 0

# Get Sandstorm OAuth Token and UserID

$userName = ($env:LOCALAPPDATA -split '\\')[-3]
$mod_io_254_user="$env:LOCALAPPDATA\mod.io\254\$userName\user.json" 
$mod_io_254_server="$env:LOCALAPPDATA\mod.io\254\ModServer\user.json" 

if (Test-Path $mod_io_254_user) {
    $getstatejson = Get-Content -Raw -Path $mod_io_254_user | ConvertFrom-Json
}
elseif (Test-Path $mod_io_254_server) {
    $getstatejson = Get-Content -Raw -Path $mod_io_254_server | ConvertFrom-Json
}
else {
    Write-Host "MISSING $mod_io_254_user" -ForegroundColor Red
    Write-Host "MISSING $mod_io_254_server" -ForegroundColor Red
    Write-Host "Cannot proceed." -ForegroundColor Red
    pause
    exit
}

[string]$token=$getstatejson.Oauth.token
$UserID=$getstatejson.Profile.id


$enable_testing=0 # 0 - Disabled, 1 - Test Json output 

if($enable_testing -eq 1)
{
    $finalpath="254\metadata\state.json"
    if (Test-Path $destination$finalpath) {
        echo "getting state.json $destination$finalpath"
        $getstatejson = Get-Content -Raw -Path $destination$finalpath | ConvertFrom-Json
    }

    # 1. Convert your object to JSON
    $jsonSU = $getstatejson | ConvertTo-Json -Depth 100

    # 2. Fix ONLY Unicode characters (e.g., \u0027) while keeping literal \n untouched
    $cleanJson = [regex]::Replace($jsonSU, '\\u([0-9a-fA-F]{4})', { 
        param($match) [char][int]"0x$($match.Groups[1].Value)" 
    })

    # 3. Export to a valid UTF-8 file
    $cleanJson | Out-File "state_Sandstorm.json" -Encoding utf8
}

# Used to simplify y/n prompts further in the script
function User-Confirm
{
	param ([string]$msg)
	do
	{
		$yn = Read-Host "$msg [y/n]";
		if ($yn -eq 'n')
		{
			return $false
		}
		elseif ($yn -ne 'y')
		{
			echo "Enter y fer yes or n for no"
		}
	}
	while($yn -ne "y")
	return $true
}

# Display GUI Selector of all subscribed mods and ask user to
# select any number of the mods to force a download and update
function Mod-Reset
{
    echo ""
    echo "=============================================="
    echo "   Select Mods to FORCE Download and Update   "
    echo "=============================================="
    echo ""

    if (Test-Path ModList.json)
    {
	    echo "Reading settings from ModList.json."
        echo ""
	    $ModListData=Get-Content ModList.json | ConvertFrom-Json
    }
    else
    {
        Write-Host "ModList.json is MISSING and cannot proceed." -ForegroundColor Red
        pause
        exit
    }

    $ModList = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $ModListData) {

        # Get each dynamic top element name and value
        foreach ($property in $item.PSObject.Properties) {
            $topName = $property.Name
            $topValue = $property.Value

            # Check if the value is a nested object/custom object
            if ($topValue -is [System.Management.Automation.PSCustomObject]) {
            
                # Extract nested names and values
                foreach ($nestedProp in $topValue.PSObject.Properties) {
                    if($($nestedProp.Name) -eq "name")
                    {
                        $modname = $($nestedProp.Value)
                    }
                }
            }
            # Standard property output
            [void]$ModList.Add($modname+" | "+$topName + (' ' * 50)) # [void] suppresses the default .Add() output
        }
    }

    $ModList.Sort()

    # Pass to Out-GridView for interactive multi-selection
    $SelectedMods = $ModList | Out-GridView -Title "Select one or more Mods to Update" -OutputMode Multiple

    if ($null -eq $SelectedMods -or $SelectedMods.Count -eq 0) {
        Write-Host "No Mods were selected" -ForegroundColor Red
        $global:forced_updates=0

        return
    }

    # Output the selected items
    Write-Host "You selected the following items:" -ForegroundColor Green
    $SelectedMods
    echo ""

    if(-not(User-Confirm "Last Chance: Do you really want to force an update for these items?"))
    {
        $global:forced_updates=0

        return
    }
    else
    {
        
        $tlen=$SelectedMods.count
        if( $tlen -gt 1)
        {
            for ($t = 0; $t -lt $tlen; $t++) {
                $modid = ($SelectedMods[$t] -split " \| ")[1].Trim()
                $ModListData.PSObject.Properties.Remove($modid)
            }
        }
        else
        {
            $modid = ($SelectedMods -split " \| ")[1].Trim()
            $ModListData.PSObject.Properties.Remove($modid)
        }

        # Update ModList.json 
        $ModListData | ConvertTo-Json | Set-Content ModList.json
        $global:forced_updates=1

        return
    }
}

# Display GUI Selector of all subscribed mods and ask user to
# select any number of the mods to UNSUBSCRIBE and DELETE
function Mod-Unsub
{
    echo ""
    echo "=============================================="
    echo "    Select Mods to Unsubscribe and Delete   "
    echo "=============================================="
    echo ""

    $gameId = 254
    $apiUrl = "https://api.mod.io/v1"
    $destinationMods="$destination"+"254\mods\"

    if (Test-Path ModList.json)
    {
	    echo "Reading settings from ModList.json."
        echo ""
	    $ModListData=Get-Content ModList.json | ConvertFrom-Json
    }
    else
    {
        Write-Host "ModList.json is MISSING and cannot proceed." -ForegroundColor Red
        pause
        exit
    }

    # Set up the headers with Bearer Token authentication
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type"  = "application/x-www-form-urlencoded"
    }

    $ModList = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $ModListData) {

        # Get each dynamic top element name and value
        foreach ($property in $item.PSObject.Properties) {
            $topName = $property.Name
            $topValue = $property.Value

            # Check if the value is a nested object/custom object
            if ($topValue -is [System.Management.Automation.PSCustomObject]) {
            
                # Extract nested names and values
                foreach ($nestedProp in $topValue.PSObject.Properties) {
                    if($($nestedProp.Name) -eq "name")
                    {
                        $modname = $($nestedProp.Value)
                    }
                }
            }
            # Standard property output
            [void]$ModList.Add($modname+" | "+$topName + (' ' * 50)) # [void] suppresses the default .Add() output
        }
    }

    $ModList.Sort()

    # Pass to Out-GridView for interactive multi-selection
    $SelectedMods = $ModList | Out-GridView -Title "Select one or more Mods you would like to Unsubscribe" -OutputMode Multiple

    if ($null -eq $SelectedMods -or $SelectedMods.Count -eq 0) {
        Write-Host "No Mods were selected" -ForegroundColor Red

        return
    }

    # Output the selected items
    Write-Host "You selected the following items:" -ForegroundColor Green
    $SelectedMods
    echo ""

    if(-not(User-Confirm "Last Chance: Do you really want to Unsubscribe and Delete these items?"))
    {
        return
    }
    else
    {
        
        $tlen=$SelectedMods.count
        if( $tlen -gt 1)
        {
            for ($t = 0; $t -lt $tlen; $t++) {
                $modid = ($SelectedMods[$t] -split " \| ")[1].Trim()
                $ModListData.PSObject.Properties.Remove($modid)

                # Construct the API endpoint
                $endpoint = "$apiUrl/games/$gameId/mods/$modid/subscribe"

                # Execute the Unsubscribe request
                try {
                    $response = Invoke-RestMethod -Uri $endpoint -Method Delete -Headers $headers -ErrorAction Stop
                    Write-Host "Successfully unsubscribed from mod: $modid" -ForegroundColor Green

                	if(-not(Test-Path "$destinationMods$modid"))
	                {
                        Write-Host "Mod: $modid directory not found" -ForegroundColor Yellow
                    }
                    else
                    {
                        Write-Host "Deleting Unsubscribed Mod Directory: $modid" -ForegroundColor Red
                        Remove-Item -Path "$destinationMods$modid" -Recurse -Force
                    }
                } catch {
#                    Write-Host "Failed to unsubscribe. Error: $_" -ForegroundColor Red
                    # 1. Retrieve the HTTP status code
                    $StatusCode = $_.Exception.Response.StatusCode.value__

                    # 2. Extract the error body
                    $ErrorStream = $_.Exception.Response.GetResponseStream()
                    $Reader = New-Object System.IO.StreamReader($ErrorStream)
                    $ResponseBody = $Reader.ReadToEnd()
    
                    # 3. Convert to a PowerShell object to access mod.io's specific error_ref
                    $ErrorDetails = $ResponseBody | ConvertFrom-Json

                    if ($StatusCode -eq 400) {
                        Write-Warning "Not Currently Subscribed to $modid"
                    }
                }

                $headers2 = @{
                    "Authorization" = "Bearer $token"
                    "Accept"        = "application/json"
                }

                $endpoint = "$apiUrl/games/$gameId/mods/$modid/events"
                $epResult = Invoke-RestMethod -Uri $endpoint -Method Get -Headers $headers2 -ErrorAction Stop

                # Delay for mod.io api limit
                Start-Sleep -Milliseconds 250
            }
        }
        else
        {
            $modid = ($SelectedMods -split " \| ")[1].Trim()
            $ModListData.PSObject.Properties.Remove($modid)

            # Construct the API endpoint
            $endpoint = "$apiUrl/games/$gameId/mods/$modid/subscribe"

            # Execute the Unsubscribe request
            try {
                $response = Invoke-RestMethod -Uri $endpoint -Method Delete -Headers $headers -ErrorAction Stop
                Write-Host "Successfully unsubscribed from mod: $modid" -ForegroundColor Green

               	if(-not(Test-Path "$destinationMods$modid"))
                {
                    Write-Host "Mod: $modid directory not found" -ForegroundColor Yellow
                }
                else
                {
                    Write-Host "Deleting Unsubscribed Mod Directory: $modid" -ForegroundColor Red
                    Remove-Item -Path "$destinationMods$modid" -Recurse -Force
                }
            } catch {
#                Write-Host "Failed to unsubscribe. Error: $_" -ForegroundColor Red
                # 1. Retrieve the HTTP status code
                $StatusCode = $_.Exception.Response.StatusCode.value__

                # 2. Extract the error body
                $ErrorStream = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorStream)
                $ResponseBody = $Reader.ReadToEnd()

                # 3. Convert to a PowerShell object to access mod.io's specific error_ref
                $ErrorDetails = $ResponseBody | ConvertFrom-Json

                if ($StatusCode -eq 400) {
                    Write-Warning "Not Currently Subscribed to $modid"
                }
            }

            $headers2 = @{
                "Authorization" = "Bearer $token"
                "Accept"        = "application/json"
            }

            $endpoint = "$apiUrl/games/$gameId/mods/$modid/events"
            $epResult = Invoke-RestMethod -Uri $endpoint -Method Get -Headers $headers2 -ErrorAction Stop
        }

        # Update ModList.json 
        $ModListData | ConvertTo-Json | Set-Content ModList.json

        echo ""
        echo "=============================================="
        echo " Selected Mods have been Unsubscribed/Deleted    "
        echo "=============================================="

        return
    }
}

# 
function Mod-Test
{
	# Load the Windows Forms assembly quietly
	Add-Type -AssemblyName System.Windows.Forms

    # Create a dummy form to act as the owner and force focus
    $parentForm = New-Object System.Windows.Forms.Form -Property @{TopMost = $true}
    $parentForm.TopLevel = $true
    $parentForm.ShowInTaskbar = $false

	# Create the folder browser dialog object
	$FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog

	# Set custom prompt description text
	$FolderBrowser.Description = "Please select a target directory"

	# Show the 'New Folder' button inside the GUI
	$FolderBrowser.ShowNewFolderButton = $true

	# Open the GUI dialog and check if the user clicked 'OK'
	if ($FolderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) 
    {
       # Store the selected folder path in a variable
 	    $destination = $FolderBrowser.SelectedPath+"\mod.io\"
    }
    else
    {
        $destination=$destination_Store
    }

    # Cleanup
    $parentForm.Dispose()
    $FolderBrowser.Dispose()
    return $destination
}

if (-not(Test-Path ModList.json))
{
    echo "As this is your first time running this script all of your subscribed mods"
    echo "will be re-downloaded and updated to make sure they are all up to date."
    echo "After this process only newly updated or subscribed mods will be downloaded"
    echo "and updated. Do not Abort this process once started."
    echo ""

    if((User-Confirm "Would you like to read the Sandstorm_Mod_Manager_Guide.pdf now?") -eq $true)
    {
        Start-Process "Sandstorm_Mod_Manager_Guide.pdf"
        pause
    }

	$ModListData=@{}
    # Write initial ModList.json file
    # (so that the user doesn't have to go trough the setup again if the script doesn't run completely)
    $ModListData | ConvertTo-Json | Set-Content ModList.json
}

function Process-Subscriptions
{
    echo ""
    echo "=============================================="
    echo "       Downloading your Subscriptions         "
    echo "=============================================="
    echo ""

    if (Test-Path ModList.json)
    {
	    echo "Reading settings from ModList.json."
        echo ""
	    $ModListData=Get-Content ModList.json | ConvertFrom-Json
    }

    if(-not(Test-Path "$destination"))
    {
       $null=mkdir "$destination" -ErrorAction SilentlyContinue
    }

    $destinationMods="$destination"+"254\mods\"

    $error_success_msg=@()
    $error_warning_msg=@()
    $error_fatal_msg=@()
    $error_success = 0
    $error_warning = 0
    $error_fatal = 0

    $totalMBdownloaded = 0
    $totalMBdiskStorage = 0
    $totalTimeDownloading = 0

    $dataOffset=0
    $dataLimit=100
    $workingHash = @{}
    $workingHash.WorkArray = @()
    $workingHashCounter=0

    Do {
        $queryParams = @{
            "_limit" = $dataLimit
            "_offset" = $dataOffset
        }

        $sublist_json=Invoke-WebRequest -UseBasicParsing -URI https://api.mod.io/v1/me/subscribed?game_id=254 -Body $queryParams -Method GET -Headers @{"Authorization"="Bearer ${token}";"Accept"="application/json"}
        $sublist=ConvertFrom-Json $sublist_json.Content

        $dataOffset   = $sublist.result_offset + $sublist.result_count
        $totalResults = $sublist.result_total
        $workingHash.WorkArray += $null
        $workingHash.WorkArray[$workingHashCounter] = $sublist.psobject.Copy()
        $workingHashCounter = $workingHashCounter + 1

        Start-Sleep -Milliseconds 250

    } Until (($dataOffset) -ge $totalResults)

    # Initial state.json array for Sandstorm

    $jsonObject = [PSCustomObject]@{
        "Mods" = @(
        )
        "version" = 1
    }

    $result_total = $workingHash.WorkArray[0].result_total

    for ($i = 1; $i -le $result_total; $i++) {
        $newMod = [ordered]@{
            Profile = [ordered]@{
                # Add specific key-value pairs here if needed
            }
        }
    
        # Append the object to the mods array
        $jsonobject.mods += $newMod
    }

    $dataOffset=0
    $dataLimit=25
    $count_of_files = 0
    $ModListData_delete_comparison=@{}

    # Get how many pages of mods found
    $PageCount=$workingHash.WorkArray.length
    if ($PageCount -ne 1)
    {
        $plural="s"
    }
    else
    {
        $plural=""
    }
    [string]$Page_Count=$PageCount
    echo "Found $Page_Count Subscription Page$plural."
    echo ""

    [string]$resulttotal=$result_total
    if ($result_total -ne 1)
    {
        $plural="s"
    }
    else
    {
        $plural=""
    }
    echo "Found $resulttotal Subscription$plural."
    echo ""

    for ($p = 0; $p -lt $PageCount; $p++)
    {

        # Get current hashtable element count
        $len=$workingHash.WorkArray[$p].result_count

        for ($i = 0; $i -lt $len; $i++)
        {
            echo "=============================================="
	        $sub=$workingHash.WorkArray[$p].data[$i]
	        $subname=$sub.name

            # Variables and Data to be transfered from mod.io state.json to Sandstorm state.json

            $jsonObject.Mods[$count_of_files]["ID"]=$sub.id
            $jsonObject.Mods[$count_of_files]["NeverRetryCategory"]=0
            $jsonObject.Mods[$count_of_files]["NeverRetryCode"]=0
            $jsonObject.Mods[$count_of_files]["PathOnDisk"]=$destinationMods+$sub.id
            $jsonObject.Mods[$count_of_files]["Profile"]["date_added"]=$sub.date_added
            $jsonObject.Mods[$count_of_files]["Profile"]["date_live"]=$sub.date_live
            $jsonObject.Mods[$count_of_files]["Profile"]["date_updated"]=$sub.date_updated
            $jsonObject.Mods[$count_of_files]["Profile"]["description"]=$sub.description
            $jsonObject.Mods[$count_of_files]["Profile"]["description_plaintext"]=$sub.description_plaintext
            $jsonObject.Mods[$count_of_files]["Profile"]["id"]=$sub.id
            $jsonObject.Mods[$count_of_files]["Profile"]["logo"]=$sub.logo
            $jsonObject.Mods[$count_of_files]["Profile"]["maturity_option"]=0
            $jsonObject.Mods[$count_of_files]["Profile"]["media"]=$sub.media
            $jsonObject.Mods[$count_of_files]["Profile"]["metadata_blob"]=""
            $jsonObject.Mods[$count_of_files]["Profile"]["metadata_kvp"]=$sub.metadata_kvp

            $jsonObject.Mods[$count_of_files]["Profile"]["modfile"]=$sub.modfile
            $jsonObject.Mods[$count_of_files]["Profile"]["modfile"].PSObject.Properties.Remove("date_updated")
            $jsonObject.Mods[$count_of_files]["Profile"]["modfile"].PSObject.Properties.Remove("date_scanned")
            $jsonObject.Mods[$count_of_files]["Profile"]["modfile"].PSObject.Properties.Remove("virustotal_hash")
            $jsonObject.Mods[$count_of_files]["Profile"]["modfile"].PSObject.Properties.Remove("filehash")
            $jsonObject.Mods[$count_of_files]["Profile"]["modfile"]["md5"].PSObject.Properties.Remove("md5")
            $jsonObject.Mods[$count_of_files]["Profile"]["modfile"].PSObject.Properties.Remove("platforms")

            $jsonObject.Mods[$count_of_files]["Profile"]["name"]=$sub.name

            $jsonObject.Mods[$count_of_files]["Profile"]["stats"]=$sub.stats
            $jsonObject.Mods[$count_of_files]["Profile"]["stats"].PSObject.Properties.Remove("mod_id")
            $jsonObject.Mods[$count_of_files]["Profile"]["stats"].PSObject.Properties.Remove("downloads_today")
            $jsonObject.Mods[$count_of_files]["Profile"]["stats"].PSObject.Properties.Remove("downloads_unique")
            $jsonObject.Mods[$count_of_files]["Profile"]["stats"].PSObject.Properties.Remove("date_expires")

            $jsonObject.Mods[$count_of_files]["Profile"]["submitted_by"]=$sub.submitted_by
            $jsonObject.Mods[$count_of_files]["Profile"]["submitted_by"].PSObject.Properties.Remove("name_id")
            $jsonObject.Mods[$count_of_files]["Profile"]["submitted_by"].PSObject.Properties.Remove("date_joined")
            $jsonObject.Mods[$count_of_files]["Profile"]["submitted_by"].PSObject.Properties.Remove("timezone")
            $jsonObject.Mods[$count_of_files]["Profile"]["submitted_by"].PSObject.Properties.Remove("language")

            $jsonObject.Mods[$count_of_files]["Profile"]["summary"]=$sub.summary

            $jsonObject.Mods[$count_of_files]["Profile"]["tags"]=$sub.tags
            $tlen=$sub.tags.count
            for ($t = 0; $t -lt $tlen; $t++) {
                $jsonObject.Mods[$count_of_files]["Profile"]["tags"][$t].PSObject.Properties.Remove("name_localized")
                $jsonObject.Mods[$count_of_files]["Profile"]["tags"][$t].PSObject.Properties.Remove("date_added")
            }

            $jsonObject.Mods[$count_of_files]["Profile"]["profile_url"]=$sub.profile_url
            $jsonObject.Mods[$count_of_files]["Profile"]["visible"]=$sub.visible
            $jsonObject.Mods[$count_of_files]["SizeOnDisk"]=$sub.modfile.filesize_uncompressed
            $jsonObject.Mods[$count_of_files]["State"]=1
            $jsonObject.Mods[$count_of_files].SubscriptionCount = @(55681422)

            if($verbose -eq 1)
            {
                echo ""
            }
            $count_of_files++
            echo "Processing $count_of_files of $result_total Subscriptions : $subname"

        	[string]$modid=$sub.id
	        [string]$modFilename=$sub.modfile.filename
	        [string]$moddate_added_display=[DateTimeOffset]::FromUnixTimeSeconds($sub.modfile.date_added).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
	        [string]$moddate_added=$sub.modfile.date_added
	        [string]$modVersion=$sub.modfile.version
	        [string]$modURL=$sub.modfile.download.binary_url
	        [string]$modFilesize="{0:N2}" -f ($sub.modfile.filesize / 1MB)

            if($verbose -eq 1)
            {
                echo ""
                echo "modid: $modid"
                echo "modFilename: $modFilename"
                echo "filesize: $modFilesize MB"
                echo "moddate_added: $moddate_added_display"
                echo "modVersion: $modVersion"
                echo "modURL: $modURL"
            }

        	# Write data about this sub to ModListData

        	$update=$true
	        if ($ModListData.${modid} -eq $null)
	        {
		        $ModListData | Add-Member -Name $modid -Value @{} -MemberType NoteProperty
    		    $ModListData.${modid}.date_added=$moddate_added
                $ModListData.${modid}.name = $sub.name
	        }
	        elseif ($moddate_added -le $ModListData.${modid}.date_added){
		        $update=$false #already up to date
 	        }
            else
            {
		        $ModListData.${modid}.date_added=$moddate_added
            }

            if($verbose -eq 1)
            {
                echo ""
            }

        	$file=$modFilename
            $directory_ID=$modid
            $ModListData_delete_comparison | Add-Member -Name $modid -Value @{} -MemberType NoteProperty

        	if(-not(Test-Path "$destinationMods$directory_ID"))
	        {
            	$null=mkdir "$destinationMods$directory_ID" -ErrorAction SilentlyContinue
                $update=$true
            }

           	if ($update)
   	        {
       	        Write-Host "  Downloading $subname - $directory_ID - $modFilename - $modFilesize MB" -ForegroundColor Yellow
   		        echo ""

                # Track the precise download duration 
                $elapsedTime = Measure-Command {
                    $webClient = New-Object System.Net.WebClient
                    $webClient.DownloadFile($modURL, "zip\$modFilename")
                }

                # Calculate file size and download metrics
                $fileSizeInBytes = (Get-Item "zip\$modFilename").Length
                $totalSeconds = $elapsedTime.TotalSeconds
                $totalMBdownloaded += $fileSizeInBytes
                $totalTimeDownloading += $totalSeconds
            
                # Convert bytes to Megabits (Mb) for industry standard network speed (Mbps)
                $fileSizeInBits = $fileSizeInBytes * 8
                $megabits = $fileSizeInBits / 1MB
                $speedMbps = [Math]::Round(($megabits / $totalSeconds), 2)

                # Display the results and clean up the test file
                Write-Host "  Download complete!" -ForegroundColor Green
                Write-Host "  Time Elapsed  : $([Math]::Round($totalSeconds, 2)) seconds" -ForegroundColor White
                Write-Host "  Download Speed: $speedMbps Mbps" -ForegroundColor White
   		        echo ""

               	Write-Host "  Unpacking $subname - $directory_ID - $modFilename" -ForegroundColor Cyan

                .\bin\7za.exe x "zip\$modFilename" -o"$destinationMods$directory_ID" -aoa -y
#               tar -xvf "zip\$modFilename" -C "$destinationMods$directory_ID"
#               
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Success: Archive extracted with no errors." -ForegroundColor Green
                    $error_success_msg += "Success: $subname - $directory_ID - $modFilename no errors."
                    $error_success++
                } elseif ($LASTEXITCODE -eq 1) {
                    $error_warning_msg += "Warning: Non-fatal error $subname - $directory_ID - $modFilename"
                    $error_warning++
                } else {
                    $error_fatal_msg += "Failure: $subname - $directory_ID - $modFilename code $LASTEXITCODE."
                    $error_fatal++
                }

                $dirSize = (Get-ChildItem "$destinationMods$directory_ID" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $totalMBdiskStorage += $dirSize

                Remove-Item -Path "zip\$modFilename"
        	    }
   	        else
   	        {
       	        Write-Host "Skipped $subname up to date" -ForegroundColor Green
            }
        }
        $dataOffset+=$dataLimit
    }

    # Export new state.json file for Sandstorm

    if($enable_testing -eq 1)
    {
        # 1. Convert your object to JSON
        $jsonU = $jsonObject | ConvertTo-Json -Depth 100

        # 2. Fix ONLY Unicode characters (e.g., \u0027) while keeping literal \n untouched
        $cleanJson = [regex]::Replace($jsonU, '\\u([0-9a-fA-F]{4})', { 
            param($match) [char][int]"0x$($match.Groups[1].Value)" 
        })

        # 3. Export to a valid UTF-8 file
        $cleanJson | Out-File "state_uncompressed.json" -Encoding utf8
    }

    # 1. Convert your object to JSON
    $jsonc = $jsonObject | ConvertTo-Json -Compress -Depth 100

    # 2. Fix ONLY Unicode characters (e.g., \u0027) while keeping literal \n untouched
    $cleanJson = [regex]::Replace($jsonc, '\\u([0-9a-fA-F]{4})', { 
        param($match) [char][int]"0x$($match.Groups[1].Value)" 
    })

    if($enable_testing -eq 1)
    {
        Rename-Item -Path "state_compressed.json" -NewName ("state_compressed_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date))

        # 3. Export to a valid UTF-8 file
        $cleanJson | Out-File "state_compressed.json" -Encoding utf8
    }

    $destinationMetadata=$destinationMods -replace '(.*)mods\\(.*)$', '${1}metadata\$2'
    $jsonfilename="state.json"

    Rename-Item -Path "$destinationMetadata$jsonfilename" -NewName ("state_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date))

    # 3. Export to a valid UTF-8 file
    $cleanJson | Out-File "$destinationMetadata$jsonfilename" -Encoding utf8

    # Display Total DL Time, Total GB downloaded, Total Disk Space Used 
    echo "=============================================="
    echo ""
    $formattedTime = (New-TimeSpan -Seconds $totalTimeDownloading).ToString("mm\:ss")
    Write-Host "Total Download Time: $formattedTime" -ForegroundColor Cyan
    $diskStorageInGB = [Math]::Round(($totalMBdownloaded / 1GB), 2)
    Write-Host "Total Download Size: $diskStorageInGB GB" -ForegroundColor Green
    $diskStorageInGB = [Math]::Round(($totalMBdiskStorage / 1GB), 2)
    Write-Host "Total Disk Storage : $diskStorageInGB GB" -ForegroundColor Yellow
    echo ""

    # Display Successful Downloaded and Installed message for each mod file
    if ($error_success -ne 0) {
        echo "=============================================="
        Write-Host "Successfully Installed: $error_success file(s)" -ForegroundColor Green
        echo ""
        $error_success_msg | ForEach-Object { "$_" }
    }

    # Display WARNING about zip file for each mod
    if ($error_warning -ne 0) {
        echo "=============================================="
        Write-Warning "Warning: $error_warning file(s)"
        echo ""
        $error_warning_msg | ForEach-Object { "$_" }
    }

    # Display mod files that had errors while unzipping
    if ($error_fatal -ne 0) {
        echo "=============================================="
        echo "Error: $error_fatal file(s)"
        echo ""
        echo "If a CRC-ERROR files may have extracted without a problem."
        echo "Scroll up to find the mod to verify."
        echo ""
        $error_fatal_msg | ForEach-Object { "$_" }
    }

    # If any mods are missing from the mod.io subscribed list
    # when compared to the stored ModList.json the missing files
    # will be removed from the ModList.json and the directories 
    # will be deleted from the computer.  Compare $ModListData with
    # $ModListData_delete_comparison and remove directories of
    # missing mods.

    echo ""
    echo "=============================================="
    echo "        Checking for Unsubscribed Mods        "
    echo "=============================================="
    echo ""

    $deletedMods=0

    foreach ($item in $ModListData) {

        # Get each dynamic top element name and value
        foreach ($property in $item.PSObject.Properties) {
            $modDeleteID = $property.Name
            $modDeleteValue = $property.Value

            # Check if the value is a nested object/custom object
            if ($modDeleteValue -is [System.Management.Automation.PSCustomObject]) {
            
                # Extract nested names and values
                foreach ($nestedProp in $modDeleteValue.PSObject.Properties) {
                    if($($nestedProp.Name) -eq "name")
                    {
                        $modDeleteName = $($nestedProp.Value)
                    }
                }
            }
 
            if ($ModListData_delete_comparison.${modDeleteID} -eq $null)
            {
            	if(-not(Test-Path "$destinationMods$modDeleteID"))
	            {
                    Write-Host "Mod: $modDeleteID - $modDeleteName not found" -ForegroundColor Yellow
                }
                else
                {
                    Write-Host "Deleting Unsubscribed Mod: $modDeleteID - $modDeleteName" -ForegroundColor Red
                    Remove-Item -Path "$destinationMods$modDeleteID" -Recurse -Force
                }
                $ModListData.PSObject.Properties.Remove($modDeleteID)
                $deletedMods+=1
 	        }
        }
    }

    if ($deletedMods -eq 0)
    {
        Write-Host "No Unsubscribed Mods found." -ForegroundColor Green
    }

    # Update ModList.json 
    $ModListData | ConvertTo-Json | Set-Content ModList.json

    echo ""
    echo "=============================================="
    echo "      Sandstorm Mod File Update Complete      "
    echo "=============================================="
    echo ""

}

function Show-Menu {
    Clear-Host

    if($verbose -eq 0)
    {
        $verboseText = "Concise"
    }
    else
    {
        $verboseText = "Verbose"
    }

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "            Sandstorm Mod Manager             " -ForegroundColor Yellow
    Write-Host "               Version: $Version                 " -ForegroundColor DarkYellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "       $valid_Personal_Token" -ForegroundColor Green
    Write-Host "       $valid_Personal_Username"
    Write-Host "       $valid_Personal_UserID"
    Write-Host ""
    Write-Host "    1. Process Mod Subscriptions"
    Write-Host ""
    Write-Host "    2. Select Mods to FORCE Download and Update"
    Write-Host ""
    Write-Host "    3. Select Mods to Unsubscribe and Delete"
    Write-Host ""
    Write-Host "    4. Install/unpack mods to different location for testing purposes"
    Write-Host "       Current mod.io path: $destination" -ForegroundColor Green
    Write-Host ""
    Write-Host "    5. Would you like to view Verbose Mod Information (not saved)"
    Write-Host "       Current Setting: $verboseText" -ForegroundColor Green
    Write-Host ""
    Write-Host "    6. Move Mod.io Mod Directory to new Location"
    Write-Host ""
    Write-Host "    7. Exit"
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
}

$url = "https://api.mod.io/v1/me/"
$headers = @{
    "Authorization" = "Bearer $token"
    "Accept"        = "application/json"
}

try {
    $response = Invoke-RestMethod -Uri https://api.mod.io/v1/me/ -Method Get -Headers $headers -ErrorAction Stop

    $valid_Personal_Token = "Success: Valid OAuth Token!"
    $valid_Personal_Username = "Authenticated as: $($response.username)"
    $valid_Personal_UserID = "User ID: $($response.id)"
}
catch [System.Net.WebException] {
    if ($_.Exception.Response.StatusCode -eq 401) {
        Write-Host "Failure: The token is invalid, expired, or has been revoked." -ForegroundColor Red
    } else {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host "Run Game or Server to create Valid Token." -ForegroundColor Red
    pause
    exit
}
catch {
    Write-Host "An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Run Game or Server to create Valid Token." -ForegroundColor Red
    pause
    exit
}

do {
    Show-Menu
    $selection = Read-Host -Prompt "Please enter your selection (1-7)"
    
    switch ($selection) {
        '1' {
            Process-Subscriptions
        }
        '2' {
            Mod-Reset

            if($global:forced_updates -eq 1)
            {
                Process-Subscriptions
            }
            $global:forced_updates=0
        }
        '3' {
            Mod-Unsub
        }
        '4' {
            $destination = Mod-Test
        }
        '5' {
            $verbose = 1 - $verbose
        }
        '6' {
            .\Insurgency-Sandstorm-mod.io-Mover\Move_Sandstorm_modio_Directory.bat
            $settingsPath = Join-Path $env:LOCALAPPDATA "mod.io\globalsettings.json"

            if (Test-Path $settingsPath) {
                $StoragePath = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
            }

            $destination=$StoragePath.RootLocalStoragePath
            $destination=$destination.Replace('/', '\')
            $destination_Store=$destination
        }
        '7' {
            Write-Host "`nExiting the script. Goodbye!" -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            Exit
        }
        default {
            Write-Host "`nInvalid choice! Please select a number from 1 to 7." -ForegroundColor Red
        }
    }
    
    if ($selection -ne '4' -and $selection -ne '5' -and $selection -ne '6' -and $selection -ne '7') {
        Write-Host "`nPress any key to return to the menu..." -ForegroundColor White
        $null = [System.Console]::ReadKey($true)
    }

} until ($selection -eq '7')