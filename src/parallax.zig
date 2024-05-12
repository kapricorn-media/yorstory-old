const std = @import("std");

const app = @import("zigkm-app");
const m = @import("zigkm-math");

const App = @import("app_main.zig").App;

fn hexU8ToFloatNormalized(hexString: []const u8) !f32
{
    return @as(f32, @floatFromInt(try std.fmt.parseUnsigned(u8, hexString, 16))) / 255.0;
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
            ParallaxImage.init("DRIVE/PARALLAX/gun-flashlight.psd/1-bg.layer", 0.05),
            ParallaxImage.init("DRIVE/PARALLAX/gun-flashlight.psd/2-person-back.layer", 0.2),
            ParallaxImage.init("DRIVE/PARALLAX/gun-flashlight.psd/3-bloom.layer", 0.3),
            ParallaxImage.init("DRIVE/PARALLAX/gun-flashlight.psd/4-person-front.layer", 0.8),
            ParallaxImage.init("DRIVE/PARALLAX/gun-flashlight.psd/5-flashlight.layer", 1.1),
            ParallaxImage.init("DRIVE/PARALLAX/gun-flashlight.psd/6-gun.layer", 1.1),
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
            ParallaxImage.init("DRIVE/PARALLAX/on-hill.psd/1-cloud1.layer", 0.05),
            ParallaxImage.init("DRIVE/PARALLAX/on-hill.psd/2-cloud2.layer", 0.1),
            ParallaxImage.init("DRIVE/PARALLAX/on-hill.psd/3-person.layer", 0.25),
            ParallaxImage.init("DRIVE/PARALLAX/on-hill.psd/4-rock-left.layer", 0.6),
            ParallaxImage.init("DRIVE/PARALLAX/on-hill.psd/5-tree-right.layer", 0.75),
            ParallaxImage.init("DRIVE/PARALLAX/on-hill.psd/6-tree-left.layer", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#111111") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("DRIVE/PARALLAX/flyers.psd/1-bg.layer", 0.0),
            ParallaxImage.init("DRIVE/PARALLAX/flyers.psd/2-light.layer", 0.05),
            ParallaxImage.init("DRIVE/PARALLAX/flyers.psd/3-flyer1.layer", 0.1),
            ParallaxImage.init("DRIVE/PARALLAX/flyers.psd/4-flyer2.layer", 0.2),
            ParallaxImage.init("DRIVE/PARALLAX/flyers.psd/5-flyer3.layer", 0.4),
            ParallaxImage.init("DRIVE/PARALLAX/flyers.psd/6-window.layer", 0.7),
            ParallaxImage.init("DRIVE/PARALLAX/flyers.psd/7-person.layer", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#111111") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("DRIVE/PARALLAX/dragons.psd/1-bg.layer", 0.05),
            ParallaxImage.init("DRIVE/PARALLAX/dragons.psd/2-smoke1.layer", 0.1),
            ParallaxImage.init("DRIVE/PARALLAX/dragons.psd/3-dragon-back.layer", 0.4),
            ParallaxImage.init("DRIVE/PARALLAX/dragons.psd/4-smoke2.layer", 0.6),
            ParallaxImage.init("DRIVE/PARALLAX/dragons.psd/5-dragon-front.layer", 1.3),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/1-bg.layer", 0.0),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/2-stars.layer", 0.01),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/3-mountain-back.layer", 0.05),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/4-ring.layer", 0.08),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/5-pod-back1.layer", 0.1),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/6-pod-back2.layer", 0.2),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/7-cloud-back1.layer", 0.24),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/8-pod-front1.layer", 0.3),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/9-pod-front2.layer", 0.35),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/10-cloud-back2.layer", 0.4),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/11-cloud-back3.layer", 0.4),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/12-glow1.layer", 0.0),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/13-mountain-front.layer", 0.35),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/14-glow2.layer", 0.0),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/15-cloud-front.layer", 0.4),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/16-masterchief.layer", 1.2),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/17-glare.layer", 1.2),
            ParallaxImage.init("DRIVE/PARALLAX/halo.psd/18-fog.layer", 0.0),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("DRIVE/PARALLAX/thanos.psd/1-bg.layer", 0.01),
            ParallaxImage.init("DRIVE/PARALLAX/thanos.psd/2-person-left.layer", 0.1),
            ParallaxImage.init("DRIVE/PARALLAX/thanos.psd/3-person-right.layer", 0.15),
            ParallaxImage.init("DRIVE/PARALLAX/thanos.psd/4-thanos.layer", 0.7),
            ParallaxImage.init("DRIVE/PARALLAX/thanos.psd/5-fist.layer", 1.2),
            ParallaxImage.init("DRIVE/PARALLAX/thanos.psd/6-flare.layer", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("DRIVE/PARALLAX/moon-forest.psd/1-bg.layer", 0.01),
            ParallaxImage.init("DRIVE/PARALLAX/moon-forest.psd/2-hill.layer", 0.05),
            ParallaxImage.init("DRIVE/PARALLAX/moon-forest.psd/3-tree-back.layer", 0.1),
            ParallaxImage.init("DRIVE/PARALLAX/moon-forest.psd/4-person-back.layer", 0.35),
            ParallaxImage.init("DRIVE/PARALLAX/moon-forest.psd/5-glow1.layer", 0.0),
            ParallaxImage.init("DRIVE/PARALLAX/moon-forest.psd/6-person-front.layer", 0.85),
            ParallaxImage.init("DRIVE/PARALLAX/moon-forest.psd/7-glow2.layer", 0.0),
            ParallaxImage.init("DRIVE/PARALLAX/moon-forest.psd/8-tree-front1.layer", 1.2),
            ParallaxImage.init("DRIVE/PARALLAX/moon-forest.psd/9-tree-front2.layer", 1.3),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("DRIVE/PARALLAX/chair.psd/1-bg.layer", 0.01),
            ParallaxImage.init("DRIVE/PARALLAX/chair.psd/2-glow1.layer", 0.0),
            ParallaxImage.init("DRIVE/PARALLAX/chair.psd/3-lamps.layer", 0.1),
            ParallaxImage.init("DRIVE/PARALLAX/chair.psd/4-person-back.layer", 0.3),
            ParallaxImage.init("DRIVE/PARALLAX/chair.psd/5-person-front.layer", 0.8),
            ParallaxImage.init("DRIVE/PARALLAX/chair.psd/6-smoke.layer", 0.8),
            ParallaxImage.init("DRIVE/PARALLAX/chair.psd/7-glow2.layer", 0.0),
            ParallaxImage.init("DRIVE/PARALLAX/chair.psd/8-map.layer", 1.2),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#000000") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("DRIVE/PARALLAX/gow.psd/1-bg.layer", 0.0),
            ParallaxImage.init("DRIVE/PARALLAX/gow.psd/2-mg-guy.layer", 0.1),
            ParallaxImage.init("DRIVE/PARALLAX/gow.psd/3-mg-lady.layer", 0.2),
            ParallaxImage.init("DRIVE/PARALLAX/gow.psd/4-fg.layer", 1.0),
            ParallaxImage.init("DRIVE/PARALLAX/gow.psd/5-lensflare.layer", 0.0),
        },
    },
    .{
        .bgColor = .{
            .Color = colorHexToVec4("#111111") catch unreachable,
        },
        .images = &[_]ParallaxImage{
            ParallaxImage.init("DRIVE/PARALLAX/matahari.psd/BG.layer", 0.0),
            ParallaxImage.init("DRIVE/PARALLAX/matahari.psd/BG ladies.layer", 0.1),
            ParallaxImage.init("DRIVE/PARALLAX/matahari.psd/MG Buddha.layer", 0.3),
            ParallaxImage.init("DRIVE/PARALLAX/matahari.psd/Matahari.layer", 0.55),
            ParallaxImage.init("DRIVE/PARALLAX/matahari.psd/FG.layer", 1.8),
        },
    },
};

