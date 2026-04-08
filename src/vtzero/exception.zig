const std = @import("std");

/// Zig replacement for C++ vtzero exceptions used in the upstream tests.
/// These are lightweight message-carrying structs intended for parity in test ports.

pub const FormatException = struct {
    msg: []const u8,
    owned: bool = false,
    allocator: ?std.mem.Allocator = null,

    pub fn init(msg: []const u8) FormatException {
        return .{ .msg = msg };
    }

    pub fn initDup(allocator: std.mem.Allocator, msg: []const u8) !FormatException {
        return .{ .msg = try allocator.dupe(u8, msg), .owned = true, .allocator = allocator };
    }

    pub fn deinit(self: *FormatException) void {
        if (self.owned) self.allocator.?.free(self.msg);
        self.* = undefined;
    }

    pub fn what(self: FormatException) []const u8 {
        return self.msg;
    }
};

pub const GeometryException = struct {
    msg: []const u8,
    owned: bool = false,
    allocator: ?std.mem.Allocator = null,

    pub fn init(msg: []const u8) GeometryException {
        return .{ .msg = msg };
    }

    pub fn initDup(allocator: std.mem.Allocator, msg: []const u8) !GeometryException {
        return .{ .msg = try allocator.dupe(u8, msg), .owned = true, .allocator = allocator };
    }

    pub fn deinit(self: *GeometryException) void {
        if (self.owned) self.allocator.?.free(self.msg);
        self.* = undefined;
    }

    pub fn what(self: GeometryException) []const u8 {
        return self.msg;
    }
};

pub const TypeException = struct {
    pub fn what(_: TypeException) []const u8 {
        return "wrong property value type";
    }
};

pub const VersionException = struct {
    msg: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, version: u32) !VersionException {
        return .{
            .allocator = allocator,
            .msg = try std.fmt.allocPrint(allocator, "unknown vector tile version: {d}", .{version}),
        };
    }

    pub fn deinit(self: *VersionException) void {
        self.allocator.free(self.msg);
        self.* = undefined;
    }

    pub fn what(self: VersionException) []const u8 {
        return self.msg;
    }
};

pub const OutOfRangeException = struct {
    msg: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, index: u32) !OutOfRangeException {
        return .{
            .allocator = allocator,
            .msg = try std.fmt.allocPrint(allocator, "index out of range: {d}", .{index}),
        };
    }

    pub fn deinit(self: *OutOfRangeException) void {
        self.allocator.free(self.msg);
        self.* = undefined;
    }

    pub fn what(self: OutOfRangeException) []const u8 {
        return self.msg;
    }
};

