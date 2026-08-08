#!/usr/bin/env python3
"""Measure the visible column width of statusline output."""
import re
import sys
import unicodedata

ANSI = re.compile(r"\x1b\[[0-9;]*m|\x1b\]8;;.*?(?:\x07|\x1b\\)")


def width(s: str) -> int:
    s = ANSI.sub("", s)
    total = 0
    for ch in s:
        if unicodedata.combining(ch):
            continue
        eaw = unicodedata.east_asian_width(ch)
        # Emoji-presentation codepoints render 2 cols even when EAW says
        # ambiguous/neutral (e.g. U+26A1 HIGH VOLTAGE).
        cp = ord(ch)
        emoji = (
            0x1F300 <= cp <= 0x1FAFF
            or 0x2600 <= cp <= 0x27BF
            or cp in (0x1F004, 0x1F0CF)
        )
        total += 2 if (eaw in ("W", "F") or emoji) else 1
    return total


if __name__ == "__main__":
    print(width(sys.stdin.read()))
