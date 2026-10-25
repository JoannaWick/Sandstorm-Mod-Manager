<#PSScriptInfo
.AUTHOR Joanna Wick
.TAGS Sandstorm, Mods
.PROJECTURI https://github.com/JoannaWick/Sandstorm-Mod-Manager
#>

param(
    [string]$batchLaunch=0
)

$Version = "2.0.1" 

<# 
    Resize and center window
#>

# Read the current OS build framework directly from memory
$buildNumber = [Environment]::OSVersion.Version.Build

if ($buildNumber -ge 22000) {

    Add-Type -AssemblyName System.Windows.Forms
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    $posX = [math]::Round(($workingArea.Width + 500) / 2)
    $posY = [math]::Round(($workingArea.Height - 740) / 2)

    # FIX: Define both MoveWindow AND GetForegroundWindow in a single C# block
$Signature = @"
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
}
"@
    Add-Type -TypeDefinition $Signature -ErrorAction SilentlyContinue

    # FIX: Snag the active UI window handle directly. 
    # This completely bypasses process name filtering and permission blocks!
    $hWnd = [Win32]::GetForegroundWindow()

    if ($hWnd -ne [IntPtr]::Zero) {
        # Move and resize the current hosting cmd window frame instantly
        [void][Win32]::MoveWindow($hWnd, $posX, $posY, 600, 740, $true)
    } else {
        # Fallback to standard Mode Con formatting if running classic Conhost
        mode con: cols=120 lines=40
    }
} else {
    # Load the required .NET assembly
    Add-Type -AssemblyName System.Windows.Forms

    # Fetch the working area of the primary display
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # Output the width and height
    $screenWidth  = ($workingArea.Width+500)/2
    $screenHeight = ($workingArea.Height-740)/2

    # Definition for User32 MoveWindow
$TypeDefinition = @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
}
"@
    Add-Type -TypeDefinition $TypeDefinition

    if ($batchLaunch -eq 0)
    {
        # Get the current Powershell process window handle
        $hWnd = (Get-Process -Id $PID).MainWindowHandle
    }
    else
    {
        # Get the current cmd.exe window handle that launched Powershell process
        $parentID = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID").ParentProcessId
        $hWnd = (Get-Process -Id $parentID).MainWindowHandle
    }
    # Move window to of screen + 2 pixels center horizontally and resize it (Width=1024, Height=max height - taskbar)
    [void][Window]::MoveWindow($hWnd, $screenWidth, $screenHeight, 600, 740, $true)
}

Set-Location -Path $PSScriptRoot

$ManagerConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ManagerConfig.json"
if (-not(Test-Path $ManagerConfigPath))
{
    $global:ManagerConfig = @'
{
    "verbose":  0
}
'@ | ConvertFrom-Json
    $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath
}

$global:ManagerConfig=Get-Content $ManagerConfigPath -Raw | ConvertFrom-Json

$settingsPath = Join-Path "$env:LOCALAPPDATA" "mod.io\globalsettings.json"

if (Test-Path $settingsPath) {
    $StoragePath = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
}
else
{
    Write-Host "$settingsPath is MISSING and cannot proceed." -ForegroundColor Red
    pause
    exit
}

$destination=$StoragePath.RootLocalStoragePath
$destination=$destination.Replace('/', '\')
$global:forced_updates = 0

# Get Sandstorm OAuth Token and UserID

$userName = ("$env:LOCALAPPDATA" -split '\\')[-3]
$userName = $userName -replace ' ', ''
$mod_io_254_user="$env:LOCALAPPDATA\mod.io\254\$userName\user.json" 
$mod_io_254_server="$env:LOCALAPPDATA\mod.io\254\ModServer\user.json" 

if (Test-Path $mod_io_254_user) {
    $getuserjson = Get-Content -Raw -Path $mod_io_254_user | ConvertFrom-Json
}
elseif (Test-Path $mod_io_254_server) {
    $getuserjson = Get-Content -Raw -Path $mod_io_254_server | ConvertFrom-Json
}
else {
    Write-Host "MISSING $mod_io_254_user" -ForegroundColor Red
    Write-Host "MISSING $mod_io_254_server" -ForegroundColor Red
    Write-Host "Cannot proceed." -ForegroundColor Red
    pause
    exit
}

[string]$token=$getuserjson.Oauth.token
$UserID=$getuserjson.Profile.id

$finalpath="254\metadata\state.json"
$modsDirectoryPath = Join-Path -Path $destination -ChildPath "254\mods"

if (Test-Path $destination$finalpath) {
    $getstatejson = Get-Content -Raw -Path $destination$finalpath | ConvertFrom-Json
}

$enable_testing=0 # 0 - Disabled, 1 - Test Json output 

if($enable_testing -eq 1)
{
    # 1. Convert your object to JSON
    $jsonSU = $getstatejson | ConvertTo-Json -Depth 100

    # 2. Fix ONLY Unicode characters (e.g., \u0027) while keeping literal \n untouched
    $cleanJson = [regex]::Replace($jsonSU, '\\u([0-9a-fA-F]{4})', { 
        param($match) [char][int]"0x$($match.Groups[1].Value)" 
    })

    # 3. Export to a valid UTF-8 file
    $cleanJson | Out-File "state_Sandstorm.json" -Encoding utf8
}

function User-Confirm
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$title,
        
        [string]$infoMessage
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $title
    $Form.Size = New-Object System.Drawing.Size(420,220)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog" 
    $Form.MaximizeBox = $false
    $Form.MinimizeBox = $false
    $Form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245) # Pure White Background

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $infoMessage
    $Label.Location = New-Object System.Drawing.Point(25, 30)
    $Label.Size = New-Object System.Drawing.Size(350, 60)
    $Label.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)
    $Label.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32) # Dark Charcoal (Easier on eyes than pure black)

    $ButtonYes = New-Object System.Windows.Forms.Button
    $ButtonYes.Text = "Yes"
    $ButtonYes.Location = New-Object System.Drawing.Point(80, 115)
    $ButtonYes.Size = New-Object System.Drawing.Size(110, 32)
    $ButtonYes.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $ButtonYes.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $ButtonYes.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
    $ButtonYes.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ButtonYes.FlatAppearance.BorderSize = 1
    $ButtonYes.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200) # Soft Gray Border
    $ButtonYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes

    $ButtonNo = New-Object System.Windows.Forms.Button
    $ButtonNo.Text = "No"
    $ButtonNo.Location = New-Object System.Drawing.Point(210, 115)
    $ButtonNo.Size = New-Object System.Drawing.Size(110, 32)
    $ButtonNo.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $ButtonNo.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $ButtonNo.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
    $ButtonNo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ButtonNo.FlatAppearance.BorderSize = 1
    $ButtonNo.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $ButtonNo.DialogResult = [System.Windows.Forms.DialogResult]::No

    $Form.Add_FormClosing({
        param($sender, $e)
    
        # Check if the close action was triggered by the user clicking the 'X' or Alt+F4
        if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $Form.DialogResult = [System.Windows.Forms.DialogResult]::No
        }
    })

    $Form.Controls.AddRange(@($Label, $ButtonYes, $ButtonNo))
    return $Form.ShowDialog()
}

