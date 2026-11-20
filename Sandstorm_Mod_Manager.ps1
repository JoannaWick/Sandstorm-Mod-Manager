<#PSScriptInfo
.AUTHOR Joanna Wick
.TAGS Sandstorm, Mods
.PROJECTURI https://github.com/JoannaWick/Sandstorm-Mod-Manager
#>

param(
    [string]$batchLaunch=0
)

$VersionConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "config\Version.json"
$VersionConfig=Get-Content $VersionConfigPath -Raw | ConvertFrom-Json
$Version = $VersionConfig.Version
$ReleaseDate = $VersionConfig.ReleaseDate

<# 
    Resize and center window
#>

# Read the current OS build framework directly from memory
$buildNumber = [Environment]::OSVersion.Version.Build

if ($buildNumber -ge 22000) {

    Add-Type -AssemblyName System.Windows.Forms
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    $posX = [math]::Round(($workingArea.Width + 500) / 2)
    $posY = [math]::Round(($workingArea.Height - 830) / 2)

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
        [void][Win32]::MoveWindow($hWnd, $posX, $posY, 600, 830, $true)
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
    $screenHeight = ($workingArea.Height-830)/2

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
    [void][Window]::MoveWindow($hWnd, $screenWidth, $screenHeight, 600, 830, $true)
}

Set-Location -Path $PSScriptRoot

$ManagerConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "config\ManagerConfig.json"

if (-not (Test-Path $ManagerConfigPath)) {
    $global:ManagerConfig = [PSCustomObject]@{
        verbose                = 0
        DefaultTheme           = "Dark"
        modioPageDisplayLimit  = 25
    }
    $global:ManagerConfig | ConvertTo-Json | Set-Content -Path $ManagerConfigPath
}
else {
    $global:ManagerConfig = Get-Content -Path $ManagerConfigPath -Raw | ConvertFrom-Json

    # Check if DefaultTheme is missing, add it, and save
    if (-not ($global:ManagerConfig.PSObject.Properties.Name -contains 'DefaultTheme')) {
        $global:ManagerConfig | Add-Member -NotePropertyName 'DefaultTheme' -NotePropertyValue 'Light'
        $global:ManagerConfig | ConvertTo-Json | Set-Content -Path $ManagerConfigPath
    }

    # Check if modioPageDisplayLimit is missing, add it, and save
    if (-not ($global:ManagerConfig.PSObject.Properties.Name -contains 'modioPageDisplayLimit')) {
        $global:ManagerConfig | Add-Member -NotePropertyName 'modioPageDisplayLimit' -NotePropertyValue 25
        $global:ManagerConfig | ConvertTo-Json | Set-Content -Path $ManagerConfigPath
    }
}

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

$global:isNewSubscriptions = $false

function modio-collection-browser
{
    # Configuration

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
    $destinationMods="$destination"+"254\mods\"

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

    [string]$script:OAuthToken=$getuserjson.Oauth.token
    $UserID=$getuserjson.Profile.username
    $DefaultTheme     = $global:ManagerConfig.DefaultTheme # Options: "Light" or "Dark"

    # Configuration

    $GameId  = 254
    $BaseUrl = "https://g-$GameId.modapi.io/v1"

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Universal Font Styles
    $titleFont = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $headerFont = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $textFont = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $buttonFont = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)

    # Build Main Form & Controls

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Insurgency: Sandstorm - Mod.io Collections Browser"
    $Form.Size = New-Object System.Drawing.Size(1050, 740)
    $Form.StartPosition = "CenterScreen"
    $Form.MinimumSize = New-Object System.Drawing.Size(800, 600)
    $Form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    # Top Search & Action Panel
    $TopPanel = New-Object System.Windows.Forms.Panel
    $TopPanel.Dock = "Top"
    $TopPanel.Height = 48
    $TopPanel.Padding = New-Object System.Windows.Forms.Padding(10, 10, 10, 5)

    $LblSearch = New-Object System.Windows.Forms.Label
    $LblSearch.Text = "Filter Collections:"
    $LblSearch.AutoSize = $true
    $LblSearch.Location = New-Object System.Drawing.Point(12, 14)
    $LblSearch.Font = $textFont

    $TxtSearch = New-Object System.Windows.Forms.TextBox
    $TxtSearch.Location = New-Object System.Drawing.Point(125, 11)
    $TxtSearch.Size = New-Object System.Drawing.Size(280, 25)

    $BtnRefresh = New-Object System.Windows.Forms.Button
    $BtnRefresh.Text = "Refresh All"
    $BtnRefresh.Location = New-Object System.Drawing.Point(415, 10)
    $BtnRefresh.Size = New-Object System.Drawing.Size(95, 27)
    $BtnRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $BtnRefresh.Font = $buttonFont

    $BtnFollow = New-Object System.Windows.Forms.Button
    $BtnFollow.Text = "Follow"
    $BtnFollow.Location = New-Object System.Drawing.Point(520, 10)
    $BtnFollow.Size = New-Object System.Drawing.Size(85, 27)
    $BtnFollow.Enabled = $false
    $BtnFollow.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $BtnFollow.Font = $buttonFont
    $BtnFollow.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $BtnFollow.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)

    $BtnUnfollow = New-Object System.Windows.Forms.Button
    $BtnUnfollow.Text = "Unfollow"
    $BtnUnfollow.Location = New-Object System.Drawing.Point(615, 10)
    $BtnUnfollow.Size = New-Object System.Drawing.Size(85, 27)
    $BtnUnfollow.Enabled = $false
    $BtnUnfollow.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $BtnUnfollow.Font = $buttonFont
    $BtnUnfollow.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $BtnUnfollow.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)

    $BtnOpenWeb = New-Object System.Windows.Forms.Button
    $BtnOpenWeb.Text = "Open in Browser"
    $BtnOpenWeb.Location = New-Object System.Drawing.Point(710, 10)
    $BtnOpenWeb.Size = New-Object System.Drawing.Size(135, 27)
    $BtnOpenWeb.Enabled = $false
    $BtnOpenWeb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $BtnOpenWeb.Font = $buttonFont

    # Exit Button (Styled with a distinct alert outline boundary tint if desired)
    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = "Exit Browser"
    $btnExit.Font = $buttonFont
    $btnExit.Location = New-Object System.Drawing.Point(855, 10)
    $btnExit.Size = New-Object System.Drawing.Size(115, 27)
    $btnExit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnExit.FlatAppearance.BorderColor = [System.Drawing.Color]::RosyBrown
    $btnExit.Add_Click({
        $form.Close()
    })

    $TopPanel.Controls.AddRange(@($LblSearch, $TxtSearch, $BtnRefresh, $BtnFollow, $BtnUnfollow, $BtnOpenWeb, $btnExit))

    # Status Strip at Bottom
    $StatusStrip = New-Object System.Windows.Forms.StatusStrip
    $StatusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $StatusLabel.Text = "Ready."
    $StatusLabel.Font = $textFont
    $StatusStrip.Items.Add($StatusLabel) | Out-Null

    # SplitContainer (Top: Collections Grid, Bottom: Selected Collection Mods Grid)
    $SplitContainer = New-Object System.Windows.Forms.SplitContainer
    $SplitContainer.Dock = "Fill"
    $SplitContainer.Orientation = "Horizontal"
    $SplitContainer.SplitterDistance = 310
    $SplitContainer.Padding = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)

    # Top Grid: Collections
    $LblCollections = New-Object System.Windows.Forms.Label
    $LblCollections.Text = "Collections (Green rows = Followed | Click a row to view its mods):"
    $LblCollections.Dock = "Top"
    $LblCollections.Height = 24
    $LblCollections.Font = $textFont

    $GridCollections = New-Object System.Windows.Forms.DataGridView
    $GridCollections.Dock = "Fill"
    $GridCollections.BorderStyle = "None"
    $GridCollections.AllowUserToAddRows = $false
    $GridCollections.AllowUserToDeleteRows = $false
    $GridCollections.ReadOnly = $true
    $GridCollections.SelectionMode = "FullRowSelect"
    $GridCollections.MultiSelect = $false
    $GridCollections.RowHeadersVisible = $false
    $GridCollections.RowTemplate.Height = 32
    $GridCollections.AutoSizeColumnsMode = "Fill"
    $GridCollections.EnableHeadersVisualStyles = $false
    $GridCollections.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $GridCollections.ColumnHeadersHeight = 32

    $SplitContainer.Panel1.Controls.Add($GridCollections)
    $SplitContainer.Panel1.Controls.Add($LblCollections)

    # Bottom Grid: Mods in Selected Collection
    $LblMods = New-Object System.Windows.Forms.Label
    $LblMods.Text = "Mods in Selected Collection:"
    $LblMods.Dock = "Top"
    $LblMods.Height = 24
    $LblMods.Font = $textFont

    $GridMods = New-Object System.Windows.Forms.DataGridView
    $GridMods.Dock = "Fill"
    $GridMods.BorderStyle = "None"
    $GridMods.AllowUserToAddRows = $false
    $GridMods.AllowUserToDeleteRows = $false
    $GridMods.ReadOnly = $true
    $GridMods.SelectionMode = "FullRowSelect"
    $GridMods.MultiSelect = $false
    $GridMods.RowHeadersVisible = $false
    $GridMods.RowTemplate.Height = 32
    $GridMods.AutoSizeColumnsMode = "Fill"
    $GridMods.EnableHeadersVisualStyles = $false
    $GridMods.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $GridMods.ColumnHeadersHeight = 32

    $SplitContainer.Panel2.Controls.Add($GridMods)
    $SplitContainer.Panel2.Controls.Add($LblMods)

    $Form.Controls.Add($SplitContainer)
    $Form.Controls.Add($TopPanel)
    $Form.Controls.Add($StatusStrip)

    # Data Binding & Event Handlers

    $script:CollectionTable = New-Object System.Data.DataTable
    $script:CollectionTable.Columns.Add("ID", [int]) | Out-Null
    $script:CollectionTable.Columns.Add("Followed", [bool]) | Out-Null
    $script:CollectionTable.Columns.Add("Collection", [string]) | Out-Null
    $script:CollectionTable.Columns.Add("Author", [string]) | Out-Null
    $script:CollectionTable.Columns.Add("Followers", [int]) | Out-Null
    $script:CollectionTable.Columns.Add("Updated", [string]) | Out-Null
    $script:CollectionTable.Columns.Add("Summary", [string]) | Out-Null
    $script:CollectionTable.Columns.Add("ProfileUrl", [string]) | Out-Null

    $GridCollections.DataSource = $script:CollectionTable

    # Highlight followed rows dynamically (persists across sorting and filtering)
    $FollowedBackColor = [System.Drawing.Color]::FromArgb(220, 245, 224)
    $FollowedForeColor = [System.Drawing.Color]::FromArgb(20, 83, 45)
    $BoldGridFont = $textFont

    $GridCollections.Add_RowPrePaint({
        param($sender, $e)

        if ($e.RowIndex -lt 0) { return }

        $Row = $GridCollections.Rows[$e.RowIndex]
        $IsFollowed = $Row.Cells["Followed"].Value

        if ($IsFollowed -eq $true) {
            $Row.DefaultCellStyle.BackColor = $FollowedBackColor
            $Row.DefaultCellStyle.ForeColor = $FollowedForeColor
            $Row.DefaultCellStyle.Font      = $BoldGridFont
        }
        else 
        {
            $Row.DefaultCellStyle.Font      = $BoldGridFont
        }
    })

    # Live Filter Event

    $TxtSearch.Add_TextChanged({
        $FilterText = $TxtSearch.Text.Replace("'", "''")

        if ([string]::IsNullOrWhiteSpace($FilterText)) {
            $script:CollectionTable.DefaultView.RowFilter = ""
        }
        else 
        {
            $script:CollectionTable.DefaultView.RowFilter = "Name LIKE '%$FilterText%' OR Author LIKE '%$FilterText%' OR Summary LIKE '%$FilterText%'"
        }
        $StatusLabel.Text = "Showing $($script:CollectionTable.DefaultView.Count) matching collections."
    })

    # Collection Selection Event -> Load Mods into Bottom Grid

    $GridCollections.Add_SelectionChanged({
        if ($GridCollections.SelectedRows.Count -eq 0) {
            $BtnFollow.Enabled   = $false
            $BtnUnfollow.Enabled = $false
            $BtnOpenWeb.Enabled = $false
            return
        }

        $SelectedRow  = $GridCollections.SelectedRows[0]
        $CollectionId = $SelectedRow.Cells["ID"].Value
        $ColName      = $SelectedRow.Cells["Collection"].Value
        $IsFollowed   = [bool]$SelectedRow.Cells["Followed"].Value

        $BtnFollow.Enabled   = -not $IsFollowed
        $BtnUnfollow.Enabled = $IsFollowed
        $BtnOpenWeb.Enabled = $true

        if (-not $CollectionId) { return }

        $Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $LblMods.Text = "Mods in Selected Collection: $ColName (Loading...)"
        $StatusLabel.Text = "Fetching mods for collection '$ColName' (ID: $CollectionId)..."
        $Form.Refresh()

        $Mods = Get-CollectionMods -CollectionId $CollectionId

        $ModsTable = New-Object System.Data.DataTable
        $ModsTable.Columns.Add("ModID", [int]) | Out-Null
        $ModsTable.Columns.Add("Name", [string]) | Out-Null
        $ModsTable.Columns.Add("ResourceID", [string]) | Out-Null
        $ModsTable.Columns.Add("Author", [string]) | Out-Null
        $ModsTable.Columns.Add("Summary", [string]) | Out-Null

        foreach ($Mod in $Mods) {
            $MRow = $ModsTable.NewRow()
            $MRow["ModID"]      = $Mod.id
            $MRow["Name"]       = $Mod.name
            $MRow["ResourceID"] = $Mod.name_id
            $MRow["Author"]     = $Mod.submitted_by.username
            $MRow["Summary"]    = $Mod.summary
            $ModsTable.Rows.Add($MRow)
        }

        $GridMods.DataSource = $ModsTable

        $GridMods.RowsDefaultCellStyle.Font = $BoldGridFont

        if ($GridMods.Columns["ModID"])      { $GridMods.Columns["ModID"].FillWeight = 14 }
        if ($GridMods.Columns["Name"])       { $GridMods.Columns["Name"].FillWeight = 35 }
        if ($GridMods.Columns["ResourceID"]) { $GridMods.Columns["ResourceID"].FillWeight = 28 }
        if ($GridMods.Columns["Author"])     { $GridMods.Columns["Author"].FillWeight = 22 }
        if ($GridMods.Columns["Summary"])    { $GridMods.Columns["Summary"].FillWeight = 45 }

        $LblMods.Text = "Mods in Selected Collection: $ColName ($($Mods.Count) mods)"
        $StatusLabel.Text = "Loaded $($Mods.Count) mods for '$ColName'."
        $Form.Cursor = [System.Windows.Forms.Cursors]::Default
    })

    # Refresh Button Event

    $BtnRefresh.Add_Click({
        Load-CollectionsIntoGrid
    })

    # Open in Browser Button Event

    $BtnOpenWeb.Add_Click({
        if ($GridCollections.SelectedRows.Count -gt 0) {
            $Url = $GridCollections.SelectedRows[0].Cells["ProfileUrl"].Value
            if ($Url) {
                Start-Process $Url
            }
        }
    })

    # Follow Collection Button Event

    $BtnFollow.Add_Click({
        if ($GridCollections.SelectedRows.Count -eq 0) { return }

        $SelectedRow  = $GridCollections.SelectedRows[0]
        $CollectionId = $SelectedRow.Cells["ID"].Value
        $ColName      = $SelectedRow.Cells["Collection"].Value
        $Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $StatusLabel.Text = "Following collection '$ColName'..."
        $Form.Refresh()

        # Follow the collection
        $Result = Invoke-ModioV1 -Endpoint "/games/$GameId/collections/$CollectionId/followers" -Method Post

        if ($Result) {
            $SelectedRow.Cells["Followed"].Value = $true
            if ($null -ne $Result.stats.followers_total) {
                $SelectedRow.Cells["Followers"].Value = $Result.stats.followers_total
            }

            # Subscribe to all mods in collection
            $Result = Invoke-ModioV1 -Endpoint "/games/$GameId/collections/$CollectionId/subscriptions" -Method Post

            $BtnFollow.Enabled   = $false
            $BtnUnfollow.Enabled = $true
            $GridCollections.InvalidateRow($SelectedRow.Index)
            $StatusLabel.Text = "Now following and subscribed '$ColName' (ID: $CollectionId)."
            New_MessageBox -title "Collection Followed" -infoMessage "You are now following '$ColName' and subscribed to all mods in that Collection."
            $global:isNewSubscriptions = $true
        }
        else 
        {
            $StatusLabel.Text = "Failed to follow '$ColName'."
        }
        $Form.Cursor = [System.Windows.Forms.Cursors]::Default
    })

    # Unfollow Collection Button Event

    $BtnUnfollow.Add_Click({
        if ($GridCollections.SelectedRows.Count -eq 0) { return }

        $SelectedRow  = $GridCollections.SelectedRows[0]
        $CollectionId = $SelectedRow.Cells["ID"].Value
        $ColName      = $SelectedRow.Cells["Collection"].Value
        $Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $StatusLabel.Text = "Unfollowing collection '$ColName'..."
        $Form.Refresh()

        $Headers = @{
    "Authorization" = "Bearer $script:OAuthToken"
    "Accept"        = "application/json"
    "User-Agent"    = "SandstormPowerShellBrowser/1.0"
    "Content-Type"  = "application/x-www-form-urlencoded"
        }

        $UnfollowUri = "$BaseUrl/games/$GameId/collections/$CollectionId/followers"

        # Unfollow Collection but mods still subscribed.
        try {
            $WebResp = Invoke-WebRequest -Uri $UnfollowUri -Method Delete -Headers $Headers -UseBasicParsing -ErrorAction Stop

            if ($WebResp.StatusCode -in @(200, 204)) {
                $SelectedRow.Cells["Followed"].Value = $false
                $CurrentFollowers = [int]$SelectedRow.Cells["Followers"].Value

                if ($CurrentFollowers -gt 0) {
                    $SelectedRow.Cells["Followers"].Value = $CurrentFollowers - 1
                }

                $BtnFollow.Enabled   = $true
                $BtnUnfollow.Enabled = $false
                $GridCollections.InvalidateRow($SelectedRow.Index)
                $StatusLabel.Text = "Unfollowed '$ColName' (ID: $CollectionId)."
                New_MessageBox -title "Collection Unfollowed" -infoMessage "You have unfollowed '$ColName'."
            }
        }
        catch 
        {
            $StatusCode = $.Exception.Response.StatusCode.value__
            $ErrMsg = if ($.ErrorDetails.Message) { $.ErrorDetails.Message } else { $.Exception.Message }
            $StatusLabel.Text = "Failed to unfollow '$ColName'."
            New_MessageBox -title "mod.io API Error" -infoMessage "HTTP $StatusCode on Delete $UnfollowUri`n`n$ErrMsg"
        }
        finally {
            $Form.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    })

    $form.Add_FormClosing({
        param($sender, $e)
    
        if($global:isNewSubscriptions)
        {
            $global:isNewSubscriptions = $false
            $form.Hide()
            [System.Windows.Forms.Application]::DoEvents()
            Process-Subscriptions
            $form.Close()
        }
    })

    # Load data immediately when the window opens
    Set-CollectionBrowserTheme -ThemeName $DefaultTheme

    $Form.Add_Shown({
        Load-CollectionsIntoGrid
    })

    [void]$Form.ShowDialog()
    $Form.Dispose()
}

