const std = @import("std");

const stb = @cImport(
    @cInclude("stb_image.h")
);

const m = @import("math.zig");
const parallax = @import("parallax.zig");
const portfolio = @import("portfolio.zig");
const render = @import("render.zig");
const w = @import("wasm_bindings.zig");
const ww = @import("wasm.zig");

const Memory = struct {
    persistent: [64 * 1024]u8 align(8),
    transient: [64 * 1024]u8 align(8),

    const Self = @This();

    fn getState(self: *Self) *State
    {
        return @ptrCast(*State, @alignCast(8, &self.persistent[0]));
    }

    fn getTransientAllocator(self: *Self) std.heap.FixedBufferAllocator
    {
        return std.heap.FixedBufferAllocator.init(&self.transient);
    }
};

var _memory: *Memory = undefined;

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

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    w.log(message_level, scope, format, args);
}

const Texture = enum(usize) {
    DecalTopLeft,
    IconContact,
    IconHome,
    IconPortfolio,
    IconWork,
    StickerBackgroundWithIcons,
    StickerNumber,
};

const TextureData = struct {
    id: c_uint,
    size: m.Vec2i,

    const Self = @This();

    fn init(url: []const u8, wrapMode: c_uint) !Self
    {
        const texture = w.createTexture(&url[0], url.len, wrapMode);
        if (texture == -1) {
            return error.createTextureFailed;
        }

        return Self {
            .id = texture,
            .size = m.Vec2i.zero, // set later when the image is loaded from URL
        };
    }

    fn loaded(self: Self) bool
    {
        return !m.Vec2i.eql(self.size, m.Vec2i.zero);
    }
};

const Assets = struct {
    const numStaticTextures = @typeInfo(Texture).Enum.fields.len;
    const maxDynamicTextures = 256;

    staticTextures: [numStaticTextures]TextureData,
    numDynamicTextures: usize,
    dynamicTextures: [maxDynamicTextures]TextureData,
    idMap: std.StringHashMap(usize),

    const Self = @This();

    fn init(allocator: std.mem.Allocator) !Self
    {
        var self: Self = undefined;
        self.staticTextures[@enumToInt(Texture.DecalTopLeft)] = try TextureData.init(
            "/images/decal-topleft-white.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.IconContact)] = try TextureData.init(
            "/images/icon-contact.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.IconHome)] = try TextureData.init(
            "/images/icon-home.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.IconPortfolio)] = try TextureData.init(
            "/images/icon-portfolio.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.IconWork)] = try TextureData.init(
            "/images/icon-work.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.StickerBackgroundWithIcons)] = try TextureData.init(
            "/images/sticker-background-white.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.StickerNumber)] = try TextureData.init(
            "/images/sticker-number.png", w.GL_CLAMP_TO_EDGE
        );
        self.numDynamicTextures = 0;
        self.idMap = std.StringHashMap(usize).init(allocator);
        return self;
    }

    fn getStaticTextureData(self: Self, texture: Texture) TextureData
    {
        return self.staticTextures[@enumToInt(texture)];
    }

    fn getDynamicTextureData(self: Self, id: usize) ?TextureData
    {
        if (id >= self.numDynamicTextures) {
            return null;
        }
        return self.dynamicTextures[id];
    }

    fn getDynamicTextureDataUri(self: Self, uri: []const u8) ?TextureData
    {
        const id = self.idMap.get(uri) orelse return null;
        return self.getDynamicTextureData(id);
    }

    fn registerDynamicTexture(self: *Self, url: []const u8, wrapMode: c_uint) !usize
    {
        if (self.numDynamicTextures >= self.dynamicTextures.len) {
            return error.FullDynamicTextures;
        }

        const id = self.numDynamicTextures;
        self.dynamicTextures[id] = try TextureData.init(url, wrapMode);

        try self.idMap.put(url, id);

        self.numDynamicTextures += 1;
        return id;
    }
};

// return true when pressed
fn updateButton(topLeft: m.Vec2, size: m.Vec2, mouseState: MouseState, scrollY: f32, mouseHoverGlobal: *bool) bool
{
    const mousePosF = m.Vec2.initFromVec2i(mouseState.pos);
    const topLeftScroll = m.Vec2.init(topLeft.x, topLeft.y - scrollY);
    if (m.isInsideRect(mousePosF, topLeftScroll, size)) {
        mouseHoverGlobal.* = true;
        for (mouseState.clickEvents[0..mouseState.numClickEvents]) |clickEvent| {
            std.log.info("{}", .{clickEvent});
            const clickPosF = m.Vec2.initFromVec2i(clickEvent.pos);
            if (!clickEvent.down and clickEvent.clickType == ClickType.Left and m.isInsideRect(clickPosF, topLeftScroll, size)) {
                return true;
            }
        }
        return false;
    } else {
        return false;
    }
}

