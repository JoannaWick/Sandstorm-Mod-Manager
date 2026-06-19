# SandstormModManager
# Created for Insurgency Sandstorm 1.21 by Joanna Wick
# Version: 1.0
# Date: 2026-06-19

<mark>Recommend reading How_To_Use_Sandstorm_Mod_Manager.pdf the first time you run the script.  It will give
detailed information with image examples of the process.  When you run the script for the first time 
you will be asked if you want to view the PDF.  Click on Y(es) is highly recommended.</mark>

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

After the first time running the script it will only download and update any files that have changed on mod.io
since the last time the script was run.

If you Unsubscribe to any mod on Mod.io just run this script and it will delete the directories containing
those mods so you will not need to do it manually.

## Usage

1. Download the zip file and extract it anywhere.
2. Right-click the `Download_Sandstorm_Mods.ps1` file and select "Run with PowerShell".
4. You will be asked for a mod.io Token and read the How_To_Use_Sandstorm_Mod_Manager.pdf for how to get one (REQUIRED).

Use this method to get your Mod.io Token

1. Go to Mod.io and Log In to your account.
2. Click on the Button bottom right with a Letter in it to open your Navigation Menu.
3. Select API Access from the navigation menu.
4. Scroll to the OAuth Access section.
5. Where it says "Token Name*" enter Sandstorm and click on the + button.
6. You will see TOKEN CREATED! Click on the two pieces of paper (Copy to Clipboard) button on the left side of the
   string of number and letters.  This will copy the token.
7. When asked for the the Token 'OAuth token (Press ENTER to use CURRENT) []' paste what you have copied end press enter.

Your token will be saved for future use.  If you ever delete the token.cfg file you will need to repeate the above process.
You cannot retrieve the token at a later date.  You will need to delete the old token from your API Access page on
mod.io and then recreate it again for a new token. Tokens have a 1 Year expiration date. When they expire you will
need to delete the old one and create a new one.

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

1.0 (2026-06-19) Initial Release

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

To Do
=====

    Nothing at this time