<#
    Word Wrap long text lines and allow for fore and background colors
#>

function Write-WrappedHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        
        [string]$ForegroundColor = 'Gray',
        
        [string]$BackgroundColor = 'Black'
    )

    # Get the current console buffer width, subtracting 1 to avoid forcing a newline
    $width = $Host.UI.RawUI.WindowSize.Width - 1

    # Split the string by spaces to get all individual words
    $words = $Text -split ' '

    $spaceCount = $Text.Length - $Text.TrimStart().Length
    $currentLine = (" " * ($spaceCount/2))

    foreach ($word in $words) {
        # Test if adding the next word exceeds the window width
        if (($currentLine.Length + $word.Length + 1) -gt $width) {
            # Print current line, then reset
            Write-Host $currentLine -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
            $currentLine = $word
        } else {
            # Otherwise, append the word with a space
            if ($currentLine) { $currentLine += " " }
            $currentLine += $word
        }
    }
    # Output the remaining text
    if ($currentLine) {
        Write-Host $currentLine -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    }
}

Function mod_GUI_selector
{
    param (
        [string[]]$ModList,
        [string]$GUItitle
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    $screenWidth  = ($workingArea.Width-1500)/2
    $screenHeight = ($workingArea.Height-740)/2

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $GUItitle
    $Form.Size = New-Object System.Drawing.Size(500, 740)
    $Form.StartPosition = "Manual"
    $Form.Location = New-Object System.Drawing.Point($screenWidth, $screenHeight)

    $DataGridView = New-Object System.Windows.Forms.DataGridView
    $DataGridView.Dock = [System.Windows.Forms.DockStyle]::Fill
    $DataGridView.ReadOnly = $true
    $DataGridView.AllowUserToAddRows = $false
    $DataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill

    $DataGridView.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $DataGridView.MultiSelect = $true  # Allows Ctrl+Click and Shift+Click selections

    $Column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $Column.HeaderText = "Mod Name"
    $Column.Name = "ModName"
    [void]$DataGridView.Columns.Add($Column)

    foreach ($Mod in $ModList) {
        [void]$DataGridView.Rows.Add($Mod)
    }

    $ButtonPanel = New-Object System.Windows.Forms.Panel
    $ButtonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $ButtonPanel.Height = 50

    $ClearButton = New-Object System.Windows.Forms.Button
    $ClearButton.Text = "Clear All"
    $ClearButton.Location = New-Object System.Drawing.Point(35, 10)
    $ClearButton.Size = New-Object System.Drawing.Size(85, 30)

    $ClearButton.Add_Click({
        $dataGridView.ClearSelection()
    })

    $SelectAllButton = New-Object System.Windows.Forms.Button
    $SelectAllButton.Text = "Select All"
    $SelectAllButton.Location = New-Object System.Drawing.Point(135, 10)
    $SelectAllButton.Size = New-Object System.Drawing.Size(85, 30)

    $SelectAllButton.Add_Click({
        $dataGridView.SelectAll()
    })

    $OKButton = New-Object System.Windows.Forms.Button
    $OKButton.Text = "OK"
    $OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $OKButton.Location = New-Object System.Drawing.Point(260, 10)
    $OKButton.Size = New-Object System.Drawing.Size(85, 30)

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = "Cancel"
    $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $CancelButton.Location = New-Object System.Drawing.Point(360, 10)
    $CancelButton.Size = New-Object System.Drawing.Size(85, 30)

    $ButtonPanel.Controls.AddRange(@($OKButton, $CancelButton, $SelectAllButton, $ClearButton))
    $Form.Controls.Add($DataGridView)  # Added first so Dock.Fill respects the panel space
    $Form.Controls.Add($ButtonPanel)
    $Form.AcceptButton = $OKButton
    $Form.CancelButton = $CancelButton

    $Form.Add_Load({
        $DataGridView.ClearSelection()
    })

    $Result = $Form.ShowDialog()

    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
        $SelectedMods = foreach ($Row in $DataGridView.SelectedRows) {
            $Row.Cells["ModName"].Value
        }
    
        if ($null -ne $SelectedMods) {
            [array]::Reverse($SelectedMods)
        }
    } else {
        $SelectedMods = $null
    }

    $Form.Dispose()

    return $SelectedMods
}


# Display GUI Selector of all subscribed mods and ask user to
# select any number of the mods to force a download and update
function Mod-Reset
{
    Clear-Host
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "   Select Mods to FORCE Download and Update   " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path $ModListJsonPath)
    {
	    Write-Host "Reading settings from ModList.json."
        Write-Host ""
	    $ModListData=Get-Content $ModListJsonPath | ConvertFrom-Json
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
            [void]$ModList.Add($modname+" | "+$topName) # [void] suppresses the default .Add() output
        }
    }

    $ModList.Sort()

    $GUItitle = "Select One or More Mods to Force Update"
    $SelectedMods = mod_GUI_selector -ModList $ModList -GUItitle $GUItitle

    if ($null -eq $SelectedMods -or $SelectedMods.Count -eq 0) {
        Write-Host "No Mods were selected" -ForegroundColor Red
        $global:forced_updates=0

        return
    }

    # Output the selected items
    Write-Host "You selected the following items:" -ForegroundColor Green
    $tlen=$SelectedMods.count
    if( $tlen -gt 1)
    {
        for ($t = 0; $t -lt $tlen; $t++) {
            Write-Host $SelectedMods[$t]
        }
    }
    else
    {
        Write-Host $SelectedMods
    }
    Write-Host ""

    $UserChoice = User-Confirm -title "Forced Mod Update" -infoMessage "Last Chance: Do you really want to force an update for these items?"

    if ($UserChoice -eq "Yes") {
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
        $ModListData | ConvertTo-Json | Set-Content $ModListJsonPath
        $global:forced_updates=1

        return
    }
    else
    {
        Write-Host ""
        Write-Host "Forced Mod Update Canceled" -ForegroundColor Yellow
    }

}

