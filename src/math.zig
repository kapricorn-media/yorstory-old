pub const Vec2i = packed struct {
    x: i32 align(4),
    y: i32 align(4),

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
};

pub const Vec2 = packed struct {
    x: f32 align(4),
    y: f32 align(4),

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
    x: f32 align(4),
    y: f32 align(4),
    z: f32 align(4),

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
            .z = v1.z - v2.z,
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

pub const Mat4x4 = packed struct {
    e: [4][4]f32 align(4),

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
