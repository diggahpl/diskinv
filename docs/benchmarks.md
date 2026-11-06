# Benchmarks behind the numbers in the listing and the README

Measured on 5 November 2026, MacBook Air with an Apple M4 (10 cores) and 16 GB, macOS 27.0.1, Xcode 27.2,
Release builds, ad-hoc signed, hardened runtime off, with other applications running (so the absolute times
are a little pessimistic, but both sides ran under the same conditions).

**What was compared.** The baseline is commit
`276224d`: the Swift port 2.0.0 with the crash fix, the
last state before the speed work (it already contains the benchmark). The other side is this version
(2.1.0). This is not a comparison with the original Objective-C Disk Inventory X 1.x, which cannot be built
with the current Xcode without changes; the Swift port has the same algorithms, but nothing here measures the
Objective-C original.

**Folder.** `/Applications` with package contents shown: 900,335 files, 67 GB. The tree is scanned as the app
scans a disk, laid out and rendered into a 3000×1800 pixel bitmap (a 1500×900 pt window on a Retina display),
and 200,000 random points are hit-tested.

**Method.** `TreeMapPerformanceTests.testBenchmarkRealFolder` (see `CLAUDE.md`), three runs of each build,
run alternately; the median of the runs is shown (the benchmark itself reports the median of 8 layout and
render runs, 3 tree builds and 5 hit-test runs per execution).

```sh
TEST_RUNNER_DIX_TREEMAP_BENCH=1 TEST_RUNNER_DIX_BENCH_PATH=/Applications \
xcodebuild test -project "src/Disk Inventory X.xcodeproj" -scheme "Disk Inventory X" -configuration Release \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO ENABLE_HARDENED_RUNTIME=NO \
  -only-testing:"Disk Inventory XTests/TreeMapPerformanceTests/testBenchmarkRealFolder"
```

| Phase | Before (2.0.0) | Now (2.1.0) | Speed-up |
| --- | ---: | ---: | ---: |
| Scan of the folder | 33.5 s (33.0, 33.5, 33.7) | 3.35 s (3.40, 3.35, 3.32) | 10× |
| Build the tree map's item tree | 1205 ms | 423 ms | 2.9× |
| Layout | 280 ms | 19.6 ms | 14× |
| Render the colored blocks | 230 ms | 26.7 ms | 8.6× |
| Hit test, 200,000 points | 685 ms | 90 ms | 7.6× |

The scan numbers include building the file tree. Memory use was not measured here, so the listing makes no claim about it.

The rendered bitmaps of the two builds differ because the new look changed the palette; the shader itself is
pinned by hashes in the test suite (`TreeMapPerformanceTests`), recorded from the old implementation.
