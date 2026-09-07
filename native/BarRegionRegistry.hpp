#pragma once
#include "BarPressGuard.hpp"
#include <chrono>
#include <string>
#include <string_view>
#include <unordered_map>

namespace TapeBarPress {
// Each shell service owns its own expiring registrations. Destruction of an
// older service may clear only that owner's registration on the output.
class RegionRegistry {
  public:
    using Clock = std::chrono::steady_clock;
    static constexpr auto lease = std::chrono::milliseconds(3500);
    static constexpr size_t limit = 256;

    bool refresh(std::string_view monitor, std::string_view owner, Region bounds, Clock::time_point now) {
        if (!bounds.valid() || !validName(monitor,256) || !validName(owner,128)) return false;
        std::erase_if(m_regions,[now](const auto& item) {return now-item.second.refreshed > lease;});
        const auto id=key(monitor,owner);
        if (m_regions.size() >= limit && !m_regions.contains(id)) return false;
        m_regions[id]={std::string{monitor},bounds,now};
        return true;
    }
    void clear(std::string_view monitor,std::string_view owner) {m_regions.erase(key(monitor,owner));}
    void clearAll() {m_regions.clear();}
    bool contains(std::string_view monitor,double x,double y,Clock::time_point now) const {
        for (const auto& [id,entry]:m_regions)
            if (entry.monitor==monitor && now-entry.refreshed <= lease && entry.bounds.contains(x,y)) return true;
        return false;
    }
    size_t count(Clock::time_point now) const {
        size_t count=0;
        for (const auto& [id,entry]:m_regions) if (now-entry.refreshed <= lease) ++count;
        return count;
    }
  private:
    struct Entry {std::string monitor;Region bounds;Clock::time_point refreshed;};
    std::unordered_map<std::string,Entry> m_regions;
    static bool validName(std::string_view value,size_t maximum) {
        return !value.empty() && value.size() <= maximum && value.find('\0')==std::string_view::npos;
    }
    static std::string key(std::string_view monitor,std::string_view owner) {return std::string{owner}+'\0'+std::string{monitor};}
};
}
