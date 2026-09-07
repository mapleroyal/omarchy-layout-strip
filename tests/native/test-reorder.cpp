#include "Reorder.hpp"
#include <cassert>
#include <iostream>

static void near(double a, double b) { assert(std::abs(a - b) < 1e-8); }

int main() {
    using TapeReorder::plan;
    const std::vector<double> widths{500, 667, 1000, 500, 667, 500, 1000};
    // Offscreen changes on one side leave the visible app and camera untouched.
    auto p = plan(widths, 1000, 1167, 5, 6, true, 2);
    near(p.offset, 1167);
    assert(p.anchor == 2 && p.anchorPreserved);
    assert((p.order == std::vector<size_t>{0, 1, 2, 3, 4, 6, 5}));
    // Crossing from the left offscreen side to the right shifts the tape origin;
    // subtracting the moved width keeps the visible focused column stationary.
    p = plan(widths, 1000, 1167, 0, 6, true, 2);
    near(p.offset, 667);
    assert(p.anchor == 2 && p.anchorPreserved);
    // Offscreen focus itself is not a request to browse to the dragged source.
    p = plan(widths, 1000, 1167, 0, 6, true, 0);
    near(p.offset, 667);
    assert(p.anchor == 2 && p.anchorPreserved);
    // A visible focused source moved to the far end stays visible with minimum
    // necessary movement. The old anchor cannot also be retained in this case.
    p = plan(widths, 1000, 1167, 2, 6, true, 2);
    near(p.offset, 3834);
    assert(!p.anchorPreserved || !p.anchor);
    // Same-slot drops preserve deliberate half-placement camera margins.
    p = plan({500, 500}, 1000, -250, 0, 1, false, std::nullopt);
    near(p.offset, -250);
    assert(p.destination == 0);
    p = plan({500, 500}, 1000, -250, 0, 0, true, std::nullopt);
    near(p.offset, -250);

    size_t checked = 0;
    for (size_t n = 2; n <= 9; ++n) {
        std::vector<double> w(n);
        for (size_t i = 0; i < n; ++i) w[i] = std::vector<double>{500, 667, 1000}[i % 3];
        for (size_t source = 0; source < n; ++source)
            for (size_t target = 0; target < n; ++target)
                for (bool after : {false, true})
                    for (double offset : {0., 500., 1167.}) {
                        const auto result = plan(w, 1000, offset, source, target, after, std::nullopt);
                        auto untouched = result.order;
                        std::erase(untouched, source);
                        std::vector<size_t> expected;
                        for (size_t i = 0; i < n; ++i) if (i != source) expected.push_back(i);
                        assert(untouched == expected);
                        assert(result.order[result.destination] == source);
                        auto sorted = result.order;
                        std::sort(sorted.begin(), sorted.end());
                        for (size_t i = 0; i < n; ++i) assert(sorted[i] == i);
                        if (source != target) {
                            const auto targetIt = std::find(result.order.begin(), result.order.end(), target);
                            const auto sourceIt = std::find(result.order.begin(), result.order.end(), source);
                            assert(after ? sourceIt == targetIt + 1 : targetIt == sourceIt + 1);
                        }
                        assert(std::isfinite(result.offset));
                        ++checked;
                    }
    }
    for (const auto& invalid : std::vector<std::vector<double>>{{}, {500, -1}, {NAN, 500}, {INFINITY, 500}}) {
        bool rejected = false;
        try { plan(invalid, 1000, 0, 0, 1, true, std::nullopt); }
        catch (const std::invalid_argument&) { rejected = true; }
        assert(rejected);
    }
    using TapeReorder::Box;
    using TapeReorder::suppressOffscreenAnimation;
    const Box view{0,0,1000,800};
    const Box left{-500,0,500,800}, right{1000,0,667,800}, middle{0,0,500,800};
    assert(suppressOffscreenAnimation(left,left,right,view));
    assert(suppressOffscreenAnimation(right,right,left,view));
    assert(!suppressOffscreenAnimation(left,left,middle,view));
    assert(!suppressOffscreenAnimation(middle,middle,right,view));
    assert(!suppressOffscreenAnimation(left,middle,right,view));
    assert(!suppressOffscreenAnimation(right,left,right,view)); // unchanged goal
    assert(!suppressOffscreenAnimation({-499,0,500,800},left,right,view)); // one visible pixel
    assert(suppressOffscreenAnimation({0,-800,1000,800},{0,-800,1000,800},{0,800,1000,800},view));
    // Stacked targets are evaluated independently and retain their own heights.
    assert(suppressOffscreenAnimation({-500,0,500,400},{-500,0,500,400},{1000,0,500,400},view));
    assert(!suppressOffscreenAnimation({-500,400,500,400},{0,400,500,400},{1000,400,500,400},view));
    std::cout << checked << " order/geometry cases plus explicit camera and invalid-input checks passed\n";
}
