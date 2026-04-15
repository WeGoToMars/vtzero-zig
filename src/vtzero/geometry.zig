const std = @import("std");
const pbf = @import("detail/pbf.zig");
const types = @import("types.zig");

pub const GeomType = types.GeomType;
pub const Geometry = types.Geometry;
pub const Point = types.Point;
pub const RingType = types.RingType;

/// Geometry command identifiers from spec section 4.3.
pub const CommandId = enum(u32) {
    MOVE_TO = 1,
    LINE_TO = 2,
    CLOSE_PATH = 7,
};

/// Pack command id and count into a command integer.
pub fn commandInteger(id: CommandId, count: u32) u32 {
    return (@intFromEnum(id) & 0x7) | (count << 3);
}

pub fn commandMoveTo(count: u32) u32 {
    return commandInteger(.MOVE_TO, count);
}

pub fn commandLineTo(count: u32) u32 {
    return commandInteger(.LINE_TO, count);
}

pub fn commandClosePath() u32 {
    return commandInteger(.CLOSE_PATH, 1);
}

fn commandId(value: u32) u32 {
    return value & 0x7;
}

fn commandCount(value: u32) u32 {
    return value >> 3;
}

fn det(a: Point, b: Point) i64 {
    return @as(i64, a.x) * @as(i64, b.y) - @as(i64, b.x) * @as(i64, a.y);
}

/// Stateful geometry decoder
pub const GeometryDecoder = struct {
    it: pbf.PackedUInt32Iterator,
    cursor: Point = .{},
    max_count: u32,
    count_left: u32 = 0,

    pub fn init(data: []const u8, max: usize) !GeometryDecoder {
        const max_count = std.math.cast(u32, max) orelse return error.CountTooLarge;
        return .{
            .it = .init(data),
            .max_count = max_count,
        };
    }

    pub fn count(self: GeometryDecoder) u32 {
        return self.count_left;
    }

    pub fn done(self: GeometryDecoder) bool {
        return self.it.pos >= self.it.data.len;
    }

    /// Advance to the next command and validate its type.
    pub fn nextCommand(self: *GeometryDecoder, expected: CommandId) !bool {
        std.debug.assert(self.count_left == 0);
        const maybe_raw = try self.it.next();
        if (maybe_raw == null) return false;
        const raw = maybe_raw.?;

        const actual = commandId(raw);
        if (actual != @intFromEnum(expected)) return error.UnexpectedCommand;

        if (expected == .CLOSE_PATH) {
            // Spec 4.3.3.3: ClosePath must always have count 1.
            if (commandCount(raw) != 1) return error.InvalidClosePathCount;
        } else {
            self.count_left = commandCount(raw);
            if (self.count_left > self.max_count) return error.CountTooLarge;
        }

        return true;
    }

    /// Decode the next delta-encoded point and update the cursor.
    pub fn nextPoint(self: *GeometryDecoder) !Point {
        std.debug.assert(self.count_left > 0);

        const maybe_dx = try self.it.next();
        const maybe_dy = try self.it.next();
        if (maybe_dx == null or maybe_dy == null) return error.TooFewPoints;

        const dx = pbf.decodeZigZag32(maybe_dx.?);
        const dy = pbf.decodeZigZag32(maybe_dy.?);
        self.cursor.x +%= dx;
        self.cursor.y +%= dy;
        self.count_left -= 1;

        return self.cursor;
    }

    /// Decode a point or multipoint geometry into a handler.
    pub fn decodePoint(self: *GeometryDecoder, handler: anytype) !HandlerResultType(@TypeOf(handler)) {
        if (!try self.nextCommand(.MOVE_TO)) return error.ExpectedMoveToPoint;
        if (self.count() == 0) return error.ZeroPointCount;

        try callMaybe(handler, "points_begin", .{self.count()});
        while (self.count() > 0) {
            try callMaybe(handler, "points_point", .{try self.nextPoint()});
        }
        if (!self.done()) return error.AdditionalPointData;
        try callMaybe(handler, "points_end", .{});

        return resultOrVoid(handler);
    }

    /// Decode a linestring or multilinestring geometry into a handler.
    pub fn decodeLinestring(self: *GeometryDecoder, handler: anytype) !HandlerResultType(@TypeOf(handler)) {
        while (try self.nextCommand(.MOVE_TO)) {
            if (self.count() != 1) return error.InvalidLinestringMoveToCount;
            const first = try self.nextPoint();

            if (!try self.nextCommand(.LINE_TO)) return error.ExpectedLineTo;
            if (self.count() == 0) return error.ZeroLineToCount;

            try callMaybe(handler, "linestring_begin", .{self.count() + 1});
            try callMaybe(handler, "linestring_point", .{first});
            while (self.count() > 0) {
                try callMaybe(handler, "linestring_point", .{try self.nextPoint()});
            }
            try callMaybe(handler, "linestring_end", .{});
        }

        return resultOrVoid(handler);
    }

    /// Decode a polygon or multipolygon geometry into a handler.
    pub fn decodePolygon(self: *GeometryDecoder, handler: anytype) !HandlerResultType(@TypeOf(handler)) {
        while (try self.nextCommand(.MOVE_TO)) {
            if (self.count() != 1) return error.InvalidPolygonMoveToCount;

            var sum: i64 = 0;
            const start = try self.nextPoint();
            var last = start;

            if (!try self.nextCommand(.LINE_TO)) return error.ExpectedPolygonLineTo;

            try callMaybe(handler, "ring_begin", .{self.count() + 2});
            try callMaybe(handler, "ring_point", .{start});

            while (self.count() > 0) {
                const point = try self.nextPoint();
                sum += det(last, point);
                last = point;
                try callMaybe(handler, "ring_point", .{point});
            }

            if (!try self.nextCommand(.CLOSE_PATH)) return error.ExpectedClosePath;

            sum += det(last, start);
            try callMaybe(handler, "ring_point", .{start});
            // `ring_end` accepts either RingType or signed area, like vtzero.
            try ringEnd(handler, sum);
        }

        return resultOrVoid(handler);
    }
};

