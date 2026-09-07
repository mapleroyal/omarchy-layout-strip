#pragma once

#include <cmath>
#include <optional>

namespace TapeBarPress {

struct Region {
    double x, y, width, height;
    bool valid() const {
        return std::isfinite(x) && std::isfinite(y) && std::isfinite(width) && std::isfinite(height) &&
               width > 0 && height > 0 && std::abs(x) < 1e7 && std::abs(y) < 1e7 && width < 1e7 && height < 1e7;
    }
    bool contains(double px, double py) const {
        return px >= x && py >= y && px < x + width && py < y + height;
    }
};

// Only restore an inhibitor we acquired. A subsequent independent change of
// either field transfers ownership away from us and must not be overwritten.
template <typename Inhibitor>
class Lease {
  public:
    bool acquire(Inhibitor& target, double camera) {
        if (m_saved || target.isInhibited || !std::isfinite(camera))
            return false;
        m_saved = target;
        m_camera = camera;
        target.isInhibited = true;
        target.offsetWhenInhibited = camera;
        return true;
    }
    bool restore(Inhibitor& target) {
        if (!m_saved)
            return false;
        const bool owned = target.isInhibited && target.offsetWhenInhibited == m_camera;
        if (owned)
            target = *m_saved;
        m_saved.reset();
        return owned;
    }
  private:
    std::optional<Inhibitor> m_saved;
    double m_camera = 0;
};

} // namespace TapeBarPress