function Load-CollectionsIntoGrid {
    $Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $StatusLabel.Text = "Fetching collections and followed status from mod.io..."
    $Form.Refresh()

    $FollowedIds    = Get-FollowedCollectionIds
    $RawCollections = Get-AllSandstormCollections
    $script:CollectionTable.Clear()

    foreach ($Col in $RawCollections) {
        $UpdatedDate = ([DateTimeOffset]::FromUnixTimeSeconds($Col.date_updated)).ToString("MMM d, yyyy")
        $Row = $script:CollectionTable.NewRow()
        $Row["ID"]         = $Col.id
        $Row["Followed"]   = ($null -ne $FollowedIds -and $FollowedIds.Contains([int]$Col.id))
        $Row["Collection"]       = $Col.name
        $Row["Author"]     = $Col.submitted_by.username
        $Row["Followers"]  = $Col.stats.followers_total
        $Row["Updated"]    = $UpdatedDate
        $Row["Summary"]    = $Col.summary
        $Row["ProfileUrl"] = $Col.submitted_by.profile_url + "/c"
        $script:CollectionTable.Rows.Add($Row)
    }

    if ($GridCollections.Columns["ID"])         { $GridCollections.Columns["ID"].FillWeight = 10 }
    if ($GridCollections.Columns["Followed"])   { $GridCollections.Columns["Followed"].FillWeight = 10 }
    if ($GridCollections.Columns["Collection"]) { $GridCollections.Columns["Collection"].FillWeight = 35 }
    if ($GridCollections.Columns["Author"])     { $GridCollections.Columns["Author"].FillWeight = 22 }
    if ($GridCollections.Columns["Followers"])  { $GridCollections.Columns["Followers"].FillWeight = 10 }
    if ($GridCollections.Columns["Updated"])    { $GridCollections.Columns["Updated"].FillWeight = 14}
    if ($GridCollections.Columns["Summary"])    { $GridCollections.Columns["Summary"].FillWeight = 45 }
    if ($GridCollections.Columns["ProfileUrl"]) { $GridCollections.Columns["ProfileUrl"].Visible = $false }
    $GridCollections.Invalidate()
    $StatusLabel.Text = "Loaded $($RawCollections.Count) collections ($($FollowedIds.Count) followed)."
    $Form.Cursor = [System.Windows.Forms.Cursors]::Default
}

# Pagination Helpers Using Invoke-ModioV1

function Get-AllSandstormCollections {
    $AllCollections = @()
    $Limit  = 100
    $Offset = 0

    do {
        $Response = Invoke-ModioV1 -Endpoint "/games/$GameId/collections" -Method Get -QueryParams @{
            "_limit"  = $Limit
            "_offset" = $Offset
            "_sort"   = "name"
        }

        if (-not $Response) { break }

        if ($Response.data) {
            $AllCollections += $Response.data
        }
        $Offset += $Limit
    } while ($AllCollections.Count -lt $Response.result_total)

    return ,$AllCollections
}

function Get-FollowedCollectionIds {
    $FollowedIds = New-Object 'System.Collections.Generic.HashSet[int]'
    $Limit  = 100
    $Offset = 0

    do {
        $Response = Invoke-ModioV1 -Endpoint "/me/following/collections" -Method Get -QueryParams @{
            "_limit"  = $Limit
            "_offset" = $Offset
        }

        if (-not $Response) { break }

        if ($Response.data) {
            foreach ($Item in $Response.data) {
                [void]$FollowedIds.Add([int]$Item.id)
            }
        }
        $Offset += $Limit
    } while ($FollowedIds.Count -lt $Response.result_total)

    return ,$FollowedIds
}

function Get-CollectionMods {
    param([int]$CollectionId)

    $Mods   = @()
    $Limit  = 100
    $Offset = 0

    do {
        $Response = Invoke-ModioV1 -Endpoint "/games/$GameId/collections/$CollectionId/mods" -Method Get -QueryParams @{
            "_limit"  = $Limit
            "_offset" = $Offset
        }

        if (-not $Response) { break }

        if ($Response.data) {
            $Mods += $Response.data
        }
        $Offset += $Limit
    } while ($Mods.Count -lt $Response.result_total)

    return ,$Mods
}

function Switch-UserProfile {
    param (
        [PSCustomObject]$Profile,
        [System.Windows.Forms.Label]$StatusLabel
    )

    if (-not $Profile -or [string]::IsNullOrWhiteSpace($Profile.Token) -or $Profile.Token -eq "YOUR_OAUTH_ACCESS_TOKEN_HERE") {
        $script:OAuthToken = ""
        $script:SubscribedIds.Clear()
        Apply-SubscribedRowHighlights
        $StatusLabel.Text = "Selected profile '$($Profile.DisplayName)' has no valid oauth_token. Edit $($Profile.FilePath)."
        return
    }

    $script:OAuthToken = $Profile.Token
    $StatusLabel.Text = "Authenticating $($Profile.DisplayName) on $BaseUrl..."
    [System.Windows.Forms.Application]::DoEvents()

    $Me = Invoke-ModioV1 -Endpoint "/me" -Method Get
    if ($Me) {
        $StatusLabel.Text = "Connected as $($Me.username) | Syncing subscribed mods..."
        [System.Windows.Forms.Application]::DoEvents()
        Sync-SubscribedIds -StatusLabel $StatusLabel
        Apply-SubscribedRowHighlights
        if ($script:CurrentPageMods.Count -gt 0 -and $Grid.SelectedRows.Count -gt 0) {
            $TopRow = $Grid.SelectedRows[0]
            $SelId = [int]$TopRow.Cells["ModID"].Value
            $MatchedMod = $script:CurrentPageMods | Where-Object { $_.ModID -eq $SelId } | Select-Object -First 1
            Update-PreviewPanel -ModObj $MatchedMod
        }
        $StatusLabel.Text = "Active User: $($Me.username) ($($Profile.DisplayName)) | $($script:SubscribedIds.Count) subscribed mod(s) synced."
    } else {
        $script:SubscribedIds.Clear()
        Apply-SubscribedRowHighlights
        $StatusLabel.Text = "Authentication failed for $($Profile.DisplayName) on $BaseUrl."
    }
}

function Invoke-ModioV1 {
    param (
        [string]$Endpoint,
        [ValidateSet("Get", "Post", "Delete")]
        [string]$Method = "Get",
        [hashtable]$QueryParams = @{}
    )

    if (-not $Endpoint.StartsWith("/")) {
        $Endpoint = "/$Endpoint"
    }

    $Headers = @{
        "Authorization" = "Bearer $script:OAuthToken"
        "Accept"        = "application/json"
        "User-Agent"    = "SandstormPowerShellBrowser/1.0"
    }

    if ($Method -in @("Post", "Delete")) {
        $Headers["Content-Type"] = "application/x-www-form-urlencoded"
    }

    $Uri = "$BaseUrl$Endpoint"
    if ($QueryParams.Count -gt 0) {
        $QueryString = ($QueryParams.GetEnumerator() | ForEach-Object { 
            "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" 
        }) -join "&"
        $Uri = "$Uri`?$QueryString"
    }

    try {
        return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -ErrorAction Stop
    }
    catch {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        $ErrMsg = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        New_MessageBox -title "mod.io API Error" -infoMessage "HTTP $StatusCode on $Method $Uri`n`n$ErrMsg"
        return $null
    }
}

function Get-ModioAllPages {
    param (
        [string]$Endpoint,
        [hashtable]$BaseParams = @{},
        [System.Windows.Forms.Label]$StatusLabel = $null
    )

    $AllItems = @()
    $Offset = 0
    $PageNum = 1

    while ($true) {
        $PageParams = @{}
        foreach ($Key in $BaseParams.Keys) { $PageParams[$Key] = $BaseParams[$Key] }
        $PageParams["_limit"]  = "$ApiFetchLimit"
        $PageParams["_offset"] = "$Offset"

        if ($StatusLabel) {
            $StatusLabel.Text = "Downloading catalog batch $PageNum from $BaseUrl$Endpoint (offset $Offset)..."
            [System.Windows.Forms.Application]::DoEvents()
        }

        $Response = Invoke-ModioV1 -Endpoint $Endpoint -Method Get -QueryParams $PageParams
        if (-not $Response -or $null -eq $Response.data) { break }

        $Batch = @($Response.data)
        if ($Batch.Count -eq 0) { break }

        $AllItems += $Batch
        $TotalAvailable = [int]$Response.result_total

        if ($StatusLabel) {
            $StatusLabel.Text = "Downloaded $($AllItems.Count) of $TotalAvailable total mods..."
            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($AllItems.Count -ge $TotalAvailable -or $Batch.Count -lt $ApiFetchLimit) {
            break
        }

        $Offset += $ApiFetchLimit
        $PageNum++
    }

    return ,$AllItems
}

# Loads the full mod catalog from local disk cache or downloads all pages from https://mod.io

function Load-MasterCatalog {
    param (
        [switch]$ForceRefresh,
        [System.Windows.Forms.Label]$StatusLabel
    )

    $UseCache = $false
    if (-not $ForceRefresh -and (Test-Path $CatalogCachePath)) {
        $FileInfo = Get-Item $CatalogCachePath
        $AgeHours = ((Get-Date) - $FileInfo.LastWriteTime).TotalHours
        if ($AgeHours -lt $CacheMaxHours) {
            $UseCache = $true
        }
    }

    if ($UseCache) {
        $StatusLabel.Text = "Loading full mod catalog from local cache ($CatalogCachePath)..."
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $RawJson = Get-Content -Path $CatalogCachePath -Raw -Encoding UTF8
            $Parsed = $RawJson | ConvertFrom-Json
            $script:MasterCatalog = @($Parsed | Sort-Object -Property name)
            return
        }
        catch {
            Write-Warning "Local cache unreadable, re-downloading from $BaseUrl..."
        }
    }

    $Downloaded = Get-ModioAllPages -Endpoint "/games/$GameId/mods" -BaseParams @{ "_sort" = "name" } -StatusLabel $StatusLabel
    $script:MasterCatalog = @($Downloaded)

    if ($script:MasterCatalog.Count -gt 0) {
        $StatusLabel.Text = "Saving $($script:MasterCatalog.Count) mods to local cache..."
        [System.Windows.Forms.Application]::DoEvents()
        $script:MasterCatalog | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $CatalogCachePath -Encoding UTF8
    }
}

function Sync-SubscribedIds {
    param ([System.Windows.Forms.Label]$StatusLabel = $null)

    $SubMods = Get-ModioAllPages -Endpoint "/me/subscribed" -BaseParams @{ "game_id" = "$GameId" } -StatusLabel $StatusLabel
    $script:SubscribedIds.Clear()
    foreach ($Sub in @($SubMods)) {
        if ($Sub.id) {
            [void]$script:SubscribedIds.Add([int]$Sub.id)
        }
    }
}

function Get-CachedModImage {
    param (
        [string]$ImageUrl,
        [PSCustomObject]$Dialog,
        [int]$currentcount,
        [int]$totalCount
    )

    if ([string]::IsNullOrWhiteSpace($ImageUrl)) { return $null }

    # Check fast in-memory cache first
    if ($script:ImageCache.ContainsKey($ImageUrl)) {
        return $script:ImageCache[$ImageUrl]
    }

    # Build a deterministic filename from the URL's SHA-256 hash
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    $HashBytes = $Sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ImageUrl))
    $UrlHash = ([System.BitConverter]::ToString($HashBytes)).Replace("-", "").ToLower()

    $Ext = ".jpg"
    if ($ImageUrl -match "\.(png|jpg|jpeg|gif|webp)(?:$|\?)") {
        $Ext = "." + $Matches[1].ToLower()
    }
    $LocalFilePath = Join-Path $ImageCacheDir "$UrlHash$Ext"

    try {
        # If not already on disk, download from URL and save to image_cache
        if (-not (Test-Path $LocalFilePath)) {
            $fileName = [System.IO.Path]::GetFileName($ImageUrl)
            $dialogText = "Downloading $currentcount of $totalCount `n$fileName"
            $dialog.Label.Text = $dialogText
            $WebClient = New-Object System.Net.WebClient
            $WebClient.Headers.Add("User-Agent", "SandstormPowerShellBrowser/1.0")
            $WebClient.DownloadFile($ImageUrl, $LocalFilePath)
        }

        # Load from local disk into memory without locking the file
        $Bytes  = [System.IO.File]::ReadAllBytes($LocalFilePath)
        $Stream = New-Object System.IO.MemoryStream(,$Bytes)
        $Img    = [System.Drawing.Image]::FromStream($Stream)

        $script:ImageCache[$ImageUrl] = $Img
        return $Img
    }
    catch {
        # Remove corrupt/partial file if download or decode failed
        if (Test-Path $LocalFilePath) {
            Remove-Item -Path $LocalFilePath -Force -ErrorAction SilentlyContinue
        }
        return $null
    }
}

