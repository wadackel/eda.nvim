# Render benchmarks

Run commands from the repository root inside `nix develop`. Keep the fixture,
Neovim version, viewport, and machine identical when comparing revisions. Run
benchmarks sequentially, without tests or other benchmark processes competing
for CPU time.

## Painter and pipeline scenarios

```sh
nvim --headless -l benchmarks/render.lua /path/to/fixture
```

`render.lua` reports nine scenarios, with five warmup iterations and twenty
measured iterations per scenario. Scenario 7 profiles a **full** paint after a
single toggle; scenario 9 compares incremental and full painting. Neither is a
measurement of terminal display latency. The default icon provider may have no
file icons when its optional provider is unavailable.

## Actual directory-toggle workload

`toggle.lua` opens the explorer, expands a 100-directory / 10,000-file fixture,
and invokes the normal `select` action followed by an explicit redraw. It uses
deterministic ASCII icons on every row, disables Git and the header, and uses a
replacement window. Each of five repetitions contains five warmup pairs and
twenty measured collapse/expand pairs: 100 samples per direction in total.

Create the fixture once:

```sh
export EDA_BENCH_DIR="$(mktemp -d)"
python3 - <<'PYTHON'
import os
from pathlib import Path
root = Path(os.environ["EDA_BENCH_DIR"])
for directory in range(100):
    parent = root / f"dir-{directory:03d}"
    parent.mkdir()
    for file in range(100):
        (parent / f"file-{file:03d}.txt").write_text("benchmark\n")
PYTHON
```

Headless run (the script sets a 140-column, 40-row viewport):

```sh
EDA_BENCH_OUTPUT=/tmp/eda-toggle-headless.json \
  nvim --headless --clean -n -c 'luafile benchmarks/toggle.lua'
```

Attached TUI run: set the terminal to 140 columns by 40 rows, then run:

```sh
EDA_BENCH_OUTPUT=/tmp/eda-toggle-tui.json \
  nvim --clean -n -c 'luafile benchmarks/toggle.lua'
```

The script exits after writing JSON. Check that `ui` contains an entry for the
TUI run and that `visible_lines` is nonzero. Explicit `:redraw` also invokes the
decoration provider in this headless workload; ordinary headless RPC tests do
not necessarily exercise it. `total_ms` covers action dispatch, completion,
and Neovim's redraw work, including instrumentation. It does not measure the
host terminal's final display latency. `render_ms` and `resync_ms` are nested
components of the total, not additional time to add to it.

The output records icon writes/namespace clears, decorated row counts, visible
line callbacks, redraw resynchronization, each sample's repetition, the Neovim
version, and the first ten screen rows. Use the same script on both revisions;
copy it outside the checkout when measuring a revision that predates it.

## Recorded comparison: incremental icon placement

Measured on macOS arm64 with Neovim 0.12.5, comparing base `7406556` with the
incremental icon placement and changedtick redraw guard. The attached TUI used
a 140 x 40 PTY, with 38 visible-line callbacks per toggle. No other test or
benchmark processes ran alongside these measurements.

Actual action + redraw, mean ± sample standard deviation in milliseconds
(100 samples per direction):

| Mode | Direction | Before | After |
| --- | --- | ---: | ---: |
| Headless | Collapse | 25.437 ± 4.851 | 7.445 ± 3.382 |
| Headless | Expand | 25.595 ± 5.151 | 7.487 ± 2.954 |
| Attached TUI | Collapse | 28.444 ± 5.572 | 7.353 ± 3.799 |
| Attached TUI | Expand | 29.209 ± 7.260 | 7.546 ± 3.314 |

Across the five TUI repetitions, collapse means ranged from 26.210–32.068 ms
before and 6.612–8.384 ms after; expand means ranged from 26.542–34.628 ms before
and 7.127–8.107 ms after. The reduction exceeds the observed variation for this
workload. Screen text and visible-line callback counts were unchanged.

| Work per toggle | Collapse, before → after | Expand, before → after |
| --- | ---: | ---: |
| Icon extmark writes | 10,000 → 1 | 10,100 → 102 |
| Redraw resynchronizations | 1 → 0 | 1 → 0 |
| Decorated rows | 10,000 → 10,000 | 10,100 → 10,100 |

