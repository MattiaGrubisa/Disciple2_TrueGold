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

#ifndef MENURACECAMPAIGN_H
#define MENURACECAMPAIGN_H

#include "menurace.h"
#include "midgardid.h"

namespace game {

struct CMenuPhase;

/**
 * Race selection menu shown when starting a new campaign.
 * Uses DLG_CHOOSE_RACE from Interf.dlg, same as the skirmish race menu.
 * Found by reverse engineering the GOG Rise of the Elves v3.01 executable.
 */
namespace CMenuRaceCampaignApi {

struct Api
{
    /**
     * Initializes the campaign race menu: calls CMenuRace constructor, zeroes field at
     * offset 16, sets vftable. GOG address 0x4ee5fc.
     */
    using Constructor = CMenuRace*(__thiscall*)(CMenuRace* thisptr, CMenuPhase* menuPhase);
    Constructor constructor;

    /**
     * Stores the chosen campaign in CMenuPhase and moves on to the next screen.
     * Called by the 'start campaign' vftable method with the race's first campaign id,
     * and by the destructor with emptyId. GOG address 0x4ee7a0.
     */
    using SelectCampaign = void(__thiscall*)(CMenuRace* thisptr, CMidgardID campaignId);
    SelectCampaign selectCampaign;

    /**
     * BTN_CONTINUE click handler. Gets the race on screen (CMenuRaceApi::getRaceCategory with
     * menuRaceData->screenIndex), then calls the 'start campaign' vftable method (offset 0x8c)
     * with it. GOG address 0x4ee4d9.
     */
    using ContinueCallback = void(__thiscall*)(CMenuRace* thisptr);
    ContinueCallback continueCallback;
};

/** Addresses are only known for the GOG version, other versions return nullptrs. */
Api& get();

/**
 * Vftable of the campaign race menu (GOG 0x6dd874). The skirmish and custom saga race menu
 * uses the same dialog with a different vftable (GOG 0x6dd7dc).
 */
const void* vftable();

} // namespace CMenuRaceCampaignApi

} // namespace game

#endif // MENURACECAMPAIGN_H