const ParallaxImage = struct {
    url: []const u8,
    factor: f32,
    assetId: ?usize,

    const Self = @This();

    pub fn init(url: []const u8, factor: f32) Self
    {
        return Self{
            .url = url,
            .factor = factor,
            .assetId = null,
        };
    }
};

const ParallaxBgColorType = enum {
    Color,
    Gradient,
};

const ParallaxBgColor = union(ParallaxBgColorType) {
    Color: m.Vec4,
    Gradient: struct {
        colorTop: m.Vec4,
        colorBottom: m.Vec4,
    },
};

const ParallaxSet = struct {
    bgColor: ParallaxBgColor,
    images: []ParallaxImage,
};

fn initParallaxSets(allocator: std.mem.Allocator) ![]ParallaxSet
{
    return try allocator.dupe(ParallaxSet, &[_]ParallaxSet{
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#101010"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax1-1.png", 0.01),
                ParallaxImage.init("/images/parallax/parallax1-2.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax1-3.png", 0.2),
                ParallaxImage.init("/images/parallax/parallax1-4.png", 0.5),
                ParallaxImage.init("/images/parallax/parallax1-5.png", 0.9),
                ParallaxImage.init("/images/parallax/parallax1-6.png", 1.2),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#000000"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax2-1.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax2-2.png", 0.1),
                ParallaxImage.init("/images/parallax/parallax2-3.png", 0.25),
                ParallaxImage.init("/images/parallax/parallax2-4.png", 1.0),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#212121"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax3-1.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax3-2.png", 0.2),
                ParallaxImage.init("/images/parallax/parallax3-3.png", 0.3),
                ParallaxImage.init("/images/parallax/parallax3-4.png", 0.8),
                ParallaxImage.init("/images/parallax/parallax3-5.png", 1.1),
            }),
        },
        .{
            .bgColor = .{
                .Gradient = .{
                    .colorTop = try colorHexToVec4("#1a1b1a"),
                    .colorBottom = try colorHexToVec4("#ffffff"),
                },
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax4-1.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax4-2.png", 0.1),
                ParallaxImage.init("/images/parallax/parallax4-3.png", 0.25),
                ParallaxImage.init("/images/parallax/parallax4-4.png", 0.6),
                ParallaxImage.init("/images/parallax/parallax4-5.png", 0.75),
                ParallaxImage.init("/images/parallax/parallax4-6.png", 1.2),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#111111"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax5-1.png", 0.0),
                ParallaxImage.init("/images/parallax/parallax5-2.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax5-3.png", 0.1),
                ParallaxImage.init("/images/parallax/parallax5-4.png", 0.2),
                ParallaxImage.init("/images/parallax/parallax5-5.png", 0.4),
                ParallaxImage.init("/images/parallax/parallax5-6.png", 0.7),
                ParallaxImage.init("/images/parallax/parallax5-7.png", 1.2),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#111111"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("/images/parallax/parallax6-1.png", 0.05),
                ParallaxImage.init("/images/parallax/parallax6-2.png", 0.1),
                ParallaxImage.init("/images/parallax/parallax6-3.png", 0.4),
                ParallaxImage.init("/images/parallax/parallax6-4.png", 0.7),
                ParallaxImage.init("/images/parallax/parallax6-5.png", 1.5),
            }),
        },
    });
}

const ClickType = enum {
    Left,
    Middle,
    Right,
    Other,
};

const ClickEvent = struct {
    pos: m.Vec2i,
    clickType: ClickType,
    down: bool,
};

const MouseState = struct {
    pos: m.Vec2i,
    numClickEvents: usize,
    clickEvents: [64]ClickEvent,

    pub fn init() MouseState
    {
        return MouseState {
            .pos = m.Vec2i.zero,
            .numClickEvents = 0,
            .clickEvents = undefined,
        };
    }
};

const PageType = enum {
    Home,
    Entry,
};

const PageData = union(PageType) {
    Home: void,
    Entry: struct {
        portfolioIndex: usize,
    },
};

fn uriToPageData(uri: []const u8) !PageData
{
    if (std.mem.eql(u8, uri, "/")) {
        return PageData {
            .Home = {},
        };
    }
    for (portfolio.PORTFOLIO_LIST) |pf, i| {
        if (std.mem.eql(u8, uri, pf.uri)) {
            return PageData {
                .Entry = .{
                    .portfolioIndex = i,
                }
            };
        }
    }
    return error.UnknownPage;
}

