#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
xcrun clang -std=c11 -Wall -Wextra -Werror -fsanitize=undefined Tests/AudioBufferSafetyTests.c -o .build/tests/audio-buffer-safety
.build/tests/audio-buffer-safety
