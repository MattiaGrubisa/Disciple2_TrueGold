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

#include "menuracecampaignhooks.h"
#include "button.h"
#include "categoryids.h"
#include "customsaga.h"
#include "dialoginterf.h"
#include "gamesettings.h"
#include "globaldata.h"
#include "log.h"
#include "menubase.h"
#include "menuphase.h"
#include "menurace.h"
#include "menuracecampaign.h"
#include "midgard.h"
#include "originalfunctions.h"
#include "racecategory.h"
#include "racelist.h"
#include "smartptr.h"
#include "textboxinterf.h"
#include <cstdlib>
#include <cstring>
#include <fmt/format.h>

namespace hooks {

// Controls added to DLG_CHOOSE_RACE in Interf.dlg. If they are missing, the menu works as before.
static const char dialogName[] = "DLG_CHOOSE_RACE";
static const char buttonName[] = "BTN_GALLEAN";
static const char labelName[] = "TXT_GALLEAN";
static const char logFile[] = "mss32RaceCampaign.log";

/**
 * True only while our button's click is being handled.
 * The game's Continue handler runs synchronously and calls SelectCampaign before returning,
 * so SelectCampaign can tell which button was clicked by looking at this flag.
 */
static bool galleansReturnClicked{false};

/** Dark Prophecy campaign id and the Gallean's Return campaign of the same race. */
struct CampaignPair
{
    game::RaceId race;
    const char* darkProphecy;
    const char* galleansReturn;
};

// From campaign\CCamp.dbf, PLAY_RACE column. Elves (C000CC0006) have no second campaign.
static const CampaignPair campaignPairs[] = {
    {game::RaceId::Human, "C000CC0002", "C000CC0012"},  // Empire
    {game::RaceId::Dwarf, "C000CC0003", "C000CC0013"},  // Mountain Clans
    {game::RaceId::Heretic, "C000CC0004", "C000CC0014"}, // Legions of the Damned
    {game::RaceId::Undead, "C000CC0005", "C000CC0015"}, // Undead Hordes
};

// The Elves' second campaign is a custom saga in the campaign folder
static const char elvesSagaFile[] = "The Alliance Crusade.csg";

static game::RaceId raceOnScreen(game::CMenuRace* menu)
{
    using namespace game;

    LRaceCategory race;
    CMenuRaceApi::get().getRaceCategory(&race, menu->menuRaceData->screenIndex);
    return race.id;
}

/** Returns true if the race has a Gallean's Return campaign. */
static bool hasSecondCampaign(game::RaceId race)
{
    for (const auto& pair : campaignPairs) {
        if (race == pair.race) {
            return true;
        }
    }

    return false;
}

static bool endsWithNoCase(const char* text, const char* suffix)
{
    const std::size_t textLength{std::strlen(text)};
    const std::size_t suffixLength{std::strlen(suffix)};

    return textLength >= suffixLength
           && _stricmp(text + textLength - suffixLength, suffix) == 0;
}

static const char* textOrEmpty(const game::String& string)
{
    return string.string ? string.string : "";
}

/**
 * Starts a custom saga from the campaign race menu, as if the player had picked it on the
 * Custom Saga screen and then picked 'race' on its race menu.
 * Replays the Custom Saga 'Continue' handler (GOG 0x4dbebd) followed by the custom race
 * menu's start method (GOG 0x4ee5de). Returns false without changing anything if the saga
 * can't be found or unpacked.
 */
static bool startCustomSaga(game::CMenuRace* menu, const char* sagaFileName, game::RaceId raceId)
{
    using namespace game;

    const auto& sagaApi{CustomSagaApi::get()};
    const auto& menuPhaseApi{CMenuPhaseApi::get()};

    CMidgard* midgard{CMidgardApi::get().instance()};
    const GameSettings* settings{*midgard->data->settings};

    // 1. Build the same saga list the Custom Saga menu shows and find our saga in it
    CustomSagaList sagas;
    sagaApi.listConstructor(&sagas, textOrEmpty(settings->campaignFolder), 1);

    const CustomSagaEntry* entry{nullptr};
    const int count{sagaApi.listCount(&sagas)};
    for (int i = 0; i < count; ++i) {
        const CustomSagaEntry* candidate{sagaApi.listGet(&sagas, i)};
        if (endsWithNoCase(textOrEmpty(candidate->filePath), sagaFileName)) {
            entry = candidate;
            break;
        }
    }

    if (!entry) {
        logDebug(logFile, fmt::format("Saga '{:s}' not found among {:d} sagas in '{:s}'",
                                      sagaFileName, count, textOrEmpty(settings->campaignFolder)));
        sagaApi.listDestructor(&sagas);
        return false;
    }

    const char* sagaPath{textOrEmpty(entry->filePath)};
    logDebug(logFile, fmt::format("Found saga '{:s}': unknown30 {:d}, unknown34 {:d}, "
                                  "unknown38 {:d}, raceValue {:#x}, suggestedLevel {:d}",
                                  sagaPath, entry->unknown30, entry->unknown34, entry->unknown38,
                                  entry->raceValue, entry->suggestedLevel));

    // 2. Unpack the first mission to exports\D2CC_Current.sg, like Continue does
    char currentPath[260]{};
    _makepath_s(currentPath, nullptr, textOrEmpty(settings->exportsFolder), "D2CC_Current.sg",
                nullptr);

    if (!sagaApi.extractScenario(0, sagaPath, currentPath)) {
        logDebug(logFile, fmt::format("Failed to unpack first mission of '{:s}' to '{:s}'",
                                      sagaPath, currentPath));
        sagaApi.listDestructor(&sagas);
        return false;
    }

    // 3. Point the menu phase at the unpacked mission
    CMenuPhase* menuPhase{menu->menuBaseData->menuPhase};
    CMenuPhaseData* data{menuPhase->data};

    data->unknown8 = true;
    menuPhaseApi.setScenarioFilePath(menuPhase, currentPath);
    const bool fileOpened{sagaApi.openScenarioFile(menuPhase, currentPath)};

    // 4. Name and description come from the mission's own header
    CustomSagaScenarioHeader header{};
    sagaApi.headerConstructor(&header);
    sagaApi.readHeader(&header, currentPath);

    CMidgardID customCampaignId;
    CMidgardIDApi::get().fromString(&customCampaignId, "C000CC0001");
    menuPhaseApi.setCampaignId(menuPhase, &customCampaignId);
    menuPhaseApi.setScenarioName(menuPhase, textOrEmpty(header.name));
    menuPhaseApi.setScenarioDescription(menuPhase, textOrEmpty(header.description));
    data->suggestedLevel = entry->suggestedLevel;

    logDebug(logFile, fmt::format("Mission '{:s}', file opened: {:d}", textOrEmpty(header.name),
                                  fileOpened));
    sagaApi.headerDestructor(&header);

    // 5. CMidgard remembers which saga is running, used for later missions
    sagaApi.setSagaPath(midgard, sagaPath);
    sagaApi.setSagaUnknownEC(midgard, 0);
    sagaApi.setSagaUnknownF0(midgard, entry->unknown30);

    // 6. The saga is played by one race: the one on screen
    const GlobalData* globalData{*GlobalDataApi::get().getGlobalData()};
    const int raceIdValue{static_cast<int>(raceId)};
    LRaceCategory race{};
    LRaceCategoryTableApi::get().findCategoryById(globalData->raceCategories, &race,
                                                  &raceIdValue);

    const auto& listApi{RaceCategoryListApi::get()};
    listApi.freeNodes(&data->races);
    listApi.add(&data->races, &race);
    data->maxPlayers = 1;

    // What the custom race menu's start method does (0x4ee5de): set race, then move on
    data->race.table = race.table;
    data->race.id = race.id;

    sagaApi.listDestructor(&sagas);

    sagaApi.raceMenuFinish(menu);
    return true;
}

/**
 * Shows the right label for the race on screen, and greys the button out where it does nothing:
 * on races without a second campaign, and on the skirmish / custom saga race menu, which uses
 * the same DLG_CHOOSE_RACE layout.
 */
static void refreshSecondCampaignControls(game::CMenuRace* menu)
{
    using namespace game;

    const auto& dialogApi{CDialogInterfApi::get()};
    CDialogInterf* dialog{CMenuBaseApi::get().getDialogInterface(menu)};

    CButtonInterf* button{dialogApi.findButton(dialog, buttonName)};
    CTextBoxInterf* label{dialogApi.findTextBox(dialog, labelName)};
    if (!button && !label) {
        return;
    }

    const char* text{""};
    // Checking the vftable tells the campaign menu apart from the skirmish one
    if (*reinterpret_cast<const void* const*>(menu) == CMenuRaceCampaignApi::vftable()) {
        const RaceId race{raceOnScreen(menu)};

        if (race == RaceId::Elf) {
            text = "The Alliance Crusade";
        } else if (hasSecondCampaign(race)) {
            text = "Gallean's Return";
        }
    }

    if (button) {
        button->vftable->setEnabled(button, text[0] != '\0');
    }

    if (label) {
        CTextBoxInterfApi::get().setString(label, text);
    }
}

void __stdcall menuRaceUpdateButtonsHooked(game::CMenuRace* thisptr)
{
    getOriginalFunctions().menuRaceUpdateButtons(thisptr);
    refreshSecondCampaignControls(thisptr);
}

/**
 * BTN_GALLEAN click handler: same as Continue, but starts the race's second campaign.
 * Empire, Clans, Legions and Undead get Gallean's Return, Elves get The Alliance Crusade.
 */
static void __fastcall galleanButtonCallback(game::CMenuRace* thisptr, int /*%edx*/)
{
    using namespace game;

    const RaceId race{raceOnScreen(thisptr)};

    if (race == RaceId::Elf) {
        if (!startCustomSaga(thisptr, elvesSagaFile, race)) {
            logDebug(logFile, "Could not start the Elves saga, staying on race menu");
        }
        return;
    }

    if (!hasSecondCampaign(race)) {
        logDebug(logFile, "Second campaign button clicked for a race without one");
        return;
    }

    galleansReturnClicked = true;
    CMenuRaceCampaignApi::get().continueCallback(thisptr);
    galleansReturnClicked = false;
}

game::CMenuRace* __fastcall menuRaceCampaignCtorHooked(game::CMenuRace* thisptr,
                                                       int /*%edx*/,
                                                       game::CMenuPhase* menuPhase)
{
    using namespace game;

    // Build the screen exactly as the game does
    getOriginalFunctions().menuRaceCampaignCtor(thisptr, menuPhase);

    const auto& menuBase{CMenuBaseApi::get()};
    const auto& dialogApi{CDialogInterfApi::get()};
    CDialogInterf* dialog{menuBase.getDialogInterface(thisptr)};

    // Wire our button to our click handler, same way the toolset does for BTN_RANDOM_MAP
    const bool buttonFound{dialogApi.findControl(dialog, buttonName) != nullptr};
    if (buttonFound) {
        SmartPointer functor;
        auto callback = (CMenuBaseApi::Api::ButtonCallback)galleanButtonCallback;

        menuBase.createButtonFunctor(&functor, 0, thisptr, &callback);
        CButtonInterfApi::get().assignFunctor(dialog, buttonName, dialogName, &functor, 0);
        SmartPointerApi::get().createOrFreeNoDtor(&functor, nullptr);
    }

    // updateButtons already ran inside the parent constructor, before this menu's vftable was
    // set, so it treated the menu as a skirmish one. Refresh now that construction is done.
    refreshSecondCampaignControls(thisptr);

    logDebug(logFile, fmt::format("Campaign race menu created. Button found: {:d}", buttonFound));
    return thisptr;
}

void __fastcall menuRaceCampaignSelectCampaignHooked(game::CMenuRace* thisptr,
                                                     int /*%edx*/,
                                                     game::CMidgardID campaignId)
{
    using namespace game;

    const auto& original{getOriginalFunctions().menuRaceCampaignSelectCampaign};

    // Only our button sets this flag; Continue and the destructor go straight through
    if (galleansReturnClicked) {
        const auto& idApi{CMidgardIDApi::get()};

        for (const auto& pair : campaignPairs) {
            CMidgardID dpId;
            idApi.fromString(&dpId, pair.darkProphecy);

            if (campaignId == dpId) {
                idApi.fromString(&campaignId, pair.galleansReturn);
                logDebug(logFile, fmt::format("Starting Gallean's Return campaign {:s}",
                                              pair.galleansReturn));
                break;
            }
        }
    }

    original(thisptr, campaignId);
}

} // namespace hooks