const State = struct {
    fbAllocator: std.heap.FixedBufferAllocator,

    renderState: render.RenderState,

    assets: Assets,

    pageData: PageData,
    screenSizePrev: m.Vec2i,
    scrollYPrev: c_int,
    timestampMsPrev: c_int,
    mouseState: MouseState,
    activeParallaxSetIndex: usize,
    parallaxImageSets: []ParallaxSet,
    parallaxTX: f32,
    parallaxIdleTimeMs: c_int,

    debug: bool,

    const Self = @This();
    const PARALLAX_SET_INDEX_START = 3;
    comptime {
        if (PARALLAX_SET_INDEX_START >= parallax.PARALLAX_SETS.len) {
            @compileError("start parallax index out of bounds");
        }
    }

    pub fn init(buf: []u8, uri: []const u8) !Self
    {
        var fbAllocator = std.heap.FixedBufferAllocator.init(buf);

        return Self {
            .fbAllocator = fbAllocator,

            .renderState = try render.RenderState.init(),

            .assets = try Assets.init(fbAllocator.allocator()),

            .pageData = try uriToPageData(uri),
            .screenSizePrev = m.Vec2i.zero,
            .scrollYPrev = -1,
            .timestampMsPrev = 0,
            .mouseState = MouseState.init(),
            .activeParallaxSetIndex = PARALLAX_SET_INDEX_START,
            .parallaxImageSets = try initParallaxSets(fbAllocator.allocator()),
            .parallaxTX = 0,
            .parallaxIdleTimeMs = 0,

            .debug = false,
        };
    }

    pub fn deinit(self: Self) void
    {
        self.gpa.deinit();
    }

    pub fn allocator(self: Self) std.mem.Allocator
    {
        return self.fbAllocator.allocator();
    }
};

export fn onInit() void
{
    std.log.info("onInit", .{});

    _memory = std.heap.page_allocator.create(Memory) catch |err| {
        std.log.err("Failed to allocate WASM memory, error {}", .{err});
        return;
    };

    var buf: [64]u8 = undefined;
    const uriLen = ww.getUri(&buf);
    const uri = buf[0..uriLen];

    var state = _memory.getState();
    var remaining = _memory.persistent[@sizeOf(State)..];
    state.* = State.init(remaining, uri) catch |err| {
        std.log.err("State init failed, err {}", .{err});
        return;
    };

    w.glClearColor(0.0, 0.0, 0.0, 1.0);
    w.glEnable(w.GL_DEPTH_TEST);
    w.glDepthFunc(w.GL_LEQUAL);

    w.glEnable(w.GL_BLEND);
    w.glBlendFunc(w.GL_SRC_ALPHA, w.GL_ONE_MINUS_SRC_ALPHA);

    ww.setCursor("auto");
}

export fn onMouseMove(x: c_int, y: c_int) void
{
    var state = _memory.getState();
    state.mouseState.pos = m.Vec2i.init(x, y);
}

fn addClickEvent(mouseState: *MouseState, pos: m.Vec2i, clickType: ClickType, down: bool) void
{
    const i = mouseState.numClickEvents;
    if (i >= mouseState.clickEvents.len) {
        return;
    }

    mouseState.clickEvents[i] = ClickEvent{
        .pos = pos,
        .clickType = clickType,
        .down = down,
    };
    mouseState.numClickEvents += 1;
}

fn buttonToClickType(button: c_int) ClickType
{
    return switch (button) {
        0 => ClickType.Left,
        1 => ClickType.Middle,
        2 => ClickType.Right,
        else => ClickType.Other,
    };
}

fn tryLoadAndGetParallaxSet(state: *State, index: usize) ?ParallaxSet
{
    if (index >= state.parallaxImageSets.len) {
        return null;
    }

    const parallaxSet = state.parallaxImageSets[index];
    var loaded = true;
    for (parallaxSet.images) |*parallaxImage| {
        if (parallaxImage.assetId) |id| {
            if (state.assets.getDynamicTextureData(id)) |parallaxTexData| {
                if (!parallaxTexData.loaded()) {
                    loaded = false;
                    break;
                }
            } else {
                std.log.err("Bad asset ID {}", .{id});
            }
        } else {
            parallaxImage.assetId = state.assets.registerDynamicTexture(
                parallaxImage.url, w.GL_CLAMP_TO_EDGE
            ) catch |err| {
                std.log.err("register texture error {}", .{err});
                loaded = false;
                break;
            };
        }
    }

    return if (loaded) parallaxSet else null;
}

const GridImage = struct {
    uri: []const u8,
    title: ?[]const u8,
    goToUri: ?[]const u8,
};