Standard harness results below are mean ± standard deviation of the reported
means from five separate runs, rather than 100 individual samples:

| Scenario | Direction | Before (ms) | After (ms) |
| --- | --- | ---: | ---: |
| 7: profiled full paint | Collapse | 12.050 ± 0.645 | 14.017 ± 2.118 |
| 7: profiled full paint | Expand | 12.217 ± 0.773 | 14.121 ± 2.291 |
| 9: full paint | Collapse | 12.376 ± 0.530 | 12.162 ± 0.241 |
| 9: full paint | Expand | 12.241 ± 0.622 | 12.108 ± 0.386 |
| 9: incremental paint | Collapse | 2.568 ± 0.212 | 2.085 ± 0.234 |
| 9: incremental paint | Expand | 2.640 ± 0.219 | 2.260 ± 0.291 |

Scenario 7's profiled full-paint runs were slower and more variable after the
change, while scenario 9's full-paint control was similar. These results do
not establish an improvement to full painting. The measured benefit is
specific to the incremental path and redundant redraw resynchronization.
Flattening, decorating all rows, rebuilding maps/snapshots, and reading line
lengths still scale with the visible tree. Arbitrary custom decorators retain
their existing invocation behavior; this is not a decoration cache.

## Dirty-buffer navigation

Use the same 100 x 100 fixture created above:

```sh
EDA_BENCH_OUTPUT=/tmp/eda-dirty-toggle.json \
  nvim --headless --clean -n -c 'luafile benchmarks/dirty-toggle.lua'
```

`dirty-toggle.lua` inserts one new entry, renames another using a text edit
that preserves its ID extmark, and deletes a third entry. These edits are in
a different directory from the toggle target. It invokes `collapse_node`
with the cursor on the directory and then on its child, reopening via
`select`. Each cursor mode has five repetitions of five warmup pairs and
twenty measured pairs (100 samples per direction per mode). Every measured
pair verifies exact buffer text, rename/delete IDs, create anchors, and the
modified flag outside the timed region. It never saves the fixture.

Recorded on macOS arm64 / Neovim 0.12.5, base `ac08bff`, with the same fixture,
140 x 40 headless viewport, Git disabled, and no external icon provider.
Runs were sequential. `total_ms` includes dispatch, completion, and explicit
redraw, but not host terminal display latency. Capture includes parsing, so
`parse_ms` must not be added to `capture_ms`.

| Cursor / direction | Capture calls before → after | Capture before → after (ms) | Total before (ms) | Total after (ms) |
| --- | ---: | ---: | ---: | ---: |
| Directory / collapse | 2 → 1 | 19.166 → 10.640 | 45.555 ± 3.831 | 37.601 ± 5.531 |
| Directory / expand | 1 → 1 | 9.434 → 10.951 | 34.722 ± 4.081 | 37.631 ± 4.125 |
| Child / collapse | 2 → 1 | 19.181 → 11.443 | 46.749 ± 4.948 | 39.425 ± 5.079 |
| Child / expand | 1 → 1 | 9.133 → 10.250 | 35.440 ± 5.273 | 39.061 ± 5.618 |

Totals are mean ± sample standard deviation. Directory-collapse repetition
means ranged from 45.054–46.076 ms before and 36.232–38.991 ms after;
child-collapse means ranged from 44.797–48.877 ms before and 37.252–41.643 ms
after. The unchanged expansion control was slower after, so these timings do
not establish a general navigation speedup. The confirmed work reduction is
two captures to one for either `collapse_node` branch. Collapse improved by
about 7–8 ms in this run despite that control variation.

The reused capture exists only within the synchronous collapse invocation.
It is passed directly to the existing edit-preserving render, after changing
the directory's open flag. No buffer writes, I/O completion, root transition,
or extmark shift intervene. A later action captures again, including after
new edits or undo/redo. No cross-action capture cache is introduced.

Parsing remains the largest capture component: collapse parsing averaged
16.964/16.902 ms before (two calls) and 9.454/10.241 ms after (one call) for
directory/child cursors. The parser itself has not been optimized. A future
parser optimization should profile extmark decoding and row/path allocation
first. Reusing parsed rows across actions would require invalidation for
buffer text, ID extmarks, root/store identity, and painter snapshots, plus
subtree invalidation when indentation or a parent path changes. A changedtick
key alone would not establish those invariants, and every paint/replay also
changes the buffer, limiting cache reuse.