function Get-SafeDirectoryName {
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,

        [string]$Replacement = '_'
    )

    # Replace all OS-invalid filename characters
    $InvalidChars = [System.IO.Path]::GetInvalidFileNameChars() -join ''
    $Regex = "[{0}]" -f [RegEx]::Escape($InvalidChars)
    $SafeName = $Name -replace $Regex, $Replacement

    # Remove trailing spaces and periods (invalid on Windows)
    $SafeName = $SafeName.Trim().TrimEnd('.')

    # Guard against Windows reserved device names (e.g., CON, NUL, COM1, LPT1)
    if ($SafeName -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') {
        $SafeName = "$Replacement$SafeName"
    }

    # Fallback if the string was empty or contained only invalid characters
    if ([string]::IsNullOrWhiteSpace($SafeName)) {
        $SafeName = 'Unnamed_Folder'
    }

    return $SafeName
}

function Update-PageDropdown {
    param(
        [int]$CurrentPage,
        [int]$TotalPages
    )

    # Temporarily pause event firing while rebuilding the list
    $script:IsUpdatingPageDropdown = $true
    $CmbPageSelect.Items.Clear()

    if ($TotalPages -le 0) {
        [void]$CmbPageSelect.Items.Add("Page 0 of 0")
        $CmbPageSelect.SelectedIndex = 0
    }
    else 
    {
        for ($i = 1; $i -le $TotalPages; $i++) {
            [void]$CmbPageSelect.Items.Add("Page $i of $TotalPages")
        }
        # Select the active page (0-based index)
        $CmbPageSelect.SelectedIndex = [Math]::Max(0, [Math]::Min($CurrentPage - 1, $TotalPages - 1))
    }

    $script:IsUpdatingPageDropdown = $false
}

function Show-MediaInGui {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return }

    $mediaForm = New-Object System.Windows.Forms.Form
    $mediaForm.Text = "Media Viewer (Double-click to toggle full size)"
    $mediaForm.Size = New-Object System.Drawing.Size(1024, 768)
    $mediaForm.StartPosition = "CenterParent"
    $mediaForm.BackColor = [System.Drawing.Color]::Black
    $mediaForm.KeyPreview = $true

    # Allow Escape key to exit full screen or close the window
    $mediaForm.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            if ($mediaForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized -and $mediaForm.FormBorderStyle -eq [System.Windows.Forms.FormBorderStyle]::None) {
                $mediaForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
                $mediaForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            }
            else {
                $mediaForm.Close()
            }
        }
    })

    $toggleFullScreen = {
        if ($mediaForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized -and $mediaForm.FormBorderStyle -eq [System.Windows.Forms.FormBorderStyle]::None) {
            $mediaForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
            $mediaForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        else {
            $mediaForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
            $mediaForm.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
        }
    }

    $cleanPath = ($Url -split '\?')[0].ToLower()
    $isYouTube = $Url -match '(?:youtube\.com/(?:watch\?v=|embed/|shorts/)|youtu\.be/)([a-zA-Z0-9_-]{11})'
    $youTubeId = if ($isYouTube) { $matches[1] } else { $null }
    $isVideoFile = $cleanPath -match '\.(mp4|webm|ogg|mov|m4v)$'

    # Use WebView2 (Chromium) for YouTube links and direct video files
    if ($isYouTube -or $isVideoFile) {
        Start-Process $Url
        return
    }
    else 
    {
        # Native PictureBox for images
        $picBox = New-Object System.Windows.Forms.PictureBox
        $picBox.Dock = [System.Windows.Forms.DockStyle]::Fill
        $picBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $picBox.BackColor = [System.Drawing.Color]::Black
        $picBox.Cursor = [System.Windows.Forms.Cursors]::Hand
        $picBox.Add_DoubleClick($toggleFullScreen)

        try {
            $picBox.Load($Url)
        }
        catch {
            New_MessageBox -title "Error" -infoMessage "Could not load media: $($_.Exception.Message)"
            return
        }
        $mediaForm.Controls.Add($picBox)
    }

    [void]$mediaForm.ShowDialog()
    $mediaForm.Dispose()
}

function Set-PreviewHtmlContent {
    param ([string]$RawHtml)

    $script:CurrentSummaryHtml = $RawHtml

    if ($script:CurrentTheme -eq "Dark") {
        $BgHex     = "#2A2F38"
        $TextHex   = "#ECF0F6"
        $LinkHex   = "#60A5FA"
        $BorderHex = "#3E4450"
        $CardBg    = "#1F242B"
    } else {
        $BgHex     = "#FAFBFD"
        $TextHex   = "#282D37"
        $LinkHex   = "#0070E0"
        $BorderHex = "#DCE0E6"
        $CardBg    = "#EEF1F6"
    }

    $ProcessedHtml = $RawHtml

    if (-not [string]::IsNullOrWhiteSpace($ProcessedHtml)) {
        # Match <iframe src="https://www.youtube.com/embed/IE4uqOc4t80" ...></iframe>
        $YtPattern = '(?is)<iframe[^>]+src=["''](?:https?:)?//(?:www\.)?(?:youtube\.com|youtube-nocookie\.com)/embed/([a-zA-Z0-9_-]{11})[^"'']*["''][^>]*>.*?</iframe>'

        $Replacement = @"
<div style="margin: 8px 0; padding: 8px; background-color: $CardBg; border: 1px solid $BorderHex; text-align: center;">
  <a href="https://www.youtube.com/watch?v=`$1" style="display: block; text-decoration: none; color: $LinkHex;">
    <img src="https://img.youtube.com/vi/`$1/0.jpg" alt="YouTube Video" style="max-width: 100%; height: auto; display: block; margin: 0 auto 6px auto; border: 0;" />
    <span style="font-weight: bold;">&#9654; Watch Video on YouTube</span>
  </a>
</div>
"@
        $ProcessedHtml = [regex]::Replace($ProcessedHtml, $YtPattern, $Replacement)
    }

    $BodyContent = if ([string]::IsNullOrWhiteSpace($ProcessedHtml)) {
        "<p style='opacity:0.7;'>No description or summary provided.</p>"
    } else {
        $ProcessedHtml
    }

    $StyledDoc = @"
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="X-UA-Compatible" content="IE=edge" />
<style>
  body {
    background-color: $BgHex;
    color: $TextHex;
    font-family: 'Segoe UI', Tahoma, sans-serif;
    font-size: 9.5pt;
    line-height: 1.45;
    margin: 8px;
    padding: 0;
    word-wrap: break-word;
    border-top: 1px solid $BorderHex;
  }
  a { color: $LinkHex; text-decoration: none; }
  a:hover { text-decoration: underline; }
  img { max-width: 100%; height: auto; }
  h1, h2, h3, h4 { margin: 8px 0 4px 0; font-size: 10.5pt; }
  p { margin: 0 0 8px 0; }
  ul, ol { margin: 4px 0 8px 18px; padding: 0; }
</style>
</head>
<body>$BodyContent</body>
</html>
"@

    $WebPreviewSummary.DocumentText = $StyledDoc
}

# Highlight Subscribed Rows dynamically based on Theme & Subscription Status

function Apply-SubscribedRowHighlights {
    if ($script:CurrentTheme -eq "Dark") {
        $SubBack = [System.Drawing.Color]::FromArgb(26, 64, 44)
        $SubFore = [System.Drawing.Color]::FromArgb(167, 243, 208)
    } else {
        $SubBack = [System.Drawing.Color]::FromArgb(220, 252, 231)
        $SubFore = [System.Drawing.Color]::FromArgb(20, 83, 45)
    }
    foreach ($Row in $Grid.Rows) {
        $RowModId = [int]$Row.Cells["ModID"].Value
        $IsSub = $script:SubscribedIds.Contains($RowModId)
        $IsBlackListed = $script:ModBlackListIds.Contains($RowModId)

        if ($IsSub) { $statusModtext = " Subscribed" } else { $statusModtext = "" }
        if ($IsSub -and $IsBlackListed) { $statusModtext += "`n" }
        if ($IsBlackListed) { $statusModtext += "    Broken" }

        $Row.Cells["Status"].Value = $statusModtext

        if ($IsSub) {
            $Row.DefaultCellStyle.BackColor = $SubBack
            $Row.DefaultCellStyle.ForeColor = $SubFore
        } else {
            $Row.DefaultCellStyle.BackColor = [System.Drawing.Color]::Empty
            $Row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Empty
        }
    }
    $Grid.Refresh()
}

# Helper to switch active image or video in main preview frame

function Set-ActiveMediaItem {
    param (
        [string]$ThumbUrl,
        [string]$TargetUrl,
        [bool]$IsVideo
    )

    $script:ActiveMediaUrl = $TargetUrl
    $script:ActiveIsVideo  = $IsVideo
    $PicMainMedia.Image    = Get-CachedModImage -ImageUrl $ThumbUrl
    if (-not [string]::IsNullOrWhiteSpace($TargetUrl)) {
        $BtnOpenMedia.Visible = $true
        if ($IsVideo) {
            $BtnOpenMedia.Text      = "Watch Video on YouTube (Opens Browser)"
            $BtnOpenMedia.BackColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
            $BtnOpenMedia.ForeColor = [System.Drawing.Color]::White
        } else {
            $BtnOpenMedia.Text      = "Open Image"
            if ($script:CurrentTheme -eq "Dark") {
                $BtnOpenMedia.BackColor = [System.Drawing.Color]::FromArgb(52, 58, 69)
                $BtnOpenMedia.ForeColor = [System.Drawing.Color]::FromArgb(236, 240, 246)
            } else {
                $BtnOpenMedia.BackColor = [System.Drawing.Color]::FromArgb(236, 240, 246)
                $BtnOpenMedia.ForeColor = [System.Drawing.Color]::FromArgb(30, 34, 42)
            }
        }
    } else {
        $BtnOpenMedia.Visible = $false
    }
}

# Helper to update Preview Panel with all images and videos

