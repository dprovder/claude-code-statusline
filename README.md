# claude-code-statusline

A responsive, color-vision-friendly status line for [Claude Code](https://code.claude.com).

```
cmux-themed | (tab-bar-style-7458) | ███████░░░░░░░ 47% | $0.47 | +156 -23 | 5h 24% 7d 41% | Opus 5
```

Left to right: repository, git branch, context-window bar with percentage, session
cost, lines added/removed, 5-hour and 7-day rate limit usage, and the model.

Text only — no emoji, no nerd-font glyphs, nothing that needs a patched font.

## Install

```bash
git clone https://github.com/dprovder/claude-code-statusline
cd claude-code-statusline
./install.sh
```

Then restart Claude Code.

`install.sh` copies `statusline.sh` to `~/.claude/` and adds a `statusLine` block to
`~/.claude/settings.json`, backing up the existing file to `settings.json.bak` first.
Pass `--symlink` to link the script instead of copying it, so edits in your clone
apply without reinstalling. It respects `$CLAUDE_CONFIG_DIR` if you have one set.

**Requirements:** bash (3.2 is fine — stock macOS works), `jq`, `git`, and Claude Code
v2.1.153+ for width detection.

## What makes it different

### It adapts to the window

Claude Code captures a status line script's stdout rather than attaching it to the
terminal, so `tput cols` and language-level width detection report a useless default.
Claude Code exports `COLUMNS` instead. This script reads that and budgets for *less*
than the full width, because system notifications — MCP errors, auto-update messages,
the context-low warning — render on the right of the same row and will truncate you
mid-segment otherwise.

As the window narrows, segments are sacrificed least-valuable-first:

| Columns | Rendered |
|---|---|
| 140 | `cmux-themed \| (tab-bar-style-7458) \| █████████░░░░░░░░░░░ 47% \| $0.47 \| +156 -23 \| 5h 24% 7d 41% \| Opus 5 (1M context)` |
| 110 | `cmux-themed \| (tab-bar-style-7…) \| ███████░░░░░░░ 47% \| $0.47 \| 5h 24% 7d 41% \| Opus 5` |
| 85 | `cmux-themed \| (tab-bar-style-7…) \| ███░░░ 47% \| 5h 24% 7d 41% \| Opus 5` |
| 60 | `(tab-bar-style-7…) \| 47% \| Opus 5` |
| 40 | `(tab-bar-styl…) \| 47% \| Opus 5` |
| 20 | `47% \| Opus 5` |

Order of sacrifice: shorten the model name → truncate the branch → drop code
velocity → cost → repo → rate limits → branch → bar → model. The context
percentage is the last thing standing.

The bar is capped at the tier for the current width so it only ever shrinks as the
window shrinks. Letting it grow freely into whatever slack appeared was
non-monotonic: dropping a segment frees space, so narrowing the window could make
the bar jump *bigger*, which reads as a rendering bug.

### It doesn't rely on color alone

The default palette ramps **blue → purple → red**. That is the blue/red axis, which
stays distinguishable under protan and deuteran color vision deficiency — unlike the
usual green → yellow → red, which collapses toward a single muddy hue. Colors are
also held at mid luminance so the same output reads on both light and dark terminal
backgrounds.

Severity has a second, non-color encoding: a `!` prefix appears at 70% context and
`!!` at 90%. The warning survives a monochrome terminal or a screenshot run through
a grayscale filter. Below 70% there is no marker, so the common case stays quiet.

Set `CLAUDE_STATUSLINE_PALETTE=classic` for a conventional green → yellow → red ramp.

### It's fast

The status line runs after every assistant message, and a slow script blocks updates
(Claude Code cancels an in-flight run if a new one triggers). This one avoids
subshells in the hot paths: one `jq` invocation for all fields, colors and rounding
via `printf -v` rather than command substitution, and a single `git rev-parse` that
returns both the toplevel and the ref — with a second call only on a detached HEAD.
Roughly 30ms per render on an M-series Mac, most of which is process startup.

## Configuration

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_STATUSLINE_PALETTE` | `daltonized` | `classic` for green → yellow → red |
| `CLAUDE_STATUSLINE_RESERVE` | `14` | Columns kept clear for notifications, capped at ¼ of the width |
| `CLAUDE_STATUSLINE_COLUMNS` | — | Force a width; used by the tests |

To change which segments appear, edit the `add` calls at the bottom of the script and
the matching entries in `recalc()`, which tracks each segment's display width. The
full set of fields Claude Code provides on stdin — token counts, effort level, vim
mode, worktree info, reset timestamps — is documented at
[code.claude.com/docs/en/statusline](https://code.claude.com/docs/en/statusline).

## Tests

```bash
./test/render.sh      # assert
./test/render.sh -v   # print every rendered line
```

Checks 27 terminal widths from 200 columns down to 10, asserting each render fits its
budget and that the bar never grows as the window narrows; verifies the severity
marker at its threshold boundaries; and confirms degenerate payloads (absent rate
limits, null context, empty object, non-git directory) and malformed JSON produce a
sensible line or silence rather than a broken one. Width is measured with ANSI
escapes stripped and wide characters counted as two columns, via `test/measure.py`
(needs python3).

## Credits

The original concept, layout, and gradient-bar idea come from a
[status line guide gist by AKCodez](https://gist.github.com/AKCodez/ffb420ba6a7662b5c3dda2edce7783de).
This version rewrites the implementation — single-pass JSON parsing, the responsive
cascade, the colorblind-safe palette, rate limits, and the removal of emoji — but the
shape of the thing is theirs. That gist does not state a license.

## License

MIT — see [LICENSE](LICENSE).
