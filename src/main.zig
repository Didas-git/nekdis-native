const std = @import("std");
const Schema = @import("./schema.zig").Schema;

const Validator = @import("./validator.zig").Validator;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var SchemaStore = std.StringHashMap(StoredSchema).init(gpa.allocator());

const StoredSchema = struct {
    options: ValidateOptions = ValidateOptions{},
    schema: Schema,
};

const ValidateOptions = packed struct {
    allow_excess_properties: bool = false,
    should_parse: bool = true,
};

pub fn main() !void {}

test "validate and parse JSON" {
    const validate_and_parse = Validator(true);
    const is_valid_JSON = Validator(false);

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
    try std.testing.expectEqualSlices(u8, "{\"a\":1,\"b\":2,\"c\":{\"d\":\"s\"}}", result.parsed);

    const result2 = try is_valid_JSON(&SchemaStore.get("TEST").?.schema, &parsed.value.object);
    try std.testing.expect(result2 == .boolean);
}
