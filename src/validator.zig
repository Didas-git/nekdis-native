const std = @import("std");
const Schema = @import("./schema.zig").Schema;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const Object = std.json.ObjectMap;

const ValidationError = error{
    OutOfMemory,
    MissingKey,
    InvalidType,
    InvalidPoint,
};

const Valid = union(enum) {
    boolean,
    parsed: []const u8,
};

pub fn Validator(comptime enable_parsing: bool) fn (schema: *const Schema, obj: *const Object) ValidationError!Valid {
    return struct {
        fn _validator(schema: *const Schema, obj: *const Object) ValidationError!Valid {
            var iter = schema.iterator();

            var out = if (enable_parsing) std.ArrayList(u8).init(gpa.allocator());
            var writer = if (enable_parsing) std.json.writeStream(out.writer(), .{});

            if (enable_parsing) try writer.beginObject();

            while (iter.next()) |schema_entry| {
                const schema_key = schema_entry.key_ptr.*;
                const schema_field = schema_entry.value_ptr.*;

                const value = obj.get(schema_key) orelse std.json.Value{ .null = {} };

                if (value == .null) {
                    if (schema_field.options.optional) {
                        if (enable_parsing) {
                            switch (schema_field.type) {
                                .object => return ValidationError.MissingKey,
                                .vector => |vec| switch (vec) {
                                    inline else => |vecType| {
                                        if (vecType.default) |default| {
                                            try writer.objectField(schema_key);
                                            try writer.write(default);
                                            continue;
                                        } else return ValidationError.MissingKey;
                                    },
                                },
                                inline else => |data| {
                                    if (data.default) |default| {
                                        try writer.objectField(schema_key);
                                        try writer.write(default);
                                        continue;
                                    } else return ValidationError.MissingKey;
                                },
                            }
                        } else continue;
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
                        const parsed = try _validator(&schema_field.type.object, &value.object);
                        if (enable_parsing) {
                            try writer.objectField(schema_key);
                            try out.writer().writeByte(':');
                            try out.writer().writeAll(parsed.parsed);
                            // Make the writer think valueDone was called
                            // This is what makes it possible to not have to call write
                            writer.next_punctuation = .comma;
                        }
                        continue;
                    },
                }

                if (enable_parsing) {
                    try writer.objectField(schema_key);
                    try writer.write(value);
                }
            }

            if (enable_parsing) {
                try writer.endObject();
            }

            const slice = if (enable_parsing) try out.toOwnedSlice();
            if (enable_parsing) writer.deinit();

            return if (enable_parsing) Valid{ .parsed = slice } else Valid{ .boolean = {} };
        }
    }._validator;
}