# Display GUI Selector of all subscribed mods and ask user to
# select any number of the mods to UNSUBSCRIBE and DELETE
function Mod-Unsub
{
    Clear-Host
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "    Select Mods to Unsubscribe and Delete   " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    $gameId = 254
    $apiUrl = "https://api.mod.io/v1"
    $destinationMods="$destination"+"254\mods\"

    if (Test-Path $ModListJsonPath)
    {
	    Write-Host "Reading settings from ModList.json."
        Write-Host ""
	    $ModListData=Get-Content $ModListJsonPath | ConvertFrom-Json
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
            [void]$ModList.Add($modname+" | "+$topName) # [void] suppresses the default .Add() output
        }
    }

    $ModList.Sort()

    $GUItitle = "Select One or More Mods to UNSUBSCRIBE and DELETE"
    $SelectedMods = mod_GUI_selector -ModList $ModList -GUItitle $GUItitle

    if ($null -eq $SelectedMods -or $SelectedMods.Count -eq 0) {
        Write-Host "No Mods were selected" -ForegroundColor Red

        return
    }

    # Output the selected items
    Write-Host "You selected the following items:" -ForegroundColor Green
    $tlen=$SelectedMods.count
    if( $tlen -gt 1)
    {
        for ($t = 0; $t -lt $tlen; $t++) {
            Write-Host $SelectedMods[$t]
        }
    }
    else
    {
        Write-Host $SelectedMods
    }
    Write-Host ""

    $UserChoice = User-Confirm -title "Mod Unsubscribe and Delete" -infoMessage "Last Chance: Do you really want to Unsubscribe and Delete these items?"

    if ($UserChoice -eq "No") {
        Write-Host "Mod Unsubscribe and Delete Canceled" -ForegroundColor Yellow
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
        $ModListData | ConvertTo-Json | Set-Content $ModListJsonPath

        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host " Selected Mods have been Unsubscribed/Deleted    " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan

        return
    }
}

