const std = @import("std");

const app = @import("zigkm-app");
const m = @import("zigkm-math");

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

pub const PARALLAX_SETS = [_]ParallaxSet {
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#212121") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/gun-flashlight/1-bg.png", 0.05),
            ParallaxImage.init("images/parallax/gun-flashlight/2-person-back.png", 0.2),
            ParallaxImage.init("images/parallax/gun-flashlight/3-bloom.png", 0.3),
            ParallaxImage.init("images/parallax/gun-flashlight/4-person-front.png", 0.8),
            ParallaxImage.init("images/parallax/gun-flashlight/5-flashlight.png", 1.1),
            ParallaxImage.init("images/parallax/gun-flashlight/6-gun.png", 1.1),
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
            ParallaxImage.init("images/parallax/on-hill/1-cloud1.png", 0.05),
            ParallaxImage.init("images/parallax/on-hill/2-cloud2.png", 0.1),
            ParallaxImage.init("images/parallax/on-hill/3-person.png", 0.25),
            ParallaxImage.init("images/parallax/on-hill/4-rock-left.png", 0.6),
            ParallaxImage.init("images/parallax/on-hill/5-tree-right.png", 0.75),
            ParallaxImage.init("images/parallax/on-hill/6-tree-left.png", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#111111") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/flyers/1-bg.png", 0.0),
            ParallaxImage.init("images/parallax/flyers/2-light.png", 0.05),
            ParallaxImage.init("images/parallax/flyers/3-flyer1.png", 0.1),
            ParallaxImage.init("images/parallax/flyers/4-flyer2.png", 0.2),
            ParallaxImage.init("images/parallax/flyers/5-flyer3.png", 0.4),
            ParallaxImage.init("images/parallax/flyers/6-window.png", 0.7),
            ParallaxImage.init("images/parallax/flyers/7-person.png", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#111111") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/dragons/1-bg.png", 0.05),
            ParallaxImage.init("images/parallax/dragons/2-smoke1.png", 0.1),
            ParallaxImage.init("images/parallax/dragons/3-dragon-back.png", 0.4),
            ParallaxImage.init("images/parallax/dragons/4-smoke2.png", 0.6),
            ParallaxImage.init("images/parallax/dragons/5-dragon-front.png", 1.3),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/halo/1-bg.png", 0.0),
            ParallaxImage.init("images/parallax/halo/2-stars.png", 0.01),
            ParallaxImage.init("images/parallax/halo/3-mountain-back.png", 0.05),
            ParallaxImage.init("images/parallax/halo/4-ring.png", 0.08),
            ParallaxImage.init("images/parallax/halo/5-pod-back1.png", 0.1),
            ParallaxImage.init("images/parallax/halo/6-pod-back2.png", 0.2),
            ParallaxImage.init("images/parallax/halo/7-cloud-back1.png", 0.24),
            ParallaxImage.init("images/parallax/halo/8-pod-front1.png", 0.3),
            ParallaxImage.init("images/parallax/halo/9-pod-front2.png", 0.35),
            ParallaxImage.init("images/parallax/halo/10-cloud-back2.png", 0.4),
            ParallaxImage.init("images/parallax/halo/11-cloud-back3.png", 0.4),
            ParallaxImage.init("images/parallax/halo/12-glow1.png", 0.0),
            ParallaxImage.init("images/parallax/halo/13-mountain-front.png", 0.35),
            ParallaxImage.init("images/parallax/halo/14-glow2.png", 0.0),
            ParallaxImage.init("images/parallax/halo/15-cloud-front.png", 0.4),
            ParallaxImage.init("images/parallax/halo/16-masterchief.png", 1.2),
            ParallaxImage.init("images/parallax/halo/17-glare.png", 1.2),
            ParallaxImage.init("images/parallax/halo/18-fog.png", 0.0),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/thanos/1-bg.png", 0.01),
            ParallaxImage.init("images/parallax/thanos/2-person-left.png", 0.1),
            ParallaxImage.init("images/parallax/thanos/3-person-right.png", 0.15),
            ParallaxImage.init("images/parallax/thanos/4-thanos.png", 0.7),
            ParallaxImage.init("images/parallax/thanos/5-fist.png", 1.2),
            ParallaxImage.init("images/parallax/thanos/6-flare.png", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/moon-forest/1-bg.png", 0.01),
            ParallaxImage.init("images/parallax/moon-forest/2-hill.png", 0.05),
            ParallaxImage.init("images/parallax/moon-forest/3-tree-back.png", 0.1),
            ParallaxImage.init("images/parallax/moon-forest/4-person-back.png", 0.35),
            ParallaxImage.init("images/parallax/moon-forest/5-glow1.png", 0.0),
            ParallaxImage.init("images/parallax/moon-forest/6-person-front.png", 0.85),
            ParallaxImage.init("images/parallax/moon-forest/7-glow2.png", 0.0),
            ParallaxImage.init("images/parallax/moon-forest/8-tree-front1.png", 1.2),
            ParallaxImage.init("images/parallax/moon-forest/9-tree-front2.png", 1.3),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/chair/1-bg.png", 0.01),
            ParallaxImage.init("images/parallax/chair/2-glow1.png", 0.0),
            ParallaxImage.init("images/parallax/chair/3-lamps.png", 0.1),
            ParallaxImage.init("images/parallax/chair/4-person-back.png", 0.3),
            ParallaxImage.init("images/parallax/chair/5-person-front.png", 0.8),
            ParallaxImage.init("images/parallax/chair/6-smoke.png", 0.8),
            ParallaxImage.init("images/parallax/chair/7-glow2.png", 0.0),
            ParallaxImage.init("images/parallax/chair/8-map.png", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/chair/1-bg.png", 0.01),
            ParallaxImage.init("images/parallax/chair/2-glow1.png", 0.0),
            ParallaxImage.init("images/parallax/chair/3-lamps.png", 0.1),
            ParallaxImage.init("images/parallax/chair/4-person-back.png", 0.3),
            ParallaxImage.init("images/parallax/chair/5-person-front.png", 0.8),
            ParallaxImage.init("images/parallax/chair/6-smoke.png", 0.8),
            ParallaxImage.init("images/parallax/chair/7-glow2.png", 0.0),
            ParallaxImage.init("images/parallax/chair/8-map.png", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/gow/1-bg.png", 0.0),
            ParallaxImage.init("images/parallax/gow/2-mg-guy.png", 0.1),
            ParallaxImage.init("images/parallax/gow/3-mg-lady.png", 0.2),
            ParallaxImage.init("images/parallax/gow/4-fg.png", 1.0),
            ParallaxImage.init("images/parallax/gow/5-lensflare.png", 0.0),
        },
    },
};

pub fn tryLoadAndGetParallaxSet(assets: anytype, index: usize, priority: u32, textureWrap: app.asset_data.TextureWrapMode, textureFilter: app.asset_data.TextureFilter) ?*const ParallaxSet
{
    if (index >= PARALLAX_SETS.len) {
        return null;
    }

    var loaded = true;
    for (PARALLAX_SETS[index].images) |parallaxImage| {
        const loadState = assets.getTextureLoadState(.{.dynamic = parallaxImage.url});
        loaded = loaded and loadState == .loaded;
        if (loadState == .free) {
            assets.loadTexturePriority(.{.dynamic = parallaxImage.url}, &.{
                .path = parallaxImage.url,
                .filter = textureFilter,
                .wrapMode = textureWrap,
            }, priority) catch |err| {
                std.log.err("Failed to register {s}, err {}", .{parallaxImage.url, err});
            };
        }
    }

    return if (loaded) &PARALLAX_SETS[index] else null;
}
