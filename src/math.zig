const std = @import("std");

pub fn lerpFloat(comptime T: type, v1: T, v2: T, t: f32) T
{
    return v1 * (1.0 - t) + v2 * t;
}

pub fn lerpVec(comptime T: type, v1: T, v2: T, t: f32) T
{
    return T.add(T.multScalar(v1, 1.0 - t), T.multScalar(v2, t));
}

pub fn isInsideRect(p: Vec2, rectOrigin: Vec2, rectSize: Vec2) bool
{
    return p.x >= rectOrigin.x and p.x <= rectOrigin.x + rectSize.x
        and p.y >= rectOrigin.y and p.y <= rectOrigin.y + rectSize.y;
}

fn assertMathType(comptime T: type) void
{
    std.debug.assert(T == Vec2i or T == Vec2 or T == Vec3 or T == Vec4);
}

pub fn add(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1)
{
    const T = @TypeOf(v1);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @field(v1, f.name) + @field(v2, f.name);
    }
    return result;
}

pub fn sub(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1)
{
    const T = @TypeOf(v1);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @field(v1, f.name) - @field(v2, f.name);
    }
    return result;
}

pub fn max(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1)
{
    const T = @TypeOf(v1);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @max(@field(v1, f.name), @field(v2, f.name));
    }
    return result;
}

pub fn min(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1)
{
    const T = @TypeOf(v1);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @min(@field(v1, f.name), @field(v2, f.name));
    }
    return result;
}

pub const Vec2i = packed struct {
    x: i32,
    y: i32,

    const Self = @This();

    pub const zero  = init(0, 0);
    pub const one   = init(1, 1);
    pub const unitX = init(1, 0);
    pub const unitY = init(0, 1);

    pub fn init(x: i32, y: i32) Self
    {
        return Self { .x = x, .y = y };
    }

    pub fn eql(v1: Self, v2: Self) bool
    {
        return v1.x == v2.x and v1.y == v2.y;
    }

    pub fn add(v1: Self, v2: Self) Self
    {
        return Self {
            .x = v1.x + v2.x,
            .y = v1.y + v2.y,
        };
    }

    pub fn sub(v1: Self, v2: Self) Self
    {
        return Self {
            .x = v1.x - v2.x,
            .y = v1.y - v2.y,
        };
    }

    pub fn multScalar(v: Self, s: i32) Self
    {
        return Self {
            .x = v.x * s,
            .y = v.y * s,
        };
    }

    pub fn divScalar(v: Self, s: i32) Self
    {
        return Self {
            .x = v.x / s,
            .y = v.y / s,
        };
    }

    pub fn dot(v1: Self, v2: Self) f32
    {
        return v1.x * v2.x + v1.y * v2.y;
    }

    pub fn max(v1: Self, v2: Self) Self
    {
        return Self {
            .x = @max(v1.x, v2.x),
            .y = @max(v1.y, v2.y),
        };
    }

    pub fn min(v1: Self, v2: Self) Self
    {
        return Self {
            .x = @min(v1.x, v2.x),
            .y = @min(v1.y, v2.y),
        };
    }
};

pub const Vec2 = packed struct {
    x: f32,
    y: f32,

    const Self = @This();

    pub const zero  = init(0.0, 0.0);
    pub const one   = init(1.0, 1.0);
    pub const unitX = init(1.0, 0.0);
    pub const unitY = init(0.0, 1.0);

    pub fn init(x: f32, y: f32) Self
    {
        return Self { .x = x, .y = y };
    }

    pub fn initFromVec2i(v: Vec2i) Self
    {
        return Self.init(@intToFloat(f32, v.x), @intToFloat(f32, v.y));
    }

    pub fn eql(v1: Self, v2: Self) bool
    {
        return v1.x == v2.x and v1.y == v2.y;
    }

    pub fn add(v1: Self, v2: Self) Self
    {
        return Self {
            .x = v1.x + v2.x,
            .y = v1.y + v2.y,
        };
    }

    pub fn sub(v1: Self, v2: Self) Self
    {
        return Self {
            .x = v1.x - v2.x,
            .y = v1.y - v2.y,
        };
    }

    pub fn multScalar(v: Self, s: f32) Self
    {
        return Self {
            .x = v.x * s,
            .y = v.y * s,
        };
    }

    pub fn divScalar(v: Self, s: f32) Self
    {
        return Self {
            .x = v.x / s,
            .y = v.y / s,
        };
    }

    pub fn dot(v1: Self, v2: Self) f32
    {
        return v1.x * v2.x + v1.y * v2.y;
    }
};