fn tryLoadAndGetParallaxSet(assets: anytype, index: usize, priority: u32, textureWrap: app.asset_data.TextureWrapMode, textureFilter: app.asset_data.TextureFilter) ?*const ParallaxSet
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
            }, priority, undefined) catch |err| {
                std.log.err("Failed to register {s}, err {}", .{parallaxImage.url, err});
            };
        }
    }

    return if (loaded) &PARALLAX_SETS[index] else null;
}

/// Returns bool to indicate whether the active parallax scene is fully loaded and was drawn.
pub fn loadAndDrawParallax(
    pos: m.Vec2, size: m.Vec2, depth: f32,
    appData: *App,
    renderQueue: *app.render.RenderQueue,
    screenSize: m.Vec2,
    deltaS: f64,
    textureWrap: app.asset_data.TextureWrapMode,
    textureFilter: app.asset_data.TextureFilter) bool
{
    const parallaxMotionMax = screenSize.x / 8.0;

    const parallaxIndex = blk: {
        switch (appData.pageData) {
            .Admin => unreachable,
            .Home, .Unknown => break :blk appData.activeParallaxSetIndex,
            .Entry => |entryData| {
                const project = appData.portfolio.?.projects[entryData.portfolioIndex];
                break :blk project.parallaxIndex;
            },
        }
    };

    // Determine whether the active parallax set is loaded
    var activeParallaxSet = tryLoadAndGetParallaxSet(
        &appData.assets, parallaxIndex, 5, textureWrap, textureFilter
    );

    // Load later sets
    if (appData.pageData == .Home and activeParallaxSet != null) {
        appData.parallaxIdleTimeS += deltaS;
        const nextSetIndex = (parallaxIndex + 1) % PARALLAX_SETS.len;
        const nextParallaxSet = tryLoadAndGetParallaxSet(&appData.assets, nextSetIndex, 20, textureWrap, textureFilter);
        if (nextParallaxSet) |_| {
            if (appData.parallaxIdleTimeS >= @as(f64, App.PARALLAX_SET_SWAP_SECONDS)) {
                appData.parallaxIdleTimeS = 0;
                appData.activeParallaxSetIndex = nextSetIndex;
                activeParallaxSet = nextParallaxSet;
            } else {
                for (PARALLAX_SETS, 0..) |_, i| {
                    if (tryLoadAndGetParallaxSet(&appData.assets, i, 20, textureWrap, textureFilter) == null) {
                        break;
                    }
                }
            }
        }
    }

    if (activeParallaxSet) |parallaxSet| {
        switch (parallaxSet.bgColor) {
            .Color => |color| {
                renderQueue.quad(pos, size, depth, 0, color);
            },
            .Gradient => |gradient| {
                renderQueue.quadGradient(pos, size, depth, 0,
                    [4]m.Vec4 {
                        gradient.colorBottom,
                        gradient.colorBottom,
                        gradient.colorTop,
                        gradient.colorTop,
                    }
                );
            },
        }

        for (parallaxSet.images) |parallaxImage| {
            const textureData = appData.assets.getTextureData(.{.dynamic = parallaxImage.url}) orelse unreachable;

            const textureDataF = m.Vec2.initFromVec2usize(textureData.size);
            const textureSize = m.Vec2.init(
                size.y * textureDataF.x / textureDataF.y,
                size.y
            );
            const parallaxOffsetX = appData.parallaxTX * parallaxMotionMax * parallaxImage.factor;

            const imgPos = m.Vec2.init(
                screenSize.x / 2.0 - textureSize.x / 2.0 + parallaxOffsetX,
                pos.y
            );
            renderQueue.texQuad(imgPos, textureSize, depth, 0.0, textureData);
        }
    }
    return activeParallaxSet != null;
}
