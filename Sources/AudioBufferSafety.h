#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <limits.h>

// HAL dimensions come from an audio device. Reject values that cannot fit the
// UInt32 byte counts used by AudioBuffer and AudioUnitRender before multiplying.
static inline bool TWAudioBufferBytes(uint32_t frames, uint32_t channels, uint32_t *bytes) {
    if (!bytes || !channels || channels > UINT32_MAX / sizeof(float)) return false;
    uint32_t frameBytes = channels * (uint32_t)sizeof(float);
    if (frames > UINT32_MAX / frameBytes) return false;
    *bytes = frames * frameBytes;
    return true;
}
