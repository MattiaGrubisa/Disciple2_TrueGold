# All Campaigns for Disciples II: Rise of the Elves [![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Play every Disciples II campaign in one game: **Dark Prophecy**, **Gallean's Return** and **Rise of the Elves**, all from the GOG version of Rise of the Elves.

## Why this exists

On GOG, Disciples II comes as two separate games:

- **Dark Prophecy / Gallean's Return** (v2.02): the original campaigns plus the Gallean's Return add-on campaigns.
- **Rise of the Elves** (v3.01): the newer engine with the Elven Alliance and their campaign. It still has the Dark Prophecy campaigns, but the Gallean's Return ones are missing. The game lists their twelve missions, but they're empty placeholder maps with no menu to start them.

So if you want the Gallean's Return story, you normally have to go back to the older game and lose the Elves, the newer engine and mods built for Rise of the Elves, such as Lazy Mod.

This mod fixes that. It copies the real Gallean's Return missions from your own Dark Prophecy install into Rise of the Elves and adds a button to start them. One install, all campaigns, and your Rise of the Elves saves and mods stay where they are.

## What it adds

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

Only the GOG executable is supported (optionally with Lazy Mod 1.06, see below). The mod hooks fixed addresses inside `Discipl2.exe`, and the installer refuses any other version. The original Akella / Russobit / Steam builds won't work.

The mod contains no game files. Every map, text and image comes from your own copies of the games.

## Install

1. Download the latest `AllCampaigns-*.zip` from the [Releases](../../releases) page (not the "Source code" zip) and unpack it anywhere.
2. Double-click `install.bat`.
3. It offers the GOG folders it finds. Press Enter to accept each one, or paste a different path.
4. It asks whether to also install two optional mods (see [Optional mods](#optional-mods)). If one is already installed, it skips the question.
5. Start the game, choose *New Campaign*, pick a race and click the new button.

The installer:

- checks `Discipl2.exe` is GOG Rise of the Elves v3.01;
- backs up every file it changes into `_AllCampaigns_backup` in the game folder;
- renames `MSS32.DLL` to `mss23.dll` and puts the mod's `mss32.dll` and `Scripts` folder next to it;
- adds the button to `DLG_CHOOSE_RACE` in `interf\Interf.dlg`;
- copies the Gallean's Return missions from your Dark Prophecy install into the `scens` tables (see below);
- creates the `SaveGame` folder. The GOG install doesn't have one, and without it the game silently fails to save;
- installs the optional mods you said yes to, backing up every file they replace.

Everything is checked before anything is changed: if a folder, file or download is wrong, the installer stops and the game stays as it was.

GOG Galaxy updates may overwrite modded files. Run `uninstall.bat` and then `install.bat` again after an update.

## Uninstall

Double-click `uninstall.bat`. It removes the mod, and the optional mods if the installer added them, restores everything from `_AllCampaigns_backup` and deletes the backup folder. Your saved games are kept.

## How it works

**The button.** The mod is built on the [Disciples 2 modding toolset](https://github.com/VladimirMakeev/D2ModdingToolset) by Vladimir Makeev, which loads into the game as a replacement `mss32.dll` and lets code hook game functions. This repository is a fork of it. The mod adds three hooks to the campaign race menu (`mss32/src/menuracecampaignhooks.cpp`):

- the menu constructor wires up `BTN_GALLEAN`;
- campaign selection swaps the Dark Prophecy campaign id for the matching Gallean's Return one when the button was used;
- the button update hook sets the label per race and disables the button on the skirmish menu.

For the Elves, the button replays what the *Custom Saga* menu does when you pick a saga, using *The Alliance Crusade.csg* from the game's `campaign` folder (`mss32/src/customsaga.cpp`).

**The missions.** Rise of the Elves lists the Gallean's Return campaigns, but its scenarios S123 to S134 are empty placeholder maps. The real ones live in the Dark Prophecy install. Both games store scenarios in dBase tables (`scens\*.dbf`), but Rise of the Elves added and widened columns, so rows can't be copied as raw bytes. The installer rebuilds each row column by column:

- columns both games have are copied and re-padded to the new width;
- resource strings such as `G0100:R0000:Y0000:E0000:W0000` get `:B0000` added for the Elves' mana;
- columns only Rise of the Elves has get the most common value from its own rows.

All other Rise of the Elves rows are left exactly as they were.

## Optional mods

Neither is part of this mod. They're made by other people, so the installer fetches them from their own pages, and the credit stays with their authors.

### DisciplesGL-Modern (OpenGL wrapper)

[DisciplesGL-Modern](https://github.com/gitTerebi/DisciplesGL-Modern) is a maintained build of Verokster's DisciplesGL wrapper. It makes the game display properly on modern Windows and monitors. The installer downloads release **v2026.4** from GitHub and checks the file's SHA-256 before using it. The version is pinned on purpose, so a newer release can't be installed without being tested first.

It replaces `C4dll-R.dll` and `SHW32.dll` and adds `CB63.dll`, `Imgs\Wrapper.ff`, `Imgs\IsoClouds.ff` and `Mods\timer.mod`. None of these are files this mod touches.

No internet? Download `DisciplesGL-Modern-C4dll-R.zip` from the v2026.4 release yourself and run `install.ps1 -WrapperZip <path to the zip>`.

### Lazy Mod 1.06

[Lazy Mod](https://www.moddb.com/mods/d2rote-lazy-mod/downloads/disciples-2-lazy-mod-106) is a rebalance of Rise of the Elves: stronger heroes, new skills, reworked items and a tougher AI. ModDB doesn't allow downloads from scripts, so the installer opens the download page in your browser and asks for the zip (or the folder you unpacked it to). It only accepts Lazy Mod **1.06**, recognised by its `Discipl2.exe`.

It works with this mod, whether Lazy Mod goes in before or after it:

- Lazy Mod's `Discipl2.exe` is the same size and code as the GOG one. It only blanks six unit ids in the data section, so the hooks still land on the same functions. The installer accepts it.
- Lazy Mod's `CCamp.dbf` keeps the same campaign ids, so the button still picks the right Gallean's Return campaign.
- Every unit, item, spell and landmark id the Gallean's Return maps use still exists in Lazy Mod's `Globals`.
- Lazy Mod doesn't touch `Interf.dlg` or `scens`, the files this mod edits.

The Gallean's Return missions then play with Lazy Mod's balance changes. Lazy Mod also ships the same four campaigns as Custom Sagas; this mod runs them as real campaigns instead.

## Known limits

- GOG Rise of the Elves v3.01 only (optionally with Lazy Mod 1.06).
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
- **Verokster** for [DisciplesGL](https://verokster.blogspot.com/2019/03/disciples-i-ii-gl-wrapper-patch.html), and **gitTerebi** for [DisciplesGL-Modern](https://github.com/gitTerebi/DisciplesGL-Modern) (MIT licence). Not included here; downloaded from its GitHub release.
- The author of [Lazy Mod](https://www.moddb.com/mods/d2rote-lazy-mod). Not included here; downloaded by the player from ModDB.
- Strategy First and .dat for Disciples II. This is an unofficial fan mod, not affiliated with them or with GOG.

## Licence

GPL-3.0, the same as the toolset. See `LICENSE`.