/// Decode a point geometry.
pub fn decodePointGeometry(geometry: Geometry, handler: anytype) !HandlerResultType(@TypeOf(handler)) {
    std.debug.assert(geometry.geom_type == .POINT);
    var decoder = try GeometryDecoder.init(geometry.data, geometry.data.len / 2);
    return decoder.decodePoint(handler);
}

/// Decode a linestring geometry.
pub fn decodeLinestringGeometry(geometry: Geometry, handler: anytype) !HandlerResultType(@TypeOf(handler)) {
    std.debug.assert(geometry.geom_type == .LINESTRING);
    var decoder = try GeometryDecoder.init(geometry.data, geometry.data.len / 2);
    return decoder.decodeLinestring(handler);
}

/// Decode a polygon geometry.
pub fn decodePolygonGeometry(geometry: Geometry, handler: anytype) !HandlerResultType(@TypeOf(handler)) {
    std.debug.assert(geometry.geom_type == .POLYGON);
    var decoder = try GeometryDecoder.init(geometry.data, geometry.data.len / 2);
    return decoder.decodePolygon(handler);
}

/// Dispatch to the appropriate decoder based on geometry type.
pub fn decodeGeometry(geometry: Geometry, handler: anytype) !HandlerResultType(@TypeOf(handler)) {
    var decoder = try GeometryDecoder.init(geometry.data, geometry.data.len / 2);
    return switch (geometry.geom_type) {
        .POINT => decoder.decodePoint(handler),
        .LINESTRING => decoder.decodeLinestring(handler),
        .POLYGON => decoder.decodePolygon(handler),
        .UNKNOWN => error.UnknownGeometryType,
    };
}

fn baseType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.child,
        else => T,
    };
}

pub fn HandlerResultType(comptime T: type) type {
    const base = baseType(T);
    if (@hasDecl(base, "result")) {
        const info = @typeInfo(@TypeOf(base.result));
        return switch (info) {
            .@"fn" => |f| f.return_type orelse void,
            else => void,
        };
    }
    return void;
}

/// Call `result()` if present; otherwise return `void`.
fn resultOrVoid(handler: anytype) HandlerResultType(@TypeOf(handler)) {
    const base = baseType(@TypeOf(handler));
    if (@hasDecl(base, "result")) {
        return @call(.auto, @field(base, "result"), .{handler});
    }
}

/// Call a handler method if it exists, supporting both fallible and infallible signatures.
fn callMaybe(handler: anytype, comptime name: []const u8, args: anytype) !void {
    const base = baseType(@TypeOf(handler));
    if (@hasDecl(base, name)) {
        const func = @field(base, name);
        const return_type = @typeInfo(@TypeOf(func)).@"fn".return_type orelse void;
        if (@typeInfo(return_type) == .error_union) {
            _ = try @call(.auto, func, .{handler} ++ args);
        } else {
            _ = @call(.auto, func, .{handler} ++ args);
        }
    }
}

/// Call `ring_end` with either ring classification or signed area/2.
fn ringEnd(handler: anytype, area2: i64) !void {
    const handler_type = baseType(@TypeOf(handler));
    if (!@hasDecl(handler_type, "ring_end")) return;

    const fn_info = @typeInfo(@TypeOf(handler_type.ring_end)).@"fn";
    const arg_type = fn_info.params[1].type orelse void;
    if (arg_type == RingType) {
        const value: RingType = if (area2 > 0) .outer else if (area2 < 0) .inner else .invalid;
        const func = @field(handler_type, "ring_end");
        const return_type = fn_info.return_type orelse void;
        if (@typeInfo(return_type) == .error_union) {
            _ = try @call(.auto, func, .{ handler, value });
        } else {
            _ = @call(.auto, func, .{ handler, value });
        }
    } else if (arg_type == i64) {
        const func = @field(handler_type, "ring_end");
        const return_type = fn_info.return_type orelse void;
        if (@typeInfo(return_type) == .error_union) {
            _ = try @call(.auto, func, .{ handler, @divTrunc(area2, 2) });
        } else {
            _ = @call(.auto, func, .{ handler, @divTrunc(area2, 2) });
        }
    } else {
        @compileError("ring_end must accept vtzero.RingType or i64");
    }
}
