# SandstormModManager
## Created for Insurgency Sandstorm 1.21 by Joanna Wick
### Version: 1.1.3
### Date: 2026-07-10

## YOU should Double-Click on Start_Sandstorm_Mod_Manager.bat to execute the program.

### If you see the following message when you run the script enter A or Y.

> Execution Policy Change

> The execution policy helps protect you from scripts that you do not trust. Changing the execution policy might expose
> you to the security risks described in the about_Execution_Policies help topic at

> http://go.microsoft.com/fwlink/?LinkID=135170. Do you want to change the execution policy?

> [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "N"):

This PowerShell script will automatically download all subscribed mods for Insurgency Sandstorm from Mod.io
and install them for use with your Sandstorm game on Windows and Windows Servers.  It will also update the
state.json file located in the mod.io/254/metadata directory.  This is where the game stores all information 
about each mod that it uses in the game.  This script will also download, install and update the state.json 
file for any new mods you have subscribed  without having to load the game.

If you want to make sure any new mods or new updates are installed just run this script before playing the 
game. The scan is very fast. Any updated mod or map will be downloaded and installed as well as anything new 
you have subscribed. You won't have to worry if the game is actually downloading anything anymore when you 
start the game.

The Download Progress Bar has been disabled because it slows the actual downloads to a crawl. A 1MB download
could take 15-20+ minutes no matter how fast your connection.  With the Download Progress diabled the downloads
are very fast.  After downloading the time to download and download speed with be shown for the file.
An un-zip progress indicator that will run for each download.

The first time you run the script it will re-download all of the mods you are subscribed and reinstall them,
build a new state.json and store it's own update data for use next time you run the script.  I am doing this
because sometimes the mod files that are actually stored do not match what the game thinks is stored.

If you Unsubscribe to any mod on Mod.io just run this script and it will delete the directories containing
those mods so you will not need to do it manually.

## Usage

1. Download the zip file and extract it anywhere.
2. Double-Click on Start_Sandstorm_Mod_Manager.bat

Re-running the script at a later date, will check your subscriptions for updates and only download mods from new 
subscriptions or mods which have been updated.

If you start the game you and see more than one mod downloadinging then the game may think the state.json is corrupt 
(vary rare). You can delete the state.json and rename the state_<date_time>.json (latestversion by time) back to 
state.json and everything will be back to normal.  As I daid it is a very, very rare occurrence but there will always 
be a backup file created just in case.  If the game runs without redownloading you can delete those backup files.

If you receive a Warning List of files this just indicates 7-Zip found some unexpected things and the archive should have
extracted without issue.

If you receive an Error List of files you should scroll back up through Powershell to find those files to get more
detailed information about the error.  You can also see if the files were extracted or not.

Common 7-Zip Unzipping Errors

Data Error / CRC Error: Meaning: The data inside the Zip archive is corrupted, meaning the compressed data does not match the 
file's original Cyclic Redundancy Check (CRC) value.

Can not open file as archive :Meaning: 7-Zip fails to recognize the file structure or format. This happens if the file download is 
incomplete, if the file extension is incorrect (e.g., trying to open a .gz file that is actually an XML document), or if the file 
was password-protected by a format 7-Zip doesn't fully support.

Headers Error: The header section of the archive—which contains critical metadata and structural information—is damaged.

Can not open output file / Access is denied: 7-Zip cannot create or write the destination file on your computer because of a 
Lack of administrator privileges on the destination folder.

Not enough space on disk: The destination drive doesn't have enough free storage to hold the unzipped files.

The most common errors will be CRC_Error or Lack of Drive Space.  I have found a couple of mod files that give CRC_Errors
and it looks like they were compressed and a bad CRC was created by whatever program was used to create the zip.

Change Log
==========

1.1.3 (2026-07-08)
    1. [FIXED] When selecting test directory and it is drive root then there would be two // instead of just one /

