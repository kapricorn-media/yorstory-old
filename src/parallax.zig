const std = @import("std");

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

pub const ParallaxSet = struct {
    images: []const ParallaxImage,
};

pub const PARALLAX_SETS = [_]ParallaxSet{
    .{
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/parallax1-1.png", 0.01),
            ParallaxImage.init("images/parallax/parallax1-2.png", 0.05),
            ParallaxImage.init("images/parallax/parallax1-3.png", 0.2),
            ParallaxImage.init("images/parallax/parallax1-4.png", 0.5),
            ParallaxImage.init("images/parallax/parallax1-5.png", 0.9),
            ParallaxImage.init("images/parallax/parallax1-6.png", 1.2),
        },
    },
    .{
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/parallax2-1.png", 0.05),
            ParallaxImage.init("images/parallax/parallax2-2.png", 0.1),
            ParallaxImage.init("images/parallax/parallax2-3.png", 0.25),
            ParallaxImage.init("images/parallax/parallax2-4.png", 1.0),
        },
    },
    .{
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/parallax3-1.png", 0.05),
            ParallaxImage.init("images/parallax/parallax3-2.png", 0.2),
            ParallaxImage.init("images/parallax/parallax3-3.png", 0.3),
            ParallaxImage.init("images/parallax/parallax3-4.png", 0.8),
            ParallaxImage.init("images/parallax/parallax3-5.png", 1.1),
        },
    },
    .{
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/parallax4-1.png", 0.05),
            ParallaxImage.init("images/parallax/parallax4-2.png", 0.1),
            ParallaxImage.init("images/parallax/parallax4-3.png", 0.25),
            ParallaxImage.init("images/parallax/parallax4-4.png", 0.6),
            ParallaxImage.init("images/parallax/parallax4-5.png", 0.75),
            ParallaxImage.init("images/parallax/parallax4-6.png", 1.2),
        },
    },
    .{
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/parallax5-1.png", 0.0),
            ParallaxImage.init("images/parallax/parallax5-2.png", 0.05),
            ParallaxImage.init("images/parallax/parallax5-3.png", 0.1),
            ParallaxImage.init("images/parallax/parallax5-4.png", 0.2),
            ParallaxImage.init("images/parallax/parallax5-5.png", 0.4),
            ParallaxImage.init("images/parallax/parallax5-6.png", 0.7),
            ParallaxImage.init("images/parallax/parallax5-7.png", 1.2),
        },
    },
    .{
        .images = &[_]ParallaxImage{
            ParallaxImage.init("images/parallax/parallax6-1.png", 0.05),
            ParallaxImage.init("images/parallax/parallax6-2.png", 0.1),
            ParallaxImage.init("images/parallax/parallax6-3.png", 0.4),
            ParallaxImage.init("images/parallax/parallax6-4.png", 0.7),
            ParallaxImage.init("images/parallax/parallax6-5.png", 1.5),
        },
    },
};