fn drawImageGrid(images: []const GridImage, itemsPerRow: usize, topLeft: m.Vec2, width: f32, spacing: f32, fontSize: f32, fontColor: m.Vec4, mouseState: MouseState, scrollY: f32, mouseHoverGlobal: *bool, assets: *Assets, renderQueue: *render.RenderQueue, callback: fn(GridImage) void) f32
{
    const itemWidth = (width - spacing * (@intToFloat(f32, itemsPerRow) - 1)) / @intToFloat(f32, itemsPerRow);
    const itemSize = m.Vec2.init(itemWidth, itemWidth * 0.5);

    for (images) |img, i| {
        const rowF = @intToFloat(f32, i / itemsPerRow);
        const colF = @intToFloat(f32, i % itemsPerRow);
        const spacingY = if (img.title) |_| spacing * 4 else spacing;
        const itemPos = m.Vec2.init(
            topLeft.x + colF * (itemSize.x + spacing),
            topLeft.y + rowF * (itemSize.y + spacingY)
        );
        if (assets.getDynamicTextureDataUri(img.uri)) |tex| {
            if (tex.loaded()) {
                renderQueue.quadTex(
                    itemPos, itemSize, 0, tex.id, m.Vec4.one
                );
            }
        } else {
            _ = assets.registerDynamicTexture(img.uri, w.GL_CLAMP_TO_EDGE) catch |err| {
                std.log.err("failed to register {s}, err {}", .{img.uri, err});
                return 0;
            };
        }

        if (img.title) |title| {
            const textPos = m.Vec2.init(
                itemPos.x,
                itemPos.y + itemSize.y + spacing * 2
            );
            renderQueue.textLine(
                title, textPos, fontSize, 0.0, fontColor, "HelveticaBold"
            );
        }

        if (updateButton(itemPos, itemSize, mouseState, scrollY, mouseHoverGlobal)) {
            callback(img);
            // ww.setUri(img.uri);
        }
    }

    // TODO doesn't work with titles
    return @intToFloat(f32, ((images.len - 1) / itemsPerRow) + 1) * (itemSize.y + spacing);
}

export fn onMouseDown(button: c_int, x: c_int, y: c_int) void
{
    std.log.info("onMouseDown {} ({},{})", .{button, x, y});

    var state = _memory.getState();
    addClickEvent(&state.mouseState, m.Vec2i.init(x, y), buttonToClickType(button), true);
}

export fn onMouseUp(button: c_int, x: c_int, y: c_int) void
{
    std.log.info("onMouseUp {} ({},{})", .{button, x, y});

    var state = _memory.getState();
    addClickEvent(&state.mouseState, m.Vec2i.init(x, y), buttonToClickType(button), false);
}

export fn onKeyDown(keyCode: c_int) void
{
    std.log.info("onKeyDown: {}", .{keyCode});

    var state = _memory.getState();

    if (keyCode == 71) {
        state.debug = !state.debug;
    }
}

