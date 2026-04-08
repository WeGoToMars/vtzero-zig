# vtzero-zig

A Zig port of the [mapbox/vtzero](https://github.com/mapbox/vtzero) C++ library for encoding and decoding vector map tiles in MVT format. Work in progress, but should be OK for personal projects.

Implements the ++[Mapbox Vector Tile Specification 2.x](https://www.mapbox.com/vector-tiles/specification)++.

The implementation mostly mirrors C++, so most of the documentation for the original library should still apply.

## Requirements

- Zig 0.16

## Features:

- Full parity to vtzero functionality (as of version 1.2.0)
- Complete port of the test suite from Catch2 to Zig's test system
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

See code in [src/benchmark](/src/benchmark/), build executables with `zig build bench`.
Currently only tile parsing is tested, more should be added in the future.
Tilesets are from [mvt-fixtures](https://github.com/mapbox/mvt-fixtures) repo.

Results (max optimization, average of 5):


| Tileset      | Zig vs original  |
| ------------ | ---------------- |
| bangkok      | **1.21x faster** |
| chicago      | **1.09x faster** |
| nepal        | **1.36x faster** |
| sanfrancisco | **1.19x faster** |