function Modio_mod_directory {
    param(
        [string]$Filter = "" # Example: "*.pak", "*.zip", or leave empty/blank for folders only
    )

    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")

    # --- WIN32 API DECLARATIONS FOR NATIVE ICON EXTRACTION ---
    $IconApiDefinition = @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32Icon {
        [DllImport("shell32.dll", EntryPoint = "ExtractIconExW", CharSet = CharSet.Unicode)]
        public static extern int ExtractIconEx(string lpszFile, int nIconIndex, out IntPtr phiconLarge, out IntPtr phiconSmall, int nIcons);
        
        [DllImport("user32.dll", EntryPoint = "DestroyIcon", SetLastError = true)]
        public static extern bool DestroyIcon(IntPtr hIcon);
    }
"@
    if (-not ([System.Management.Automation.PSTypeName]'Win32Icon').Type) {
        Add-Type -TypeDefinition $IconApiDefinition
    }

    # Helper function to pull system icons natively
    Function Get-SystemIcon {
        Param([string]$SourceFile, [int]$Index)
        $phiconLarge = [IntPtr]::Zero
        $phiconSmall = [IntPtr]::Zero
        [void][Win32Icon]::ExtractIconEx($SourceFile, $Index, [ref]$phiconLarge, [ref]$phiconSmall, 1)
        if ($phiconSmall -ne [IntPtr]::Zero) {
            $Icon = [System.Drawing.Icon]::FromHandle($phiconSmall).Clone()
            [void][Win32Icon]::DestroyIcon($phiconSmall)
            if ($phiconLarge -ne [IntPtr]::Zero) { [void][Win32Icon]::DestroyIcon($phiconLarge) }
            return $Icon
        }
        return $null
    }

    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $formWidth   = 500
    $formHeight  = 740
    $screenWidth  = [int](($workingArea.Width - ($formWidth + 1000)) / 2)
    $screenHeight = [int](($workingArea.Height - $formHeight) / 2)

    # Main Window Canvas (Light Theme UI)
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = if ([string]::IsNullOrEmpty($Filter)) { "Select Folder to Move Mod Directory" } else { "Select $Filter" }
    $Form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
    $Form.BackColor = [System.Drawing.Color]::White
    $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $Form.Location = New-Object System.Drawing.Point($screenWidth, $screenHeight)

    # Path Display Banner (Top Area)
    $PathLabel = New-Object System.Windows.Forms.Label
    $PathLabel.Text = "Current Folder: This PC"
    $PathLabel.Location = New-Object System.Drawing.Point(15, 15)
    $PathLabel.Size = New-Object System.Drawing.Size(450, 25)
    $PathLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $PathLabel.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    [void]$Form.Controls.Add($PathLabel)

    # --- SYSTEM ICON IMAGELIST SETUP ---
    $ImageList = New-Object System.Windows.Forms.ImageList
    $ImageList.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
    $ImageList.ImageSize = New-Object System.Drawing.Size(16, 16)

    # Map Windows resource indices into our library array
    $SysDir = [System.Environment]::SystemDirectory
    [void]$ImageList.Images.Add("Drive", (Get-SystemIcon "$SysDir\shell32.dll" 8))
    [void]$ImageList.Images.Add("Folder", (Get-SystemIcon "$SysDir\shell32.dll" 3))
    [void]$ImageList.Images.Add("HiddenFolder", (Get-SystemIcon "$SysDir\imageres.dll" 53)) 
    [void]$ImageList.Images.Add("Up", (Get-SystemIcon "$SysDir\shell32.dll" 45))
    [void]$ImageList.Images.Add("File", (Get-SystemIcon "$SysDir\shell32.dll" 0))

    # Main Folder Display Grid (List View)
    $ListView = New-Object System.Windows.Forms.ListView
    $ListView.Location = New-Object System.Drawing.Point(15, 50)
    $ListView.Size = New-Object System.Drawing.Size(450, 570)
    $ListView.View = [System.Windows.Forms.View]::Details
    $ListView.FullRowSelect = $true
    $ListView.GridLines = $false
    $ListView.SmallImageList = $ImageList 
    $ListView.BackColor = [System.Drawing.Color]::FromArgb(252, 252, 252) 
    $ListView.ForeColor = [System.Drawing.Color]::Black
    $ListView.Font = New-Object System.Drawing.Font("Segoe UI", 14)

    # Single column since we only focus on folder hierarchy
    $titleName = if ([string]::IsNullOrEmpty($Filter)) { "Select Folder to Move Mod Directory" } else { "Select $Filter" }
    [void]$ListView.Columns.Add($titleName, 430)
    [void]$Form.Controls.Add($ListView)

    # Action Buttons (Bottom Area)
    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = "Cancel"
    $CancelButton.Location = New-Object System.Drawing.Point(15, 640) 
    $CancelButton.Size = New-Object System.Drawing.Size(100, 35)
    $CancelButton.BackColor = [System.Drawing.Color]::FromArgb(250, 230, 230) 
    $CancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $CancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    [void]$Form.Controls.Add($CancelButton)

    $SelectButton = New-Object System.Windows.Forms.Button
    $SelectButton.Text = if ([string]::IsNullOrEmpty($Filter)) { "Select Folder" } else { "Select File" }
    $SelectButton.Location = New-Object System.Drawing.Point(290, 640) 
    $SelectButton.Size = New-Object System.Drawing.Size(175, 35)
    $SelectButton.BackColor = [System.Drawing.Color]::FromArgb(230, 242, 255) 
    $SelectButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $SelectButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    [void]$Form.Controls.Add($SelectButton)

    # Global tracking variables
    $script:CurrentPath = "THIS_PC"
    $script:FinalSelection = $false

    # Function to safely pull directories, drives, or files
    Function Update-FolderBrowser {
        Param([string]$TargetDirectory)
        
        [void]$ListView.Items.Clear()
        $script:CurrentPath = $TargetDirectory

        # Default action button configuration based on active filters
        if (-not [string]::IsNullOrEmpty($Filter)) {
            $SelectButton.Enabled = $false # Lock down button globally until a matching file is highlighted
        } else {
            $SelectButton.Enabled = ($TargetDirectory -ne "THIS_PC") # Standard folder validation rules
        }

        # Scenario A: We are at the "This PC" root view
        if ($TargetDirectory -eq "THIS_PC") {
            $PathLabel.Text = "Current Folder: This PC"
            
            $Drives = [System.IO.DriveInfo]::GetDrives()
            ForEach ($Drive in $Drives) {
                $Label = if ($Drive.IsReady) { "$($Drive.Name) ($($Drive.VolumeLabel))" } else { "$($Drive.Name) (Drive not ready)" }
                $Item = New-Object System.Windows.Forms.ListViewItem($Label)
                $Item.Tag = @{ Path = $Drive.Name; IsDirectory = $true }
                $Item.ImageKey = "Drive" 
                [void]$ListView.Items.Add($Item)
            }
        } 
        # Scenario B: We are inside a standard folder path
        else {
            $PathLabel.Text = "Current Folder: $TargetDirectory"
            
            # Add up-navigation link
            $UpItem = New-Object System.Windows.Forms.ListViewItem(".. [Go Up to Parent Directory]")
            $UpItem.Tag = @{ Action = if ($TargetDirectory.Length -le 3) { "GO_TO_THIS_PC" } else { "UP_DIR" } }
            $UpItem.ImageKey = "Up"
            $UpItem.ForeColor = [System.Drawing.Color]::Gray
            [void]$ListView.Items.Add($UpItem)

            Try {
                # 1. Fetch Folders
                $Dirs = Get-ChildItem -LiteralPath $TargetDirectory -Directory -Force -ErrorAction SilentlyContinue
                ForEach ($Dir in $Dirs) {
                    $IsHidden = $Dir.Attributes.HasFlag([System.IO.FileAttributes]::Hidden)
                    $Item = New-Object System.Windows.Forms.ListViewItem($Dir.Name)
                    $Item.Tag = @{ Path = $Dir.FullName; IsDirectory = $true }
                    
                    if ($IsHidden) {
                        $Item.ImageKey = "HiddenFolder" 
                        $Item.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 140)
                    } else {
                        $Item.ImageKey = "Folder" 
                        $Item.ForeColor = [System.Drawing.Color]::Black
                    }
                    [void]$ListView.Items.Add($Item)
                }

                # 2. Fetch Files if a Filter argument is supplied
                if (-not [string]::IsNullOrEmpty($Filter)) {
                    $Files = Get-ChildItem -LiteralPath $TargetDirectory -File -Filter $Filter -Force -ErrorAction SilentlyContinue
                    ForEach ($File in $Files) {
                        $Item = New-Object System.Windows.Forms.ListViewItem($File.Name)
                        $Item.Tag = @{ Path = $File.FullName; IsDirectory = $false }
                        $Item.ImageKey = "File"
                        $Item.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
                        [void]$ListView.Items.Add($Item)
                    }
                }
            } Catch {
                [void][System.Windows.Forms.MessageBox]::Show("Access Denied or Directory Unreadable.", "Permission Error")
            }
        }
    }

    # --- DYNAMIC SELECTION VALIDATION LATCH ---
    # Monitors item clicks to lock or unlock the Select button instantly
    $ListView.Add_SelectedIndexChanged({
        if ($ListView.SelectedItems.Count -eq 1) {
            $Target = $ListView.SelectedItems[0].Tag
            
            if (-not [string]::IsNullOrEmpty($Filter)) {
                # If a filter is set, button ONLY unlocks when a non-directory file is highlighted
                $SelectButton.Enabled = ($null -ne $Target -and $Target.IsDirectory -eq $false -and $null -ne $Target.Path)
            } else {
                # Standard folder rule: Can select anything except root structural system commands
                $SelectButton.Enabled = ($null -ne $Target -and $null -ne $Target.Path)
            }
        } else {
            # No item selected
            if (-not [string]::IsNullOrEmpty($Filter)) {
                $SelectButton.Enabled = $false
            } else {
                $SelectButton.Enabled = ($script:CurrentPath -ne "THIS_PC")
            }
        }
    })

    # Interactive Navigation Logic (Triggered on Double-Click)
    $ListView.Add_DoubleClick({
        if ($ListView.SelectedItems.Count -eq 1) {
            $Target = $ListView.SelectedItems[0].Tag
            if ($Target.Action -eq "GO_TO_THIS_PC") {
                Update-FolderBrowser -TargetDirectory "THIS_PC"
            }
            elseif ($Target.Action -eq "UP_DIR") {
                $ParentDir = Split-Path $script:CurrentPath -Parent
                Update-FolderBrowser -TargetDirectory $ParentDir
            }
            elseif ($Target.IsDirectory) {
                Update-FolderBrowser -TargetDirectory $Target.Path
            }
            else {
                # If filter is passed, double-clicking a validated file exits and returns it
                if (-not [string]::IsNullOrEmpty($Filter)) {
                    $script:FinalSelection = $Target.Path
                    $Form.Close()
                }
            }
        }
    })

    # Button Commits
    $SelectButton.Add_Click({
        if ($ListView.SelectedItems.Count -eq 1) 
        {
            $Target = $ListView.SelectedItems[0].Tag
            if ($Target.Path) 
            {
                # Strict verification guard check
                if (-not [string]::IsNullOrEmpty($Filter) -and $Target.IsDirectory) { return }
                $script:FinalSelection = $Target.Path
                $Form.Close()
            }
        } else {
            # Fall back to folder logic if no explicit item highlighted and no filter exists
            if ([string]::IsNullOrEmpty($Filter) -and $script:CurrentPath -ne "THIS_PC") {
                $script:FinalSelection = $script:CurrentPath
                $Form.Close()
            }
        }
    })

    $CancelButton.Add_Click({
        $script:FinalSelection = $false
        $Form.Close()
    })

    # Kick off default layout population
    Update-FolderBrowser -TargetDirectory "THIS_PC"
    [void]$Form.ShowDialog()
    $Form.Dispose()
    return $script:FinalSelection
}

<#
    Repair GlobalSettings.json
#>


