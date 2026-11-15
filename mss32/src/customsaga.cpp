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

#include "customsaga.h"
#include "version.h"
#include <array>

namespace game::CustomSagaApi {

// clang-format off
static std::array<Api, 3> functions = {{
    // Akella (unknown)
    Api{},
    // Russobit (unknown)
    Api{},
    // Gog
    Api{
        (Api::ListConstructor)0x66b49c,
        (Api::ListDestructor)0x66b8ce,
        (Api::ListCount)0x66b8e4,
        (Api::ListGet)0x66b8f2,
        (Api::ExtractScenario)0x66a762,
        (Api::HeaderConstructor)0x4dc242,
        (Api::ReadHeader)0x669ef1,
        (Api::HeaderDestructor)0x42a8bd,
        (Api::OpenScenarioFile)0x4eaf69,
        (Api::SetSagaPath)0x403645,
        (Api::SetInt)0x40367a,
        (Api::SetInt)0x40368a,
        (Api::RaceMenuFinish)0x4ee514,
    }
}};
// clang-format on

Api& get()
{
    return functions[static_cast<int>(hooks::gameVersion())];
}

} // namespace game::CustomSagaApi