function Update-PreviewPanel {
    param ([PSCustomObject]$ModObj)

    $MediaStrip.Controls.Clear()

    if (-not $ModObj) {
        $PicMainMedia.Image = $null
        $BtnOpenMedia.Visible = $false
        $LblMediaCount.Text = ""
        $LblPreviewTitle.Text = "Select a mod to view its images, videos, and summary"
        $LblPreviewMeta.Text = ""
        Set-PreviewHtmlContent -RawHtml ""
        return
    }

    $SubTag = if ($script:SubscribedIds.Contains([int]$ModObj.ModID)) { " [SUBSCRIBED]" } else { "" }
    $LblPreviewTitle.Text = "$($ModObj.Name) (ID: $($ModObj.ModID))$SubTag"

    [string]$moddate_updated_display=[DateTimeOffset]::FromUnixTimeSeconds($ModObj.date_updated).LocalDateTime.ToString("MMM d, yyyy")
    [string]$moddate_added_display=[DateTimeOffset]::FromUnixTimeSeconds($ModObj.date_added).LocalDateTime.ToString("MMM d, yyyy")

    $LblPreviewMeta.Text  = "By $($ModObj.Author)  |  $($ModObj.Size_MB) MB  |  $($ModObj.Downloads) downloads`nTags: $($ModObj.Tags)`nLast Updated: $moddate_updated_display  |  Added: $moddate_added_display"
    $HtmlText = if (-not [string]::IsNullOrWhiteSpace($ModObj.DescriptionHtml)) {
        $ModObj.DescriptionHtml
    } elseif (-not [string]::IsNullOrWhiteSpace($ModObj.Summary)) {
        [System.Net.WebUtility]::HtmlEncode($ModObj.Summary) -replace "`r?`n", "<br/>"
    } else {
        ""
    }

    Set-PreviewHtmlContent -RawHtml $HtmlText

    $MediaItems = @()

    if (-not [string]::IsNullOrWhiteSpace($ModObj.LogoThumb)) {
        $MediaItems += [PSCustomObject]@{
            Type      = "Logo"
            ThumbUrl  = $ModObj.LogoThumb
            TargetUrl = $ModObj.LogoFull
            IsVideo   = $false
        }
    }

    foreach ($ImgEntry in $ModObj.GalleryImages) {
        $MediaItems += [PSCustomObject]@{
            Type      = "Image"
            ThumbUrl  = $ImgEntry.Thumb
            TargetUrl = $ImgEntry.Full
            IsVideo   = $false
        }
    }

    foreach ($YtEntry in $ModObj.YouTubeVideos) {
        $RawYt = if ($YtEntry -is [string]) {
            $YtEntry
        } elseif ($YtEntry.youtube) {
            [string]$YtEntry.youtube
        } elseif ($YtEntry.url) {
            [string]$YtEntry.url
        } else {
            [string]$YtEntry
        }

        $VidId = $null
        $RegexFull = [regex]::Match($RawYt, '(?:v=|youtu\.be/|embed/|shorts/)([a-zA-Z0-9_-]{11})')
        if ($RegexFull.Success) {
            $VidId = $RegexFull.Groups[1].Value
        }
        else 
        {
            $RegexRaw = [regex]::Match($RawYt.Trim(), '^([a-zA-Z0-9_-]{11})$')
            if ($RegexRaw.Success) {
                $VidId = $RegexRaw.Groups[1].Value
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($VidId)) {
            $YtThumb  = "https://img.youtube.com/vi/$VidId/0.jpg"
            $WatchUrl = "https://www.youtube.com/watch?v=$VidId"
            $MediaItems += [PSCustomObject]@{
                Type      = "Video"
                ThumbUrl  = $YtThumb
                TargetUrl = $WatchUrl
                IsVideo   = $true
            }
        }
    }

    $ImgTotal = @($MediaItems | Where-Object { -not $_.IsVideo }).Count
    $VidTotal = @($MediaItems | Where-Object { $_.IsVideo }).Count
    $LblMediaCount.Text = "$ImgTotal image(s), $VidTotal video(s)"

    if ($MediaItems.Count -gt 0) {
        $First = $MediaItems[0]
        Set-ActiveMediaItem -ThumbUrl $First.ThumbUrl -TargetUrl $First.TargetUrl -IsVideo ([bool]$First.IsVideo)
    } 
    else 
    {
        $PicMainMedia.Image = $null
        $BtnOpenMedia.Visible = $false
        $script:ActiveMediaUrl = ""
    }

    $dialog = info-dialog
    $currentCount = 1
    foreach ($Item in $MediaItems) {
        $ThumbContainer = New-Object System.Windows.Forms.Panel
        $ThumbContainer.Size = New-Object System.Drawing.Size(114, 62)
        $ThumbContainer.Margin = New-Object System.Windows.Forms.Padding(3,0,3,0)
        $ThumbContainer.BackColor = if ($Item.IsVideo) { [System.Drawing.Color]::FromArgb(220, 38, 38) } else { [System.Drawing.Color]::FromArgb(140, 148, 160) }
        $ThumbContainer.Padding = New-Object System.Windows.Forms.Padding(2)
        $ThumbBox = New-Object System.Windows.Forms.PictureBox
        $ThumbBox.Dock = "Fill"
        $ThumbBox.SizeMode = "Zoom"
        $ThumbBox.BackColor = [System.Drawing.Color]::Black
        $ThumbBox.Cursor = [System.Windows.Forms.Cursors]::Hand
        $ThumbBox.Image = Get-CachedModImage -ImageUrl $Item.ThumbUrl -dialog $dialog -currentcount $currentCount -totalCount $MediaItems.Count
        $ThumbBox.Tag = $Item
        if ($Item.IsVideo) {
            $Badge = New-Object System.Windows.Forms.Label
            $Badge.Text = "VIDEO"
            $Badge.AutoSize = $true
            $Badge.BackColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
            $Badge.ForeColor = [System.Drawing.Color]::White
            $Badge.Font = New-Object System.Drawing.Font("Segoe UI", 6.5, [System.Drawing.FontStyle]::Bold)
            $Badge.Location = New-Object System.Drawing.Point(2, 2)
            $ThumbBox.Controls.Add($Badge)
        }

        $ThumbBox.Add_Click({
            param($Sender, $EventArgs)
            $Clicked = $Sender.Tag
            Set-ActiveMediaItem -ThumbUrl $Clicked.ThumbUrl -TargetUrl $Clicked.TargetUrl -IsVideo ([bool]$Clicked.IsVideo)

            $Container = $Sender.Parent
            $Strip = $Container.Parent
            if ($Strip -and $Strip.Controls.Count -gt 0) {
                $Idx = $Strip.Controls.IndexOf($Container)
                $VisibleWidth = $Strip.ClientSize.Width

                # Check if the clicked thumbnail is the rightmost visible item (or partially cut off on the right)
                if (($Container.Right + $Container.Margin.Right) -ge ($VisibleWidth - 15)) {
                    if ($Idx -lt ($Strip.Controls.Count - 1)) {
                        $Strip.ScrollControlIntoView($Strip.Controls[$Idx + 1])
                    } else {
                        $Strip.ScrollControlIntoView($Container)
                    }
                }
                # Check if the clicked thumbnail is the leftmost visible item (or partially cut off on the left)
                elseif (($Container.Left - $Container.Margin.Left) -le 15) {
                    if ($Idx -gt 0) {
                        $Strip.ScrollControlIntoView($Strip.Controls[$Idx - 1])
                    } else {
                        $Strip.ScrollControlIntoView($Container)
                    }
                }
            }
        })

        $ThumbContainer.Controls.Add($ThumbBox)
        $MediaStrip.Controls.Add($ThumbContainer)
        [System.Windows.Forms.Application]::DoEvents()
        $currentCount += 1
    }
    $dialog.Label.Text = "Finished"
}

# Renders a specific $global:ManagerConfig.modioPageDisplayLimit mod slice from $script:AllFetchedMods into the DataGridView

function Show-ModPage {
    param ([int]$PageNumber)
    $script:IsLoadingThumbs = $false
    $TotalCount = @($script:AllFetchedMods).Count
    if ($TotalCount -eq 0) {
        $script:CurrentPage     = 0
        $script:TotalPages      = 0
        $script:CurrentPageMods = @()
        $Grid.DataSource        = $null
        $LblPageInfo.Text       = "Page 0 of 0"
        $BtnPrevPage.Enabled    = $false
        $BtnNextPage.Enabled    = $false
        Update-PreviewPanel -ModObj $null
        return
    }

    $script:TotalPages  = [int][math]::Ceiling($TotalCount / $global:ManagerConfig.modioPageDisplayLimit)
    $script:CurrentPage = [Math]::Max(1, [Math]::Min($PageNumber, $script:TotalPages))
    $StartIndex = ($script:CurrentPage - 1) * $global:ManagerConfig.modioPageDisplayLimit
    $EndIndex   = [Math]::Min($StartIndex + $global:ManagerConfig.modioPageDisplayLimit - 1, $TotalCount - 1)
    $PageSlice  = @($script:AllFetchedMods[$StartIndex..$EndIndex])

    Update-PageDropdown -CurrentPage $script:CurrentPage -TotalPages $script:TotalPages

    $BtnPrevPage.Enabled = ($script:CurrentPage -gt 1)
    $BtnNextPage.Enabled = ($script:CurrentPage -lt $script:TotalPages)
    $Table = New-Object System.Data.DataTable
    [void]$Table.Columns.Add("Status", [string])
    [void]$Table.Columns.Add("ModID", [int])
    [void]$Table.Columns.Add("Image", [System.Drawing.Image])
    [void]$Table.Columns.Add("Name", [string])
    [void]$Table.Columns.Add("Author", [string])
    [void]$Table.Columns.Add("Tags", [string])
    [void]$Table.Columns.Add("Size_MB", [double])
    [void]$Table.Columns.Add("Downloads", [int])

    $script:CurrentPageMods = @()

    foreach ($Mod in $PageSlice) {
        $TagList    = ($Mod.tags | ForEach-Object { $_.name }) -join ", "
        $SizeMB     = if ($Mod.modfile.filesize) { [math]::Round($Mod.modfile.filesize / 1MB, 2) } else { 0 }

        $IsSub = $script:SubscribedIds.Contains([int]$Mod.id)
        $IsBlackListed = $script:ModBlackListIds.Contains([int]$Mod.id)

        if ($IsSub) { $StatusText = " Subscribed" } else { $statusModtext = "" }
        if ($IsSub -and $IsBlackListed) { $StatusText += "`n" }
        if ($IsBlackListed) { $StatusText += "    Broken" }

        $LogoThumb = if ($Mod.logo.thumb_320x180) { $Mod.logo.thumb_320x180 } else { $Mod.logo.original }
        $LogoFull  = if ($Mod.logo.original) { $Mod.logo.original } else { $LogoThumb }
        $Gallery = @()
        if ($Mod.media -and $Mod.media.images) {
            foreach ($Img in $Mod.media.images) {
                $TUrl = if ($Img.thumb_320x180) { $Img.thumb_320x180 } else { $Img.original }
                $FUrl = if ($Img.original) { $Img.original } else { $TUrl }
                if (-not [string]::IsNullOrWhiteSpace($TUrl)) {
                    $Gallery += [PSCustomObject]@{ Thumb = $TUrl; Full = $FUrl }
                }
            }
        }

        $Videos = @()
        if ($Mod.media -and $Mod.media.youtube) {
            $Videos = @($Mod.media.youtube)
        }
        $ModObj = [PSCustomObject]@{
            ModID         = $Mod.id
            Name          = $Mod.name
            Author        = $Mod.submitted_by.username
            Tags          = $TagList
            Size_MB       = $SizeMB
            Downloads     = $Mod.stats.downloads_total
            Summary       = $Mod.summary
            DescriptionHtml = $Mod.description
            LogoThumb     = $LogoThumb
            LogoFull      = $LogoFull
            GalleryImages = $Gallery
            YouTubeVideos = $Videos
            DownloadUrl   = $Mod.modfile.download.binary_url
            Filename      = $Mod.modfile.filename
            FileID        = $Mod.modfile.id
            date_updated  = $Mod.date_updated
            date_added    = $Mod.date_added
        }
        $script:CurrentPageMods += $ModObj
        $InitialThumb = if ($LogoThumb -and $script:ImageCache.ContainsKey($LogoThumb)) {
            $script:ImageCache[$LogoThumb]
        } else {
            $script:PlaceholderImg
        }
        [void]$Table.Rows.Add(
            [string]$StatusText,
            [int]$ModObj.ModID,
            $InitialThumb,
            [string]$ModObj.Name,
            [string]$ModObj.Author,
            [string]$ModObj.Tags,
            [double]$ModObj.Size_MB,
            [int]$ModObj.Downloads
        )
    }

    $Grid.DataSource = $Table
    $Grid.Columns["Status"].DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True

    if ($script:GridRightClickHandler) {
        $Grid.remove_CellMouseUp($script:GridRightClickHandler)
    }

    $script:GridRightClickHandler = {
        param($sender, $e)

        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right -and $e.RowIndex -ge 0) {
        
            $sender.ClearSelection()
            $sender.Rows[$e.RowIndex].Selected = $true

            $Row     = $sender.Rows[$e.RowIndex]
            $ModID   = [int]$Row.Cells["ModID"].Value
            $ModName = [string]$Row.Cells["Name"].Value

            $IsBlackListed = $script:ModBlackListIds.Contains($ModID)

            if ($IsBlackListed) {
                $UserChoice = User-Confirm -title "Remove from Blacklist" -infoMessage "Remove '$ModName' (ID: $ModID) from the blacklist?"

                if ($UserChoice -eq "Yes") {
                    [void]$script:ModBlackListIds.Remove($ModID)
                    Save-ModBlackList -ModID $ModID -Action "Remove"

                    $IsSub = $script:SubscribedIds.Contains($ModID)
                    $Row.Cells["Status"].Value = if ($IsSub) { " Subscribed" } else { "" }
                }
            }
            else {
                $UserChoice = User-Confirm -title "Add to Blacklist" -infoMessage "Add '$ModName' (ID: $ModID) to the blacklist?"

                if ($UserChoice -eq "Yes") {
                    [void]$script:ModBlackListIds.Add($ModID)
                    Save-ModBlackList -ModID $ModID -ModName $ModName -Action "Add"

                    $IsSub = $script:SubscribedIds.Contains($ModID)
                    $NewStatus = if ($IsSub) { " Subscribed`n    Broken" } else { "    Broken" }
                    $Row.Cells["Status"].Value = $NewStatus
                }
            }
        }
    }

    $Grid.Add_CellMouseUp($script:GridRightClickHandler)

    if ($Grid.Columns["Image"]) {
        $Grid.Columns["Image"].ImageLayout  = [System.Windows.Forms.DataGridViewImageCellLayout]::Zoom
        $Grid.Columns["Image"].AutoSizeMode = "None"
        $Grid.Columns["Image"].Width        = 100
    }
    if ($Grid.Columns["Status"])    { $Grid.Columns["Status"].FillWeight    = 58 }
    if ($Grid.Columns["ModID"])     { $Grid.Columns["ModID"].FillWeight     = 45 }
    if ($Grid.Columns["Name"])      { $Grid.Columns["Name"].FillWeight      = 130 }
    if ($Grid.Columns["Author"])    { $Grid.Columns["Author"].FillWeight    = 80 }
    if ($Grid.Columns["Tags"])      { $Grid.Columns["Tags"].FillWeight      = 115 }
    if ($Grid.Columns["Size_MB"])   { $Grid.Columns["Size_MB"].FillWeight   = 50 }
    if ($Grid.Columns["Downloads"]) { $Grid.Columns["Downloads"].FillWeight = 60 }
    Apply-SubscribedRowHighlights
    if ($script:CurrentPageMods.Count -gt 0) {
        Update-PreviewPanel -ModObj $script:CurrentPageMods[0]
    } else {
        Update-PreviewPanel -ModObj $null
    }
    $MatchedSubs = @($script:AllFetchedMods | Where-Object { $script:SubscribedIds.Contains([int]$_.id) }).Count
    $LblStatus.Text = "Page $($script:CurrentPage) of $($script:TotalPages): Showing mods $($StartIndex + 1)–$($EndIndex + 1) of $TotalCount ($MatchedSubs subscribed | Catalog total: $($script:MasterCatalog.Count))."

    # Progressively load thumbnails for the $global:ManagerConfig.modioPageDisplayLimit rows on this page

    $dialog = info-dialog
    $PageToken = $script:CurrentPage
    $script:IsLoadingThumbs = $true
    $currentCount = 1
    for ($i = 0; $i -lt $Table.Rows.Count; $i++) {
        if (-not $script:IsLoadingThumbs -or $script:CurrentPage -ne $PageToken) { break }
        $ModItem = $script:CurrentPageMods[$i]
        if (-not [string]::IsNullOrWhiteSpace($ModItem.LogoThumb)) {
            $FetchedImg = Get-CachedModImage -ImageUrl $ModItem.LogoThumb -dialog $dialog -currentcount $currentCount -totalCount $Table.Rows.Count
            if ($FetchedImg -and $script:CurrentPage -eq $PageToken) {
                $Table.Rows[$i]["Image"] = $FetchedImg
            }
        }
        [System.Windows.Forms.Application]::DoEvents()
        $currentCount += 1
    }
    $dialog.Label.Text = "Finished"
    $script:IsLoadingThumbs = $false
    $Grid.ClearSelection()
}

# Local In-Memory Filter Function (runs instantaneously against $script:MasterCatalog)

function Invoke-LocalCatalogSearch {
    $Filtered = @($script:MasterCatalog)
    $NameTerm = $TxtName.Text.Trim()

    if (-not [string]::IsNullOrWhiteSpace($NameTerm)) {
        $Filtered = @($Filtered | Where-Object { $_.name -like "*$NameTerm*" })
    }

    $AuthorTerm = $TxtAuthor.Text.Trim()

    if (-not [string]::IsNullOrWhiteSpace($AuthorTerm)) {
        $Filtered = @($Filtered | Where-Object { $_.submitted_by.username -like "*$AuthorTerm*" })
    }

    if ($ChkTags.CheckedItems.Count -gt 0) {
        $SelectedTags = @($ChkTags.CheckedItems | ForEach-Object { $_.ToString().ToLower() })
        $Filtered = @($Filtered | Where-Object {
            $ModTags = @($_.tags | ForEach-Object { $_.name.ToLower() })
            $HasAll = $true
            foreach ($ReqTag in $SelectedTags) {
                if ($ModTags -notcontains $ReqTag) {
                    $HasAll = $false
                    break
                }
            }
            $HasAll
        })
    }

    $script:AllFetchedMods = @($Filtered)
    Show-ModPage -PageNumber 1
}

function Load-UserProfiles {
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

    [string]$OAuthToken=$getuserjson.Oauth.token
    $UserID=$getuserjson.Profile.username

    $script:UserProfiles += [PSCustomObject]@{
        DisplayName = $UserID
        FilePath    = $File.FullName
        Token       = $OAuthToken
    }
}

function Get-SelectedModObjects {
    if ($Grid.SelectedRows.Count -eq 0) {
        New_MessageBox -title "No Selection" -infoMessage "Please select one or more mods in the table first."
        return @()
    }
    $SelectedIds = @()
    foreach ($Row in $Grid.SelectedRows) {
        $SelectedIds += [int]$Row.Cells["ModID"].Value
    }
    return @($script:CurrentPageMods | Where-Object { $SelectedIds -contains $_.ModID })
}


function Save-ModBlackList {
    param(
        [int]$ModID,
        [string]$ModName = "",
        [ValidateSet("Add", "Remove")]
        [string]$Action
    )

    $ModBlacklistPath = Join-Path $PSScriptRoot "config\ModBlackList.json"

    # Load existing JSON object, or start a fresh one if the file is missing/empty
    if (Test-Path $ModBlacklistPath) {
        $RawJson = Get-Content -Path $ModBlacklistPath -Raw
        $JsonObj = if ([string]::IsNullOrWhiteSpace($RawJson)) { [PSCustomObject]@{} } else { $RawJson | ConvertFrom-Json }
    } else {
        $JsonObj = [PSCustomObject]@{}
    }

    $Key = [string]$ModID

    if ($Action -eq "Add") {
        # Add the ID as a top-level property if it doesn't already exist
        if (-not $JsonObj.PSObject.Properties[$Key]) {
            $Entry = [PSCustomObject]@{ name = $ModName }
            $JsonObj | Add-Member -MemberType NoteProperty -Name $Key -Value $Entry
        }
    }
    elseif ($Action -eq "Remove") {
        # Remove the ID property if it exists
        if ($JsonObj.PSObject.Properties[$Key]) {
            $JsonObj.PSObject.Properties.Remove($Key)
        }
    }

    # Ensure directory exists and save formatted JSON back to disk
    $ParentDir = Split-Path -Path $ModBlacklistPath -Parent
    if (-not (Test-Path $ParentDir)) {
        [void](New-Item -ItemType Directory -Path $ParentDir -Force)
    }

    $JsonObj | ConvertTo-Json -Depth 5 | Set-Content -Path $ModBlacklistPath -Encoding UTF8
}