Scenario 8 was also run in five separate standard-harness processes per
revision (five warmups / twenty iterations each). Its full capture call is
unchanged by the action-level reuse; below are mean ± standard deviation of
the five reported means, with profiled parser time shown separately:

| Revision | Full capture (ms) | Profiled parser mean (ms) |
| --- | ---: | ---: |
| Before | 7.152 ± 0.090 | 6.387 |
| After | 8.981 ± 0.715 | 8.338 |

The standard scenario uses its existing insert/whole-line replacement fixture;
the actual-action workload above additionally exercises a surviving rename ID
and deletion. Neither result demonstrates that an individual parse became
faster.

## Symlink scan workload

Create three 1,000-entry directories containing 0, 100, and 1,000 symlinks.
Link targets alternate between a file, a directory, and a missing path:

```sh
export EDA_BENCH_DIR="$(mktemp -d)"
python3 - <<'PYTHON'
import os
from pathlib import Path
root = Path(os.environ["EDA_BENCH_DIR"])
(root / "targets").mkdir()
(root / "targets" / "file").write_text("target\n")
(root / "targets" / "directory").mkdir()
for links in (0, 100, 1000):
    directory = root / f"links-{links}"
    directory.mkdir()
    for index in range(1000):
        entry = directory / f"entry-{index:04d}"
        if index < links:
            target = ("file", "directory", "missing")[index % 3]
            entry.symlink_to(root / "targets" / target)
        else:
            entry.write_text("ordinary\n")
PYTHON
EDA_BENCH_OUTPUT=/tmp/eda-symlinks.json \
  nvim --headless -l benchmarks/symlinks.lua
```

The harness runs one warmup and five measured scans for every link count,
`follow_symlinks` setting, and delay setting. The zero-delay mode uses the real
local filesystem. The synthetic mode adds a 1 ms delay to each metadata call:
a blocking sleep for synchronous calls or a deferred callback for asynchronous
calls. This is a controlled latency model, not a measurement of a network
filesystem. Runs should be sequential, without competing benchmark/test work.

JSON records directory enumeration time (through `fs_closedir` completion),
metadata call counts and accumulated request times, synchronous metadata
blocking time, `_apply_entries` call duration, store reconciliation, sorting,
plain painting, total scan latency, and the maximum gap in a 1 ms heartbeat.
Metadata request times overlap when asynchronous and must not be added to total
latency. `_apply_entries` returns after queuing asynchronous metadata; subsequent
reconciliation is timed separately. For ordinary files it still reconciles
before returning. Sorting and plain painting are measured after scan completion
and are not included in `scan_ms`; no terminal display latency is measured.

Recorded on macOS arm64 / Neovim 0.12.5, comparing base `fad6cc9` with bounded
asynchronous symlink metadata. Each row summarizes five measured scans after
one warmup. Scan times show mean ± sample standard deviation in milliseconds;
heartbeat columns show the mean of each scan's maximum gap.

| Added delay (ms/call) | Links | Follow | Scan before (ms) | Scan after (ms) | Heartbeat gap before → after (ms) |
| ---: | ---: | --- | ---: | ---: | ---: |
| 0 | 0 | true | 7.828 ± 0.710 | 7.240 ± 0.324 | 7.112 → 6.728 |
| 0 | 0 | false | 7.236 ± 0.175 | 7.039 ± 0.346 | 6.750 → 6.613 |
| 0 | 100 | true | 11.101 ± 1.234 | 9.501 ± 0.686 | 10.557 → 6.798 |
| 0 | 100 | false | 10.513 ± 0.446 | 9.523 ± 0.729 | 10.088 → 6.985 |
| 0 | 1,000 | true | 42.718 ± 2.668 | 25.393 ± 0.397 | 42.133 → 7.340 |
| 0 | 1,000 | false | 42.359 ± 1.405 | 24.265 ± 0.630 | 41.825 → 6.724 |
| 1 | 0 | true | 8.743 ± 2.270 | 7.417 ± 0.250 | 7.956 → 6.860 |
| 1 | 0 | false | 7.225 ± 0.196 | 8.926 ± 2.498 | 6.854 → 7.839 |
| 1 | 100 | true | 221.808 ± 0.614 | 15.573 ± 0.759 | 221.466 → 6.189 |
| 1 | 100 | false | 138.803 ± 1.592 | 13.036 ± 1.387 | 137.936 → 6.231 |
| 1 | 1,000 | true | 2158.818 ± 10.444 | 78.799 ± 1.448 | 2158.359 → 6.635 |
| 1 | 1,000 | false | 1324.969 ± 19.909 | 59.457 ± 6.259 | 1324.182 → 6.553 |

