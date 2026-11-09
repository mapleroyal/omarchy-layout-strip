#pragma once

#include <lua.hpp>
#include <cstdint>
#include <limits>
#include <optional>
#include <string_view>

// Hyprland 0.57 keeps numbered Lua workspace IDs but gives special workspaces
// only an addressable_name. Match that exact identity without parsing names,
// inventing integer IDs, or allowing numeric wraparound to another workspace.
namespace TapeWorkspaceKey {
inline bool valid(lua_State* lua, int index) {
    if (lua_isinteger(lua, index)) {
        const auto value = lua_tointeger(lua, index);
        return value >= 0 && static_cast<uint64_t>(value) <= std::numeric_limits<uint32_t>::max();
    }
    if (lua_type(lua, index) != LUA_TSTRING)
        return false;
    size_t size = 0;
    const char* text = lua_tolstring(lua, index, &size);
    const std::string_view name{text, size};
    return !name.empty() && name.find('\0') == std::string_view::npos;
}

inline bool matches(lua_State* lua, int index, std::optional<uint32_t> numberedID, std::string_view addressableName) {
    if (!valid(lua, index))
        return false;
    if (lua_isinteger(lua, index))
        return numberedID && static_cast<uint64_t>(lua_tointeger(lua, index)) == *numberedID;
    size_t size = 0;
    const char* text = lua_tolstring(lua, index, &size);
    return addressableName == std::string_view{text, size};
}
}
