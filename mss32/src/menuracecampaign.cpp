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

#include "menuracecampaign.h"
#include "version.h"
#include <array>

namespace game::CMenuRaceCampaignApi {

// clang-format off
static std::array<Api, 3> functions = {{
    // Akella (unknown)
    Api{
        (Api::Constructor)nullptr,
        (Api::SelectCampaign)nullptr,
        (Api::ContinueCallback)nullptr,
    },
    // Russobit (unknown)
    Api{
        (Api::Constructor)nullptr,
        (Api::SelectCampaign)nullptr,
        (Api::ContinueCallback)nullptr,
    },
    // Gog
    Api{
        (Api::Constructor)0x4ee5fc,
        (Api::SelectCampaign)0x4ee7a0,
        (Api::ContinueCallback)0x4ee4d9,
    }
}};
// clang-format on

static std::array<const void*, 3> vftables = {{
    // Akella (unknown)
    nullptr,
    // Russobit (unknown)
    nullptr,
    // Gog
    (const void*)0x6dd874,
}};
// clang-format on

Api& get()
{
    return functions[static_cast<int>(hooks::gameVersion())];
}

const void* vftable()
{
    return vftables[static_cast<int>(hooks::gameVersion())];
}

} // namespace game::CMenuRaceCampaignApi
