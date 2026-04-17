# vtzero-zig

[![Tests](https://github.com/WeGoToMars/vtzero-zig/actions/workflows/test.yml/badge.svg)](https://github.com/WeGoToMars/vtzero-zig/actions/workflows/test.yml)
[![Coverage Status](https://coveralls.io/repos/github/WeGoToMars/vtzero-zig/badge.svg?branch=main)](https://coveralls.io/github/WeGoToMars/vtzero-zig?branch=main)

A Zig port of the [mapbox/vtzero](https://github.com/mapbox/vtzero) C++ library for encoding and decoding vector map tiles in MVT format.

Implements the [Mapbox Vector Tile Specification 2.x](https://www.mapbox.com/vector-tiles/specification).

The implementation mostly mirrors C++, so most of the documentation for the original library should still apply.

## Requirements

- Zig 0.16

## Features:

- Full parity to vtzero functionality (as of version 1.2.0)
- Complete port of the test suite from Catch2 to Zig's test system + new tests for increased coverage
- Improved performance!

## Using the library

1. Add `vtzero-zig` to your package list.
```sh
zig fetch --save "git+https://github.com/WeGoToMars/vtzero-zig#master"
```
2. Use the `vtzero` module. In your `build.zig`'s build function, add the dependency as module before `b.installArtifact(exe)`.
```zig
pub fn build(b: *std.Build) !void {
    //...
    // first create a build for the dependency
    const vtzero_dep = b.dependency("vtzero", .{
        .target = target,
        .optimize = optimize,
    });
    //...

    // and then use the dependency as a module
    exe.root_module.addImport("vtzero", vtzero_dep.module("vtzero"));
}
```

## Performance benchmarks

See code in [src/benchmark](/src/benchmark/), run comparative `zig build bench`.
Currently only tile parsing and decoding are tested, more should be added in the future.
Tilesets are from [mvt-fixtures](https://github.com/mapbox/mvt-fixtures) repo.

Results (updated occasionally, execution on GitHub Action runner):


| Folder            | Benchmark         | Speedup   |
|:------------------|:-------------|:----------|
| bangkok           | parse-only   | 1.128x    |
| chicago           | parse-only   | 1.097x    |
| nepal             | parse-only   | 1.173x    |
| norway            | parse-only   | 1.138x    |
| osm-qa-astana     | parse-only   | 1.024x    |
| osm-qa-montevideo | parse-only   | 0.997x    |
| sanfrancisco      | parse-only   | 1.168x    |
| uruguay           | parse-only   | 1.095x    |
| bangkok           | parse+decode | 1.687x    |
| chicago           | parse+decode | 1.566x    |
| nepal             | parse+decode | 1.586x    |
| norway            | parse+decode | 1.651x    |
| osm-qa-astana     | parse+decode | 1.490x    |
| osm-qa-montevideo | parse+decode | 1.210x    |
| sanfrancisco      | parse+decode | 1.616x    |
| uruguay           | parse+decode | 1.649x    |

