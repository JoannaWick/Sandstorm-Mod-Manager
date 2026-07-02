# Insurgency-Sandstorm-mod.io-Mover

I created this batch file to easily move the mod.io directory from the
C:\Users\Public directory to any drive or directory on your computer.
It will only work for Windows computers and can be used to move the mod.io
directory on both Sandstorm Servers and Player computers.

This script can be used to repeatedly move the mod.io directory to any
location. If you moved it to D:\MySandstorm\WheretheModsStay\ and decided to
move it to a new drive you just added like F:\ you can do so.  You can place it
on the root of a drive or place it directories deep (just not too many 
directories deep). After moving the mod files will not need to be re-downloaded.

This script will also move mod files for every game that uses 'RootLocalStoragePath'
in the globalsettings.json file for mod.io. The script will update the metadata
only for Sandstorm.  If any other games use metadata that points to the old location
it will not be updated.

If Sandstorm is the only game you have installed that uses Mod.io then go ahead and 
use this script.  

Any game that is installed after the mod.io directory has been moved will use the 
new location for their mods.

Sandstorm uses a state.json file that contains all information from graphic links
to descriptions to direct paths to individual mod directory locations to etc. about 
mods that have been downloaded. Information like mod location must be updated.

IE: {"Mods":[{"ID":98145,"NeverRetryCategory":0,"NeverRetryCode":0,"PathOnDisk":"F:\\mod.io\\254\\mods\\98145",

This location information is repeated for every mod you have subscribed.  This script
will alter those locations for you.

The script is pretty simple and easy to use and I hope everyone enjoys it.

Joanna Wick

Change Log
==========

0.2.3 (2026-07-02)

    1. Added creation of globalsettings.backup

0.2.2 (2026-06-12)

    1. Made the messages and interface look better and cleaned a couple of code issues

0.2.1 (2026-06-01)

    1. Missing backslash (\) at the end of a directory path when testing if you 
       could write to directory instead of a drive
    
0.2 (2026-06-01)

    1. Added check to convert Windows Path in globalsettings.json to json path
    2. Added conversion of escaped backslash (\\) pathing to json forward slash (/).
    3. Added test to see if destination directory is read/writable.
       If not writable it will ask for a new destination.

0.1 (2026-05-29) Initial Release
