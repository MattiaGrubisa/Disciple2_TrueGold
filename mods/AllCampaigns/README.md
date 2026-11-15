# All Campaigns for Disciples II: Rise of the Elves

Play the **Gallean's Return** campaigns from the GOG version of **Rise of the Elves**, so you don't need to keep two installs around.

A new button sits above *Continue* on the campaign race screen:

| Race | Button starts |
|---|---|
| Empire, Mountain Clans, Legions of the Damned, Undead Hordes | Their Gallean's Return campaign |
| Elven Alliance | *The Alliance Crusade*, the fan saga that ships with GOG Rise of the Elves |

*Continue* still starts the normal campaign. The button is greyed out on the skirmish / custom saga race screen.

## Requirements

You need **both** GOG games installed:

- **Disciples II: Rise of the Elves** v3.01 (GOG). The mod is installed into this one.
- **Disciples II: Dark Prophecy / Gallean's Return** v2.02 (GOG). Only read: the installer copies the Gallean's Return missions out of it.

Only the GOG executable is supported. The mod hooks fixed addresses inside `Discipl2.exe`, and the installer refuses any other version. The original Akella / Russobit / Steam builds won't work.

The mod contains no game files. Every map, text and image comes from your own copies of the games.

## Install

1. Download the latest `AllCampaigns-*.zip` from the [Releases](../../releases) page (not the "Source code" zip) and unpack it anywhere.
2. Double-click `install.bat`.
3. It offers the GOG folders it finds. Press Enter to accept each one, or paste a different path.
4. Start the game, choose *New Campaign*, pick a race and click the new button.

The installer:

- checks `Discipl2.exe` is GOG Rise of the Elves v3.01;
- backs up every file it changes into `_AllCampaigns_backup` in the game folder;
- renames `MSS32.DLL` to `mss23.dll` and puts the toolset's `mss32.dll` and `Scripts` folder next to it;
- adds the button to `DLG_CHOOSE_RACE` in `interf\Interf.dlg`;
- copies the Gallean's Return missions from your Dark Prophecy install into the `scens` tables (see below);
- creates the `SaveGame` folder. The GOG install doesn't have one, and without it the game silently fails to save.

Rise of the Elves is a different game on GOG, so updates from GOG Galaxy may overwrite modded files. Run `uninstall.bat` and then `install.bat` again after an update.

## Uninstall

Double-click `uninstall.bat`. It restores everything from `_AllCampaigns_backup` and deletes the backup folder. Your saved games are kept.

## How it works

**The button.** The mod is built on the [Disciples 2 modding toolset](https://github.com/VladimirMakeev/D2ModdingToolset), which loads into the game as a replacement `mss32.dll` and hooks game functions. This fork adds three hooks to the campaign race menu (`mss32/src/menuracecampaignhooks.cpp`):

- the menu constructor wires up `BTN_GALLEAN`;
- campaign selection swaps the Dark Prophecy campaign id for the matching Gallean's Return one when the button was used;
- the button update hook sets the label per race and disables the button on the skirmish menu.

For the Elves, the button replays what the *Custom Saga* menu does when you pick a saga, using *The Alliance Crusade.csg* from the game's `campaign` folder (`mss32/src/customsaga.cpp`).

**The missions.** Rise of the Elves lists the Gallean's Return campaigns, but its scenarios S123 to S134 are empty placeholder maps. The real ones live in the Dark Prophecy install. Both games store scenarios in dBase tables (`scens\*.dbf`), but Rise of the Elves added and widened columns, so rows can't be copied as raw bytes. The installer rebuilds each row column by column:

- columns both games have are copied and re-padded to the new width;
- resource strings such as `G0100:R0000:Y0000:E0000:W0000` get `:B0000` added for the Elves' mana;
- columns only Rise of the Elves has get the most common value from its own rows.

All other Rise of the Elves rows are left exactly as they were.

## Known limits

- GOG Rise of the Elves v3.01 only.
- The other features of the toolset are installed too, with its default `Scripts\settings.lua`. They are off or vanilla-compatible by default.
- Running alongside another mod that also replaces `mss32.dll` or edits `Interf.dlg` / `scens` isn't supported.

## Building from source

Requires Visual Studio with the C++ desktop workload (x86 toolset).

```powershell
cd mss32
msbuild mss32.sln /p:Configuration=Release /p:Platform=x86
```

If the `DISCIPLES2_PATH` environment variable points at a game folder, the build copies `mss32.dll` there. `mods\AllCampaigns\package.ps1` then builds the release zip from that DLL and the repository's `Scripts` folder.

## Credits

- **Vladimir Makeev** and the toolset contributors (see `CONTRIBUTORS.md`) for the [modding toolset](https://github.com/VladimirMakeev/D2ModdingToolset) this is built on.
- **Emanuel Wall** for *The Alliance Crusade*. The saga isn't included here; it ships with GOG Rise of the Elves.
- Strategy First and .dat for Disciples II. This is an unofficial fan mod, not affiliated with them or with GOG.

## Licence

GPL-3.0, the same as the toolset. See `LICENSE`.
