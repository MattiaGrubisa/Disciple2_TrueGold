/*
 * This file is part of the modding toolset for Disciples 2.
 * (https://github.com/VladimirMakeev/D2ModdingToolset)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef CUSTOMSAGA_H
#define CUSTOMSAGA_H

#include "d2assert.h"
#include "d2string.h"

namespace game {

struct CMidgard;
struct CMenuPhase;
struct CMenuRace;

/**
 * One row of the Custom Saga list: built by the game for each .csg file it finds.
 * Only fields used by the Custom Saga 'Continue' handler (GOG 0x4dbebd) are named.
 */
struct CustomSagaEntry
{
    String filePath;   /**< Full path to the .csg file. */
    String unknown10;  /**< From saga object, function 0x4cc7bc. */
    String unknown20;  /**< From saga object, function 0x66b1c2. */
    int unknown30;     /**< Passed to CMidgard setter 0x40368a. */
    int unknown34;     /**< From 0x66b6f7. */
    int unknown38;     /**< From 0x66b780. */
    int raceValue;     /**< Fed into the race lookup chain by the game. */
    int suggestedLevel;
    String unknown44;  /**< From saga object, function 0x66b1d1. */
};

assert_size(CustomSagaEntry, 84);
assert_offset(CustomSagaEntry, unknown30, 48);
assert_offset(CustomSagaEntry, raceValue, 60);
assert_offset(CustomSagaEntry, suggestedLevel, 64);

/** List of custom sagas found in a folder. Holds a pointer to an array of CustomSagaEntry. */
struct CustomSagaList
{
    void* entries;
};

assert_size(CustomSagaList, 4);

/** Scenario header read from a .sg file. Only name and description are known. */
struct CustomSagaScenarioHeader
{
    String name;        /**< Offset 0, read by Continue as [header + 8]. */
    String description; /**< Offset 16, read by Continue as [header + 24]. */
    char unknown[480];  /**< Real size unknown; game uses less, extra space is a safety margin. */
};

namespace CustomSagaApi {

struct Api
{
    /** Scans 'folder' for .csg files. filter 1 is what the Custom Saga menu uses. GOG 0x66b49c */
    using ListConstructor = CustomSagaList*(__thiscall*)(CustomSagaList* thisptr,
                                                         const char* folder,
                                                         int filter);
    ListConstructor listConstructor;

    /** Frees the entries. GOG 0x66b8ce */
    using ListDestructor = void(__thiscall*)(CustomSagaList* thisptr);
    ListDestructor listDestructor;

    /** GOG 0x66b8e4 */
    using ListCount = int(__thiscall*)(CustomSagaList* thisptr);
    ListCount listCount;

    /** GOG 0x66b8f2 */
    using ListGet = CustomSagaEntry*(__thiscall*)(CustomSagaList* thisptr, int index);
    ListGet listGet;

    /** Unpacks scenario 'index' of a .csg into 'outputPath'. GOG 0x66a762 */
    using ExtractScenario = bool(__stdcall*)(int index,
                                             const char* sagaPath,
                                             const char* outputPath);
    ExtractScenario extractScenario;

    /** GOG 0x4dc242 */
    using HeaderConstructor = void(__thiscall*)(CustomSagaScenarioHeader* thisptr);
    HeaderConstructor headerConstructor;

    /** Reads header from a .sg file. GOG 0x669ef1 */
    using ReadHeader = void(__stdcall*)(CustomSagaScenarioHeader* header, const char* path);
    ReadHeader readHeader;

    /** GOG 0x42a8bd */
    using HeaderDestructor = void(__thiscall*)(CustomSagaScenarioHeader* thisptr);
    HeaderDestructor headerDestructor;

    /** Opens scenario file and stores handle in CMenuPhaseData. GOG 0x4eaf69 */
    using OpenScenarioFile = bool(__thiscall*)(CMenuPhase* thisptr, const char* path);
    OpenScenarioFile openScenarioFile;

    /** CMidgard string at data offset 0xdc: current saga file path. GOG 0x403645 */
    using SetSagaPath = void(__thiscall*)(CMidgard* thisptr, const char* path);
    SetSagaPath setSagaPath;

    /** CMidgard int at data offset 0xec. Custom Saga Continue sets it to 0. GOG 0x40367a */
    using SetInt = void(__thiscall*)(CMidgard* thisptr, int value);
    SetInt setSagaUnknownEC;

    /** CMidgard int at data offset 0xf0, set from CustomSagaEntry::unknown30. GOG 0x40368a */
    SetInt setSagaUnknownF0;

    /** Race menu: refresh buttons and transition to the lord menu. GOG 0x4ee514 */
    using RaceMenuFinish = void(__thiscall*)(CMenuRace* thisptr);
    RaceMenuFinish raceMenuFinish;
};

/** Addresses are only known for the GOG version, other versions return nullptrs. */
Api& get();

} // namespace CustomSagaApi

} // namespace game

#endif // CUSTOMSAGA_H
