const property_value_mod = @import("property_value.zig");

pub const PropertyValue = property_value_mod.PropertyValue;

/// Key/value view for a feature property.
pub const Property = struct {
    key_data: ?[]const u8 = null,
    value_data: PropertyValue = .{},

    pub fn valid(self: Property) bool {
        return self.key_data != null;
    }

    /// Returns the property key bytes.
    /// Empty for invalid/default properties.
    pub fn key(self: Property) []const u8 {
        return self.key_data orelse "";
    }

    /// Returns the property value view.
    pub fn value(self: Property) PropertyValue {
        return self.value_data;
    }
};