export fn onAnimationFrame(width: c_int, height: c_int, scrollY: c_int, timestampMs: c_int) c_int
{
    const screenSizeI = m.Vec2i.init(@intCast(i32, width), @intCast(i32, height));
    const screenSizeF = m.Vec2.initFromVec2i(screenSizeI);

    var state = _memory.getState();
    defer {
        state.timestampMsPrev = timestampMs;
        state.scrollYPrev = scrollY;
        state.screenSizePrev = screenSizeI;
        state.mouseState.numClickEvents = 0;
    }

    var tempAllocatorObj = _memory.getTransientAllocator();
    const tempAllocator = tempAllocatorObj.allocator();

    var renderQueue = render.RenderQueue.init(tempAllocator);

    const scrollYF = @intToFloat(f32, scrollY);

    const mousePosF = m.Vec2.initFromVec2i(state.mouseState.pos);
    var mouseHoverGlobal = false;

    const deltaMs = if (state.timestampMsPrev > 0) (timestampMs - state.timestampMsPrev) else 0;
    const deltaS = @intToFloat(f32, deltaMs) / 1000.0;

    state.parallaxIdleTimeMs += deltaMs;

    if (state.scrollYPrev != scrollY) {
    }
    // TODO
    // } else {
    //     return 0;
    // }

    const refSize = m.Vec2i.init(3840, 2000);
    // const refImageSize = m.Vec2i.init(3692, 1778);
    const gridRefSize = 74;

    const fontStickerSize = 124 / @intToFloat(f32, refSize.y) * screenSizeF.y;
    const fontStickerSmallSize = 26 / @intToFloat(f32, refSize.y) * screenSizeF.y;
    const fontSubtitleSize = 84 / @intToFloat(f32, refSize.y) * screenSizeF.y;
    const fontTextSize = 30 / @intToFloat(f32, refSize.y) * screenSizeF.y;
    const gridSize = std.math.round(
        @intToFloat(f32, gridRefSize) / @intToFloat(f32, refSize.y) * screenSizeF.y
    );
    const halfGridSize = gridSize / 2.0;

    const maxAspect = 2.0;
    var targetWidth = screenSizeF.x;
    if (screenSizeF.x / screenSizeF.y > maxAspect) {
        targetWidth = screenSizeF.y * maxAspect;
    }
    const marginX = (screenSizeF.x - targetWidth) / 2.0;

    w.glClear(w.GL_COLOR_BUFFER_BIT | w.GL_DEPTH_BUFFER_BIT);

    // const colorWhite = m.Vec4.init(1.0, 1.0, 1.0, 1.0);
    const colorBlack = m.Vec4.init(0.0, 0.0, 0.0, 1.0);
    const colorUi = switch (state.pageData) {
        .Home => m.Vec4.init(234.0 / 255.0, 1.0, 0.0, 1.0),
        .Entry => m.Vec4.init(0.0, 220.0 / 255.0, 164.0 / 255.0, 1.0),
    };
    const parallaxMotionMax = screenSizeF.x / 8.0;

    const landingImagePos = m.Vec2.init(
        marginX + gridSize * 1,
        gridSize * 1
    );
    const landingImageSize = m.Vec2.init(
        screenSizeF.x - marginX * 2 - gridSize * 2,
        screenSizeF.y - gridSize * 3
    );
    switch (state.pageData) {
        .Home => {
            // Determine whether the active parallax set is loaded
            var activeParallaxSet = tryLoadAndGetParallaxSet(state, state.activeParallaxSetIndex);
            const parallaxSetSwapSeconds = 8;
            if (activeParallaxSet) |_| {
                const nextSetIndex = (state.activeParallaxSetIndex + 1) % state.parallaxImageSets.len;
                var nextParallaxSet = tryLoadAndGetParallaxSet(state, nextSetIndex);
                if (nextParallaxSet != null and state.parallaxIdleTimeMs >= parallaxSetSwapSeconds * 1000) {
                    state.parallaxIdleTimeMs = 0;
                    state.activeParallaxSetIndex = nextSetIndex;
                    activeParallaxSet = nextParallaxSet;
                }
            }

            const targetParallaxTX = mousePosF.x / screenSizeF.x * 2.0 - 1.0; // -1 to 1
            const parallaxTXMaxSpeed = 10.0;
            const parallaxTXMaxDelta = parallaxTXMaxSpeed * deltaS;
            const parallaxTXDelta = targetParallaxTX - state.parallaxTX;
            if (std.math.absFloat(parallaxTXDelta) > 0.01) {
                state.parallaxTX += std.math.clamp(
                    parallaxTXDelta, -parallaxTXMaxDelta, parallaxTXMaxDelta
                );
            }

            if (activeParallaxSet) |parallaxSet| {
                switch (parallaxSet.bgColor) {
                    .Color => |color| {
                        renderQueue.quad(landingImagePos, landingImageSize, 1.0, color);
                    },
                    .Gradient => |gradient| {
                        renderQueue.quadGradient(
                            landingImagePos, landingImageSize, 1.0,
                            gradient.colorTop, gradient.colorTop,
                            gradient.colorBottom, gradient.colorBottom);
                    },
                }

                for (parallaxSet.images) |parallaxImage| {
                    const assetId = parallaxImage.assetId orelse continue;
                    const textureData = state.assets.getDynamicTextureData(assetId) orelse continue;
                    if (!textureData.loaded()) continue;

                    const textureSizeF = m.Vec2.initFromVec2i(textureData.size);
                    const scaledWidth = landingImageSize.y * textureSizeF.x / textureSizeF.y;
                    const parallaxOffsetX = state.parallaxTX * parallaxMotionMax * parallaxImage.factor;

                    const imgPos = m.Vec2.init(
                        screenSizeF.x / 2.0 - scaledWidth / 2.0 + parallaxOffsetX,
                        landingImagePos.y
                    );
                    const imgSize = m.Vec2.init(scaledWidth, landingImageSize.y);
                    renderQueue.quadTex(imgPos, imgSize, 0.5, textureData.id, m.Vec4.one);
                }
            } else {
                // render temp thingy
            }
        },
        .Entry => |entryData| {
            const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
            if (state.assets.getDynamicTextureDataUri(pf.landing)) |landingTex| {
                if (landingTex.loaded()) {
                    renderQueue.quadTex(landingImagePos, landingImageSize, 1.0, landingTex.id, m.Vec4.one);
                }
            } else {
                _ = state.assets.registerDynamicTexture(pf.landing, w.GL_CLAMP_TO_EDGE) catch |err| {
                    std.log.err("register failed for {s} error {}", .{pf.landing, err});
                };
            }
        },
    }

    const iconTextures = [_]Texture {
        Texture.IconHome,
        Texture.IconPortfolio,
        Texture.IconWork,
        Texture.IconContact,
    };
    var allLoaded = true;
    for (iconTextures) |iconTexture| {
        if (!state.assets.getStaticTextureData(iconTexture).loaded()) {
            allLoaded = false;
            break;
        }
    }

    if (allLoaded) {
        for (iconTextures) |iconTexture, i| {
            const textureData = state.assets.getStaticTextureData(iconTexture);

            const iF = @intToFloat(f32, i);
            const iconSizeF = m.Vec2.init(
                gridSize * 2.162,
                gridSize * 2.162,
            );
            const iconPos = m.Vec2.init(
                marginX + gridSize * 5 + gridSize * 2.5 * iF,
                gridSize * 5,
            );
            renderQueue.quadTex(
                iconPos, iconSizeF, 0.0, textureData.id, m.Vec4.one
            );
            if (updateButton(iconPos, iconSizeF, state.mouseState, scrollYF, &mouseHoverGlobal)) {
                const uri = switch (iconTexture) {
                    .IconHome => "/",
                    else => continue,
                };
                ww.setUri(uri);
            }
        }
    }

    const decalTopLeft = state.assets.getStaticTextureData(Texture.DecalTopLeft);
    if (decalTopLeft.loaded()) {
        // landing page, four corners
        const decalSize = m.Vec2.init(gridSize * 5, gridSize * 5);
        const decalMargin = gridSize * 2;

        const posTL = m.Vec2.init(
            marginX + decalMargin,
            decalMargin,
        );
        const uvOriginTL = m.Vec2.init(0, 0);
        const uvSizeTL = m.Vec2.init(1, 1);
        renderQueue.quadTexUvOffset(
            posTL, decalSize, 0, uvOriginTL, uvSizeTL, decalTopLeft.id, colorUi
        );

        const posTR = m.Vec2.init(
            screenSizeF.x - marginX - decalMargin - decalSize.x,
            decalMargin,
        );
        const uvOriginTR = m.Vec2.init(1, 0);
        const uvSizeTR = m.Vec2.init(-1, 1);
        renderQueue.quadTexUvOffset(
            posTR, decalSize, 0, uvOriginTR, uvSizeTR, decalTopLeft.id, colorUi
        );

        const posBL = m.Vec2.init(
            marginX + decalMargin,
            screenSizeF.y - decalMargin - gridSize - decalSize.y,
        );
        const uvOriginBL = m.Vec2.init(0, 1);
        const uvSizeBL = m.Vec2.init(1, -1);
        renderQueue.quadTexUvOffset(
            posBL, decalSize, 0, uvOriginBL, uvSizeBL, decalTopLeft.id, colorUi
        );

        const posBR = m.Vec2.init(
            screenSizeF.x - marginX - decalMargin - decalSize.x,
            screenSizeF.y - decalMargin - gridSize - decalSize.y,
        );
        const uvOriginBR = m.Vec2.init(1, 1);
        const uvSizeBR = m.Vec2.init(-1, -1);
        renderQueue.quadTexUvOffset(
            posBR, decalSize, 0, uvOriginBR, uvSizeBR, decalTopLeft.id, colorUi
        );

        // content page, 2 start
        const posContentTL = m.Vec2.init(
            marginX + decalMargin,
            screenSizeF.y + gridSize * 3,
        );
        renderQueue.quadTexUvOffset(
            posContentTL, decalSize, 0, uvOriginTL, uvSizeTL, decalTopLeft.id, colorUi
        );
        const posContentTR = m.Vec2.init(
            screenSizeF.x - marginX - decalMargin - decalSize.x,
            screenSizeF.y + gridSize * 3,
        );
        renderQueue.quadTexUvOffset(
            posContentTR, decalSize, 0, uvOriginTR, uvSizeTR, decalTopLeft.id, colorUi
        );
    }

    // sticker
    const stickerBackground = state.assets.getStaticTextureData(Texture.StickerBackgroundWithIcons);
    if (stickerBackground.loaded()) {
        const stickerSize = m.Vec2.init(gridSize * 14.5, gridSize * 3);
        const stickerPos = m.Vec2.init(
            marginX + gridSize * 4.5,
            screenSizeF.y - gridSize * 6 - stickerSize.y
        );
        renderQueue.quadTex(
            stickerPos, stickerSize, 0, stickerBackground.id, colorUi
        );
    }

    const stickerText = switch (state.pageData) {
        .Home => "yorstory",
        .Entry => "HALO IV",
    };
    const textStickerPos1 = m.Vec2.init(
        marginX + gridSize * 5.5,
        screenSizeF.y - gridSize * 7.4
    );
    renderQueue.textLine(
        stickerText,
        textStickerPos1, fontStickerSize, gridSize * -0.05,
        colorBlack, "HelveticaBold"
    );

    const textStickerPos2 = m.Vec2.init(
        marginX + gridSize * 5.5,
        screenSizeF.y - gridSize * 6.5
    );
    renderQueue.textLine(
        "A YORSTORY company © 2018-2022.",
        textStickerPos2, fontStickerSmallSize, 0.0,
        colorBlack, "HelveticaBold",
    );

    const textStickerPos3 = m.Vec2.init(
        marginX + gridSize * 12,
        screenSizeF.y - gridSize * 8.55
    );
    renderQueue.textBox(
        "At Yorstory, alchemists and wizards fashion your story with style, light, and shadow.",
        textStickerPos3, gridSize * 6,
        fontStickerSmallSize, fontStickerSmallSize, 0.0,
        colorBlack, "HelveticaBold",
    );

    const framePos = m.Vec2.init(marginX + gridSize * 1, gridSize * 1);
    const frameSize = m.Vec2.init(
        screenSizeF.x - marginX * 2 - gridSize * 2,
        screenSizeF.y - gridSize * 3 + scrollYF,
    );
    renderQueue.roundedFrame(m.Vec2.zero, screenSizeF, 0, framePos, frameSize, 0.0, colorBlack);

    // sub-landing text
    const lineHeight = fontTextSize * 1.5;
    const textSubLeftPos = m.Vec2.init(
        marginX + gridSize * 5.5,
        screenSizeF.y
    );
    renderQueue.textBox(
        "Yorstory is a creative development studio specializing in sequential art. We are storytellers with over 20 years of experience in the Television, Film, and Video Game industries.",
        textSubLeftPos, gridSize * 13,
        fontTextSize, lineHeight, 0.0,
        colorUi, "HelveticaMedium"
    );
    const textSubRightPos = m.Vec2.init(
        marginX + gridSize * 19.5,
        screenSizeF.y
    );
    renderQueue.textBox(
        "Our diverse experience has given us an unparalleled understanding of multiple mediums, giving us the tools to create a cohesive, story-centric vision, along with the visuals needed to create a shared understanding between multiple deparments or disciplines.",
        textSubRightPos, gridSize * 13,
        fontTextSize, lineHeight, 0.0,
        colorUi, "HelveticaMedium"
    );

    // content section
    const headerText = switch (state.pageData) {
        .Home => "projects",
        .Entry => "boarding the mechanics ***",
    };
    const subText = switch (state.pageData) {
        .Home => "In alchemy, the term chrysopoeia (from Greek χρυσοποιία, khrusopoiia, \"gold-making\") refers to the artificial production of gold, most commonly by the alleged transmutation of base metals such as lead. A related term is argyropoeia (ἀργυροποιία, arguropoiia, \"silver-making\"), referring to the artificial production...",
        .Entry => "In 2010, Yorstory partnered with Microsoft/343 Studios to join one of the video game industry's most iconic franchises - Halo. Working with the team's weapons and mission designers, we were tasked with helping visualize some of the game's weapons and idealized gameplay scenarios. The result was an exciting blend of enthusiasm sci-fi mayhem, starring the infamous Master Chief.",
    };

    const contentHeaderPos = m.Vec2.init(
        marginX + gridSize * 5.5,
        screenSizeF.y + gridSize * 7.75,
    );
    renderQueue.textLine(
        headerText,
        contentHeaderPos, fontStickerSize, 0.0,
        colorUi, "HelveticaBold"
    );

    const contentSubPos = m.Vec2.init(
        marginX + gridSize * 5.5,
        screenSizeF.y + gridSize * 9,
    );
    const contentSubWidth = screenSizeF.x - marginX * 2 - gridSize * 5.5 * 2;
    renderQueue.textBox(
        subText,
        contentSubPos, contentSubWidth,
        fontTextSize, lineHeight, 0.0,
        colorUi, "HelveticaMedium"
    );

    const CB = struct {
        fn home(image: GridImage) void
        {
            if (image.goToUri) |uri| {
                ww.setUri(uri);
            }
        }

        fn entry(image: GridImage) void
        {
            _ = image;
        }
    };

    var yMax: f32 = 0;
    switch (state.pageData) {
        .Home => {
            var images = std.ArrayList(GridImage).init(tempAllocator);
            for (portfolio.PORTFOLIO_LIST) |pf| {
                images.append(GridImage {
                    .uri = pf.cover,
                    .title = pf.title,
                    .goToUri = pf.uri,
                }) catch |err| {
                    std.log.err("image append failed {}", .{err});
                };
            }

            const itemsPerRow = 3;
            const topLeft = m.Vec2.init(
                marginX + gridSize * 5.5,
                screenSizeF.y + gridSize * 12,
            );
            const spacing = gridSize * 0.25;
            const y = drawImageGrid(images.items, itemsPerRow, topLeft, contentSubWidth, spacing, fontTextSize, colorUi, state.mouseState, scrollYF, &mouseHoverGlobal, &state.assets, &renderQueue, CB.home);

            yMax = topLeft.y + y + gridSize * 3;
        },
        .Entry => |entryData| {
            const texNumber = state.assets.getStaticTextureData(Texture.StickerNumber);
            const pf = portfolio.PORTFOLIO_LIST[entryData.portfolioIndex];
            var images = std.ArrayList(GridImage).init(tempAllocator);

            const x = marginX + gridSize * 5.5;
            var y = screenSizeF.y + gridSize * 13;
            for (pf.subprojects) |sub, i| {
                const numberPos = m.Vec2.init(
                    marginX + gridSize * 2.5,
                    y - gridSize * 2.25,
                );
                const numberSize = m.Vec2.init(gridSize * 2, gridSize * 2);
                if (texNumber.loaded()) {
                    renderQueue.quadTex(
                        numberPos, numberSize, 0, texNumber.id, m.Vec4.one
                    );
                }
                const numStr = std.fmt.allocPrint(tempAllocator, "{}", .{i + 1}) catch unreachable;
                const numberTextPos = m.Vec2.init(
                    numberPos.x + numberSize.x * 0.3,
                    numberPos.y + numberSize.y * 0.76
                );
                renderQueue.textLine(
                    numStr, numberTextPos, fontStickerSize, 0.0, colorBlack, "HelveticaBold"
                );

                renderQueue.textLine(
                    sub.name, m.Vec2.init(x, y), fontSubtitleSize, 0.0, colorUi, "HelveticaLight"
                );
                y += gridSize * 1;

                renderQueue.textBox(
                    sub.description, m.Vec2.init(x, y), contentSubWidth, fontTextSize, lineHeight, 0.0, colorUi, "HelveticaMedium"
                );
                y += gridSize * 2;

                images.clearRetainingCapacity();
                for (sub.images) |img| {
                    images.append(GridImage {
                        .uri = img,
                        .title = null,
                        .goToUri = null,
                    }) catch |err| {
                        std.log.err("image append failed {}", .{err});
                    };
                }

                const itemsPerRow = 6;
                const topLeft = m.Vec2.init(x, y);
                const spacing = gridSize * 0.25;
                y += drawImageGrid(images.items, itemsPerRow, topLeft, contentSubWidth, spacing, fontTextSize, colorUi, state.mouseState, scrollYF, &mouseHoverGlobal, &state.assets, &renderQueue, CB.entry);
                y += gridSize * 3;
            }

            yMax = y + gridSize * 2;
        },
    }

    renderQueue.renderShapes(state.renderState, screenSizeF, scrollYF);
    if (!m.Vec2i.eql(state.screenSizePrev, screenSizeI)) {
        std.log.info("resize, clearing text", .{});
        w.clearAllText();
        renderQueue.renderText();
    }

    // TODO don't do all the time
    if (mouseHoverGlobal) {
        ww.setCursor("pointer");
    } else {
        ww.setCursor("auto");
    }

    // debug grid
    if (state.debug) {
        const colorGrid = m.Vec4.init(0.6, 0.6, 0.6, 1.0);
        const colorGridHalf = m.Vec4.init(0.2, 0.2, 0.2, 1.0);

        var i: i32 = undefined;

        const nH = 20;
        const sizeH = m.Vec2.init(screenSizeF.x, 1);
        i = 0;
        while (i < nH) : (i += 1) {
            const iF = @intToFloat(f32, i);
            const color = if (@rem(i, 2) == 0) colorGrid else colorGridHalf;
            const posTop = m.Vec2.init(0, screenSizeF.y - halfGridSize * iF);
            state.renderState.quadState.drawQuad(posTop, sizeH, 0, color, screenSizeF);
            const posBottom = m.Vec2.init(0, halfGridSize * iF);
            state.renderState.quadState.drawQuad(posBottom, sizeH, 0, color, screenSizeF);
        }

        const nV = 40;
        const sizeV = m.Vec2.init(1, screenSizeF.y);
        i = 0;
        while (i < nV) : (i += 1) {
            const iF = @intToFloat(f32, i);
            const color = if (@rem(i, 2) == 0) colorGrid else colorGridHalf;
            const posLeft = m.Vec2.init(marginX + halfGridSize * iF, 0);
            state.renderState.quadState.drawQuad(posLeft, sizeV, 0, color, screenSizeF);
            const posRight = m.Vec2.init(-marginX + screenSizeF.x - halfGridSize * iF, 0);
            state.renderState.quadState.drawQuad(posRight, sizeV, 0, color, screenSizeF);
        }
    }

    return @floatToInt(c_int, yMax); //@floatToInt(c_int, screenSizeF.y * 2.5);
}

export fn onTextureLoaded(textureId: c_uint, width: c_int, height: c_int) void
{
    std.log.info("onTextureLoaded {}: {} x {}", .{textureId, width, height});

    var state = _memory.getState();

    var found = false;
    for (state.assets.staticTextures) |*texture| {
        if (texture.id == textureId) {
            texture.size = m.Vec2i.init(width, height);
            found = true;
            break;
        }
    }
    for (state.assets.dynamicTextures) |*texture| {
        if (texture.id == textureId) {
            texture.size = m.Vec2i.init(width, height);
            found = true;
            break;
        }
    }

    if (!found) {
        std.log.err("onTextureLoaded not found!", .{});
    }
}

export fn onTex() void
{
}
