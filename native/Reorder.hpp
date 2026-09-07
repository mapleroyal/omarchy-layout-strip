#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <numeric>
#include <optional>
#include <stdexcept>
#include <vector>

namespace TapeReorder {

struct Box { double x, y, width, height; };

inline bool overlaps(const Box& a, const Box& b) {
    return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
}

inline bool suppressOffscreenAnimation(const Box& oldGoal, const Box& oldCurrent, const Box& newGoal, const Box& viewport) {
    const bool changed = std::abs(oldGoal.x - newGoal.x) > 0.01 || std::abs(oldGoal.y - newGoal.y) > 0.01 ||
                         std::abs(oldGoal.width - newGoal.width) > 0.01 || std::abs(oldGoal.height - newGoal.height) > 0.01;
    // Preserve any already-running animation that touches the viewport. Also
    // leave unchanged targets alone, even if they are animating offscreen.
    return changed && !overlaps(oldGoal, viewport) && !overlaps(oldCurrent, viewport) && !overlaps(newGoal, viewport);
}

struct Plan {
    std::vector<size_t> order;
    size_t destination = 0;
    std::optional<size_t> anchor;
    double offset = 0;
    bool anchorPreserved = true;
};

// Geometry uses native primary-axis strip sizes and camera goals, independently
// of the clients' animated positions. Identifiers are original vector indices.
inline Plan plan(const std::vector<double>& widths, double viewport, double offset,
                 size_t source, size_t target, bool after, std::optional<size_t> focused) {
    if (widths.empty() || source >= widths.size() || target >= widths.size() ||
        (focused && *focused >= widths.size()) || !std::isfinite(viewport) || viewport <= 0 || !std::isfinite(offset))
        throw std::invalid_argument("invalid reorder geometry");

    std::vector<double> oldStarts(widths.size()), newStarts(widths.size());
    double total = 0;
    for (size_t i = 0; i < widths.size(); ++i) {
        if (!std::isfinite(widths[i]) || widths[i] <= 0)
            throw std::invalid_argument("invalid column width");
        oldStarts[i] = total;
        total += widths[i];
    }
    if (!std::isfinite(total))
        throw std::invalid_argument("invalid tape extent");

    Plan result;
    result.order.resize(widths.size());
    std::iota(result.order.begin(), result.order.end(), size_t{0});
    result.offset = offset;
    result.destination = source;
    if (source == target)
        return result;

    result.order.erase(result.order.begin() + source);
    const auto neighbor = std::find(result.order.begin(), result.order.end(), target);
    const auto insertion = neighbor + (after ? 1 : 0);
    result.destination = static_cast<size_t>(insertion - result.order.begin());
    result.order.insert(insertion, source);
    if (result.destination == source)
        return result;

    const auto overlap = [&](size_t i) {
        return std::max(0.0, std::min(oldStarts[i] + widths[i], offset + viewport) - std::max(oldStarts[i], offset));
    };
    // Prefer the visible focused app, otherwise the largest visible unchanged
    // column. An offscreen focused app is not an instruction to navigate to it.
    if (focused && *focused != source && overlap(*focused) > 0.5)
        result.anchor = focused;
    else {
        double best = 0.5;
        for (size_t i = 0; i < widths.size(); ++i) {
            if (i != source && overlap(i) > best) {
                best = overlap(i);
                result.anchor = i;
            }
        }
    }

    double start = 0;
    for (const auto i : result.order) {
        newStarts[i] = start;
        start += widths[i];
    }
    if (result.anchor)
        result.offset += newStarts[*result.anchor] - oldStarts[*result.anchor];

    // Normal bounds match the Lua tape policy. Keep any already intentional
    // half-placement margin rather than snapping it away as a reorder side effect.
    const double normalMin = total < viewport ? std::round((total - viewport) / 2) : 0;
    const double normalMax = std::max(normalMin, total - viewport);
    const double minimum = std::min(normalMin, offset);
    const double maximum = std::max(normalMax, offset);
    result.offset = std::clamp(result.offset, minimum, maximum);

    // If the focused source was visible, move the camera only as much as needed
    // to keep it visible after the requested move. Already offscreen focus stays
    // offscreen; rearranging it must not unexpectedly navigate the desktop.
    if (focused && *focused == source && overlap(source) > 0.5) {
        const double low = newStarts[source] + widths[source] - viewport;
        const double high = newStarts[source];
        result.offset = low <= high ? std::clamp(result.offset, low, high) : newStarts[source] + (widths[source] - viewport) / 2;
        result.offset = std::clamp(result.offset, minimum, maximum);
    }
    if (result.anchor)
        result.anchorPreserved = std::abs((newStarts[*result.anchor] - result.offset) - (oldStarts[*result.anchor] - offset)) < 0.5;
    return result;
}

} // namespace TapeReorder