function repair_globalsettings
{
    Clear-Host
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "      Repair globalsettings.json Location     " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    $settingsPath = Join-Path "$env:LOCALAPPDATA" "mod.io\globalsettings.json"

    if (Test-Path $settingsPath) {
        $globalsettings_old = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
        $globalSettingSource = $globalsettings_old.RootLocalStoragePath
        $globalSettingSource = $globalSettingSource.Replace('/', '\')
    }
    else
    {
        Write-Host "$settingsPath is MISSING and cannot proceed." -ForegroundColor Red
        Write-Host ""
        return
    }
    Write-Host "Current Mod Storage: $globalSettingSource" -ForegroundColor Green
    Write-Host ""
    Write-Host "If your globalsettings.json Root Directory Path has been reset, corrupted or points to the wrong location you can change it back to where it is located."
    Write-Host ""
    Write-WrappedHost -Text "Select the directory path to where the state.json is located for the mod files you are wanting to import.  These files can be located on this server or any server accessable on your network." -ForegroundColor DarkYellow
    Write-Host ""

    Modio_mod_directory -filter "state.json"

    if ($script:FinalSelection -ne $false) {
        $SelectedFilePath = $script:FinalSelection
        $Source_mods_Path = Split-Path -Path $SelectedFilePath -Parent
        $Source_mods_Path = Split-Path -Path $Source_mods_Path -Parent
        $Source_mods_Path = Split-Path -Path $Source_mods_Path -Parent

        Write-Host "Directory path to state.json: $Source_mods_Path" -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "Repair Canceled" -ForegroundColor Yellow
        return
    }

    $UserChoice = User-Confirm -title "Pick state.json to Import" -infoMessage "Would you like to use this state.json Mod.io location?"

    if ($UserChoice -eq 'No') {
        Write-Host ""
        Write-Host "globalsetting.json Repair Canceled" -ForegroundColor Yellow
        return
    }

    $newStatejsonPath = Join-Path -Path $Source_mods_Path -ChildPath "254\metadata\state.json"
    $modsLocation = Join-Path -Path $Source_mods_Path -ChildPath "254\mods"
          
    # Load and convert JSON to a PowerShell object
    $state = Get-Content -Path $newStatejsonPath -Raw | ConvertFrom-Json

    # Loop through the Mods array and change the path
    $state.Mods | ForEach-Object {
        # Replace the path with the C: drive (adjust folder structure as needed)
        $_.PSObject.Properties['PathOnDisk'].Value = -join ("$modsLocation", "\") + ($_.PSObject.Properties['PathOnDisk'].Value | Split-Path -Leaf)
    }

    # Convert your object to JSON
    $jsonc = $state | ConvertTo-Json -Compress -Depth 100
                          
    # Fix ONLY Unicode characters (e.g., \u0027) while keeping literal \n untouched
    $cleanJson = [regex]::Replace($jsonc, '\\u([0-9a-fA-F]{4})', { 
        param($match) [char][int]"0x$($match.Groups[1].Value)" 
    })

    # Export to a valid UTF-8 file
    $cleanJson | Out-File "$newStatejsonPath" -Encoding utf8

    & $UpdateUIData
    Write-Host ""
    Write-Host "State.json Repaired at location $script:FinalSelection" -ForegroundColor Green
}

function move_Sandstorm_mods
{
    Clear-Host
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "             Move Sandstorm Mods              " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    $settingsPath = Join-Path "$env:LOCALAPPDATA" "mod.io\globalsettings.json"

    if (Test-Path $settingsPath) {
        $globalsettings_old = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
        $globalSettingSource = $globalsettings_old.RootLocalStoragePath
        $globalSettingSource = $globalSettingSource.Replace('/', '\')
    }
    else
    {
        Write-Host "$settingsPath is MISSING and cannot proceed." -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host "Current Mod Storage: $globalSettingSource" -ForegroundColor Green
    Write-Host ""
    Write-WrappedHost -Text "Select the directory path to store Mod.io mod downloads. If no directory path selected move is aborted." -ForegroundColor DarkYellow
    Write-Host ""

    Modio_mod_directory

    if(-not $script:FinalSelection)
    {
        Write-Host ""
        Write-Host "Mod Move Aborted" -ForegroundColor Yellow
        return
    }

    $destination = $script:FinalSelection

    $UserChoice = User-Confirm -title "Select Directory/Folder you would like to move Mods" -infoMessage "Do you really want to move Mods to [$destination]?"

    if ($UserChoice -eq 'No')
    {
        Write-Host ""
        Write-Host "Mod Move Aborted" -ForegroundColor Yellow
        return
    }
    else
    {
        $destination254 = "$destination\mod.io\254"
        $destination = "$destination\mod.io\"

        $rootdestination=$destination.Replace('\', '/')
                    
        $globalsettings=@{
            RootLocalStoragePath = "$rootdestination"
        }

        $globalsettings | ConvertTo-Json | Set-Content "$settingsPath"
        Write-Host ""
        Write-Host "Saved $settingsPath RootLocalStoragePath = $rootdestination"
        Write-Host ""
        Write-Host "Source Directory path: $globalSettingSource" -ForegroundColor Yellow
        Write-Host "Destination Directory path: $rootdestination" -ForegroundColor Yellow

        $safeSource = $globalSettingSource.TrimEnd('\')
        $safeDest   = $rootdestination.TrimEnd('\')
        #copy cache, metadata and mods directory    
#        robocopy "$safeSource" "$safeDest" /MOVE /E | Out-Host
        Start-Process -FilePath "robocopy.exe" -ArgumentList "`"$safeSource`"", "`"$safeDest`"", "/MOVE", "/E" -NoNewWindow -Wait
                
        $newStatejsonPath = "$destination254\metadata\state.json"
        $newModsPath = "$destination254\mods"
                     
        # Load and convert JSON to a PowerShell object
        $state = Get-Content -Path $newStatejsonPath -Raw | ConvertFrom-Json

        # Loop through the Mods array and change the path
        $state.Mods | ForEach-Object {
            # Replace the path with the C: drive (adjust folder structure as needed)
            $_.PSObject.Properties['PathOnDisk'].Value = -join ("$newModsPath", "\") + ($_.PSObject.Properties['PathOnDisk'].Value | Split-Path -Leaf)
        }

        # 1. Convert your object to JSON
        $jsonc = $state | ConvertTo-Json -Compress -Depth 100
                            
        # 2. Fix ONLY Unicode characters (e.g., \u0027) while keeping literal \n untouched
        $cleanJson = [regex]::Replace($jsonc, '\\u([0-9a-fA-F]{4})', { 
            param($match) [char][int]"0x$($match.Groups[1].Value)" 
        })

        # 3. Export to a valid UTF-8 file
        $cleanJson | Out-File "$newStatejsonPath" -Encoding utf8

        $cleanupPath = "$destination254\metadata"
        Get-ChildItem -Path "$cleanupPath" -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 12 | Remove-Item -Force

        & $UpdateUIData
        Write-Host ""
        Write-Host "Mods copied to location $script:FinalSelection" -ForegroundColor Green
    }
}

function Process-Subscriptions
{
    Clear-Host
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "       Downloading your Subscriptions         " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    $isNetworkMonitor = $false

    if (Test-Path $ModListJsonPath)
    {
	    Write-Host "Reading settings from ModList.json."
        Write-Host ""
	    $ModListData=Get-Content $ModListJsonPath | ConvertFrom-Json
    }

    $settingsPath = Join-Path "$env:LOCALAPPDATA" "mod.io\globalsettings.json"

    if (Test-Path $settingsPath) {
        $StoragePath = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
    }
    else
    {
        Write-Host "$settingsPath is MISSING and cannot proceed." -ForegroundColor Red
        exit
    }

    $destination=$StoragePath.RootLocalStoragePath
    $destination=$destination.Replace('/', '\')

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
    Write-Host "Found $Page_Count Subscription Page$plural."
    Write-Host ""

    [string]$resulttotal=$result_total
    if ($result_total -ne 1)
    {
        $plural="s"
    }
    else
    {
        $plural=""
    }
    Write-Host "Found $resulttotal Subscription$plural."
    Write-Host ""

    for ($p = 0; $p -lt $PageCount; $p++)
    {

        # Get current hashtable element count
        $len=$workingHash.WorkArray[$p].result_count

        for ($i = 0; $i -lt $len; $i++)
        {
            Write-Host "==============================================" -ForegroundColor Cyan
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

            if($global:ManagerConfig.verbose -eq 1)
            {
                Write-Host ""
            }
            $count_of_files++
            Write-Host "Processing $count_of_files of $result_total Subscriptions : $subname"

        	[string]$modid=$sub.id
	        [string]$modFilename=$sub.modfile.filename
	        [string]$moddate_added_display=[DateTimeOffset]::FromUnixTimeSeconds($sub.modfile.date_added).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
	        [string]$moddate_added=$sub.modfile.date_added
	        [string]$modVersion=$sub.modfile.version
	        [string]$modURL=$sub.modfile.download.binary_url
	        [string]$modFilesize="{0:N2}" -f ($sub.modfile.filesize / 1MB)

            if($global:ManagerConfig.verbose -eq 1)
            {
                Write-Host ""
                Write-Host "modid: $modid"
                Write-Host "modFilename: $modFilename"
                Write-Host "filesize: $modFilesize MB"
                Write-Host "moddate_added: $moddate_added_display"
                Write-Host "modVersion: $modVersion"
                Write-Host "modURL: $modURL"
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

            if($global:ManagerConfig.verbose -eq 1)
            {
                Write-Host ""
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
   		        Write-Host ""

            # Track the precise download duration 
<#            $elapsedTime = Measure-Command {
#                $webClient = New-Object System.Net.WebClient
#                $webClient.DownloadFile($modURL, "zip\$modFilename")

                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $modURL -OutFile "zip\$modFilename" -TimeoutSec 30 -UseBasicParsing
                $ProgressPreference = 'Continue'
            }
#>

# Explicitly load the missing HTTP assembly into the current session
Add-Type -AssemblyName System.Net.Http

$elapsedTime = Measure-Command {
    # Initialize the modern web client handler using the type accelerator
    $httpClient = [System.Net.Http.HttpClient]::new()
    
    try {
        # Send request and pull the raw web data stream
        $responseTask = ($httpClient.GetAsync($modURL, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead))
        $response = $responseTask.GetAwaiter().GetResult()
        
        # Get true file size from headers (fallback to 0 if hidden)
        $totalBytes = if ($response.Content.Headers.ContentLength) {$response.Content.Headers.ContentLength } else { 0 }
        $totalMb = $totalBytes / 1MB

        $responseStreamTask = $response.Content.ReadAsStreamAsync()
        $responseStream = $responseStreamTask.GetAwaiter().GetResult()

        # Ensure \$modFilename isn't empty to prevent null file crashes
        if ([string]::IsNullOrWhiteSpace($modFilename)) {
            throw "The variable `$modFilename is empty. Cannot create a file with no name."
        }

        # Use an ABSOLUTE path for .NET compatibility
        $targetFolder = Join-Path $PSScriptRoot "zip" 
        if (-not (Test-Path $targetFolder)) { New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null }
        $absoluteFilePath = Join-Path $targetFolder $modFilename

        # Create local zip destination file payload layout securely
        $fileStream = [System.IO.File]::Create($absoluteFilePath)

        # Set a 64KB transit memory buffer block size
        $buffer = New-Object Byte[] 65536
        $bytesReceived = 0

        # Start a high-precision stopwatch to track live speed and ETA
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Actively copy chunks to disk and calculate numbers raw
        while (($bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {$fileStream.Write($buffer, 0,$bytesRead)
            $bytesReceived += $bytesRead
            
            $mbReceived = $bytesReceived / 1MB
            $elapsedSec = $stopwatch.Elapsed.TotalSeconds

            if ($totalBytes -gt 0) {$percent = ($bytesReceived / $totalBytes) * 100
                
                # Calculate live speed and estimated time remaining
                if ($elapsedSec -gt 0.1) {$bytesPerSec = $bytesReceived / $elapsedSec
                    $bytesRemaining = $totalBytes - $bytesReceived
                    $secondsLeft = [Math]::Max(0, ($bytesRemaining / $bytesPerSec))
                    
                    # Format time cleanly as MM:SS
                    $etaTime = [TimeSpan]::FromSeconds($secondsLeft)
                    $etaString = "{0:D2}m:{1:D2}s" -f $etaTime.Minutes, $etaTime.Seconds
                } else {
                    $etaString = "--m:--s"
                }

                Write-Host ("`r  Downloaded: {0:N2} MB of {1:N2} MB ({2:N2}%) | ETA: {3}" -f $mbReceived, $totalMb, $percent, $etaString) -NoNewline
            } else {
                # Fallback layout if the web server hides the file size header
                Write-Host ("`r  Downloaded: {0:N2} MB (Total size unknown)" -f $mbReceived) -NoNewline
            }
        }
    }
    catch {
        # This catches errors that Measure-Command normally hides
        Write-Error "A terminating error occurred: \$_"
    }
    finally {
        # Clean up file handlers cleanly and reliably even if a crash happens
        if ($null -ne $stopwatch) {$stopwatch.Stop() }
        if ($null -ne $fileStream) { $fileStream.Close(); $fileStream.Dispose() }
        if ($null -ne $responseStream) { $responseStream.Close(); $responseStream.Dispose() }
        if ($null -ne $httpClient) { $httpClient.Dispose() }
        
        Write-Host "" # Break line safely on finish
        Write-Host "" # Break line safely on finish
    }
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
   		        Write-Host ""

               	Write-Host "  Unpacking $subname - $directory_ID - $modFilename" -ForegroundColor Cyan

#                .\bin\7za.exe x "zip\$modFilename" -o"$destinationMods$directory_ID" -aoa -y
                $7zArgs = @(
                    "x",
                    "zip\$modFilename",
                    "-o$destinationMods$directory_ID",
                    "-aoa",
                    "-y"
                )

                $Process = Start-Process -FilePath ".\bin\7za.exe" -ArgumentList $7zArgs -NoNewWindow -Wait -PassThru
                $ExitCode = $Process.ExitCode

                if ($ExitCode -eq 0) {
                    Write-Host "Success: Archive extracted with no errors." -ForegroundColor Green
                    $error_success_msg += "Success: $subname - $directory_ID - $modFilename no errors."
                    $error_success++
                } elseif ($ExitCode -eq 1) {
                    $error_warning_msg += "Warning: Non-fatal error $subname - $directory_ID - $modFilename"
                    $error_warning++
                } else {
                    $error_fatal_msg += "Failure: $subname - $directory_ID - $modFilename code $LASTEXITCODE."
                    $error_fatal++
                }
<#
    switch ($ExitCode) {
        0 { 
            Write-Host "Success! Extraction completed with exit code 0." -ForegroundColor Green 
        }
        1 { 
            Write-Host "Warning: Non-fatal error occurred (Exit Code 1)." -ForegroundColor Yellow 
        }
        2 { 
            Write-Host "Fatal Error: Misuse, bad arguments, or unexpected crash (Exit Code 2)." -ForegroundColor Red 
        }
        7 { 
            Write-Host "Error: Command line error / wrong syntax (Exit Code 7)." -ForegroundColor Red 
        }
        8 { 
            Write-Host "Error: Not enough memory for operation (Exit Code 8)." -ForegroundColor Red 
        }
        255 { 
            Write-Host "User Error: Process was stopped or interrupted by user (Exit Code 255)." -ForegroundColor Yellow 
        }
        Default { 
            Write-Host "Extraction failed with unknown error code: $ExitCode" -ForegroundColor Red 
        }
#>
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

    $cleanupPath = "$destination\254\metadata"
    Get-ChildItem -Path "$cleanupPath" -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip 12 | Remove-Item -Force

    # Display Total DL Time, Total GB downloaded, Total Disk Space Used 
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
    $formattedTime = (New-TimeSpan -Seconds $totalTimeDownloading).ToString("mm\:ss")
    Write-Host "Total Download Time: $formattedTime" -ForegroundColor Cyan
    $diskStorageInGB = [Math]::Round(($totalMBdownloaded / 1GB), 2)
    Write-Host "Total Download Size: $diskStorageInGB GB" -ForegroundColor Green
    $diskStorageInGB = [Math]::Round(($totalMBdiskStorage / 1GB), 2)
    Write-Host "Total Disk Storage : $diskStorageInGB GB" -ForegroundColor Yellow
    Write-Host ""

    # Display Successful Downloaded and Installed message for each mod file
    if ($error_success -ne 0) {
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "Successfully Installed: $error_success file(s)" -ForegroundColor Green
        Write-Host ""
        $error_success_msg | ForEach-Object { "$_" } | Out-Host
    }

    # Display WARNING about zip file for each mod
    if ($error_warning -ne 0) {
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Warning "Warning: $error_warning file(s)"
        Write-Host ""
        $error_warning_msg | ForEach-Object { "$_" } | Out-Host
    }

    # Display mod files that had errors while unzipping
    if ($error_fatal -ne 0) {
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "Error: $error_fatal file(s)"
        Write-Host ""
        Write-Host "If a CRC-ERROR files may have extracted without a problem."
        Write-Host "Scroll up to find the mod to verify."
        Write-Host ""
        $error_fatal_msg | ForEach-Object { "$_" } | Out-Host
    }

    # If any mods are missing from the mod.io subscribed list
    # when compared to the stored ModList.json the missing files
    # will be removed from the ModList.json and the directories 
    # will be deleted from the computer.  Compare $ModListData with
    # $ModListData_delete_comparison and remove directories of
    # missing mods.

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "        Checking for Unsubscribed Mods        " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

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
    $ModListData | ConvertTo-Json | Set-Content $ModListJsonPath

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "      Sandstorm Mod File Update Complete      " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

}

$ModListJsonPath = Join-Path -Path "$env:LOCALAPPDATA" -ChildPath "JoannaWick\Sandstorm\ModList.json"

if (-not(Test-Path $ModListJsonPath))
{
    $ParentDirectory = Split-Path -Path $ModListJsonPath -Parent

    if (-not (Test-Path -Path $ParentDirectory)) {
        $null = New-Item -Path $ParentDirectory -ItemType Directory -Force
    }

	$ModListData=@{}
    # Write initial ModList.json file
    # (so that the user doesn't have to go trough the setup again if the script doesn't run completely)
    $ModListData | ConvertTo-Json | Set-Content $ModListJsonPath

    $Subscription_Count = 0
    # Scan state.json building initial ModList.json so mods not downloaded on first run.
    $ModListData=Get-Content $ModListJsonPath | ConvertFrom-Json
    # Loop through the Mods array and change the path
    $getstatejson.Mods | ForEach-Object {
        # Replace the path with the C: drive (adjust folder structure as needed)
        $subname = $_.PSObject.Properties['Profile'].Value
        $modid = $subname.modfile.'mod_id'
        $date_added = $subname.modfile.'date_added'
        $name = $subname.name

        $ModListData | Add-Member -Name $modid -Value @{} -MemberType NoteProperty
	    $ModListData.${modid}.date_added=$date_added
        $ModListData.${modid}.name = $name
        $Subscription_Count+=1
    }

    $ModListData | ConvertTo-Json | Set-Content $ModListJsonPath
}

$Subscription_Count = 0
$getstatejson.Mods | ForEach-Object {
    $Subscription_Count+=1
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

$ModStorageSize = "{0:N2} GB" -f ((Get-ChildItem -Path "$modsDirectoryPath" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB)


function Show-Menu-GUI {
    # Ensure the .NET WinForms classes are loaded
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # 1. Main Window Container (Light Theme)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Sandstorm Mod Manager $Version"
    $form.Size = New-Object System.Drawing.Size(500, 740)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245) # Soft white/light gray background
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false

    # Universal Font Styles
    $titleFont = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $headerFont = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $textFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $buttonFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)

    # Color Palette
    $darkText = [System.Drawing.Color]::FromArgb(40, 40, 40)
    $mutedText = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $accentColor = [System.Drawing.Color]::FromArgb(0, 120, 215) # Slate blue accent
    $buttonBg = [System.Drawing.Color]::FromArgb(255, 255, 255)  # Pure white buttons
    $greenStatus = [System.Drawing.Color]::FromArgb(0, 150, 0)
    $burntStatus = [System.Drawing.Color]::FromArgb(107, 76, 45)
    $darkredStatus = [System.Drawing.Color]::FromArgb(150, 30, 30)

    # 2. Header Panel
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Sandstorm Mod Manager"
    $titleLabel.Font = $titleFont
    $titleLabel.ForeColor = $darkText
    $titleLabel.Location = New-Object System.Drawing.Point(20, 15)
    $titleLabel.Size = New-Object System.Drawing.Size(440, 35)
    $form.Controls.Add($titleLabel)

    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = "Version: $Version"
    $versionLabel.Font = $textFont
    $versionLabel.ForeColor = $mutedText
    $versionLabel.Location = New-Object System.Drawing.Point(22, 49)
    $versionLabel.Size = New-Object System.Drawing.Size(440, 20)
    $form.Controls.Add($versionLabel)

    # Divider Line
    $line = New-Object System.Windows.Forms.Label
    $line.BackColor = $accentColor
    $line.Location = New-Object System.Drawing.Point(20, 70)
    $line.Size = New-Object System.Drawing.Size(440, 2)
    $form.Controls.Add($line)

    # 3. User Info / Stats Group Box
    $statsBox = New-Object System.Windows.Forms.GroupBox
    $statsBox.Text = " Account / Storage Status "
    $statsBox.Font = $headerFont
    $statsBox.ForeColor = $accentColor
    $statsBox.Location = New-Object System.Drawing.Point(20, 85)
    $statsBox.Size = New-Object System.Drawing.Size(440, 220)
    $statsBox.BackColor = [System.Drawing.Color]::White
    
    if ($valid_Personal_Token -like "*Success*") {
       $tokenStatus = $greenStatus
    }
    else
    {
       $tokenStatus = $darkredStatus
    }

    # Token & User Info inside the stats box
    $infoText = "$valid_Personal_Token`n$valid_Personal_Username ($valid_Personal_UserID)"
    $statsLabel1 = New-Object System.Windows.Forms.Label
    $statsLabel1.Text = $infoText
    $statsLabel1.Font = $textFont
    $statsLabel1.ForeColor = $tokenStatus
    $statsLabel1.Location = New-Object System.Drawing.Point(15, 25)
    $statsLabel1.Size = New-Object System.Drawing.Size(410, 62)
    $statsBox.Controls.Add($statsLabel1)

    # Subscriptions & Directory Paths
    if($global:ManagerConfig.verbose -eq 0) { $verboseText = "Concise" }else{ $verboseText = "Verbose" }
    $settingsPath = Join-Path "$env:LOCALAPPDATA" "mod.io\globalsettings.json"

    if (Test-Path $settingsPath) {
        $globalsettings_old = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
        $globalSettingSource = $globalsettings_old.RootLocalStoragePath
        $globalSettingSource = $globalSettingSource.Replace('/', '\')
    }

    $statsText2 = "Total Subscriptions: $Subscription_Count`nMod Storage Size: $ModStorageSize`n" +
                  "Mod Storage Path: $globalSettingSource"
    
    $statsLabel2 = New-Object System.Windows.Forms.Label
    $statsLabel2.Text = $statsText2
    $statsLabel2.Font = $textFont
    $statsLabel2.ForeColor = $burntStatus
    $statsLabel2.Location = New-Object System.Drawing.Point(15, 90)
    $statsLabel2.Size = New-Object System.Drawing.Size(410, 120)
    $statsBox.Controls.Add($statsLabel2)
    $form.Controls.Add($statsBox)

    # 4. Action Buttons (Replacing CLI Number Choices)
    $buttonWidth = 440
    $buttonHeight = 40
    $startY = 325
    $spacing = 50

$UpdateUIData = {
    # 1. Evaluate the global state variable
    if ($global:ManagerConfig.verbose -eq 0) {
        $verboseText = "Concise" 
    } else { 
        $verboseText = "Verbose" 
    }
    
    # 2. Grab the local path data
    $settingsPath = Join-Path "$env:LOCALAPPDATA" "mod.io\globalsettings.json"

    if (Test-Path $settingsPath) {
        $globalsettings_old = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
        $globalSettingSource = $globalsettings_old.RootLocalStoragePath
        $globalSettingSource = $globalSettingSource.Replace('/', '\')
    }

    # 3. DIRECTLY UPDATE THE LIVE UI LABELS (Crucial Step)
    $statsText2 = "Total Subscriptions: $Subscription_Count`nMod Storage Size: $ModStorageSize`n" +
                  "Mod Storage Path: $globalSettingSource"
        $statsLabel2.Text = $statsText2

    # 4. Update the toggle button text dynamically
    if ($btn4) {
        $btn4.Text = "Toggle Verbose Mod Information (Current: $verboseText)"
    }
}

    # Helper function to generate standardized buttons quickly
    function Create-MenuButton {
        param(
            [string]$text,
            [int]$yLocation,
            [scriptblock]$actionCode
        )
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $text
        $btn.Font = $buttonFont
        $btn.ForeColor = $darkText
        $btn.BackColor = $buttonBg
        $btn.Location = New-Object System.Drawing.Point(20, $yLocation)
        $btn.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
        $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::LightGray
        $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
        
        # 1. Store the script block directly inside the button object so it doesn't get lost
        $btn | Add-Member -MemberType NoteProperty -Name "CustomAction" -Value $actionCode
        
        # 2. Reference the button object ($this) to call the stored action
        $btn.Add_Click({
            & $this.CustomAction # '$this' refers to the clicked button, pulling its own action safely
            $form.Refresh() 
        })
        return $btn
    }

    # Register actions into their corresponding script blocks using named arguments
    $btn1 = Create-MenuButton -text "Process Mod Subscriptions" -yLocation $startY -actionCode { 
        Process-Subscriptions
    }
    
    $btn2 = Create-MenuButton -text "FORCE Download and Update Specific Mods" -yLocation ($startY + $spacing) -actionCode {
            Mod-Reset

            if($global:forced_updates -eq 1)
            {
                Process-Subscriptions
            }
            $global:forced_updates=0
    }

    $btn3 = Create-MenuButton -text "Unsubscribe and Delete Specific Mods" -yLocation ($startY + ($spacing * 2)) -actionCode {
            Mod-Unsub
    }

    $btn4 = Create-MenuButton -text "Toggle Verbose Mod Information (Current: $verboseText)" -yLocation ($startY + ($spacing * 3)) -actionCode {
    if ($global:ManagerConfig.verbose -eq 0) { 
        $global:ManagerConfig.verbose = 1 
        $highLevelState = "Concise"
    } else { 
        $global:ManagerConfig.verbose = 0 
        $highLevelState = "Verbose"
    }
    $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath

    # 2. Force the data engine to push new string layers to your form components
    & $UpdateUIData
        }

    $btn5 = Create-MenuButton -text "Move Mod.io Mod Directory to New Location" -yLocation ($startY + ($spacing * 4)) -actionCode {
            move_Sandstorm_mods
    }

    $btn6 = Create-MenuButton -text "Repair globalsettings.json Storage Location" -yLocation ($startY + ($spacing * 5)) -actionCode {
            repair_globalsettings
    }


    # Exit Button (Styled with a distinct alert outline boundary tint if desired)
    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = "Exit Manager"
    $btnExit.Font = $buttonFont
    $btnExit.ForeColor = [System.Drawing.Color]::DarkRed
    $btnExit.BackColor = $buttonBg
    $btnExit.Location = New-Object System.Drawing.Point(20, ($startY + ($spacing * 6) + 10))
    $btnExit.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $btnExit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnExit.FlatAppearance.BorderColor = [System.Drawing.Color]::RosyBrown
    $btnExit.Add_Click({
        $form.Close()
    })

    # Add all interactive layout blocks onto the GUI frame
    $form.Controls.Add($btn1)
    $form.Controls.Add($btn2)
    $form.Controls.Add($btn3)
    $form.Controls.Add($btn4)
    $form.Controls.Add($btn5)
    $form.Controls.Add($btn6)
    $form.Controls.Add($btnExit)

    # 5. Open Form Window Display Dialog
    $form.ShowDialog() | Out-Null
}
Show-Menu-GUI