function modio-browser
{
    # Configuration

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
    $destinationMods="$destination"+"254\mods\"

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

    [string]$script:OAuthToken=$getuserjson.Oauth.token
    $UserID=$getuserjson.Profile.username

    # Configuration
    # $BaseUrl          = "https://api.mod.io/v1" # Deprecated

    $CatalogCachePath = Join-Path $PSScriptRoot "config\sandstorm_catalog.json"
    $ImageCacheDir    = Join-Path $PSScriptRoot "image_cache"
    if (-not (Test-Path $ImageCacheDir)) {
        New-Item -ItemType Directory -Path $ImageCacheDir -Force | Out-Null
    }
    $GameId           = 254  # Insurgency: Sandstorm
    $DownloadFolder   = Join-Path $PSScriptRoot "zip"
    $CacheMaxHours    = 24   # Auto-refresh disk cache if older than this many hours
    $ApiFetchLimit    = 100  # mod.io API page size
    $DefaultTheme     = $global:ManagerConfig.DefaultTheme # Options: "Light" or "Dark"
    $BaseUrl          = "https://g-$GameId.modapi.io/v1"
    $script:UserProfiles = @()

    $AcceptedTags = @(
        "checkpoint",
        "outpost",
        "push",
        "frontline",
        "firefight",
        "team deathmatch",
        "domination",
        "total conversion",
        "custom theater",
        "game mode",
        "mutator",
        "2020 mapping contest"
    )

    # Ensure the .NET WinForms classes are loaded

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    if ($OAuthToken -eq "YOUR_OAUTH_ACCESS_TOKEN_HERE" -or [string]::IsNullOrWhiteSpace($OAuthToken)) {
        New_MessageBox -title "Missing OAuth Token" -infoMessage "You Mod.io OAuth Token is missing, invalid or revoked."
        exit
    }

    $script:MasterCatalog    = @() # Complete downloaded catalog of all Insurgency: Sandstorm mods
    $script:AllFetchedMods   = @() # Current filtered slice shown in pagination
    $script:CurrentPageMods  = @() # Active 25 mods on screen
    $script:CurrentPage      = 1
    $script:TotalPages       = 1
    $script:SubscribedIds    = [System.Collections.Generic.HashSet[int]]::new()
    $script:ModBlackListIds  = [System.Collections.Generic.HashSet[int]]::new()
    $script:ImageCache       = @{}
    $script:ActiveMediaUrl   = ""
    $script:ActiveIsVideo    = $false
    $script:CurrentTheme     = $DefaultTheme
    $script:IsLoadingThumbs  = $false

    $script:PlaceholderImg = New-Object System.Drawing.Bitmap(96, 54)

    # Read and parse the JSON file for IDs
    $ModPlacklistPath = Join-Path $PSScriptRoot "config\ModBlackList.json"
    $BlackListData = Get-Content -Path $ModPlacklistPath -Raw | ConvertFrom-Json

    # Loop through the top-level property names (the Mod IDs) and add them as integers
    foreach ($id in $BlackListData.PSObject.Properties.Name) {
        [void]$script:ModBlackListIds.Add([int]$id)
    }

    # Main Window Container

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Insurgency: Sandstorm Mod.io Mod Browser"
    $Form.Size = New-Object System.Drawing.Size(1340, 800)
    $Form.MinimumSize = New-Object System.Drawing.Size(1080, 640)
    $Form.StartPosition = "CenterScreen"
    $Form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    # Top Panel: Search, Tags, Mode Buttons, and Theme Toggle

    $TopPanel = New-Object System.Windows.Forms.Panel
    $TopPanel.Dock = "Top"
    $TopPanel.Height = 165
    $TopPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    $Form.Controls.Add($TopPanel)

    $TopBorder = New-Object System.Windows.Forms.Panel
    $TopBorder.Dock = "Bottom"
    $TopBorder.Height = 1
    $TopPanel.Controls.Add($TopBorder)

    # Mod Name Input

    $LblName = New-Object System.Windows.Forms.Label
    $LblName.Text = "Mod Name (instant local filter):"
    $LblName.Location = New-Object System.Drawing.Point(15, 14)
    $LblName.AutoSize = $true
    $TopPanel.Controls.Add($LblName)

    $TxtName = New-Object System.Windows.Forms.TextBox
    $TxtName.Location = New-Object System.Drawing.Point(15, 36)
    $TxtName.Size = New-Object System.Drawing.Size(235, 26)
    $TopPanel.Controls.Add($TxtName)

    # Author Input

    $LblAuthor = New-Object System.Windows.Forms.Label
    $LblAuthor.Text = "Author Username (instant local filter):"
    $LblAuthor.Location = New-Object System.Drawing.Point(15, 74)
    $LblAuthor.AutoSize = $true
    $TopPanel.Controls.Add($LblAuthor)

    $TxtAuthor = New-Object System.Windows.Forms.TextBox
    $TxtAuthor.Location = New-Object System.Drawing.Point(15, 96)
    $TxtAuthor.Size = New-Object System.Drawing.Size(235, 26)
    $TopPanel.Controls.Add($TxtAuthor)

    # Tags Multi-Select CheckedListBox

    $LblTags = New-Object System.Windows.Forms.Label
    $LblTags.Text = "Accepted Tags (check one or more):"
    $LblTags.Location = New-Object System.Drawing.Point(268, 14)
    $LblTags.AutoSize = $true
    $TopPanel.Controls.Add($LblTags)

    $ChkTags = New-Object System.Windows.Forms.CheckedListBox
    $ChkTags.Location = New-Object System.Drawing.Point(258, 36)
    $ChkTags.Size = New-Object System.Drawing.Size(455, 112)
    $ChkTags.MultiColumn = $true
    $ChkTags.ColumnWidth = 148
    $ChkTags.CheckOnClick = $true
    $ChkTags.Cursor = [System.Windows.Forms.Cursors]::Hand
    foreach ($Tag in $AcceptedTags) {
        [void]$ChkTags.Items.Add($Tag)
    }
    $TopPanel.Controls.Add($ChkTags)

    # Search & Action Buttons

    $BtnSearch = New-Object System.Windows.Forms.Button
    $BtnSearch.Text = "Filter Mods"
    $BtnSearch.Location = New-Object System.Drawing.Point(720, 35)
    $BtnSearch.Size = New-Object System.Drawing.Size(115, 24)
    $BtnSearch.BackColor = [System.Drawing.Color]::FromArgb(0, 112, 224)
    $BtnSearch.ForeColor = [System.Drawing.Color]::White
    $BtnSearch.FlatStyle = "Flat"
    $BtnSearch.FlatAppearance.BorderSize = 0
    $BtnSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $BtnSearch.Cursor = [System.Windows.Forms.Cursors]::Hand
    $TopPanel.Controls.Add($BtnSearch)

    $BtnSubscribed = New-Object System.Windows.Forms.Button
    $BtnSubscribed.Text = "Subscribed"
    $BtnSubscribed.Location = New-Object System.Drawing.Point(720, 62)
    $BtnSubscribed.Size = New-Object System.Drawing.Size(115, 24)
    $BtnSubscribed.FlatStyle = "Flat"
    $BtnSubscribed.Cursor = [System.Windows.Forms.Cursors]::Hand
    $TopPanel.Controls.Add($BtnSubscribed)

    $BtnClearFilters = New-Object System.Windows.Forms.Button
    $BtnClearFilters.Text = "Show All"
    $BtnClearFilters.Location = New-Object System.Drawing.Point(838, 35)
    $BtnClearFilters.Size = New-Object System.Drawing.Size(92, 24)
    $BtnClearFilters.FlatStyle = "Flat"
    $BtnClearFilters.Cursor = [System.Windows.Forms.Cursors]::Hand
    $TopPanel.Controls.Add($BtnClearFilters)

    $BtnRefreshCatalog = New-Object System.Windows.Forms.Button
    $BtnRefreshCatalog.Text = "Refresh List"
    $BtnRefreshCatalog.Location = New-Object System.Drawing.Point(838, 62)
    $BtnRefreshCatalog.Size = New-Object System.Drawing.Size(92, 24)
    $BtnRefreshCatalog.FlatStyle = "Flat"
    $BtnRefreshCatalog.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $BtnRefreshCatalog.Cursor = [System.Windows.Forms.Cursors]::Hand
    $TopPanel.Controls.Add($BtnRefreshCatalog)

    $LblUserProfile = New-Object System.Windows.Forms.Label
    $LblUserProfile.Text = "Select User Profile:"
    $LblUserProfile.Location = New-Object System.Drawing.Point(770, 88)
    $LblUserProfile.AutoSize = $true
    $TopPanel.Controls.Add($LblUserProfile)

    $CmbUserProfile = New-Object System.Windows.Forms.ComboBox
    $CmbUserProfile.Location = New-Object System.Drawing.Point(720, 110)
    $CmbUserProfile.Size = New-Object System.Drawing.Size(207, 24)
    $CmbUserProfile.DropDownStyle = "DropDownList"
    $CmbUserProfile.DisplayMember = "DisplayName"
    $CmbUserProfile.Cursor = [System.Windows.Forms.Cursors]::Hand
    $TopPanel.Controls.Add($CmbUserProfile)

    Load-UserProfiles

    foreach ($Prof in $script:UserProfiles) {
        [void]$CmbUserProfile.Items.Add($Prof)
    }
    if ($CmbUserProfile.Items.Count -gt 0) {
        $CmbUserProfile.SelectedIndex = 0
    }

    $CmbUserProfile.Add_SelectedIndexChanged({
        if ($CmbUserProfile.SelectedItem) {
            Switch-UserProfile -Profile $CmbUserProfile.SelectedItem -StatusLabel $LblStatus
        }
    })

    # Bottom Panel: Action Buttons, Paging Controls & Status Bar

    $BottomPanel = New-Object System.Windows.Forms.Panel
    $BottomPanel.Dock = "Bottom"
    $BottomPanel.Height = 84
    $Form.Controls.Add($BottomPanel)

    $BottomBorder = New-Object System.Windows.Forms.Panel
    $BottomBorder.Dock = "Top"
    $BottomBorder.Height = 1
    $BottomPanel.Controls.Add($BottomBorder)

    $BtnCopyIds = New-Object System.Windows.Forms.Button
    $BtnCopyIds.Text = "Copy ID(s)"
    $BtnCopyIds.Location = New-Object System.Drawing.Point(12, 12)
    $BtnCopyIds.Size = New-Object System.Drawing.Size(95, 32)
    $BtnCopyIds.FlatStyle = "Flat"
    $BottomPanel.Controls.Add($BtnCopyIds)

    $BtnSubscribe = New-Object System.Windows.Forms.Button
    $BtnSubscribe.Text = "Subscribe"
    $BtnSubscribe.Location = New-Object System.Drawing.Point(114, 12)
    $BtnSubscribe.Size = New-Object System.Drawing.Size(90, 32)
    $BtnSubscribe.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $BtnSubscribe.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
    $BtnSubscribe.FlatStyle = "Flat"
    $BottomPanel.Controls.Add($BtnSubscribe)

    $BtnUnsubscribe = New-Object System.Windows.Forms.Button
    $BtnUnsubscribe.Text = "Unsubscribe"
    $BtnUnsubscribe.Location = New-Object System.Drawing.Point(211, 12)
    $BtnUnsubscribe.Size = New-Object System.Drawing.Size(100, 32)
    $BtnUnsubscribe.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $BtnUnsubscribe.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
    $BtnUnsubscribe.FlatStyle = "Flat"
    $BottomPanel.Controls.Add($BtnUnsubscribe)

    $CmbDisplaySelect = New-Object System.Windows.Forms.ComboBox
    $CmbDisplaySelect.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $CmbDisplaySelect.Location = New-Object System.Drawing.Point(395, 14)
    $CmbDisplaySelect.Size = New-Object System.Drawing.Size(125, 32)
    $CmbDisplaySelect.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $BottomPanel.Controls.Add($CmbDisplaySelect)

    $CmbDisplaySelect.Items.Clear()

    for ($i = 25; $i -le 100; $i += 5) {
        [void]$CmbDisplaySelect.Items.Add("Display $i")
    }
    [void]$CmbDisplaySelect.Items.Add("Display ALL")

    # Determine the target string based on the saved config
    $targetItem = if ($global:ManagerConfig.modioPageDisplayLimit -eq 2000) {
        "Display ALL"
    } else {
        "Display $($global:ManagerConfig.modioPageDisplayLimit)"
    }

    # Select the matching item if it exists, otherwise default to the first item (index 0)
    if ($CmbDisplaySelect.Items.Contains($targetItem)) {
        $CmbDisplaySelect.SelectedItem = $targetItem
    } else {
        $CmbDisplaySelect.SelectedIndex = 0
    }

    $CmbDisplaySelect.Add_SelectedIndexChanged({
        $selectedPageDisplayLimit = $CmbDisplaySelect.SelectedItem -replace '^Display ', ''

        if ($selectedPageDisplayLimit -eq "ALL")
        {
            $selectedPageDisplayLimit = 2000
        }

        $global:ManagerConfig.modioPageDisplayLimit = $selectedPageDisplayLimit
        $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath

        Show-ModPage -PageNumber 1
    })

    $BtnPrevPage = New-Object System.Windows.Forms.Button
    $BtnPrevPage.Text = "< Prev"
    $BtnPrevPage.Location = New-Object System.Drawing.Point(590, 12)
    $BtnPrevPage.Size = New-Object System.Drawing.Size(80, 32)
    $BtnPrevPage.FlatStyle = "Flat"
    $BtnPrevPage.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $BtnPrevPage.Enabled = $false
    $BtnPrevPage.Cursor = [System.Windows.Forms.Cursors]::Hand
    $BottomPanel.Controls.Add($BtnPrevPage)

    $CmbPageSelect = New-Object System.Windows.Forms.ComboBox
    $CmbPageSelect.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $CmbPageSelect.Location = New-Object System.Drawing.Point(690, 14)
    $CmbPageSelect.Size = New-Object System.Drawing.Size(125, 32)
    $CmbPageSelect.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $BottomPanel.Controls.Add($CmbPageSelect)

    $CmbPageSelect.Add_SelectedIndexChanged({
        if ($script:IsUpdatingPageDropdown) { return }

        if ($CmbPageSelect.SelectedIndex -ge 0 -and $CmbPageSelect.SelectedItem -ne "Page 0 of 0") {
            $selectedPage = $CmbPageSelect.SelectedIndex + 1
            Show-ModPage -PageNumber $selectedPage
        }
    })

    $BtnNextPage = New-Object System.Windows.Forms.Button
    $BtnNextPage.Text = "Next >"
    $BtnNextPage.Location = New-Object System.Drawing.Point(835, 12)
    $BtnNextPage.Size = New-Object System.Drawing.Size(80, 32)
    $BtnNextPage.FlatStyle = "Flat"
    $BtnNextPage.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $BtnNextPage.Enabled = $false
    $BtnNextPage.Cursor = [System.Windows.Forms.Cursors]::Hand
    $BottomPanel.Controls.Add($BtnNextPage)

    $LblStatus = New-Object System.Windows.Forms.Label
    $LblStatus.Text = "Initializing connection to $BaseUrl..."
    $LblStatus.Location = New-Object System.Drawing.Point(12, 54)
    $LblStatus.Size = New-Object System.Drawing.Size(1280, 20)
    $BottomPanel.Controls.Add($LblStatus)

    # Right Preview Panel: All Images, Videos & Summary

    $PreviewPanel = New-Object System.Windows.Forms.Panel
    $PreviewPanel.Dock = "Right"
    $PreviewPanel.Width = 390
    $Form.Controls.Add($PreviewPanel)

    $PreviewLeftBorder = New-Object System.Windows.Forms.Panel
    $PreviewLeftBorder.Dock = "Left"
    $PreviewLeftBorder.Width = 1
    $PreviewPanel.Controls.Add($PreviewLeftBorder)

    $LblPreviewHeader = New-Object System.Windows.Forms.Label
    $LblPreviewHeader.Text = "Mod Media Gallery & Summary"
    $LblPreviewHeader.Location = New-Object System.Drawing.Point(16, 10)
    $LblPreviewHeader.Size = New-Object System.Drawing.Size(205, 22)
    $LblPreviewHeader.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $PreviewPanel.Controls.Add($LblPreviewHeader)

    $LblMediaCount = New-Object System.Windows.Forms.Label
    $LblMediaCount.Text = ""
    $LblMediaCount.TextAlign = "MiddleRight"
    $LblMediaCount.Location = New-Object System.Drawing.Point(220, 10)
    $LblMediaCount.Size = New-Object System.Drawing.Size(154, 22)
    $LblMediaCount.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $PreviewPanel.Controls.Add($LblMediaCount)

    $PicMainMedia = New-Object System.Windows.Forms.PictureBox
    $PicMainMedia.Location = New-Object System.Drawing.Point(16, 36)
    $PicMainMedia.Size = New-Object System.Drawing.Size(358, 201)
    $PicMainMedia.SizeMode = "Zoom"
    $PicMainMedia.BorderStyle = "FixedSingle"
    $PicMainMedia.Cursor = [System.Windows.Forms.Cursors]::Hand
    $PreviewPanel.Controls.Add($PicMainMedia)

    $BtnOpenMedia = New-Object System.Windows.Forms.Button
    $BtnOpenMedia.Text = "Open Full Image in Browser"
    $BtnOpenMedia.Location = New-Object System.Drawing.Point(16, 242)
    $BtnOpenMedia.Size = New-Object System.Drawing.Size(358, 26)
    $BtnOpenMedia.FlatStyle = "Flat"
    $BtnOpenMedia.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $BtnOpenMedia.Visible = $false
    $PreviewPanel.Controls.Add($BtnOpenMedia)

    $BtnOpenMedia.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($script:ActiveMediaUrl)) {
            Show-MediaInGui -Url $script:ActiveMediaUrl
        }
    })

    $PicMainMedia.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($script:ActiveMediaUrl)) {
            Show-MediaInGui -Url $script:ActiveMediaUrl
        }
    })

    $MediaStrip = New-Object System.Windows.Forms.FlowLayoutPanel
    $MediaStrip.Location = New-Object System.Drawing.Point(16, 273)
    $MediaStrip.Size = New-Object System.Drawing.Size(358, 90)
    $MediaStrip.AutoScroll = $true
    $MediaStrip.WrapContents = $false
    $MediaStrip.FlowDirection = "LeftToRight"
    $MediaStrip.BorderStyle = "FixedSingle"
    $MediaStrip.Padding = New-Object System.Windows.Forms.Padding(4)
    $PreviewPanel.Controls.Add($MediaStrip)

    $LblPreviewTitle = New-Object System.Windows.Forms.Label
    $LblPreviewTitle.Text = "Select a mod to view its images, videos, and summary"
    $LblPreviewTitle.Location = New-Object System.Drawing.Point(16, 365)
    $LblPreviewTitle.Size = New-Object System.Drawing.Size(358, 38)
    $LblPreviewTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $PreviewPanel.Controls.Add($LblPreviewTitle)

    $LblPreviewMeta = New-Object System.Windows.Forms.Label
    $LblPreviewMeta.Text = ""
    $LblPreviewMeta.Location = New-Object System.Drawing.Point(16, 405)
    $LblPreviewMeta.Size = New-Object System.Drawing.Size(358, 70)
    $LblPreviewMeta.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $PreviewPanel.Controls.Add($LblPreviewMeta)

    $WebPreviewSummary = New-Object System.Windows.Forms.WebBrowser
    $WebPreviewSummary.Location = New-Object System.Drawing.Point(16, 480)
    $WebPreviewSummary.Size = New-Object System.Drawing.Size(358, 270)
    $WebPreviewSummary.Anchor = "Top, Bottom, Left, Right"
    $WebPreviewSummary.AllowWebBrowserDrop = $false
    $WebPreviewSummary.IsWebBrowserContextMenuEnabled = $false
    $WebPreviewSummary.ScriptErrorsSuppressed = $true
    $PreviewPanel.Controls.Add($WebPreviewSummary)

    # Open clicked links inside the mod description in your default external browser

    $WebPreviewSummary.Add_Navigating({
        param($Sender, $EventArgs)
        $TargetUri = $EventArgs.Url.ToString()
        if ($TargetUri -ne "about:blank" -and -not $TargetUri.StartsWith("about:")) {
            $EventArgs.Cancel = $true
            Start-Process $TargetUri
        }
    })

    $script:CurrentSummaryHtml = ""

    # Center DataGridView for Mod Results

    $Grid = New-Object System.Windows.Forms.DataGridView
    $Grid.Dock = "Fill"
    $Grid.BorderStyle = "None"
    $Grid.AllowUserToAddRows = $false
    $Grid.AllowUserToDeleteRows = $false
    $Grid.ReadOnly = $true
    $Grid.SelectionMode = "FullRowSelect"
    $Grid.MultiSelect = $true
    $Grid.RowHeadersVisible = $false
    $Grid.RowTemplate.Height = 58
    $Grid.AutoSizeColumnsMode = "Fill"
    $Grid.EnableHeadersVisualStyles = $false
    $Grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $Grid.ColumnHeadersHeight = 32
    $Form.Controls.Add($Grid)
    $Grid.BringToFront()

    $Grid.Add_DataError({
        param($Sender, $EventArgs)
        $EventArgs.ThrowException = $false
    })

    $Grid.Add_Sorted({
        Apply-SubscribedRowHighlights
    })

    $Grid.Add_SelectionChanged({
        if ($Grid.SelectedRows.Count -gt 0) {
            $TopRow = $Grid.SelectedRows[0]
            $SelectedId = [int]$TopRow.Cells["ModID"].Value
            $MatchedMod = $script:CurrentPageMods | Where-Object { $_.ModID -eq $SelectedId } | Select-Object -First 1
            Update-PreviewPanel -ModObj $MatchedMod
        }
    })

    # Page Back & Page Forward Events

    $BtnPrevPage.Add_Click({
        if ($script:CurrentPage -gt 1) {
            Show-ModPage -PageNumber ($script:CurrentPage - 1)
        }
    })

    $BtnNextPage.Add_Click({
        if ($script:CurrentPage -lt $script:TotalPages) {
        Show-ModPage -PageNumber ($script:CurrentPage + 1)
        }
    })

    # Event: Clear Filters (resets inputs and shows full local catalog)

    $BtnClearFilters.Add_Click({
        $TxtName.Text = ""
        $TxtAuthor.Text = ""
        for ($i = 0; $i -lt $ChkTags.Items.Count; $i++) {
            $ChkTags.SetItemChecked($i, $false)
        }
        Invoke-LocalCatalogSearch
    })

    #Event: Filter Local Catalog

    $BtnSearch.Add_Click({
        Invoke-LocalCatalogSearch
    })

    # Pressing Enter inside Name or Author box triggers instant local search

    $TxtName.Add_KeyDown({
        param($Sender, $EventArgs)

        if ($EventArgs.KeyCode -eq "Enter") {
            $EventArgs.SuppressKeyPress = $true
            Invoke-LocalCatalogSearch
        }
    })

    $TxtAuthor.Add_KeyDown({
        param($Sender, $EventArgs)

        if ($EventArgs.KeyCode -eq "Enter") {
            $EventArgs.SuppressKeyPress = $true
            Invoke-LocalCatalogSearch
        }
    })

    # Event: Show My Subscribed Sandstorm Mods (filtered directly from local catalog)

    $BtnSubscribed.Add_Click({
        $SubList = @($script:MasterCatalog | Where-Object { $script:SubscribedIds.Contains([int]$_.id) })
        $script:AllFetchedMods = @($SubList)
        Show-ModPage -PageNumber 1
    })

    # Event: Force Re-Download ALL Mods from mod.io

    $BtnRefreshCatalog.Add_Click({
        $BtnRefreshCatalog.Enabled = $false
        $BtnSearch.Enabled = $false
        $BtnSubscribed.Enabled = $false
        Sync-SubscribedIds -StatusLabel $LblStatus
        Load-MasterCatalog -ForceRefresh -StatusLabel $LblStatus
        $BtnRefreshCatalog.Enabled = $true
        $BtnSearch.Enabled = $true
        $BtnSubscribed.Enabled = $true
        Invoke-LocalCatalogSearch
    })

    # Event: Copy Selected IDs

    $BtnCopyIds.Add_Click({
        $Selected = Get-SelectedModObjects
        if ($Selected.Count -eq 0) { return }
            $IdList = ($Selected.ModID) -join "`n"
            [System.Windows.Forms.Clipboard]::SetText($IdList)
        $LblStatus.Text = "Copied $($Selected.Count) Mod ID(s) to clipboard."
        New_MessageBox -title "Mod IDs" -infoMessage "Copied $($Selected.Count) Mod ID(s) to clipboard."
    })

    # Event: Subscribe Selected

    $BtnSubscribe.Add_Click({
        $Selected = Get-SelectedModObjects
        if ($Selected.Count -eq 0) { return }

        $Count = 0
        $subedCount = 0
        foreach ($Mod in $Selected) {
            if(-not $script:SubscribedIds.Contains([int]$Mod.ModID))
            {
                $LblStatus.Text = "Subscribing to '$($Mod.Name)'..."
                [System.Windows.Forms.Application]::DoEvents()
                $Res = Invoke-ModioV1 -Endpoint "/games/$GameId/mods/$($Mod.ModID)/subscribe" -Method Post
                if ($Res) {
                    [void]$script:SubscribedIds.Add([int]$Mod.ModID)
                    $Count++
                }
            }
            else
            {
                $subedCount += 1
            }

            # Delay for mod.io api limit
            Start-Sleep -Milliseconds 250
        }

        Apply-SubscribedRowHighlights
        $LblStatus.Text = "Subscribed to $Count selected mod(s) - $subedCount mod(s) already subscribed."
        $global:isNewSubscriptions = $true
        New_MessageBox -title "Mods Subscribed" -infoMessage "Subscribed to $Count selected mod(s)`n`n$subedCount mod(s) already subscribed."
    })

    # Event: Unsubscribe Selected

    $BtnUnsubscribe.Add_Click({
        $Selected = Get-SelectedModObjects
        if ($Selected.Count -eq 0) { return }

        $unsubCount = 0
        $notsubedCount = 0

        foreach ($Mod in $Selected) {

            if($script:SubscribedIds.Contains([int]$Mod.ModID))
            {
                $LblStatus.Text = "Unsubscribing from '$($Mod.Name)'..."
                [System.Windows.Forms.Application]::DoEvents()
                Invoke-ModioV1 -Endpoint "/games/$GameId/mods/$($Mod.ModID)/subscribe" -Method Delete | Out-Null
                [void]$script:SubscribedIds.Remove([int]$Mod.ModID)

                $unsubCount += 1

                # Delay for mod.io api limit
                Start-Sleep -Milliseconds 250
            }
            else
            {
                $notsubedCount += 1
            }
        }

        Apply-SubscribedRowHighlights

        $global:isNewSubscriptions = $true

        $LblStatus.Text = "Unsubscribed from $unsubCount mod(s) - $notsubedCount mod(s) never subscribed."
        New_MessageBox -title "Mods Unsubscribed" -infoMessage "Unsubscribed from $unsubCount mod(s)`n`n$notsubedCount mod(s) never subscribed."
    })

    # Apply initial theme & download full catalog on startup

    Set-ModioBrowserTheme -ThemeName $DefaultTheme

    $Form.Add_Shown({
        [System.Windows.Forms.Application]::DoEvents()
        if ($CmbUserProfile.SelectedItem) {
            Switch-UserProfile -Profile $CmbUserProfile.SelectedItem -StatusLabel $LblStatus
        }
        Load-MasterCatalog -StatusLabel $LblStatus
        Invoke-LocalCatalogSearch
    })

    $form.Add_FormClosing({
        param($sender, $e)
    
        if($global:isNewSubscriptions)
        {
            $global:isNewSubscriptions = $false
            $form.Hide()
            [System.Windows.Forms.Application]::DoEvents()
            Process-Subscriptions
            $form.Close()
        }
    })

    [void]$Form.ShowDialog()

}

