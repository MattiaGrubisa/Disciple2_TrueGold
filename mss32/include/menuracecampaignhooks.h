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

#ifndef MENURACECAMPAIGNHOOKS_H
#define MENURACECAMPAIGNHOOKS_H

#include "midgardid.h"

namespace game {
struct CMenuRace;
struct CMenuPhase;
} // namespace game

namespace hooks {

game::CMenuRace* __fastcall menuRaceCampaignCtorHooked(game::CMenuRace* thisptr,
                                                       int /*%edx*/,
                                                       game::CMenuPhase* menuPhase);

void __fastcall menuRaceCampaignSelectCampaignHooked(game::CMenuRace* thisptr,
                                                     int /*%edx*/,
                                                     game::CMidgardID campaignId);

/** Runs for both race menus (campaign and skirmish / custom saga) whenever the race changes. */
void __stdcall menuRaceUpdateButtonsHooked(game::CMenuRace* thisptr);

} // namespace hooks

#endif // MENURACECAMPAIGNHOOKS_H
