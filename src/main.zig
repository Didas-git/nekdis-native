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
    MissingKey,
    NullNonOptional,
    InvalidType,
    InvalidPoint,
};

const ValidateOptions = packed struct {
    allow_excess_properties: bool = false,
    should_parse: bool = true,
};

fn validate_and_parse(schema: *const Schema, obj: *const Object) ValidationError![]const u8 {
    var iter = schema.iterator();

    var out = std.ArrayList(u8).init(gpa.allocator());
    defer out.deinit();

    var writer = std.json.writeStream(out.writer(), .{});
    defer writer.deinit();
    try writer.beginObject();

    while (iter.next()) |schema_entry| {
        const schema_key = schema_entry.key_ptr.*;
        const schema_field = schema_entry.value_ptr.*;

        const value = obj.get(schema_key) orelse std.json.Value{ .null = {} };

        if (value == .null) {
            if (schema_field.options.optional) {
                switch (schema_field.type) {
                    .vector => |vec| switch (vec) {
                        inline else => |vecType| {
                            if (vecType.default) |default| {
                                try writer.objectField(schema_key);
                                try writer.write(default);
                                continue;
                            } else return ValidationError.MissingKey;
                        },
                    },
                    .object => return ValidationError.MissingKey,
                    inline else => |data| {
                        if (data.default) |default| {
                            try writer.objectField(schema_key);
                            try writer.write(default);
                            continue;
                        } else return ValidationError.MissingKey;
                    },
                }
            } else return ValidationError.MissingKey;
        }

        switch (schema_field.type) {
            .string => if (value != .string) return ValidationError.InvalidType,
            .float => if (value != .integer and value != .float) return ValidationError.InvalidType,
            .integer => if (value != .integer) return ValidationError.InvalidType,
            .bigint => if (value != .integer and value != .number_string) return ValidationError.InvalidType,
            .boolean => if (value != .bool) return ValidationError.InvalidType,
            .text => if (value != .string) return ValidationError.InvalidType,
            .date => if (value != .string and value != .integer) return ValidationError.InvalidType,
            .point => {
                if (value != .object) return ValidationError.InvalidType;
                const nested = value.object;
                if (nested.keys().len != 2 or nested.get("longitude") == null or nested.get("latitude") == null) return ValidationError.InvalidPoint;
            },
            .vector => {
                if (value != .array) return ValidationError.InvalidType;
                // TODO: Properly validate vectors
            },
            .object => {
                if (value != .object) return ValidationError.InvalidType;
                const parsed = try validate_and_parse(&schema_field.type.object, &value.object);
                try writer.objectField(schema_key);
                try out.writer().writeByte(':');
                try out.writer().writeAll(parsed);
                // Make the writer think valueDone was called
                // This is what makes it possible to not have to call write
                writer.next_punctuation = .comma;
                continue;
            },
        }
        try writer.objectField(schema_key);
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

    const result = try validate_and_parse(&SchemaStore.get("TEST").?.schema, &parsed.value.object);
    try std.testing.expectEqualSlices(u8, "{\"a\":1,\"b\":2,\"c\":{\"d\":\"s\"}}", result);
}