# Theme Switcher Function

function Set-CollectionBrowserTheme {
    param ([ValidateSet("Light", "Dark")][string]$ThemeName)

    $Form.BackColor = $global:BgWorkspace
    $Form.ForeColor = $global:FgPrimary
    $TopPanel.BackColor = $global:BgSurface

    foreach ($Lbl in @($LblSearch, $LblCollections, $LblMods)) {
        $Lbl.ForeColor = $global:FgPrimary
    }

    foreach ($Lbl in @($TxtSearch)) {
        $Lbl.ForeColor = $global:FgMuted
    }

    foreach ($SecBtn in @($BtnRefresh, $BtnOpenWeb)) {
        $SecBtn.BackColor = $global:BgSecondary
        $SecBtn.ForeColor = $global:FgPrimary
        $SecBtn.FlatAppearance.BorderColor = $global:BorderColor
    }

    $StatusStrip.BackColor = $global:BgSecondary
    $StatusStrip.ForeColor = $global:FgPrimary

    $SplitContainer.BackColor = $global:BgSecondary
    $SplitContainer.ForeColor = $global:burntStatus

    $btnExit.BackColor = $global:BgSecondary
    $btnExit.ForeColor = $global:ExitForeColor
    $btnExit.FlatAppearance.BorderColor = $global:BorderColor

    $GridCollections.BackgroundColor = $global:BgWorkspace
    $GridCollections.GridColor = $global:BorderColor
    $GridCollections.ColumnHeadersDefaultCellStyle.BackColor = $global:BgHeader
    $GridCollections.ColumnHeadersDefaultCellStyle.ForeColor = $global:FgPrimary
    $GridCollections.DefaultCellStyle.BackColor = $global:BgSurface
    $GridCollections.DefaultCellStyle.ForeColor = $global:FgPrimary
    $GridCollections.DefaultCellStyle.SelectionBackColor = $global:SelBack
    $GridCollections.DefaultCellStyle.SelectionForeColor = $global:SelFore
    $GridCollections.AlternatingRowsDefaultCellStyle.BackColor = $global:BgAltRow

    $GridMods.BackgroundColor = $global:BgWorkspace
    $GridMods.GridColor = $global:BorderColor
    $GridMods.ColumnHeadersDefaultCellStyle.BackColor = $global:BgHeader
    $GridMods.ColumnHeadersDefaultCellStyle.ForeColor = $global:FgPrimary
    $GridMods.DefaultCellStyle.BackColor = $global:BgSurface
    $GridMods.DefaultCellStyle.ForeColor = $global:FgPrimary
    $GridMods.DefaultCellStyle.SelectionBackColor = $global:SelBack
    $GridMods.DefaultCellStyle.SelectionForeColor = $global:SelFore
    $GridMods.AlternatingRowsDefaultCellStyle.BackColor = $global:BgAltRow
}

