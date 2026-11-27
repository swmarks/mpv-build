# swmarks fork overlay

This fork of [edde746/mpv-build](https://github.com/edde746/mpv-build) adds
**AC-4 audio** to the Android binaries that Plezy consumes. Nothing else differs
from upstream.

| Component | Patch | Purpose |
|---|---|---|
| FFmpeg | `9001-ac4-decoder-and-parser.patch` | librempeg AC-4 decoder + parser, wired into Makefile / allcodecs / parsers; mpegts maps the DVB AC-4 descriptor |
| mpv | `9002-matroska-a-quicktime-ac4.patch` | Map Matroska `A_QUICKTIME` tracks (e.g. AC-4 from mkvmerge) |

## Syncing with upstream

The fork's `main` is always rebuilt from scratch, never rebased:

```sh
git fetch upstream
git reset --hard upstream/main
git checkout <previous-fork-main> -- fork/   # or restore fork/ from a backup
fork/apply.sh
git add -A && git commit -m "fork: apply AC-4 overlay on upstream <sha>"
git push --force origin main
```

Plezy's `Sync Upstream & Release Android` workflow does exactly this.

## Why android-only

A patch in `series.common` changes the content keys of every platform group.
That forces apple, linux and windows rebuilds, which the fork can't publish. The
all-or-nothing **Commit manifest** job then refuses to record even the
successful Android build. Keeping the patches in `series.android` means only
Android is rebuilt. The other groups keep pointing at upstream's
already-published assets.

## Updating the FFmpeg patch

The patch is a `git format-patch` against FFmpeg `n8.0.1` **plus upstream's
android series**. To regenerate it:

```sh
python3 scripts/patches.py fetch-pinned ffmpeg android /tmp/ffsrc   # before fork/apply.sh
# edit, commit in /tmp/ffsrc, then:
git -C /tmp/ffsrc format-patch -1 --stdout > fork/patches/ffmpeg/pool/9001-ac4-decoder-and-parser.patch
```

> **Keep `#define ASSERT_LEVEL 2`** directly above
> `#include "libavutil/avassert.h"` in `ac4dec.c`. It matches the
> libmpv-android patch that worked. Without it the decoder emits bursts of NaN
> samples (~25%) and AC-4 playback is silent in both ExoPlayer and mpv.
> Plezy's `build-android.yml` smoke test fails the release if the define is
> missing.
