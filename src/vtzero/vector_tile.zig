const std = @import("std");
const pbf = @import("detail/pbf.zig");
const layer_mod = @import("layer.zig");
const mvt = @import("mvt_schema.zig");

pub const Layer = layer_mod.Layer;

/// Vector tile view and layer iterator.
pub const VectorTile = struct {
    data: []const u8,
    layer_reader: pbf.Reader,

    pub fn init(data: []const u8) VectorTile {
        return .{
            .data = data,
            .layer_reader = pbf.Reader.init(data),
        };
    }

    pub fn empty(self: VectorTile) bool {
        return self.data.len == 0;
    }

    pub fn countLayers(self: VectorTile) !usize {
        var count: usize = 0;
        var reader = pbf.Reader.init(self.data);
        while (try reader.next()) |field| {
            if (field.tag == mvt.Tile.layers and field.wire_type == .length_delimited) count += 1;
        }
        return count;
    }

    /// Iterate layers in source order.
    pub fn nextLayer(self: *VectorTile) !?Layer {
        while (try self.layer_reader.next()) |field| {
            if (field.tag == mvt.Tile.layers and field.wire_type == .length_delimited) {
                return try Layer.init(field.data);
            }
        }
        return null;
    }

    pub fn resetLayer(self: *VectorTile) void {
        self.layer_reader = pbf.Reader.init(self.data);
    }

    /// Get layer by zero-based index.
    pub fn getLayer(self: VectorTile, index: usize) !?Layer {
        var current: usize = 0;
        var reader = pbf.Reader.init(self.data);
        while (try reader.next()) |field| {
            if (field.tag == mvt.Tile.layers and field.wire_type == .length_delimited) {
                if (current == index) return try Layer.init(field.data);
                current += 1;
            }
        }
        return null;
    }

    /// Get layer by name (linear scan).
    pub fn getLayerByName(self: VectorTile, name: []const u8) !?Layer {
        var reader = pbf.Reader.init(self.data);
        while (try reader.next()) |field| {
            if (field.tag != mvt.Tile.layers or field.wire_type != .length_delimited) continue;

            // Match C++ vtzero behavior: scan for the name field anywhere in the layer.
            // If a layer is missing a name field, this is a format error (spec 4.1).
            var layer_reader = pbf.Reader.init(field.data);
            var found_name = false;
            while (try layer_reader.next()) |lf| {
                if (lf.tag == mvt.Layer.name and lf.wire_type == .length_delimited) {
                    found_name = true;
                    if (std.mem.eql(u8, lf.data, name)) return try Layer.init(field.data);
                    break; // name exists but doesn't match; continue with next layer
                }
            }
            if (!found_name) return error.MissingLayerName;
        }
        return null;
    }
};

/// Fast heuristic: vector tiles always begin with tag 3 (0x1a).
pub fn isVectorTile(data: []const u8) bool {
    return data.len > 0 and data[0] == 0x1a;
}