function Set-ModioBrowserTheme {
    param ([ValidateSet("Light", "Dark")][string]$ThemeName)

    $Form.BackColor = $global:BgWorkspace
    $Form.ForeColor = $global:FgPrimary
    $TopPanel.BackColor = $global:BgSurface
    $BottomPanel.BackColor = $global:BgSurface
    $PreviewPanel.BackColor = $global:BgSurface
    $TopBorder.BackColor = $global:BorderColor
    $BottomBorder.BackColor = $global:BorderColor
    $PreviewLeftBorder.BackColor = $global:BorderColor

    foreach ($Lbl in @($LblName, $LblAuthor, $LblTags, $LblPreviewHeader, $LblPreviewTitle, $LblUserProfile)) {
        $Lbl.ForeColor = $global:FgPrimary
    }

    foreach ($Lbl in @($LblStatus, $LblMediaCount, $LblPreviewMeta)) {
        $Lbl.ForeColor = $global:FgMuted
    }

    foreach ($InputCtrl in @($TxtName, $TxtAuthor, $ChkTags, $CmbUserProfile, $CmbPageSelect)) {
        $InputCtrl.BackColor = $global:BgInput
        $InputCtrl.ForeColor = $global:FgPrimary
    }

    Set-PreviewHtmlContent -RawHtml $script:CurrentSummaryHtml

    $MediaStrip.BackColor = $global:BgWorkspace
    $PicMainMedia.BackColor = $global:BgWorkspace

    foreach ($SecBtn in @($BtnSubscribed, $BtnCopyIds, $BtnRefreshCatalog, $BtnPrevPage, $BtnNextPage)) {
        $SecBtn.BackColor = $global:BgSecondary
        $SecBtn.ForeColor = $global:FgPrimary
        $SecBtn.FlatAppearance.BorderColor = $global:BorderColor
    }

    $BtnClearFilters.BackColor = $global:BgSurface
    $BtnClearFilters.ForeColor = $global:FgMuted
    $BtnClearFilters.FlatAppearance.BorderColor = $global:BorderColor

    if (-not $script:ActiveIsVideo) {
        $BtnOpenMedia.BackColor = $global:BgSecondary
        $BtnOpenMedia.ForeColor = $global:FgPrimary
        $BtnOpenMedia.FlatAppearance.BorderColor = $global:BorderColor
    }

    $Grid.BackgroundColor = $global:BgWorkspace
    $Grid.GridColor = $global:BorderColor
    $Grid.ColumnHeadersDefaultCellStyle.BackColor = $global:BgHeader
    $Grid.ColumnHeadersDefaultCellStyle.ForeColor = $global:FgPrimary
    $Grid.DefaultCellStyle.BackColor = $global:BgSurface
    $Grid.DefaultCellStyle.ForeColor = $global:FgPrimary
    $Grid.DefaultCellStyle.SelectionBackColor = $global:SelBack
    $Grid.DefaultCellStyle.SelectionForeColor = $global:SelFore
    $Grid.AlternatingRowsDefaultCellStyle.BackColor = $global:BgAltRow
    Apply-SubscribedRowHighlights
}

function Set-ManagerTheme {
    param ([ValidateSet("Light", "Dark")][string]$ThemeName)
    $script:CurrentTheme = $ThemeName
    if ($ThemeName -eq "Dark") {
        $global:BgWorkspace   = [System.Drawing.Color]::FromArgb(24, 27, 32)
        $global:BgSurface     = [System.Drawing.Color]::FromArgb(32, 36, 43)
        $global:BgInput       = [System.Drawing.Color]::FromArgb(42, 47, 56)
        $global:BgAltRow      = [System.Drawing.Color]::FromArgb(37, 41, 49)
        $global:BgHeader      = [System.Drawing.Color]::FromArgb(42, 47, 56)
        $global:BgSecondary   = [System.Drawing.Color]::FromArgb(52, 58, 69)
        $global:BorderColor   = [System.Drawing.Color]::FromArgb(100, 100, 100)
        $global:FgPrimary     = [System.Drawing.Color]::FromArgb(236, 240, 246)
        $global:FgMuted       = [System.Drawing.Color]::FromArgb(165, 174, 188)
        $global:SelBack       = [System.Drawing.Color]::FromArgb(28, 84, 148)
        $global:SelFore       = [System.Drawing.Color]::White
        $global:ExitForeColor = [System.Drawing.Color]::Pink
        $global:greenStatus = [System.Drawing.Color]::Lime
        $global:burntStatus = [System.Drawing.Color]::FromArgb(207, 176, 145)
        $global:darkredStatus = [System.Drawing.Color]::FromArgb(150, 30, 30)
    }
    else
    {
        $global:BgWorkspace   = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $global:BgSurface     = [System.Drawing.Color]::White
        $global:BgInput       = [System.Drawing.Color]::FromArgb(250, 251, 253)
        $global:BgAltRow      = [System.Drawing.Color]::FromArgb(249, 251, 253)
        $global:BgHeader      = [System.Drawing.Color]::FromArgb(236, 240, 246)
        $global:BgSecondary   = [System.Drawing.Color]::FromArgb(236, 240, 246)
        $global:BorderColor   = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $global:FgPrimary     = [System.Drawing.Color]::FromArgb(40, 40, 40)
        $global:FgMuted       = [System.Drawing.Color]::FromArgb(100, 100, 100)
        $global:SelBack       = [System.Drawing.Color]::FromArgb(214, 234, 255)
        $global:SelFore       = [System.Drawing.Color]::FromArgb(15, 25, 40)
        $global:ExitForeColor = [System.Drawing.Color]::DarkRed
        $global:greenStatus = [System.Drawing.Color]::FromArgb(0, 150, 0)
        $global:burntStatus = [System.Drawing.Color]::FromArgb(107, 76, 45)
        $global:darkredStatus = [System.Drawing.Color]::FromArgb(150, 30, 30)
    }
    $Form.BackColor = $global:BgWorkspace
    $Form.ForeColor = $global:FgPrimary
    $statsBox.BackColor = $global:BgSurface

    foreach ($Lbl in @($titleLabel)) {
        $Lbl.ForeColor = $global:FgPrimary
    }

    foreach ($Lbl in @($versionLabel)) {
        $Lbl.ForeColor = $global:FgMuted
    }

    foreach ($SecBtn in @($btn1, $btn2, $btn3, $btn4, $btn5, $btn6, $btn7, $btn8)) {
        $SecBtn.BackColor = $global:BgSecondary
        $SecBtn.ForeColor = $global:FgPrimary
        $SecBtn.FlatAppearance.BorderColor = $global:BorderColor
    }

    if ($valid_Personal_Token -like "*Success*") {
       $tokenStatus = $global:greenStatus
    }
    else
    {
       $tokenStatus = $global:darkredStatus
    }

    $statsLabel1.BackColor = $global:BgSecondary
    $statsLabel1.ForeColor = $tokenStatus

    $statsLabel2.BackColor = $global:BgSecondary
    $statsLabel2.ForeColor = $global:burntStatus

    $btnExit.BackColor = $global:BgSecondary
    $btnExit.ForeColor = $global:ExitForeColor
    $btnExit.FlatAppearance.BorderColor = $global:BorderColor
}

function info-dialog {

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # Define an IMessageFilter to intercept and discard mouse button events
    if (-not ("MouseClickBlocker" -as [type])) {
        Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Windows.Forms;

public class MouseClickBlocker : IMessageFilter {
    public bool PreFilterMessage(ref Message m) {
        // Intercept client and non-client mouse button down/up/double-click messages
        if ((m.Msg >= 0x0201 && m.Msg <= 0x020D) || (m.Msg >= 0x00A1 && m.Msg <= 0x00A9)) {
            return true;
        }
        return false;
    }
}
"@
    }

    # Create the Form (stays hidden until $label.Text is populated)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Downloading Images to Cache"
    $form.Size = New-Object System.Drawing.Size(350, 150)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.BackColor = $global:Bgworkspace

    # Store blocker and disabled forms inside $form.Tag so they persist across events
    $form.Tag = [PSCustomObject]@{
        ClickBlocker  = (New-Object MouseClickBlocker)
        DisabledForms = (New-Object System.Collections.Generic.List[System.Windows.Forms.Form])
    }

    # Attach cleanup method directly to $form so it never goes out of scope
    $form | Add-Member -MemberType ScriptMethod -Name "RestoreGui" -Value {
        [System.Windows.Forms.Application]::DoEvents()
        foreach ($f in $this.Tag.DisabledForms) {
            if ($f -and -not $f.IsDisposed) {
                $f.Enabled = $true
            }
        }
        $this.Tag.DisabledForms.Clear()
        [System.Windows.Forms.Application]::RemoveMessageFilter($this.Tag.ClickBlocker)
    }

    # Safety net: restore background forms if closed via 'X' or disposed early
    $form.Add_FormClosed({
        $this.RestoreGui()
    })

    # Create the Text Label with empty default text
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(20, 30)
    $label.Size = New-Object System.Drawing.Size(300, 50)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $label.ForeColor = $global:greenStatus
    $label.BackColor = $global:BgSurface
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $label.Text = ""

    $Label.Add_Paint({
        param($sender, $e)
        [System.Windows.Forms.ControlPaint]::DrawBorder(
            $e.Graphics,
            $sender.ClientRectangle,
            $global:BorderColor,
            [System.Windows.Forms.ButtonBorderStyle]::Solid
        )
    })

    $form.Controls.Add($label)

    # Disable other forms and show dialog on text; flush and re-enable on "Finished"
    $label.Add_TextChanged({
        $parentForm = $this.FindForm()
        if ($parentForm) {
            if (-not [string]::IsNullOrWhiteSpace($this.Text)) {
                if ($this.Text -eq "Finished") {
                    $parentForm.RestoreGui()
                    $parentForm.Close()
                    $parentForm.Dispose()
                }
                elseif (-not $parentForm.Visible) {
                    # Disable all other currently open forms in the application
                    foreach ($openForm in [System.Windows.Forms.Application]::OpenForms) {
                        if ($openForm -ne $parentForm -and $openForm.Enabled) {
                            $openForm.Enabled = $false
                            $parentForm.Tag.DisabledForms.Add($openForm)
                        }
                    }

                    [System.Windows.Forms.Application]::AddMessageFilter($parentForm.Tag.ClickBlocker)
                    $parentForm.Show()
                    [System.Windows.Forms.Application]::DoEvents()
                }
                else {
                    $parentForm.Refresh()
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }
        }
    })

    return [PSCustomObject]@{
        Form  = $form
        Label = $label
    }
}

function New_MessageBox
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
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog" 
    $Form.MaximizeBox = $false
    $Form.MinimizeBox = $false
    $Form.BackColor = $global:Bgworkspace

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $infoMessage
    $Label.Location = New-Object System.Drawing.Point(25, 30)
    $Label.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $label.ForeColor = $global:FgPrimary
    $label.BackColor = $global:BgSurface
    
    $Label.AutoSize = $true
    $Label.MinimumSize = New-Object System.Drawing.Size(350, 0) 
    $Label.MaximumSize = New-Object System.Drawing.Size(350, 0) 

    $Label.Add_Paint({
        param($sender, $e)
        [System.Windows.Forms.ControlPaint]::DrawBorder(
            $e.Graphics,
            $sender.ClientRectangle,
            $global:BorderColor,
            [System.Windows.Forms.ButtonBorderStyle]::Solid
        )
    })

    $Form.Controls.Add($Label)

    $ButtonOK = New-Object System.Windows.Forms.Button
    $ButtonOK.Text = "OK"
    $ButtonOK.Size = New-Object System.Drawing.Size(110, 32)
    $ButtonOK.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $ButtonOK.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $ButtonOK.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
    $ButtonOK.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ButtonOK.FlatAppearance.BorderSize = 1
    $ButtonOK.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $ButtonOK.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $ButtonY = $Label.Bottom + 25
    $ButtonOK.Location = New-Object System.Drawing.Point(150, $ButtonY)

    $FormWidth = 420
    $FormHeight = $ButtonOK.Bottom + 25
    $Form.ClientSize = New-Object System.Drawing.Size($FormWidth, $FormHeight)

    $Form.Controls.Add($ButtonOK)
    [void]$Form.ShowDialog()
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
    $Form.BackColor = $global:Bgworkspace

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $infoMessage
    $Label.Location = New-Object System.Drawing.Point(25, 30)
    $Label.Size = New-Object System.Drawing.Size(350, 60)
    $Label.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $Label.ForeColor = $global:FgPrimary
    $label.BackColor = $global:BgSurface

    $Label.Add_Paint({
        param($sender, $e)
        [System.Windows.Forms.ControlPaint]::DrawBorder(
            $e.Graphics,
            $sender.ClientRectangle,
            $global:BorderColor,
            [System.Windows.Forms.ButtonBorderStyle]::Solid
        )
    })

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
    $screenHeight = ($workingArea.Height-830)/2

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $GUItitle
    $Form.Size = New-Object System.Drawing.Size(500, 830)
    $Form.StartPosition = "Manual"
    $Form.Location = New-Object System.Drawing.Point($screenWidth, $screenHeight)
    $Form.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $Form.ForeColor = $global:FgPrimary
    $Form.BackColor = $global:Bgworkspace
    $Form.MaximizeBox = $false
    $Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle

    $DataGridView = New-Object System.Windows.Forms.DataGridView
    $DataGridView.Dock = [System.Windows.Forms.DockStyle]::Fill
    $DataGridView.ReadOnly = $true
    $DataGridView.AllowUserToAddRows = $false
    $DataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $DataGridView.AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::AllCells # Prevents text clipping when font size increases
    $DataGridView.BackgroundColor = $global:Bgworkspace
    $DataGridView.BackColor = $global:Bgworkspace

    # Required so Windows visual themes don't force light-gray headers
    $DataGridView.EnableHeadersVisualStyles = $false

    # Style the row header background, text/arrow color, and selection colors
    $DataGridView.RowHeadersDefaultCellStyle.BackColor = $global:BgSurface
    $DataGridView.RowHeadersDefaultCellStyle.ForeColor = $global:FgPrimary
    $DataGridView.RowHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::DodgerBlue
    $DataGridView.RowHeadersDefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

    # Optional: Clean up borders and adjust the row header column width
    $DataGridView.RowHeadersBorderStyle = [System.Windows.Forms.DataGridViewHeaderBorderStyle]::Single
    $DataGridView.RowHeadersWidth = 35
    $DataGridView.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $DataGridView.MultiSelect = $true  # Allows Ctrl+Click and Shift+Click selections

    $Column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $Column.HeaderText = "Mod Name"
    $Column.Name = "ModName"
    $Column.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
    $Column.DefaultCellStyle.ForeColor = $global:FgPrimary
    $Column.DefaultCellStyle.BackColor = $global:BgAltRow
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
    $ClearButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    $ClearButton.Add_Click({
        $dataGridView.ClearSelection()
    })

    $SelectAllButton = New-Object System.Windows.Forms.Button
    $SelectAllButton.Text = "Select All"
    $SelectAllButton.Location = New-Object System.Drawing.Point(135, 10)
    $SelectAllButton.Size = New-Object System.Drawing.Size(85, 30)
    $SelectAllButton.ForeColor = [System.Drawing.Color]::White
    $SelectAllButton.BackColor = [System.Drawing.Color]::DodgerBlue
    $SelectAllButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    $SelectAllButton.Add_Click({
        $dataGridView.SelectAll()
    })

    $OKButton = New-Object System.Windows.Forms.Button
    $OKButton.Text = "OK"
    $OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $OKButton.Location = New-Object System.Drawing.Point(260, 10)
    $OKButton.Size = New-Object System.Drawing.Size(85, 30)
    $OKButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $OKButton.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
    $OKButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = "Cancel"
    $CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $CancelButton.Location = New-Object System.Drawing.Point(360, 10)
    $CancelButton.Size = New-Object System.Drawing.Size(85, 30)
    $CancelButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $CancelButton.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
    $CancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

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

    $ModListData = get-subscribedList -isForced $true

    $ModList = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $ModListData) {
        # .psobject.Properties safely reveals all top-level dynamic Mod IDs
        foreach ($property in $item.psobject.Properties) {
            $topName = $property.Name
            $modname = $property.Value.name # Access the inner "name" key directly using dot-notation

            # Format and append directly into your array list
            [void]$ModList.Add("$modname | $topName")
        }
    }

    $ModList.Sort()

    $GUItitle = "Select One or More Mods to Force Update"
    $SelectedMods = mod_GUI_selector -ModList $ModList -GUItitle $GUItitle

    if ($null -eq $SelectedMods -or $SelectedMods.Count -eq 0) {
        Write-Host "No Mods were selected" -ForegroundColor Red
        $global:forced_updates=0
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "      FORCE Download and Update Canceled      " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan

        return
    }

    # Output the selected items
    Write-Host "You selected the following items:" -ForegroundColor Green
    Write-Host ""
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

        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "      FORCE Download and Update Beginning     " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host ""
        return
    }
    else
    {
        Write-Host ""
        Write-Host "Forced Mod Update Canceled" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "      FORCE Download and Update Canceled      " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
    }

}

