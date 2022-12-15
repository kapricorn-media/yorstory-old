const std = @import("std");

const m = @import("math.zig");

fn hexU8ToFloatNormalized(hexString: []const u8) !f32
{
    return @intToFloat(f32, try std.fmt.parseUnsigned(u8, hexString, 16)) / 255.0;
}

fn colorHexToVec4(hexString: []const u8) !m.Vec4
{
    if (hexString.len != 7 and hexString.len != 9) {
        return error.BadHexStringLength;
    }
    if (hexString[0] != '#') {
        return error.BadHexString;
    }

    const rHex = hexString[1..3];
    const gHex = hexString[3..5];
    const bHex = hexString[5..7];
    const aHex = if (hexString.len == 9) hexString[7..9] else "ff";
    return m.Vec4.init(
        try hexU8ToFloatNormalized(rHex),
        try hexU8ToFloatNormalized(gHex),
        try hexU8ToFloatNormalized(bHex),
        try hexU8ToFloatNormalized(aHex),
    );
}

pub const ParallaxImage = struct {
    url: []const u8,
    factor: f32,

    const Self = @This();

    pub fn init(url: []const u8, factor: f32) Self
    {
        return Self{
            .url = url,
            .factor = factor,
        };
    }
};

pub const ParallaxBgColorType = enum {
    Color,
    Gradient,
};

pub const ParallaxBgColor = union(ParallaxBgColorType) {
    Color: m.Vec4,
    Gradient: struct {
        colorTop: m.Vec4,
        colorBottom: m.Vec4,
    },
};

pub const ParallaxSet = struct {
    bgColor: ParallaxBgColor,
    images: []const ParallaxImage,
};

pub const PARALLAX_SETS = [_]ParallaxSet{
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#101010") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("/images/parallax/parallax1-1.png", 0.01),
            ParallaxImage.init("/images/parallax/parallax1-2.png", 0.05),
            ParallaxImage.init("/images/parallax/parallax1-3.png", 0.2),
            ParallaxImage.init("/images/parallax/parallax1-4.png", 0.5),
            ParallaxImage.init("/images/parallax/parallax1-5.png", 0.9),
            ParallaxImage.init("/images/parallax/parallax1-6.png", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("/images/parallax/parallax2-1.png", 0.05),
            ParallaxImage.init("/images/parallax/parallax2-2.png", 0.1),
            ParallaxImage.init("/images/parallax/parallax2-3.png", 0.25),
            ParallaxImage.init("/images/parallax/parallax2-4.png", 1.0),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#212121") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("/images/parallax/parallax3-1.png", 0.05),
            ParallaxImage.init("/images/parallax/parallax3-2.png", 0.2),
            ParallaxImage.init("/images/parallax/parallax3-3.png", 0.3),
            ParallaxImage.init("/images/parallax/parallax3-4.png", 0.8),
            ParallaxImage.init("/images/parallax/parallax3-5.png", 1.1),
        },
    },
    .{
        .bgColor = .{
            .Gradient = .{
                .colorTop = colorHexToVec4("#1a1b1a") catch unreachable,
                .colorBottom = colorHexToVec4("#ffffff") catch unreachable,
            },
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("/images/parallax/parallax4-1.png", 0.05),
            ParallaxImage.init("/images/parallax/parallax4-2.png", 0.1),
            ParallaxImage.init("/images/parallax/parallax4-3.png", 0.25),
            ParallaxImage.init("/images/parallax/parallax4-4.png", 0.6),
            ParallaxImage.init("/images/parallax/parallax4-5.png", 0.75),
            ParallaxImage.init("/images/parallax/parallax4-6.png", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#111111") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("/images/parallax/parallax5-1.png", 0.0),
            ParallaxImage.init("/images/parallax/parallax5-2.png", 0.05),
            ParallaxImage.init("/images/parallax/parallax5-3.png", 0.1),
            ParallaxImage.init("/images/parallax/parallax5-4.png", 0.2),
            ParallaxImage.init("/images/parallax/parallax5-5.png", 0.4),
            ParallaxImage.init("/images/parallax/parallax5-6.png", 0.7),
            ParallaxImage.init("/images/parallax/parallax5-7.png", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#111111") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("/images/parallax/parallax6-1.png", 0.05),
            ParallaxImage.init("/images/parallax/parallax6-2.png", 0.1),
            ParallaxImage.init("/images/parallax/parallax6-3.png", 0.4),
            ParallaxImage.init("/images/parallax/parallax6-4.png", 0.7),
            ParallaxImage.init("/images/parallax/parallax6-5.png", 1.5),
        },
    },
};

pub fn tryLoadAndGetParallaxSet(assets: anytype, index: usize, priority: u32, textureWrap: c_uint, textureFilter: c_uint) ?*const ParallaxSet
{
    if (index >= PARALLAX_SETS.len) {
        return null;
    }

    var loaded = true;
    for (PARALLAX_SETS[index].images) |parallaxImage| {
        if (assets.getTextureData(.{.DynamicUrl = parallaxImage.url})) |parallaxTexData| {
            if (!parallaxTexData.loaded()) {
                loaded = false;
                break;
            }
        } else {
            loaded = false;
            _ = assets.register(.{ .DynamicUrl = parallaxImage.url },
                parallaxImage.url, textureWrap, textureFilter, priority
            ) catch |err| {
                std.log.err("register texture error {}", .{err});
                break;
            };
        }
    }

    return if (loaded) &PARALLAX_SETS[index] else null;
}
