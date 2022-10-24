const std = @import("std");

const m = @import("math.zig");
const parallax = @import("parallax.zig");
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

    fn getTransientAllocator(self: *Self) std.heap.ArenaAllocator
    {
        return std.heap.ArenaAllocator(std.heap.FixedBufferAllocator(&self.transient[0]));
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

    const Self = @This();

    fn init() !Self
    {
        var self: Self = undefined;
        self.staticTextures[@enumToInt(Texture.DecalTopLeft)] = try TextureData.init(
            "images/decal-topleft-white.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.IconContact)] = try TextureData.init(
            "images/icon-contact.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.IconHome)] = try TextureData.init(
            "images/icon-home.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.IconPortfolio)] = try TextureData.init(
            "images/icon-portfolio.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.IconWork)] = try TextureData.init(
            "images/icon-work.png", w.GL_CLAMP_TO_EDGE
        );
        self.staticTextures[@enumToInt(Texture.StickerBackgroundWithIcons)] = try TextureData.init(
            "images/sticker-background-white.png", w.GL_CLAMP_TO_EDGE
        );
        self.numDynamicTextures = 0;
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

    fn registerDynamicTexture(self: *Self, url: []const u8, wrapMode: c_uint) !usize
    {
        if (self.numDynamicTextures >= self.dynamicTextures.len) {
            return error.FullDynamicTextures;
        }
        const id = self.numDynamicTextures;
        self.dynamicTextures[id] = try TextureData.init(url, wrapMode);
        self.numDynamicTextures += 1;
        return id;
    }
};

// return true when pressed
fn updateButton(pos: m.Vec2, size: m.Vec2, mouseState: MouseState, mouseHoverGlobal: *bool) bool
{
    const mousePosF = m.Vec2.initFromVec2i(mouseState.pos);
    if (m.isInsideRect(mousePosF, pos, size)) {
        mouseHoverGlobal.* = true;
        for (mouseState.clickEvents[0..mouseState.numClickEvents]) |clickEvent| {
            std.log.info("{}", .{clickEvent});
            const clickPosF = m.Vec2.initFromVec2i(clickEvent.pos);
            if (!clickEvent.down and clickEvent.clickType == ClickType.Left and m.isInsideRect(clickPosF, pos, size)) {
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
                ParallaxImage.init("images/parallax/parallax1-1.png", 0.01),
                ParallaxImage.init("images/parallax/parallax1-2.png", 0.05),
                ParallaxImage.init("images/parallax/parallax1-3.png", 0.2),
                ParallaxImage.init("images/parallax/parallax1-4.png", 0.5),
                ParallaxImage.init("images/parallax/parallax1-5.png", 0.9),
                ParallaxImage.init("images/parallax/parallax1-6.png", 1.2),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#000000"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("images/parallax/parallax2-1.png", 0.05),
                ParallaxImage.init("images/parallax/parallax2-2.png", 0.1),
                ParallaxImage.init("images/parallax/parallax2-3.png", 0.25),
                ParallaxImage.init("images/parallax/parallax2-4.png", 1.0),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#212121"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("images/parallax/parallax3-1.png", 0.05),
                ParallaxImage.init("images/parallax/parallax3-2.png", 0.2),
                ParallaxImage.init("images/parallax/parallax3-3.png", 0.3),
                ParallaxImage.init("images/parallax/parallax3-4.png", 0.8),
                ParallaxImage.init("images/parallax/parallax3-5.png", 1.1),
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
                ParallaxImage.init("images/parallax/parallax4-1.png", 0.05),
                ParallaxImage.init("images/parallax/parallax4-2.png", 0.1),
                ParallaxImage.init("images/parallax/parallax4-3.png", 0.25),
                ParallaxImage.init("images/parallax/parallax4-4.png", 0.6),
                ParallaxImage.init("images/parallax/parallax4-5.png", 0.75),
                ParallaxImage.init("images/parallax/parallax4-6.png", 1.2),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#111111"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("images/parallax/parallax5-1.png", 0.0),
                ParallaxImage.init("images/parallax/parallax5-2.png", 0.05),
                ParallaxImage.init("images/parallax/parallax5-3.png", 0.1),
                ParallaxImage.init("images/parallax/parallax5-4.png", 0.2),
                ParallaxImage.init("images/parallax/parallax5-5.png", 0.4),
                ParallaxImage.init("images/parallax/parallax5-6.png", 0.7),
                ParallaxImage.init("images/parallax/parallax5-7.png", 1.2),
            }),
        },
        .{
            .bgColor = .{
                .Color = try colorHexToVec4("#111111"),
            },
            .images = try allocator.dupe(ParallaxImage, &[_]ParallaxImage{
                ParallaxImage.init("images/parallax/parallax6-1.png", 0.05),
                ParallaxImage.init("images/parallax/parallax6-2.png", 0.1),
                ParallaxImage.init("images/parallax/parallax6-3.png", 0.4),
                ParallaxImage.init("images/parallax/parallax6-4.png", 0.7),
                ParallaxImage.init("images/parallax/parallax6-5.png", 1.5),
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

const Page = enum {
    Home,
    Entry,
};

fn stringToPage(uri: []const u8) !Page
{
    if (std.mem.eql(u8, uri, "/new")) {
        return Page.Home;
    }

    return error.UnknownPage;
}

const State = struct {
    fbAllocator: std.heap.FixedBufferAllocator,

    renderState: render.RenderState,

    assets: Assets,

    page: Page,
    screenSizePrev: m.Vec2i,
    scrollYPrev: c_int,
    timestampMsPrev: c_int,
    mouseState: MouseState,
    activeParallaxSetIndex: usize,
    parallaxImageSets: []ParallaxSet,
    parallaxTX: f32,

    debug: bool,

    const Self = @This();
    const PARALLAX_SET_INDEX_START = 3;
    comptime {
        if (PARALLAX_SET_INDEX_START >= parallax.PARALLAX_SETS.len) {
            @compileError("start parallax index out of bounds");
        }
    }

    pub fn init(buf: []u8, page: Page) !Self
    {
        var fbAllocator = std.heap.FixedBufferAllocator.init(buf);

        return Self {
            .fbAllocator = fbAllocator,

            .renderState = try render.RenderState.init(),

            .assets = try Assets.init(),

            .page = page,
            .screenSizePrev = m.Vec2i.zero,
            .scrollYPrev = -1,
            .timestampMsPrev = 0,
            .mouseState = MouseState.init(),
            .activeParallaxSetIndex = PARALLAX_SET_INDEX_START,
            .parallaxImageSets = try initParallaxSets(fbAllocator.allocator()),
            .parallaxTX = 0,

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

pub fn createTextLine(text: []const u8, topLeft: m.Vec2i, fontSize: i32, letterSpacing: f32,
                      color: m.Vec4, fontFamily: []const u8) void
{
    // TODO custom byte color type?
    const r = @floatToInt(u8, std.math.round(color.x * 255.0));
    const g = @floatToInt(u8, std.math.round(color.y * 255.0));
    const b = @floatToInt(u8, std.math.round(color.z * 255.0));
    const a = @floatToInt(u8, std.math.round(color.w * 255.0));

    var buf: [16]u8 = undefined;
    const hexColor = std.fmt.bufPrint(
        &buf, "#{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{r, g, b, a}
    ) catch return;

    w.addTextLine(
        &text[0], text.len,
        topLeft.x, topLeft.y, fontSize, letterSpacing,
        &hexColor[0], hexColor.len,
        &fontFamily[0], fontFamily.len
    );
}

pub fn createTextBox(text: []const u8, topLeft: m.Vec2i, width: i32, fontSize: i32, lineHeight: i32,
                     letterSpacing: f32, color: m.Vec4, fontFamily: []const u8) void
{
    // TODO custom byte color type?
    const r = @floatToInt(u8, std.math.round(color.x * 255.0));
    const g = @floatToInt(u8, std.math.round(color.y * 255.0));
    const b = @floatToInt(u8, std.math.round(color.z * 255.0));
    const a = @floatToInt(u8, std.math.round(color.w * 255.0));

    var buf: [16]u8 = undefined;
    const hexColor = std.fmt.bufPrint(
        &buf, "#{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{r, g, b, a}
    ) catch return;

    w.addTextBox(
        &text[0], text.len,
        topLeft.x, topLeft.y, width, fontSize, lineHeight, letterSpacing,
        &hexColor[0], hexColor.len,
        &fontFamily[0], fontFamily.len
    );
}

export fn onInit() void
{
    std.log.info("onInit", .{});

    _memory = std.heap.page_allocator.create(Memory) catch |err| {
        std.log.err("Failed to allocate WASM memory, error {}", .{err});
        return;
    };

    var buf: [64]u8 = undefined;
    const uriLen = ww.getUri(&buf);
    const pageString = buf[0..uriLen];
    const page = stringToPage(pageString) catch |err| {
        std.log.err("Failed to get site page from string {s}, err {}", .{pageString, err});
        return;
    };

    var state = _memory.getState();
    var remaining = _memory.persistent[@sizeOf(State)..];
    state.* = State.init(remaining, page) catch |err| {
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
    var state = _memory.getState();
    defer {
        state.timestampMsPrev = timestampMs;
        state.scrollYPrev = scrollY;
        state.mouseState.numClickEvents = 0;
    }

    const screenSizeI = m.Vec2i.init(@intCast(i32, width), @intCast(i32, height));
    const screenSizeF = m.Vec2.initFromVec2i(screenSizeI);
    const halfScreenSizeF = m.Vec2.divScalar(screenSizeF, 2.0);
    _ = halfScreenSizeF;

    const scrollYF = @intToFloat(f32, scrollY);

    const mousePosF = m.Vec2.initFromVec2i(state.mouseState.pos);
    var mouseHoverGlobal = false;

    const deltaMs = if (state.timestampMsPrev > 0) (timestampMs - state.timestampMsPrev) else 0;
    const deltaS = @intToFloat(f32, deltaMs) / 1000.0;
    _ = deltaS;

    var drawText = false;
    if (!m.Vec2i.eql(state.screenSizePrev, screenSizeI)) {
        state.screenSizePrev = screenSizeI;

        std.log.info("resize, clearing text", .{});
        w.clearAllText();
        drawText = true;
    }

    // Determine whether the active parallax set is loaded
    var activeParallaxSet = state.parallaxImageSets[state.activeParallaxSetIndex];
    var parallaxSetLoaded = true;
    for (activeParallaxSet.images) |*parallaxImage| {
        if (parallaxImage.assetId) |id| {
            if (state.assets.getDynamicTextureData(id)) |parallaxTexData| {
                if (!parallaxTexData.loaded()) {
                    parallaxSetLoaded = false;
                    break;
                }
            } else {
                std.log.err("Bad asset ID {}", .{id});
            }
        } else {
            std.log.info("register", .{});
            parallaxImage.assetId = state.assets.registerDynamicTexture(
                parallaxImage.url, w.GL_CLAMP_TO_EDGE
            ) catch |err| {
                std.log.err("register texture error {}", .{err});
                parallaxSetLoaded = false;
                break;
            };
        }
    }

    if (state.scrollYPrev != scrollY) {
    }
    // TODO
    // } else {
    //     return 0;
    // }

    const refSize = m.Vec2i.init(3840, 2000);
    const gridRefSize = 80;
    const fontStickerRefSize = 124;
    const fontStickerSmallRefSize = 26;
    const fontTextRefSize = 30;

    const fontStickerSize = @floatToInt(
        i32, fontStickerRefSize / @intToFloat(f32, refSize.y) * screenSizeF.y
    );
    const fontStickerSmallSize = @floatToInt(
        i32, fontStickerSmallRefSize / @intToFloat(f32, refSize.y) * screenSizeF.y
    );
    const fontTextSize = @floatToInt(
        i32, fontTextRefSize / @intToFloat(f32, refSize.y) * screenSizeF.y
    );
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

    const colorUi = m.Vec4.init(234.0 / 255.0, 1.0, 0.0, 1.0);
    const parallaxMotionMax = screenSizeF.x / 8.0;

    const parallaxTXLerpSpeed = 0.1;
    const tX = mousePosF.x / screenSizeF.x * 2.0 - 1.0; // -1 to 1
    state.parallaxTX = m.lerpFloat(f32, state.parallaxTX, tX, parallaxTXLerpSpeed);

    if (parallaxSetLoaded) {
        const landingImagePos = m.Vec2.init(
            marginX + gridSize * 1,
            gridSize * 2 + scrollYF
        );
        const landingImageSize = m.Vec2.init(
            screenSizeF.x - marginX * 2 - gridSize * 2,
            screenSizeF.y - gridSize * 3
        );

        switch (activeParallaxSet.bgColor) {
            .Color => |color| {
                state.renderState.quadState.drawQuad(
                    landingImagePos, landingImageSize, 1.0, color, screenSizeF
                );
            },
            .Gradient => |gradient| {
                state.renderState.quadState.drawQuadGradient(
                    landingImagePos, landingImageSize, 1.0,
                    gradient.colorTop, gradient.colorTop,
                    gradient.colorBottom, gradient.colorBottom,
                    screenSizeF
                );
            },
        }

        for (activeParallaxSet.images) |parallaxImage| {
            const assetId = parallaxImage.assetId orelse continue;
            const textureData = state.assets.getDynamicTextureData(assetId) orelse continue;
            if (!textureData.loaded()) continue;

            const textureSizeF = m.Vec2.initFromVec2i(textureData.size);
            const scaledWidth = landingImageSize.y * textureSizeF.x / textureSizeF.y;
            if (scaledWidth < landingImageSize.x) {
                // hmm, unexpected
                continue;
            }

            const fracX = landingImageSize.x / scaledWidth;
            const uvOffset = m.Vec2.init(
                (1.0 - fracX) / 2.0,
                0.0
            );
            const uvSize = m.Vec2.init(fracX, 1.0);

            const imgPos = m.Vec2.init(
                landingImagePos.x + state.parallaxTX * parallaxMotionMax * parallaxImage.factor,
                landingImagePos.y
            );
            state.renderState.quadTexState.drawQuadUvOffset(
                imgPos, landingImageSize, 0.5, uvOffset, uvSize,
                textureData.id, m.Vec4.one, screenSizeF
            );
        }
    } else {
        // render temp thingy
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
                screenSizeF.y - gridSize * 5 - iconSizeF.y + scrollYF,
            );
            state.renderState.quadTexState.drawQuad(
                iconPos, iconSizeF, 0.0, textureData.id, m.Vec4.one, screenSizeF
            );
            if (updateButton(iconPos, iconSizeF, state.mouseState, &mouseHoverGlobal)) {
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
            screenSizeF.y - decalMargin - decalSize.y + scrollYF,
        );
        const uvOriginTL = m.Vec2.init(0, 0);
        const uvSizeTL = m.Vec2.init(1, 1);
        state.renderState.quadTexState.drawQuadUvOffset(
            posTL, decalSize, 0, uvOriginTL, uvSizeTL, decalTopLeft.id, colorUi, screenSizeF
        );

        const posBL = m.Vec2.init(
            marginX + decalMargin,
            decalMargin + gridSize + scrollYF,
        );
        const uvOriginBL = m.Vec2.init(0, 1);
        const uvSizeBL = m.Vec2.init(1, -1);
        state.renderState.quadTexState.drawQuadUvOffset(
            posBL, decalSize, 0, uvOriginBL, uvSizeBL, decalTopLeft.id, colorUi, screenSizeF
        );

        const posTR = m.Vec2.init(
            screenSizeF.x - marginX - decalMargin - decalSize.x,
            screenSizeF.y - decalMargin - decalSize.y + scrollYF,
        );
        const uvOriginTR = m.Vec2.init(1, 0);
        const uvSizeTR = m.Vec2.init(-1, 1);
        state.renderState.quadTexState.drawQuadUvOffset(
            posTR, decalSize, 0, uvOriginTR, uvSizeTR, decalTopLeft.id, colorUi, screenSizeF
        );

        const posBR = m.Vec2.init(
            screenSizeF.x - marginX - decalMargin - decalSize.x,
            decalMargin + gridSize + scrollYF,
        );
        const uvOriginBR = m.Vec2.init(1, 1);
        const uvSizeBR = m.Vec2.init(-1, -1);
        state.renderState.quadTexState.drawQuadUvOffset(
            posBR, decalSize, 0, uvOriginBR, uvSizeBR, decalTopLeft.id, colorUi, screenSizeF
        );

        // content page, 2 start
        const posContentTL = m.Vec2.init(
            marginX + decalMargin,
            -gridSize * 3 - decalSize.y + scrollYF,
        );
        state.renderState.quadTexState.drawQuadUvOffset(
            posContentTL, decalSize, 0, uvOriginTL, uvSizeTL, decalTopLeft.id, colorUi, screenSizeF
        );
        const posContentTR = m.Vec2.init(
            screenSizeF.x - marginX - decalMargin - decalSize.x,
            -gridSize * 3 - decalSize.y + scrollYF,
        );
        state.renderState.quadTexState.drawQuadUvOffset(
            posContentTR, decalSize, 0, uvOriginTR, uvSizeTR, decalTopLeft.id, colorUi, screenSizeF
        );
    }

    const stickerBackground = state.assets.getStaticTextureData(Texture.StickerBackgroundWithIcons);
    if (stickerBackground.loaded()) {
        const stickerPos = m.Vec2.init(
            marginX + gridSize * 4.5,
            gridSize * 6 + scrollYF
        );
        const stickerSize = m.Vec2.init(gridSize * 14.5, gridSize * 3);
        state.renderState.quadTexState.drawQuad(
            stickerPos, stickerSize, 0, stickerBackground.id, colorUi, screenSizeF
        );
    }

    // const colorWhite = m.Vec4.init(1.0, 1.0, 1.0, 1.0);
    const colorBlack = m.Vec4.init(0.0, 0.0, 0.0, 1.0);

    const framePos = m.Vec2.init(marginX + gridSize, gridSize * 2);
    const frameSize = m.Vec2.init(
        screenSizeF.x - marginX * 2 - gridSize * 2,
        screenSizeF.y - gridSize * 3 + scrollYF,
    );
    state.renderState.roundedFrameState.drawFrame(
        m.Vec2.zero, screenSizeF, 0, framePos, frameSize, 0.0, colorBlack, screenSizeF
    );

    if (drawText) {
        // sticker
        const stickerText = switch (state.page) {
            .Home => "yorstory",
            .Entry => "HALO IV",
        };
        const textStickerPos1 = m.Vec2i.init(
            @floatToInt(i32, marginX + gridSize * 5.5),
            screenSizeI.y - @floatToInt(i32, gridSize * 7.4)
        );
        createTextLine(
            stickerText,
            textStickerPos1, fontStickerSize, gridSize * -0.05,
            colorBlack, "HelveticaBold",
        );

        const textStickerPos2 = m.Vec2i.init(
            @floatToInt(i32, marginX + gridSize * 5.5),
            screenSizeI.y - @floatToInt(i32, gridSize * 6.5)
        );
        createTextLine(
            "A YORSTORY company © 2018-2022.",
            textStickerPos2, fontStickerSmallSize, 0.0,
            colorBlack, "HelveticaBold",
        );

        const textStickerPos3 = m.Vec2i.init(
            @floatToInt(i32, marginX + gridSize * 12),
            screenSizeI.y - @floatToInt(i32, gridSize * 8.55)
        );
        createTextBox(
            "At Yorstory, alchemists and wizards fashion your story with style, light, and shadow.",
            textStickerPos3, @floatToInt(i32, gridSize * 6),
            fontStickerSmallSize, fontStickerSmallSize, 0.0,
            colorBlack, "HelveticaBold",
        );

        // sub-landing text
        const lineHeight = @floatToInt(i32, @intToFloat(f32, fontTextSize) * 1.5);
        const textSubLeftPos = m.Vec2i.init(
            @floatToInt(i32, marginX + gridSize * 5.5),
            screenSizeI.y
        );
        createTextBox(
            "Yorstory is a creative development studio specializing in sequential art. We are storytellers with over 20 years of experience in the Television, Film, and Video Game industries.",
            textSubLeftPos, @floatToInt(i32, gridSize * 13),
            fontTextSize, lineHeight, 0.0,
            colorUi, "HelveticaMedium"
        );
        const textSubRightPos = m.Vec2i.init(
            @floatToInt(i32, marginX + gridSize * 19.5),
            screenSizeI.y
        );
        createTextBox(
            "Our diverse experience has given us an unparalleled understanding of multiple mediums, giving us the tools to create a cohesive, story-centric vision, along with the visuals needed to create a shared understanding between multiple deparments or disciplines.",
            textSubRightPos, @floatToInt(i32, gridSize * 13),
            fontTextSize, lineHeight, 0.0,
            colorUi, "HelveticaMedium"
        );

        // content section
        const contentHeaderPos = m.Vec2i.init(
            @floatToInt(i32, marginX + gridSize * 5.5),
            @floatToInt(i32, screenSizeF.y + gridSize * 7.75),
        );
        createTextLine(
            "projects", contentHeaderPos, fontStickerSize, 0.0, colorUi, "HelveticaBold"
        );

        const contentSubPos = m.Vec2i.init(
            @floatToInt(i32, marginX + gridSize * 5.5),
            @floatToInt(i32, screenSizeF.y + gridSize * 9),
        );
        const contentSubWidth = @floatToInt(i32, screenSizeF.x - marginX * 2 - gridSize * 5.5 * 2);
        createTextBox(
            "In alchemy, the term chrysopoeia (from Greek χρυσοποιία, khrusopoiia, \"gold-making\") refers to the artificial production of gold, most commonly by the alleged transmutation of base metals such as lead. A related term is argyropoeia (ἀργυροποιία, arguropoiia, \"silver-making\"), referring to the artificial production...",
            contentSubPos, contentSubWidth,
            fontTextSize, lineHeight, 0.0,
            colorUi, "HelveticaMedium"
        );
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
        i = 1;
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
        i = 1;
        while (i < nV) : (i += 1) {
            const iF = @intToFloat(f32, i);
            const color = if (@rem(i, 2) == 0) colorGrid else colorGridHalf;
            const posLeft = m.Vec2.init(halfGridSize * iF, 0);
            state.renderState.quadState.drawQuad(posLeft, sizeV, 0, color, screenSizeF);
            const posRight = m.Vec2.init(screenSizeF.x - halfGridSize * iF, 0);
            state.renderState.quadState.drawQuad(posRight, sizeV, 0, color, screenSizeF);
        }
    }

    return height * 2;
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