1.1.2 (2026-07-08)
    1. [FIXED Sandstorm removes all spaces used in the User Account Name when creating the Directory inside %localappdata%\mod.io\254\[UserName] causing Sandstorm Mod Manager to not find the Directory.  If the Windows Account you are using is My Name Sandstorm would shorten it to MyName and the Mod Manager wouldn't find it.

1.1.1 (2026-07-04)

    1. [FIXED] When using the Mod Mover the mod location was not updated in the Mod Manager.
       If you tried processing, force downloading or unsubscribing to mods it would use the OLD
       location for storing and deleting mods instead of where they were moved.

1.1.0 (2026-07-02)

    1. Listing total Subscription Count right after Page Count was not showing total Subscriptions
       but only the Subscription Count to the current page being processed.
    2. Removed the need to create a Personal Access Token.  The script uses the Games OAuth Token
       stored in the user.json
    3. Added backup and restore of globalsettings.json 
       Sometimes the game will reset the globalsettings.json to point back to C:\Users\Public\mod.io
       The script will make a globalsetting.backup file if one is not present.  After that the script
       will compare the contents of the globalsettings.json with globalsettings.backup.  If they
       do not match the contents of the backup will be restored to the json file.  When you move
       the location of the mod.io directory the backup file will also be updated with the 
       new location.
       

1.0.2 (2026-06-23)

    1. When Processing Subscriptions is complete the total time downloading will be displayed in minutes:seconds,
       Total GB downloaded and Total GB of disk stoage space used.
    2. Added Start_Sandstorm_Mod_Manager.bat Double-Click on this file to start Sandstorm Mod Manager.

1.0.1 (2026-06-20)

    1. Script will now make sure your Personal Access Token is valid every time you run the script and indicate
       it is valid in the menus and under who User Name and ID it belongs.  If it detects an invalid PAT you will
       be taken to the Change Token menu item so you can enter a new token.

1.0 (2026-06-20) Initial Release

    1. Token variable moved to a token.cfg file so you will not need to get a new token if you delete the 
       config.json and haven't saved the old token id.
    2. Added getting the mod directory from the %localappdata%\mod.io\globalsettings.json
    3. Added a GUI selector for location if you want the mod files unpacked to a different 
       location for testing.
    4. A directory will now be created in the mod.io/mods directory using the mod_id to download and unpack
       the mod files.
    5. config.json now contains the mod.io mod_id number and last update time for each mod for faster lookup
       of the latest update.
    6. Mod.io json files have changed since the BoneLabModDownloader was created and it has been updated to 
       work with the current system.
    7. Dropped the internal Powershell Extractor for Zip files as it was limited and would fail if the file 
       was larger than 4GB or if there were file crc errors that didn't corrupt the archive.
    8. Added error reporting and a lot more information as mod files being downloaded and extracted.
    9. If the numeric directory a mod is stored (ex: directory 123456 located in mod.io/254/mods/) has been 
       deleted it will trigger an automatic download and update when script has been executed.
    10. Completely rebuilding the state.json file using the subscribed mod information from mod.io.
    11. Added Paging support for subscriptions that contain more than 100 mod files.
    12. Added GUI to select mods for FORCED updating.
    13. state.json is renamed to state_<date_time>.json before the new state.json is saved.  This will give
        you backups incase the newly created state.json does not for some reason.
    14. Auto delete any mod Unsubscribed on Mod.io
    15. Added Elaped Download Time and Download Speed for each mod downloaded.
    16. Added ability to unsubscribed to mods and delete the stored files.
    17. Added Menu to more easily select what to do instead of a ordered process.
    18. Added my Insurgency-Sandstorm-mod.io Mover batch file to the package and created a menu selection
    19. Renamed config.json to ModList.json to better reflect contents
    20. Both Forced Download and Unsubscribe GUI are now sorted alphabetically

To Do
=====

    1. Add displaying of all Sandstorm Collections on Mod.io
    2. Add displaying contents of a selected Sandstorm Collection
    3. Add Follwing and Unfollowing Collections