For 1,000 real links with following enabled, enumeration averaged 1.223 ms
before / 0.916 ms after, and synchronous metadata blocking fell from 34.282 ms
to zero. All 1,667 metadata requests after the change were asynchronous
(1,000 realpaths and 667 target stats). `_apply_entries` call duration fell
from 41.491 ms to 0.227 ms because it now queues that work. Reconciliation
still runs later on the main loop: 6.584 ms before / 6.708 ms after. Sorting
was 1.204/1.118 ms and plain painting 0.877/1.332 ms. Those small sort/paint
variations are not an optimization claim.

The remaining roughly 7 ms heartbeat gap is consistent with synchronous
materialization; this change does not make every scan stage asynchronous.
Normal-file scans remain in the same range. The synthetic case demonstrates
that metadata latency no longer becomes an equally long main-loop stall;
its speedup is specific to the injected delay and bounded overlapping work.

## Git status during a burst of saves

`git-burst.lua` opens three real explorer splits over a 1,000-file Git fixture.
Each burst writes 25 loaded buffers through normal Neovim `:write` commands;
filesystem watchers trigger refresh without explicit refresh calls. Git status
uses real subprocesses. One warmup burst precedes five measured bursts.

Create a disposable fixture once (the workload rewrites files 1 through 25):

```sh
export EDA_BENCH_DIR="$(mktemp -d)"
python3 - <<'PYTHON'
import os
import subprocess
from pathlib import Path
root = Path(os.environ["EDA_BENCH_DIR"])
for index in range(1000):
    (root / f"file-{index:04d}.txt").write_text("tracked\n")
subprocess.run(["git", "init", str(root)], check=True)
subprocess.run(["git", "-C", str(root), "add", "."], check=True)
subprocess.run(["git", "-C", str(root), "-c", "user.name=Benchmark",
                "-c", "user.email=benchmark@example.invalid", "-c", "commit.gpgsign=false",
                "commit", "-m", "fixture"], check=True)
PYTHON
EDA_BENCH_OUTPUT=/tmp/eda-git-burst.json \
  nvim --headless -l benchmarks/git-burst.lua
```

The output records logical status requests, settled callbacks, process launches,
peak concurrent processes, time spent saving, and time from the last save to the
last status callback. It verifies that all 25 saved paths have modified status.
A 100 ms quiet period checks settlement but is excluded from the recorded times.
These are headless watcher/status measurements, not terminal display latency.

### Recorded Git request coordination comparison

Measured sequentially on macOS arm64 with Neovim 0.12.5, comparing `d48272a`
with per-repository request coordination on the same fixture and workload.
All five bursts issued three requests and settled all three callbacks.

| Metric per burst | Before | After |
| --- | ---: | ---: |
| Status processes | 3 in every sample | 2, 2, 2, 2, 3 |
| Peak concurrent status processes | 3 in every sample | 1 in every sample |
| Save duration, ms | 121.225 ± 3.975 | 120.760 ± 1.597 |
| Last save to last status callback, ms | 161.749 ± 4.498 | 178.652 ± 3.156 |
| First save to last status callback, ms | 282.974 ± 6.281 | 299.412 ± 3.607 |

Times are means ± sample standard deviations across five bursts. Process
coordination reduced overlapping work, but this workload's completion latency
increased by about 17 ms. Requests arriving after a process starts share a fresh
follow-up round: later writes cannot safely rely on a command that may already
have read the worktree. Watcher timing can place a third request after that
follow-up starts, producing three sequential commands, as in the last sample.
There is no fixed total-process bound for a continuing stream of writes; the
bound is one active command and one queued round per repository. The fixture's
local filesystem and small Git workload do not establish network-filesystem or
large-repository latency improvements.
