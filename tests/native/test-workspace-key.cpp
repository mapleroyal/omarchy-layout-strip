#include "WorkspaceKey.hpp"
#include <cassert>
#include <iostream>

int main() {
    auto* lua = luaL_newstate();
    assert(lua);
    const auto check = [&](std::optional<uint32_t> number, std::string_view name, bool expected) {
        const auto top = lua_gettop(lua);
        assert(TapeWorkspaceKey::matches(lua, -1, number, name) == expected);
        assert(lua_gettop(lua) == top); // Matching never changes the caller's stack.
    };
    lua_pushinteger(lua, 1);
    check(1, "1", true);
    check(2, "2", false); // Stale workspace after a monitor switch.
    check(std::nullopt, "special:scratchpad", false);
    lua_pop(lua, 1);

    lua_pushstring(lua, "special:scratchpad");
    check(std::nullopt, "special:scratchpad", true);
    check(std::nullopt, "special:notes", false);
    check(1, "1", false); // No fallback to the visible numbered workspace.
    lua_pop(lua, 1);

    lua_pushstring(lua, "name:project");
    check(7, "name:project", true);
    check(8, "name:other", false);
    lua_pop(lua, 1);

    for (const auto value : {-1LL, 4294967296LL}) {
        lua_pushinteger(lua, value);
        assert(!TapeWorkspaceKey::valid(lua, -1));
        check(UINT32_MAX, "4294967295", false); // No signed/unsigned aliasing.
        lua_pop(lua, 1);
    }
    lua_pushinteger(lua, UINT32_MAX);
    check(UINT32_MAX, "4294967295", true);
    lua_pop(lua, 1);

    lua_pushnumber(lua, 1.5);
    check(1, "1", false);
    lua_pop(lua, 1);
    lua_pushboolean(lua, true);
    check(1, "1", false);
    lua_pop(lua, 1);
    lua_pushnil(lua);
    check(std::nullopt, "special:scratchpad", false);
    lua_pop(lua, 1);
    lua_pushstring(lua, "");
    check(std::nullopt, "", false);
    lua_pop(lua, 1);
    constexpr char badName[] = "special:scratchpad\0suffix";
    lua_pushlstring(lua, badName, sizeof(badName) - 1);
    check(std::nullopt, std::string_view{badName, sizeof(badName) - 1}, false);
    lua_pop(lua, 1);
    assert(lua_gettop(lua) == 0);
    lua_close(lua);
    std::cout << "workspace-key identity and rejection checks passed\n";
}