pub const Vec3 = packed struct {
    x: f32,
    y: f32,
    z: f32,

    const Self = @This();

    pub const zero  = init(0.0, 0.0, 0.0);
    pub const one   = init(1.0, 1.0, 1.0);
    pub const unitX = init(1.0, 0.0, 0.0);
    pub const unitY = init(0.0, 1.0, 0.0);
    pub const unitZ = init(0.0, 0.0, 1.0);

    pub fn init(x: f32, y: f32, z: f32) Self
    {
        return Self { .x = x, .y = y, .z = z };
    }

    pub fn eql(v1: Self, v2: Self) bool
    {
        return v1.x == v2.x and v1.y == v2.y and v1.z == v2.z;
    }

    pub fn add(v1: Self, v2: Self) Self
    {
        return Self {
            .x = v1.x + v2.x,
            .y = v1.y + v2.y,
            .z = v1.z + v2.z,
        };
    }

    pub fn sub(v1: Self, v2: Self) Self
    {
        return Self {
            .x = v1.x - v2.x,
            .y = v1.y - v2.y,
            .z = v1.z - v2.z,
        };
    }

    pub fn multScalar(v: Self, s: f32) Self
    {
        return Self {
            .x = v.x * s,
            .y = v.y * s,
            .z = v.z * s,
        };
    }

    pub fn divScalar(v: Self, s: f32) Self
    {
        return Self {
            .x = v.x / s,
            .y = v.y / s,
            .z = v.z / s,
        };
    }

    pub fn dot(v1: Self, v2: Self) f32
    {
        return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z;
    }
};

pub const Vec4 = packed struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    const Self = @This();

    pub const zero  = init(0.0, 0.0, 0.0, 0.0);
    pub const one   = init(1.0, 1.0, 1.0, 1.0);
    pub const white = one;
    pub const black = init(0.0, 0.0, 0.0, 1.0);

    pub fn init(x: f32, y: f32, z: f32, w: f32) Self
    {
        return Self { .x = x, .y = y, .z = z, .w = w };
    }

    pub fn eql(v1: Self, v2: Self) bool
    {
        return v1.x == v2.x and v1.y == v2.y and v1.z == v2.z and v1.w == v2.w;
    }

    pub fn add(v1: Self, v2: Self) Self
    {
        return Self {
            .x = v1.x + v2.x,
            .y = v1.y + v2.y,
            .z = v1.z + v2.z,
            .w = v1.w + v2.w,
        };
    }

    pub fn sub(v1: Self, v2: Self) Self
    {
        return Self {
            .x = v1.x - v2.x,
            .y = v1.y - v2.y,
            .z = v1.z - v2.z,
            .w = v1.w - v2.w,
        };
    }

    pub fn multScalar(v: Self, s: f32) Self
    {
        return Self {
            .x = v.x * s,
            .y = v.y * s,
            .z = v.z * s,
            .w = v.w * s,
        };
    }

    pub fn divScalar(v: Self, s: f32) Self
    {
        return Self {
            .x = v.x / s,
            .y = v.y / s,
            .z = v.z / s,
            .w = v.w / s,
        };
    }

    pub fn dot(v1: Self, v2: Self) f32
    {
        return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z + v1.w * v2.w;
    }
};

pub const Rect = packed struct {
    min: Vec2,
    max: Vec2,

    const Self = @This();

    pub fn init(vMin: Vec2, vMax: Vec2) Self
    {
        return Self {
            .min = vMin,
            .max = vMax,
        };
    }

    pub fn size(self: Self) Vec2
    {
        return sub(self.max, self.min);
    }
};

pub const Mat4x4 = packed struct {
    e: [4][4]f32,

    const Self = @This();

    pub const identity = Self {
        .e = [4][4]f32 {
            [4]f32 { 1.0, 0.0, 0.0, 0.0 },
            [4]f32 { 0.0, 1.0, 0.0, 0.0 },
            [4]f32 { 0.0, 0.0, 1.0, 0.0 },
            [4]f32 { 0.0, 0.0, 0.0, 1.0 },
        },
    };

    pub fn initTranslate(v: Vec3) Self
    {
        var result = identity;
        result.e[3][0] = v.x;
        result.e[3][1] = v.y;
        result.e[3][2] = v.z;
        return result;
    }
};

test "add"
{
    const v1 = Vec2i.init(1, 6);
    const v2 = Vec2i.init(4, 5);
    const result = add(v1, v2);
    try std.testing.expectEqual(Vec2i.init(5, 11), result);
}
