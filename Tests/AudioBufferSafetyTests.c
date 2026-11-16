#include "../Sources/AudioBufferSafety.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    uint32_t bytes = 0;
    assert(TWAudioBufferBytes(512, 2, &bytes) && bytes == 4096);
    assert(TWAudioBufferBytes(0, 2, &bytes) && bytes == 0);
    assert(!TWAudioBufferBytes(1, 0, &bytes));
    assert(!TWAudioBufferBytes(1, UINT32_MAX, &bytes));
    assert(!TWAudioBufferBytes(UINT32_MAX, 2, &bytes));
    assert(TWAudioBufferBytes(UINT32_MAX / 8, 2, &bytes));
    assert(!TWAudioBufferBytes(UINT32_MAX / 8 + 1, 2, &bytes));
    assert(!TWAudioBufferBytes(512, 2, NULL));
    puts("Audio buffer boundary tests passed.");
    return 0;
}
