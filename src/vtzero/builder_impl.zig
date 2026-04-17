//! Internal types for vector tile encoding.

const std = @import("std");
const pbf = @import("detail/pbf.zig");
const types = @import("types.zig");
const mvt = @import("mvt_schema.zig");

const ByteList = std.array_list.Managed(u8);

const IndexValue = types.IndexValue;

const max_entries_flat: u32 = 20;
const IndexMap = std.StringHashMap(IndexValue);

fn findInKeyTable(table: []const u8, text: []const u8) !?IndexValue {
    var reader = pbf.Reader.init(table);
    var i: u32 = 0;
    while (try reader.next()) |field| {
        if (field.tag == mvt.Layer.keys and field.wire_type == .length_delimited) {
            if (std.mem.eql(u8, field.data, text)) return IndexValue.init(i);
            i += 1;
        }
    }
    return null;
}

fn findInValueTable(table: []const u8, encoded: []const u8) !?IndexValue {
    var reader = pbf.Reader.init(table);
    var i: u32 = 0;
    while (try reader.next()) |field| {
        if (field.tag == mvt.Layer.values and field.wire_type == .length_delimited) {
            if (std.mem.eql(u8, field.data, encoded)) return IndexValue.init(i);
            i += 1;
        }
    }
    return null;
}

