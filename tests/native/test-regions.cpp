#include "BarRegionRegistry.hpp"
#include <cassert>
#include <iostream>
using Registry=TapeBarPress::RegionRegistry;
int main() {
    Registry regions;
    const auto now=Registry::Clock::now();
    const TapeBarPress::Region bounds{0,0,100,26};
    assert(regions.refresh("one","old",bounds,now));
    assert(regions.refresh("one","new",bounds,now));
    assert(regions.count(now)==2);
    regions.clear("one","old");
    assert(regions.count(now)==1 && regions.contains("one",50,10,now));
    assert(!regions.contains("two",50,10,now));
    assert(!regions.contains("one",100,10,now));
    assert(!regions.contains("one",50,26,now));
    assert(regions.refresh("two","new",{200,0,100,26},now));
    regions.clear("one","new");
    assert(regions.count(now)==1 && regions.contains("two",250,10,now));
    assert(regions.contains("two",250,10,now+Registry::lease));
    assert(!regions.contains("two",250,10,now+Registry::lease+std::chrono::milliseconds(1)));
    assert(!regions.refresh("one","",bounds,now));
    assert(!regions.refresh("one",std::string_view{"a\0b",3},bounds,now));
    assert(!regions.refresh("one","owner",{0,0,0,26},now));
    regions.clearAll();
    for (size_t i=0;i<Registry::limit;++i) assert(regions.refresh("one",std::to_string(i),bounds,now));
    assert(!regions.refresh("one","extra",bounds,now));
    assert(regions.refresh("one","0",bounds,now));
    assert(regions.refresh("one","extra",bounds,now+Registry::lease+std::chrono::milliseconds(1)));
    assert(regions.count(now+Registry::lease+std::chrono::milliseconds(1))==1);
    std::cout << "Region owner replacement, monitor isolation, expiry, bounds and capacity checks passed\n";
}
