//! Mapbox Vector Tile (MVT) protobuf schema constants.
//!
//! This module centralizes the numeric protobuf field tags used throughout the codebase.

pub const Tile = struct {
    /// `repeated Layer layers = 3;`
    pub const layers: u32 = 3;
};

pub const Layer = struct {
    /// `optional uint32 version = 15 [default = 1];`
    pub const version: u32 = 15;
    /// `required string name = 1;`
    pub const name: u32 = 1;
    /// `repeated Feature features = 2;`
    pub const features: u32 = 2;
    /// `repeated string keys = 3;`
    pub const keys: u32 = 3;
    /// `repeated Value values = 4;`
    pub const values: u32 = 4;
    /// `optional uint32 extent = 5 [default = 4096];`
    pub const extent: u32 = 5;
};

pub const Feature = struct {
    /// `optional uint64 id = 1 [default = 0];`
    pub const id: u32 = 1;
    /// `repeated uint32 tags = 2 [packed = true];`
    pub const tags: u32 = 2;
    /// `optional GeomType type = 3 [default = UNKNOWN];`
    pub const @"type": u32 = 3;
    /// `repeated uint32 geometry = 4 [packed = true];`
    pub const geometry: u32 = 4;
};

pub const Value = struct {
    /// `optional string string_value = 1;`
    pub const string_value: u32 = 1;
    /// `optional float float_value = 2;`
    pub const float_value: u32 = 2;
    /// `optional double double_value = 3;`
    pub const double_value: u32 = 3;
    /// `optional int64 int_value = 4;`
    pub const int_value: u32 = 4;
    /// `optional uint64 uint_value = 5;`
    pub const uint_value: u32 = 5;
    /// `optional sint64 sint_value = 6;`
    pub const sint_value: u32 = 6;
    /// `optional bool bool_value = 7;`
    pub const bool_value: u32 = 7;
};
