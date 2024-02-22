const std = @import("std");
const Schema = @import("./schema.zig").Schema;

const Object = std.json.ObjectMap;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var SchemaStore = std.StringHashMap(StoreSchema).init(gpa.allocator());

const StoreSchema = struct {
    options: ValidateOptions = ValidateOptions{},
    schema: Schema,
};

pub fn main() !void {}

const ValidationError = error{
    OutOfMemory,
    UnknownKey,
    NullNonOptional,
    InvalidType,
    InvalidPoint,
};

const ValidateOptions = packed struct {
    allow_excess_properties: bool = false,
    should_parse: bool = true,
};

fn validate_and_parse(schema: *const Schema, obj: *const Object, options: ValidateOptions) ValidationError![]const u8 {
    var iter = obj.iterator();

    var out = std.ArrayList(u8).init(gpa.allocator());
    defer out.deinit();

    var writer = std.json.writeStream(out.writer(), .{});
    defer writer.deinit();

    try writer.beginObject();

    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        const key_schema = schema.get(key) orelse if (options.allow_excess_properties) continue else return ValidationError.UnknownKey;

        switch (value) {
            .null => {
                switch (key_schema.type) {
                    .vector => |vec| switch (vec) {
                        inline else => |vecType| {
                            if (vecType.default) |default| {
                                try writer.objectField(key);
                                try writer.write(default);
                                continue;
                            } else return ValidationError.NullNonOptional;
                        },
                    },
                    .object => return ValidationError.NullNonOptional,
                    inline else => |data| {
                        if (data.default) |default| {
                            try writer.objectField(key);
                            try writer.write(default);
                            continue;
                        } else return ValidationError.NullNonOptional;
                    },
                }

                if (!key_schema.options.optional) return ValidationError.NullNonOptional;
            },
            .bool => if (key_schema.type != .boolean) return ValidationError.InvalidType,
            .integer => {
                if (key_schema.type != .integer and key_schema.type != .bigint and key_schema.type != .float and key_schema.type != .date) return ValidationError.InvalidType;
            },
            .float => if (key_schema.type != .float) return ValidationError.InvalidType,
            .number_string => if (key_schema.type != .bigint) return ValidationError.InvalidType,
            .string => if (key_schema.type != .string and key_schema.type != .text) return ValidationError.InvalidType,
            // TODO: Implement Arrays, Tuples, References & Relations
            .array => unreachable,
            .object => |nested| switch (key_schema.type) {
                .object => {
                    const parsed = try validate_and_parse(&key_schema.type.object, &nested, options);
                    try writer.objectField(key);
                    try out.writer().writeByte(':');
                    try out.writer().writeAll(parsed);
                    // Make the writer think valueDone was called
                    // This is what makes it possible to not have to call write
                    writer.next_punctuation = .comma;
                    continue;
                },
                .point => {
                    if (nested.keys().len != 2 or nested.get("longitude") == null or nested.get("latitude") == null) return ValidationError.InvalidPoint;
                },
                else => return ValidationError.InvalidType,
            },
        }

        try writer.objectField(key);
        try writer.write(value);
    }

    try writer.endObject();
    return std.mem.Allocator.dupe(gpa.allocator(), u8, out.items);
}

test "validate and parse JSON" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"a\":1,\"b\":2,\"c\":{\"d\":\"s\"},\"e\":3}", .{});
    defer parsed.deinit();

    var schema = Schema.init(std.testing.allocator);
    defer schema.deinit();

    var inner = Schema.init(std.testing.allocator);
    defer inner.deinit();

    try schema.put("a", .{ .type = .{ .float = .{ .default = null } } });
    try schema.put("b", .{ .type = .{ .integer = .{ .default = null } } });

    try inner.put("d", .{ .type = .{ .string = .{ .default = null } } });
    try schema.put("c", .{ .type = .{ .object = inner } });
    try SchemaStore.put("TEST", .{ .schema = schema });

    const result = try validate_and_parse(&SchemaStore.get("TEST").?.schema, &parsed.value.object, .{ .allow_excess_properties = true });
    try std.testing.expectEqualSlices(u8, "{\"a\":1,\"b\":2,\"c\":{\"d\":\"s\"}}", result);
    try std.testing.expectEqual(validate_and_parse(&SchemaStore.get("TEST").?.schema, &parsed.value.object, .{}), ValidationError.UnknownKey);
}