/// Internal layer state matching C++ `vtzero::detail::layer_builder_impl`.
pub const LayerBuilderImpl = struct {
    allocator: std.mem.Allocator,
    /// Vector tile layer `version` field (exposed like C++ `feature_builder_base::version`).
    layer_version: u32,
    /// Main layer message buffer: version, name, extent, then repeated `features` (tag 2).
    data: std.ArrayListUnmanaged(u8) = .empty,
    /// Serialized key table chunks (repeated field `keys`, tag 3), as appended by proto.
    keys_data: std.ArrayListUnmanaged(u8) = .empty,
    /// Serialized value table chunks (repeated field `values`, tag 4).
    values_data: std.ArrayListUnmanaged(u8) = .empty,
    num_keys: u32 = 0,
    num_values: u32 = 0,
    num_features: u32 = 0,

    /// Lazy hash indexes for fast duplicate detection.
    /// Mirrors C++ vtzero behavior: below `max_entries_flat` we do a flat scan; once we exceed
    /// that threshold we build these maps on-demand from the already-encoded tables.
    keys_index: ?IndexMap = null,
    values_index: ?IndexMap = null,
    /// Stable storage for hash map keys.
    /// We must not store slices pointing into `keys_data`/`values_data` because those buffers can
    /// reallocate as the layer grows. The arenas own the bytes for all interned key/value strings.
    keys_index_arena: std.heap.ArenaAllocator = undefined,
    values_index_arena: std.heap.ArenaAllocator = undefined,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: u32, extent: u32) !*LayerBuilderImpl {
        const layer = try allocator.create(LayerBuilderImpl);
        layer.* = .{
            .allocator = allocator,
            .layer_version = version,
            .keys_index_arena = std.heap.ArenaAllocator.init(allocator),
            .values_index_arena = std.heap.ArenaAllocator.init(allocator),
        };
        errdefer {
            layer.data.deinit(allocator);
            allocator.destroy(layer);
        }
        try pbf.appendVarintFieldUnmanaged(allocator, &layer.data, mvt.Layer.version, version);
        try pbf.appendLengthDelimitedFieldUnmanaged(allocator, &layer.data, mvt.Layer.name, name);
        try pbf.appendVarintFieldUnmanaged(allocator, &layer.data, mvt.Layer.extent, extent);
        return layer;
    }

    fn ensureKeysIndexPopulated(self: *LayerBuilderImpl) !*IndexMap {
        if (self.keys_index == null) self.keys_index = IndexMap.init(self.allocator);
        const map = &self.keys_index.?;
        if (map.count() != 0) return map;

        // Populate index lazily from the already-encoded key table.
        // This matches the C++ approach: build the hash map only once the table is large enough
        // that flat scanning becomes more expensive than hashing.
        var reader = pbf.Reader.init(self.keys_data.items);
        var i: u32 = 0;
        while (try reader.next()) |field| {
            if (field.tag == mvt.Layer.keys and field.wire_type == .length_delimited) {
                const owned = try self.keys_index_arena.allocator().dupe(u8, field.data);
                try map.put(owned, IndexValue.init(i));
                i += 1;
            }
        }
        return map;
    }

    fn ensureValuesIndexPopulated(self: *LayerBuilderImpl) !*IndexMap {
        if (self.values_index == null) self.values_index = IndexMap.init(self.allocator);
        const map = &self.values_index.?;
        if (map.count() != 0) return map;

        // Populate index lazily from the already-encoded value table.
        var reader = pbf.Reader.init(self.values_data.items);
        var i: u32 = 0;
        while (try reader.next()) |field| {
            if (field.tag == mvt.Layer.values and field.wire_type == .length_delimited) {
                const owned = try self.values_index_arena.allocator().dupe(u8, field.data);
                try map.put(owned, IndexValue.init(i));
                i += 1;
            }
        }
        return map;
    }

    /// Import the key/value tables from an existing layer message.
    /// This preserves table order and indexes, enabling fast feature/tag copying.
    pub fn importTablesFromLayerData(self: *LayerBuilderImpl, layer_data: []const u8) !void {
        var reader = pbf.Reader.init(layer_data);
        while (try reader.next()) |field| {
            if (field.wire_type != .length_delimited) continue;
            switch (field.tag) {
                mvt.Layer.keys => {
                    try pbf.appendLengthDelimitedFieldUnmanaged(self.allocator, &self.keys_data, mvt.Layer.keys, field.data);
                    self.num_keys += 1;
                },
                mvt.Layer.values => {
                    try pbf.appendLengthDelimitedFieldUnmanaged(self.allocator, &self.values_data, mvt.Layer.values, field.data);
                    self.num_values += 1;
                },
                else => {},
            }
        }
    }

    pub fn deinit(self: *LayerBuilderImpl) void {
        if (self.keys_index) |*m| m.deinit();
        if (self.values_index) |*m| m.deinit();
        self.keys_index_arena.deinit();
        self.values_index_arena.deinit();
        self.data.deinit(self.allocator);
        self.keys_data.deinit(self.allocator);
        self.values_data.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addKeyWithoutDupCheck(self: *LayerBuilderImpl, text: []const u8) !IndexValue {
        const idx = IndexValue.init(self.num_keys);
        try pbf.appendLengthDelimitedFieldUnmanaged(self.allocator, &self.keys_data, mvt.Layer.keys, text);
        self.num_keys += 1;
        return idx;
    }

    pub fn addKey(self: *LayerBuilderImpl, text: []const u8) !IndexValue {
        if (self.num_keys < max_entries_flat) {
            if (try findInKeyTable(self.keys_data.items, text)) |idx| return idx;
            return self.addKeyWithoutDupCheck(text);
        }

        const map = try self.ensureKeysIndexPopulated();
        if (map.get(text)) |idx| return idx;

        const idx = try self.addKeyWithoutDupCheck(text);
        const owned = try self.keys_index_arena.allocator().dupe(u8, text);
        try map.put(owned, idx);
        return idx;
    }

    pub fn addValueWithoutDupCheck(self: *LayerBuilderImpl, value: []const u8) !IndexValue {
        const idx = IndexValue.init(self.num_values);
        try pbf.appendLengthDelimitedFieldUnmanaged(self.allocator, &self.values_data, mvt.Layer.values, value);
        self.num_values += 1;
        return idx;
    }

    pub fn addValue(self: *LayerBuilderImpl, value: []const u8) !IndexValue {
        if (self.num_values < max_entries_flat) {
            if (try findInValueTable(self.values_data.items, value)) |idx| return idx;
            return self.addValueWithoutDupCheck(value);
        }

        const map = try self.ensureValuesIndexPopulated();
        if (map.get(value)) |idx| return idx;

        const idx = try self.addValueWithoutDupCheck(value);
        const owned = try self.values_index_arena.allocator().dupe(u8, value);
        try map.put(owned, idx);
        return idx;
    }

    pub fn appendFeatureSubmessage(self: *LayerBuilderImpl, allocator: std.mem.Allocator, feature_bytes: []const u8) !void {
        try pbf.appendLengthDelimitedFieldUnmanaged(allocator, &self.data, mvt.Layer.features, feature_bytes);
        self.num_features += 1;
    }

    /// Same role as committing a `geometry_feature_builder` into
    /// `vtzero::detail::layer_builder_impl::message()` in C++: append one nested `Feature`
    /// (layer field `features`, length-delimited) into `m_data` without a temp feature buffer.
    pub fn appendFeatureMessageStreaming(
        self: *LayerBuilderImpl,
        allocator: std.mem.Allocator,
        has_id: bool,
        id_value: u64,
        feature_type: types.GeomType,
        geometry_payload: []const u8,
        tags: []const u32,
    ) !void {
        var inner_len: usize = 0;
        if (has_id) {
            inner_len += pbf.varintSerializedLen(pbf.fieldKey(mvt.Feature.id, .varint));
            inner_len += pbf.varintSerializedLen(id_value);
        }
        inner_len += pbf.varintSerializedLen(pbf.fieldKey(mvt.Feature.@"type", .varint));
        inner_len += pbf.varintSerializedLen(@intFromEnum(feature_type));

        inner_len += pbf.varintSerializedLen(pbf.fieldKey(mvt.Feature.geometry, .length_delimited));
        inner_len += pbf.varintSerializedLen(geometry_payload.len);
        inner_len += geometry_payload.len;

        if (tags.len != 0) {
            const packed_tags_len = pbf.packedUInt32SerializedLen(tags);
            inner_len += pbf.varintSerializedLen(pbf.fieldKey(mvt.Feature.tags, .length_delimited));
            inner_len += pbf.varintSerializedLen(packed_tags_len);
            inner_len += packed_tags_len;
        }

        const wrapper_len = pbf.varintSerializedLen(pbf.fieldKey(mvt.Layer.features, .length_delimited)) + pbf.varintSerializedLen(inner_len);
        try self.data.ensureUnusedCapacity(allocator, wrapper_len + inner_len);

        try pbf.appendVarintUnmanaged(allocator, &self.data, pbf.fieldKey(mvt.Layer.features, .length_delimited));
        try pbf.appendVarintUnmanaged(allocator, &self.data, @intCast(inner_len));

        if (has_id) try pbf.appendVarintFieldUnmanaged(allocator, &self.data, mvt.Feature.id, id_value);
        try pbf.appendVarintFieldUnmanaged(allocator, &self.data, mvt.Feature.@"type", @intFromEnum(feature_type));
        try pbf.appendLengthDelimitedFieldUnmanaged(allocator, &self.data, mvt.Feature.geometry, geometry_payload);

        if (tags.len != 0) {
            try pbf.appendVarintUnmanaged(allocator, &self.data, pbf.fieldKey(mvt.Feature.tags, .length_delimited));
            const packed_tags_len = pbf.packedUInt32SerializedLen(tags);
            try pbf.appendVarintUnmanaged(allocator, &self.data, @intCast(packed_tags_len));
            for (tags) |t| try pbf.appendVarintUnmanaged(allocator, &self.data, t);
        }

        self.num_features += 1;
    }

    pub fn estimatedSize(self: *const LayerBuilderImpl) usize {
        if (self.num_features == 0) return 0;
        return self.data.items.len + self.keys_data.items.len + self.values_data.items.len + 8;
    }

    /// `vtzero::detail::layer_builder_impl::build()` (from-scratch path): vectored layer into a tile.
    pub fn appendTileLayerMessage(self: *const LayerBuilderImpl, out: *ByteList) !void {
        if (self.num_features == 0) return;
        const payload_len = self.data.items.len + self.keys_data.items.len + self.values_data.items.len;
        try pbf.appendVarint(out, pbf.fieldKey(mvt.Tile.layers, .length_delimited));
        try pbf.appendVarint(out, @intCast(payload_len));
        try out.appendSlice(self.data.items);
        try out.appendSlice(self.keys_data.items);
        try out.appendSlice(self.values_data.items);
    }
};

/// Matches `vtzero::detail::layer_builder_impl::build(pbf_tile_builder)` for a built layer
/// (`add_bytes_vectored(detail::pbf_tile::layers, ...)`).
pub fn appendBuiltLayerVectored(w: anytype, layer: *const LayerBuilderImpl) !void {
    if (layer.num_features == 0) return;
    const payload_len = layer.data.items.len + layer.keys_data.items.len + layer.values_data.items.len;
    try pbf.appendVarint(w, pbf.fieldKey(mvt.Tile.layers, .length_delimited));
    try pbf.appendVarint(w, @intCast(payload_len));
    try w.appendSlice(layer.data.items);
    try w.appendSlice(layer.keys_data.items);
    try w.appendSlice(layer.values_data.items);
}