# Build Current Mod List

function get-subscribedList
{
    param
    (
        [bool]$isForced = $true
    )

    if (Test-Path $ModListJsonPath)
    {
	    Write-Host "Compiling Mods from ModList.json and Mod.io Subscription List."
        Write-Host ""
	    $unsubListData=Get-Content $ModListJsonPath | ConvertFrom-Json
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

    $result_total = $workingHash.WorkArray[0].result_total

    $dataOffset=0
    $dataLimit=25
    $count_of_files = 0
    $unsubListData_delete_comparison=@{}

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
    Write-Host "New Mods will not be downloaded."
    Write-Host ""

    if($isForced)
    {
        Write-Host "Select each Mod in the FORCED Download GUI if you want to download."
        Write-Host ""
    }

    for ($p = 0; $p -lt $PageCount; $p++)
    {

        # Get current hashtable element count
        $len=$workingHash.WorkArray[$p].result_count

        for ($i = 0; $i -lt $len; $i++)
        {
	        $sub=$workingHash.WorkArray[$p].data[$i]
	        $subname=$sub.name

            # Variables and Data to be transfered from mod.io state.json to Sandstorm state.json

            $count_of_files++

        	[string]$modid=$sub.id
	        [string]$moddate_added=$sub.modfile.date_added
	        [string]$modname=$sub.name

         	# Write data about this sub to unsubListData

	        if ($unsubListData.${modid} -eq $null)
	        {
		        $unsubListData | Add-Member -Name $modid -Value @{} -MemberType NoteProperty
    		    $unsubListData.${modid}.date_added=0
                $unsubListData.${modid}.name = $modname
                Write-Host "New Mod Subscription: $modname | $modid" -ForegroundColor Yellow
            }

            $directory_ID=$modid
            $unsubListData_delete_comparison | Add-Member -Name $modid -Value @{} -MemberType NoteProperty
        }
        $dataOffset+=$dataLimit
    }

    # If any mods are missing from the mod.io subscribed list
    # when compared to the stored ModList.json the missing files
    # will be removed from the ModList.json and the directories 
    # will be deleted from the computer.  Compare $unsubListData with
    # $unsubListData_delete_comparison and remove directories of
    # missing mods.

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "        Checking for Unsubscribed Mods        " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    $deletedMods=0

    foreach ($item in $unsubListData) {
        # .psobject.Properties safely reveals all top-level dynamic Mod IDs
        foreach ($property in $item.psobject.Properties) {
            $modDeleteID = $property.Name
            $modDeleteName = $property.Value.name # Access the inner "name" key directly using dot-notation

            if ($unsubListData_delete_comparison.${modDeleteID} -eq $null)
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
                $unsubListDataListData.PSObject.Properties.Remove($modDeleteID)
                $deletedMods+=1
 	        }
        }
    }

    if ($deletedMods -eq 0)
    {
        Write-Host "No Unsubscribed Mods found." -ForegroundColor Green
    }

    # Update ModList.json 
    $unsubListData | ConvertTo-Json | Set-Content $ModListJsonPath

    return $unsubListData
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
    $formHeight  = 830
    $screenWidth  = [int](($workingArea.Width - ($formWidth + 1000)) / 2)
    $screenHeight = [int](($workingArea.Height - $formHeight) / 2)

    # Main Window Canvas (Light Theme UI)
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = if ([string]::IsNullOrEmpty($Filter)) { "Select Folder to Move Mod Directory" } else { "Select $Filter" }
    $Form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
    $Form.BackColor = $global:Bgworkspace
    $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $Form.Location = New-Object System.Drawing.Point($screenWidth, $screenHeight)
    $Form.MaximizeBox = $false
    $Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle

    # Path Display Banner (Top Area)
    $PathLabel = New-Object System.Windows.Forms.Label
    $PathLabel.Text = "Current Folder: This PC"
    $PathLabel.Location = New-Object System.Drawing.Point(15, 15)
    $PathLabel.Size = New-Object System.Drawing.Size(450, 25)
    $PathLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $PathLabel.ForeColor = $global:FgPrimary
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
    $ListView.Size = New-Object System.Drawing.Size(450, 665)
    $ListView.View = [System.Windows.Forms.View]::Details
    $ListView.FullRowSelect = $true
    $ListView.GridLines = $false
    $ListView.SmallImageList = $ImageList 
    $ListView.BackColor = $global:BgAltRow
    $ListView.ForeColor = $global:FgPrimary
    $ListView.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)

    # Single column since we only focus on folder hierarchy
    $titleName = if ([string]::IsNullOrEmpty($Filter)) { "Select Folder to Move Mod Directory" } else { "Select $Filter" }
    [void]$ListView.Columns.Add($titleName, 430)
    [void]$Form.Controls.Add($ListView)

    # Action Buttons (Bottom Area)
    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Text = "Cancel"
    $CancelButton.Location = New-Object System.Drawing.Point(365, 735) 
    $CancelButton.Size = New-Object System.Drawing.Size(100, 35)
    $CancelButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $CancelButton.BackColor = [System.Drawing.Color]::FromArgb(252, 232, 230)
    $CancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $CancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    [void]$Form.Controls.Add($CancelButton)

    $SelectButton = New-Object System.Windows.Forms.Button
    $SelectButton.Text = if ([string]::IsNullOrEmpty($Filter)) { "Select Folder" } else { "Select File" }
    $SelectButton.Location = New-Object System.Drawing.Point(15, 735) 
    $SelectButton.Size = New-Object System.Drawing.Size(175, 35)
    $SelectButton.ForeColor = [System.Drawing.Color]::FromArgb(33, 37, 41)
    $SelectButton.BackColor = [System.Drawing.Color]::FromArgb(230, 244, 234)
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
            $UpItem.ForeColor = $global:FgPrimary
            [void]$ListView.Items.Add($UpItem)

            Try {
                # Fetch Folders
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
                        $Item.ForeColor = $global:FgMuted
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
                        $Item.ForeColor = $global:greenStatus
                        [void]$ListView.Items.Add($Item)
                    }
                }
            } Catch {
                New_MessageBox -title "Permission Error" -infoMessage "Access Denied or Directory Unreadable."
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
        $global:SettingSource = $globalsettings_old.RootLocalStoragePath
        $global:SettingSource = $global:SettingSource.Replace('/', '\')
    }
    else
    {
        Write-Host "$settingsPath is MISSING and cannot proceed." -ForegroundColor Red
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host " Repair globalsettings.json Location Canceled " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        return
    }
    Write-Host "Current Mod Storage: $global:SettingSource" -ForegroundColor Green
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
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host " Repair globalsettings.json Location Canceled " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        return
    }

    $UserChoice = User-Confirm -title "Pick state.json to Import" -infoMessage "Would you like to use this state.json Mod.io location?"

    if ($UserChoice -eq 'No') {
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host " Repair globalsettings.json Location Canceled " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
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
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host " Repair globalsettings.json Location Complete " -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Cyan
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
        $global:SettingSource = $globalsettings_old.RootLocalStoragePath
        $global:SettingSource = $global:SettingSource.Replace('/', '\')
    }
    else
    {
        Write-Host "$settingsPath is MISSING and cannot proceed." -ForegroundColor Red
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "         Move Sandstorm Mods Canceled         " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        return
    }

    Write-Host "Current Mod Storage: $global:SettingSource" -ForegroundColor Green
    Write-Host ""
    Write-WrappedHost -Text "Select the directory path to store Mod.io mod downloads. If no directory path selected move is aborted." -ForegroundColor DarkYellow
    Write-Host ""

    Modio_mod_directory

    if(-not $script:FinalSelection)
    {
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "         Move Sandstorm Mods Canceled         " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
        return
    }

    $destination = $script:FinalSelection

    $UserChoice = User-Confirm -title "Select Directory/Folder you would like to move Mods" -infoMessage "Do you really want to move Mods to [$destination]?"

    if ($UserChoice -eq 'No')
    {
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "         Move Sandstorm Mods Canceled         " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan
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
        Write-Host "Source Directory path: $global:SettingSource" -ForegroundColor Yellow
        Write-Host "Destination Directory path: $rootdestination" -ForegroundColor Yellow

        $safeSource = $global:SettingSource.TrimEnd('\')
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
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "         Move Sandstorm Mods Complete         " -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Cyan

        if (Test-Path $settingsPath) {
            $globalsettings_old = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
            $global:SettingSource = $globalsettings_old.RootLocalStoragePath
            $global:SettingSource = $global:SettingSource.Replace('/', '\')
        }

        $ModStorageSize = "{0:N2} GB" -f ((Get-ChildItem -Path "$modsDirectoryPath" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB)
    
        $statsText2 = "Total Subscriptions: $result_total`nMod Storage Size: $ModStorageSize`n" +
                      "Mod Storage Path: $global:SettingSource"
        $statsLabel2.Text = $statsText2
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
	        [string]$moddate_added_display=[DateTimeOffset]::FromUnixTimeSeconds($sub.modfile.date_added).LocalDateTime.ToString("MMM d, yyyy")
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

    # Convert your object to JSON
    $jsonc = $jsonObject | ConvertTo-Json -Compress -Depth 100

    # Fix ONLY Unicode characters (e.g., \u0027) while keeping literal \n untouched
    $cleanJson = [regex]::Replace($jsonc, '\\u([0-9a-fA-F]{4})', { 
        param($match) [char][int]"0x$($match.Groups[1].Value)" 
    })

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
        # .psobject.Properties safely reveals all top-level dynamic Mod IDs
        foreach ($property in $item.psobject.Properties) {
            $modDeleteID = $property.Name
            $modDeleteName = $property.Value.name # Access the inner "name" key directly using dot-notation

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

    $ModStorageSize = "{0:N2} GB" -f ((Get-ChildItem -Path "$modsDirectoryPath" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB)
    
    $statsText2 = "Total Subscriptions: $result_total`nMod Storage Size: $ModStorageSize`n" +
                  "Mod Storage Path: $global:SettingSource"
    $statsLabel2.Text = $statsText2
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
    $form.Size = New-Object System.Drawing.Size(500, 830)
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
    $versionLabel.Text = "Version: $Version - Released: $ReleaseDate By Joanna Wick"
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
        $global:SettingSource = $globalsettings_old.RootLocalStoragePath
        $global:SettingSource = $global:SettingSource.Replace('/', '\')
    }

    $statsText2 = "Total Subscriptions: $Subscription_Count`nMod Storage Size: $ModStorageSize`n" +
                  "Mod Storage Path: $global:SettingSource"
    
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
    # Evaluate the global state variable
    if ($global:ManagerConfig.verbose -eq 0) {
        $verboseText = "Concise" 
    } else { 
        $verboseText = "Verbose" 
    }
    
    # Grab the local path data
    $settingsPath = Join-Path "$env:LOCALAPPDATA" "mod.io\globalsettings.json"

    if (Test-Path $settingsPath) {
        $globalsettings_old = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
        $global:SettingSource = $globalsettings_old.RootLocalStoragePath
        $global:SettingSource = $global:SettingSource.Replace('/', '\')
    }

    # DIRECTLY UPDATE THE LIVE UI LABELS (Crucial Step)
    $statsText2 = "Total Subscriptions: $Subscription_Count`nMod Storage Size: $ModStorageSize`n" +
                  "Mod Storage Path: $global:SettingSource"
        $statsLabel2.Text = $statsText2

    # Update the toggle button text dynamically
    if ($btn5) {
        $btn5.Text = "Toggle Verbose Mod Information (Current: $verboseText)"
    }

    # Update the toggle button text dynamically
    if ($btn6) {
        $btn6.Text = "Toggle Theme (Current: $($global:ManagerConfig.DefaultTheme))"
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

    $btn3 = Create-MenuButton -text "Mod.io Mod Browser (Subscribe/Unsubscribe)" -yLocation ($startY + ($spacing * 2)) -actionCode {
            modio-browser
    }

    $btn4 = Create-MenuButton -text "Mod.io Collection Browser (Follow/Unfollow)" -yLocation ($startY + ($spacing * 3)) -actionCode {
            modio-collection-browser
    }

    $btn5 = Create-MenuButton -text "Toggle Verbose Mod Information (Current: $verboseText)" -yLocation ($startY + ($spacing * 4)) -actionCode {
    if ($global:ManagerConfig.verbose -eq 0) { 
        $global:ManagerConfig.verbose = 1 
    } else { 
        $global:ManagerConfig.verbose = 0 
    }
    $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath

    # 2. Force the data engine to push new string layers to your form components
    & $UpdateUIData
        }

    $btn6 = Create-MenuButton -text "Toggle Theme (Current: $($global:ManagerConfig.DefaultTheme))" -yLocation ($startY + ($spacing * 5)) -actionCode {
    if ($global:ManagerConfig.DefaultTheme -eq "Light") { 
        $global:ManagerConfig.DefaultTheme = "Dark" 
    } else { 
        $global:ManagerConfig.DefaultTheme = "Light" 
    }
    $global:ManagerConfig | ConvertTo-Json | Set-Content $ManagerConfigPath
    Set-ManagerTheme -ThemeName $global:ManagerConfig.DefaultTheme

    # 2. Force the data engine to push new string layers to your form components
    & $UpdateUIData
    }

    $btn7 = Create-MenuButton -text "Move Mod.io Mod Directory to New Location" -yLocation ($startY + ($spacing * 6)) -actionCode {
            move_Sandstorm_mods
    }

    $btn8 = Create-MenuButton -text "Repair globalsettings.json Storage Location" -yLocation ($startY + ($spacing * 7)) -actionCode {
            repair_globalsettings
    }


    # Exit Button (Styled with a distinct alert outline boundary tint if desired)
    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = "Exit Manager"
    $btnExit.Font = $buttonFont
    $btnExit.ForeColor = [System.Drawing.Color]::DarkRed
    $btnExit.BackColor = $buttonBg
    $btnExit.Location = New-Object System.Drawing.Point(20, ($startY + ($spacing * 8) + 10))
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
    $form.Controls.Add($btn7)
    $form.Controls.Add($btn8)
    $form.Controls.Add($btnExit)

    $Form.Add_Shown({
        Set-ManagerTheme -ThemeName $global:ManagerConfig.DefaultTheme
        [System.Windows.Forms.Application]::DoEvents()
    })

    # 5. Open Form Window Display Dialog
    $form.ShowDialog() | Out-Null
}
Show-Menu-GUI
