#include "BarPressGuard.hpp"
#include <algorithm>
#include <cassert>
#include <iostream>
#include <vector>
#include <hyprutils/signal/Signal.hpp>
#include <wayland-server-core.h>

struct Inhibitor { bool isInhibited = false; double offsetWhenInhibited = 73; };

struct Layout {
    Inhibitor inhibitor;
    double camera = 1167;
    std::vector<double> changes;
    void setCamera(double value) {
        const auto next = inhibitor.isInhibited ? inhibitor.offsetWhenInhibited : value;
        if (next != camera) changes.push_back(next);
        camera = next;
    }
    void nativeRelease(bool focusedChatGPT) {
        // Actual upstream focusOnInput(CLICK): a cursor image extending below
        // the bar overlaps the old focused target; clipped ChatGPT fits left.
        // Discord (right-aligned half) is already completely visible.
        if (focusedChatGPT) setCamera(std::clamp(camera, 667., 1000.));
    }
    void jumpToChrome() { setCamera(2167); }
};

int main() {
    // Reproduce the user-reported opposite-direction precursor before the
    // asynchronous strip helper even runs. Fully visible Discord has no bounce.
    Layout broken;
    broken.nativeRelease(true);
    broken.jumpToChrome();
    assert((broken.changes == std::vector<double>{1000,2167}));
    Layout alreadyVisible;
    alreadyVisible.nativeRelease(false);
    alreadyVisible.jumpToChrome();
    assert((alreadyVisible.changes == std::vector<double>{2167}));

    for (bool focusedChatGPT : {false,true}) {
        for (bool nativeListenerFirst : {false,true}) {
            Layout fixed;
            TapeBarPress::Lease<Inhibitor> guard;
            assert(guard.acquire(fixed.inhibitor,fixed.camera)); // button PRESS
            // Use the compositor's actual signal and event-loop libraries,
            // independently of any display/compositor or the user's desktop.
            auto* loop = wl_event_loop_create();
            assert(loop);
            struct Cleanup { TapeBarPress::Lease<Inhibitor>* lease; Inhibitor* target; bool ran = false; } cleanup{&guard,&fixed.inhibitor};
            Hyprutils::Signal::CSignalT<> release;
            Hyprutils::Signal::CHyprSignalListener nativeListener, guardListener;
            auto addNative = [&] { nativeListener = release.listen([&] { fixed.nativeRelease(focusedChatGPT); }); };
            auto addGuard = [&] { guardListener = release.listen([&] {
                assert(wl_event_loop_add_idle(loop, [](void* value) {
                    auto& c = *static_cast<Cleanup*>(value);
                    assert(c.lease->restore(*c.target));
                    c.ran = true;
                }, &cleanup));
            }); };
            if (nativeListenerFirst) { addNative(); addGuard(); }
            else { addGuard(); addNative(); }
            release.emit();
            assert(fixed.changes.empty() && fixed.camera == 1167);
            assert(!cleanup.ran && fixed.inhibitor.isInhibited);
            wl_event_loop_dispatch_idle(loop);
            assert(cleanup.ran);
            assert(!fixed.inhibitor.isInhibited && fixed.inhibitor.offsetWhenInhibited == 73);
            fixed.jumpToChrome();
            assert((fixed.changes == std::vector<double>{2167}));
            wl_event_loop_destroy(loop);
        }
    }

    // Cancelled drags/lost release cleanup restores both original fields.
    Layout cancelled;
    TapeBarPress::Lease<Inhibitor> lease;
    assert(lease.acquire(cancelled.inhibitor,cancelled.camera));
    assert(lease.restore(cancelled.inhibitor));
    assert(!cancelled.inhibitor.isInhibited && cancelled.inhibitor.offsetWhenInhibited == 73);
    assert(!lease.restore(cancelled.inhibitor));
    // An independently active inhibitor is never acquired or removed.
    Inhibitor independentlyActive{true,777};
    assert(!lease.acquire(independentlyActive,1167));
    assert(!lease.restore(independentlyActive));
    assert(independentlyActive.isInhibited && independentlyActive.offsetWhenInhibited == 777);
    // A later external inhibitor superseding ours is not overwritten.
    assert(lease.acquire(cancelled.inhibitor,1167));
    cancelled.inhibitor.offsetWhenInhibited = 555;
    assert(!lease.restore(cancelled.inhibitor));
    assert(cancelled.inhibitor.isInhibited && cancelled.inhibitor.offsetWhenInhibited == 555);

    const TapeBarPress::Region strip{320,-146,490,26};
    assert(strip.valid() && strip.contains(400,-132));
    assert(!strip.contains(400,-112)); // ordinary app click below bar
    assert(!strip.contains(900,-132)); // another bar widget, outside strip
    assert(!strip.contains(320,-120)); // bottom is exclusive
    assert(!TapeBarPress::Region{0,0,-1,26}.valid());
    assert(!TapeBarPress::Region{0,NAN,200,26}.valid());
    assert(!TapeBarPress::Region{0,0,INFINITY,26}.valid());
    // Removing pending release cleanup on plugin unload does not leave an idle
    // callback referencing plugin code after it has been unloaded.
    auto* loop = wl_event_loop_create();
    bool unexpectedCallback = false;
    auto* pending = wl_event_loop_add_idle(loop, [](void* value) { *static_cast<bool*>(value) = true; }, &unexpectedCallback);
    assert(pending);
    wl_event_source_remove(pending);
    wl_event_loop_dispatch_idle(loop);
    assert(!unexpectedCallback);
    wl_event_loop_destroy(loop);
    std::cout << "Bar-release direction regression, both listener orders, cancellation/ownership and strip bounds passed\n";
}
