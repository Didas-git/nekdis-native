const std = @import("std");

pub const Schema = std.StringArrayHashMap(Field);

pub const Field = struct {
    type: FieldType,
    options: Options = Options{},
};

const FieldType = union(enum) {
    string: StringField,
    float: FloatField,
    integer: IntegerField,
    bigint: BigIntField,
    boolean: BooleanField,
    text: TextField,
    date: DateField,
    point: PointField,
    vector: VectorField,
    object: Schema,
};

const Options = packed struct {
    index: bool = false,
    optional: bool = false,
    sortable: bool = false,
};

const StringField = struct {
    default: ?[]const u8,
    literal: [][]const u8 = &.{},
};

const FloatField = struct {
    default: ?f64,
    literal: []f64 = &.{},
};

const IntegerField = struct {
    default: ?i64,
    literal: []i64 = &.{},
};

const BigIntField = struct {
    default: ?[]const u8,
    literal: [][]const u8 = &.{},
};

const BooleanField = struct {
    default: ?bool,
};

const PhoneticMatcher = enum(u8) { EN, FR, PT, ES };

const TextField = struct {
    default: ?[]const u8,
    weight: u8 = 1,
    phonetic: ?PhoneticMatcher,
};

const DateField = struct {
    default: ?i64,
};

const Point = struct {
    longitude: f64,
    latitude: f64,
};

const PointField = struct {
    default: ?Point,
};

const VectorField = union(enum) {
    flat: FlatVector,
    hsnw: HSNWVector,
};

const VectorType = enum(u8) { F32, F64 };
const VectorDistance = enum(u8) { L2, IP, COSINE };

const FlatVector = struct {
    type: VectorType,
    distance: VectorDistance,
    default: ?[]f64,
    dim: i64,
    size: i64 = 1024,
    cap: ?i64,
};

const HSNWVector = struct {
    type: VectorType,
    distance: VectorDistance,
    runtime: i32 = 10,
    default: ?[]f64,
    epsilon: f64 = 0.01,
    dim: i64,
    maximum: i64 = 16,
    construction: i64 = 200,
    cap: ?i64,
};
