const builtin = @import("builtin");
const std = @import("std");

const app = @import("zigkm-app");
const m = @import("zigkm-math");
const w = app.wasm_bindings;

pub usingnamespace app.exports;
pub usingnamespace @import("zigkm-stb").exports; // for stb linking

const asset = @import("asset.zig");
const parallax = @import("parallax.zig");
const portfolio = @import("portfolio.zig");

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

const SIZE_PERMANENT = 256 * 1024;
const SIZE_TRANSIENT = 32 * 1024 * 1024;

pub const MEMORY_FOOTPRINT = SIZE_PERMANENT + SIZE_TRANSIENT;

const defaultTextureFilter = app.asset_data.TextureFilter.linear;
const defaultTextureWrap = app.asset_data.TextureWrapMode.clampToEdge;

const refSizeDesktop = m.Vec2.init(3840, 2000);
const refSizeMobile = m.Vec2.init(1080, 1920);

const DEPTH_UI_ABOVEALL = 0.0;
const DEPTH_UI_OVER2 = 0.2;
const DEPTH_UI_OVER1 = 0.4;
const DEPTH_UI_GENERIC = 0.5;
const DEPTH_LANDINGIMAGE = 0.6;
const DEPTH_LANDINGBACKGROUND = 0.7;
const DEPTH_GRIDIMAGE = 0.6;
const DEPTH_UI_BELOWALL = 1.0;

const COLOR_YELLOW_HOME = m.Vec4.init(234.0 / 255.0, 1.0, 0.0, 1.0);

fn isVerticalAspect(screenSize: m.Vec2) bool
{
    const aspect = screenSize.x / screenSize.y;
    return aspect <= 1.0;
}

fn getGridSize(screenSize: m.Vec2) f32
{
    const gridRefSize = 80;
    if (isVerticalAspect(screenSize)) {
        return std.math.round(gridRefSize / refSizeMobile.x * screenSize.x);
    } else {
        return std.math.round(gridRefSize / refSizeDesktop.y * screenSize.y);
    }
}

fn fromRefFontSizePx(refFontSizePx: f32, screenSize: m.Vec2) f32
{
    if (isVerticalAspect(screenSize)) {
        const magicFactor = 1.0;
        return refFontSizePx / refSizeMobile.x * screenSize.x * magicFactor;
    } else {
        const magicFactor = 1.0;
        return refFontSizePx / refSizeDesktop.y * screenSize.y * magicFactor;
    }
}

// return true when pressed
fn updateButton(topLeft: m.Vec2, size: m.Vec2, mouseState: app.input.MouseState, scrollY: f32, mouseHoverGlobal: *bool) bool
{
    const mousePosF = m.Vec2.initFromVec2i(mouseState.pos);
    const topLeftScroll = m.add(topLeft, m.Vec2.init(0, -scrollY));
    const buttonRect = m.Rect.initOriginSize(topLeftScroll, size);
    if (m.isInsideRect(mousePosF, buttonRect)) {
        mouseHoverGlobal.* = true;
        for (mouseState.clickEvents[0..mouseState.numClickEvents]) |clickEvent| {
            const clickPosF = m.Vec2.initFromVec2i(clickEvent.pos);
            if (!clickEvent.down and clickEvent.clickType == app.input.ClickType.Left and m.isInsideRect(clickPosF, buttonRect)) {
                return true;
            }
        }
        return false;
    } else {
        return false;
    }
}

const PageType = enum {
    Home,
    Entry,
    Unknown,
};

const PageData = union(PageType) {
    Home: void,
    Entry: struct {
        portfolioIndex: usize,
        galleryImageIndex: ?usize,
    },
    Unknown: void,
};

fn uriToPageData(uri: []const u8, pf: ?portfolio.Portfolio) PageData
{
    if (std.mem.eql(u8, uri, "/")) {
        return PageData {
            .Home = {},
        };
    }
    if (pf) |pfpf| {
        for (pfpf.projects) |p, i| {
            if (std.mem.eql(u8, uri, p.uri)) {
                return PageData {
                    .Entry = .{
                        .portfolioIndex = i,
                        .galleryImageIndex = null,
                    }
                };
            }
        }
    }
    return PageData {
        .Unknown = {},
    };
}

pub const App = struct {
    memory: app.memory.Memory,
    inputState: app.input.InputState,
    renderState: app.render.RenderState,
    assets: app.asset.AssetsWithIds(asset.Font, asset.Texture, 256),

    fbTexture: c_uint,
    fbDepthRenderbuffer: c_uint,
    fb: c_uint,

    portfolio: ?portfolio.Portfolio,
    pageData: PageData,
    shouldUpdatePage: bool,
    screenSizePrev: m.Vec2usize,
    scrollYPrev: i32,
    timestampMsPrev: u64,
    activeParallaxSetIndex: usize,
    parallaxTX: f32,
    parallaxIdleTimeMs: u64,
    yMaxPrev: i32,

    // mobile
    anglesRef: m.Vec3,

    debug: bool,

    const Self = @This();
    const PARALLAX_SET_INDEX_START = 6;
    const PARALLAX_SET_SWAP_SECONDS = 6;
    comptime {
        if (PARALLAX_SET_INDEX_START >= parallax.PARALLAX_SETS.len) {
            @compileError("start parallax index out of bounds");
        }
    }

    pub fn load(self: *Self, memory: []u8, screenSize: m.Vec2usize, scale: f32) !void
    {
        std.log.info("App load ({}x{}, {}) ({} MB)", .{screenSize.x, screenSize.y, scale, memory.len / 1024 / 1024});

        self.memory = app.memory.Memory.init(memory, SIZE_PERMANENT, @sizeOf(Self));

        const permanentAllocator = self.memory.permanentAllocator();
        var tempBufferAllocator = self.memory.tempBufferAllocator();
        const tempAllocator = tempBufferAllocator.allocator();

        try self.renderState.load();
        try self.assets.load(permanentAllocator);

        w.glClearColor(0.0, 0.0, 0.0, 1.0);
        w.glEnable(w.GL_DEPTH_TEST);
        w.glDepthFunc(w.GL_LEQUAL);

        w.glEnable(w.GL_BLEND);
        w.glBlendFuncSeparate(
            w.GL_SRC_ALPHA, w.GL_ONE_MINUS_SRC_ALPHA, w.GL_ONE, w.GL_ONE
        );

        w.setCursorZ("auto");

        self.fbTexture = 0;
        self.fbDepthRenderbuffer = 0;
        self.fb = 0;

        w.httpGetZ("/portfolio"); // Load portfolio data ASAP

        self.portfolio = null;
        const uri = try w.getUriAlloc(tempAllocator);
        self.pageData = uriToPageData(uri, self.portfolio);
        self.shouldUpdatePage = false;
        self.screenSizePrev = m.Vec2usize.zero;
        self.scrollYPrev = -1;
        self.timestampMsPrev = 0;
        self.activeParallaxSetIndex = PARALLAX_SET_INDEX_START;
        self.parallaxTX = 0;
        self.parallaxIdleTimeMs = 0;
        self.yMaxPrev = 0;

        self.debug = false;

        try self.loadRelevantAssets(screenSize, tempAllocator);
    }

    pub fn updateAndRender(self: *Self, screenSize: m.Vec2usize, scrollY: i32, timestampMs: u64) i32
    {
        const screenSizeI = screenSize.toVec2i();
        const screenSizeF = screenSize.toVec2();
        const scrollYF = @intToFloat(f32, scrollY);
        defer {
            self.inputState.mouseState.clear();
            self.inputState.keyboardState.clear();

            self.timestampMsPrev = timestampMs;
            self.scrollYPrev = scrollY;
            self.screenSizePrev = screenSize;
        }

        const keyCodeEscape = 27;
        const keyCodeArrowLeft = 37;
        const keyCodeArrowRight = 39;
        const keyCodeG = 71;

        if (self.pageData == .Entry and self.pageData.Entry.galleryImageIndex != null and self.portfolio != null) {
            const imageCount = getImageCount(self.portfolio.?, self.pageData.Entry);
            if (self.inputState.keyboardState.keyDown(keyCodeEscape)) {
                self.pageData.Entry.galleryImageIndex = null;
            } else if (self.inputState.keyboardState.keyDown(keyCodeArrowLeft)) {
                if (self.pageData.Entry.galleryImageIndex.? == 0) {
                    self.pageData.Entry.galleryImageIndex.? = imageCount - 1;
                } else {
                    self.pageData.Entry.galleryImageIndex.? -= 1;
                }
            } else if (self.inputState.keyboardState.keyDown(keyCodeArrowRight)) {
                self.pageData.Entry.galleryImageIndex.? += 1;
                if (self.pageData.Entry.galleryImageIndex.? >= imageCount) {
                    self.pageData.Entry.galleryImageIndex.? = 0;
                }
            }
        }
        if (self.inputState.keyboardState.keyDown(keyCodeG)) {
            self.debug = !self.debug;
        }

        const deltaMs = if (self.timestampMsPrev > 0) (timestampMs - self.timestampMsPrev) else 0;
        const deltaS = @intToFloat(f32, deltaMs) / 1000.0;

        var tempBufferAllocator = self.memory.tempBufferAllocator();
        const tempAllocator = tempBufferAllocator.allocator();

        var renderQueue = tempAllocator.create(app.render.RenderQueue) catch {
            std.log.warn("Failed to allocate RenderQueue", .{});
            return -1;
        };
        renderQueue.load();

        const screenResize = !m.eql(self.screenSizePrev, screenSize);
        if (screenResize) {
            std.log.info("resetting screen framebuffer", .{});
            self.fbTexture = w.createTexture(screenSizeI.x, screenSizeI.y, w.GL_CLAMP_TO_EDGE, w.GL_NEAREST);

            self.fb = w.glCreateFramebuffer();
            w.glBindFramebuffer(w.GL_FRAMEBUFFER, self.fb);
            w.glFramebufferTexture2D(w.GL_FRAMEBUFFER, w.GL_COLOR_ATTACHMENT0, w.GL_TEXTURE_2D, self.fbTexture, 0);

            self.fbDepthRenderbuffer = w.glCreateRenderbuffer();
            w.glBindRenderbuffer(w.GL_RENDERBUFFER, self.fbDepthRenderbuffer);
            w.glRenderbufferStorage(w.GL_RENDERBUFFER, w.GL_DEPTH_COMPONENT16, screenSizeI.x, screenSizeI.y);
            w.glFramebufferRenderbuffer(w.GL_FRAMEBUFFER, w.GL_DEPTH_ATTACHMENT, w.GL_RENDERBUFFER, self.fbDepthRenderbuffer);

            self.loadRelevantAssets(screenSize, tempAllocator) catch |err| {
                std.log.err("loadRelevantAssets error {}", .{err});
            };
        }

        if (self.shouldUpdatePage or (self.pageData == .Unknown and self.portfolio != null)) {
            self.updatePageData(tempAllocator);
            self.loadRelevantAssets(screenSize, tempAllocator) catch |err| {
                std.log.err("loadRelevantAssets error {}", .{err});
            };
            self.shouldUpdatePage = false;
        }

        if (self.scrollYPrev != scrollY) {
        }
        // TODO
        // } else {
        //     return 0;
        // }

        // w.glBindFramebuffer(w.GL_FRAMEBUFFER, self.fb);
        w.bindNullFramebuffer();

        w.glClear(w.GL_COLOR_BUFFER_BIT | w.GL_DEPTH_BUFFER_BIT);

        const isVertical = isVerticalAspect(screenSizeF);

        var yMax: i32 = 0;
        if (isVertical) {
            yMax = drawMobile(self, deltaS, scrollYF, screenSizeF, renderQueue, tempAllocator);
        } else {
            yMax = drawDesktop(self, deltaMs, scrollYF, screenSizeF, renderQueue, tempAllocator);
        }
        defer {
            self.yMaxPrev = yMax;
        }

        renderQueue.render2(&self.renderState, screenSizeF, scrollYF, tempAllocator);
        if (!m.eql(self.screenSizePrev, screenSize) or yMax != self.yMaxPrev) {
            std.log.info("resize, clearing HTML elements", .{});
            w.clearAllEmbeds();
            // renderQueue.renderHtml();
        }

        // w.bindNullFramebuffer();
        // w.glClear(w.GL_COLOR_BUFFER_BIT | w.GL_DEPTH_BUFFER_BIT);
        // const lut1 = self.assets.getStaticTextureData(asset.Texture.Lut1);
        // // if (lut1.loaded()) {
        //     self.renderState.postProcessState.draw(self.fbTexture, lut1.id, screenSizeF);
        // // }

        const maxInflight = 8;
        self.assets.loadQueued(maxInflight);

        return yMax;
    }

    pub fn onPopState(self: *Self, screenSize: m.Vec2usize) void
    {
        var tempBufferAllocator = self.memory.tempBufferAllocator();
        const tempAllocator = tempBufferAllocator.allocator();

        self.updatePageData(tempAllocator);
        self.loadRelevantAssets(screenSize, tempAllocator) catch |err| {
            std.log.err("loadRelevantAssets error {}", .{err});
        };
    }

    pub fn onHttpGet(self: *Self, uri: []const u8, data: ?[]const u8) void
    {
        if (std.mem.eql(u8, uri, "/portfolio")) {
            const d = data orelse {
                std.log.err("/portfolio request failed, no data", .{});
                return;
            };
            const pf = portfolio.Portfolio.init(d, self.memory.permanentAllocator()) catch |err| {
                std.log.err("Error {} while parsing /portfolio response", .{err});
                std.log.err("Response:\n{s}", .{d});
                return;
            };
            self.portfolio = pf;
            std.log.info("Loaded portfolio ({} projects)", .{pf.projects.len});
        }
    }

    fn updatePageData(self: *Self, allocator: std.mem.Allocator) void
    {
        const uri = w.getUriAlloc(allocator) catch {
            std.log.err("getUriAlloc failed", .{});
            return;
        };
        self.pageData = uriToPageData(uri, self.portfolio);
    }

    fn changePage(self: *Self, newUri: []const u8) void
    {
        w.pushStateZ(newUri);
        w.setScrollY(0);
        self.shouldUpdatePage = true;
        self.assets.clearLoadQueue();
    }

    fn loadRelevantAssets(self: *Self, screenSize: m.Vec2usize, allocator: std.mem.Allocator) !void
    {
        const screenSizeF = screenSize.toVec2();
        const isVertical = isVerticalAspect(screenSizeF);
        const gridSize = getGridSize(screenSizeF);

        // _ = try self.assets.register(.{ .Static = asset.Texture.Lut1 },
        //     "images/LUTs/identity.png", defaultTextureWrap, defaultTextureFilter, 2
        // );
        const FontLoadInfo = struct {
            font: asset.Font,
            path: []const u8,
            atlasSize: usize,
            size: f32,
            scale: f32,
            kerning: f32,
            lineHeight: f32,
        };
        const TextureLoadInfo = struct {
            texture: asset.Texture,
            path: []const u8,
            priority: u32,
        };

        var fontsToLoad = std.ArrayList(FontLoadInfo).init(allocator);
        var texturesToLoad = std.ArrayList(TextureLoadInfo).init(allocator);

        try texturesToLoad.appendSlice(&[_]TextureLoadInfo {
            .{
                .texture = .StickerCircle,
                .path = "images/sticker-circle.png",
                .priority = 2,
            },
            .{
                .texture = .LoadingGlyphs,
                .path = "images/loading-glyphs.png",
                .priority = 2,
            },
            .{
                .texture = .DecalTopLeft,
                .path = "images/decal-topleft.png",
                .priority = 2,
            },
            .{
                .texture = .StickerShiny,
                .path = "images/sticker-shiny.png",
                .priority = 5,
            },
        });

        switch (self.pageData) {
            .Home => {
                if (!isVertical) {
                    try texturesToLoad.appendSlice(&[_]TextureLoadInfo {
                        .{
                            .texture = .LogosAll,
                            .path = "images/logos-all.png",
                            .priority = 8,
                        },
                        .{
                            .texture = .ProjectSymbols,
                            .path = "images/project-symbols.png",
                            .priority = 8,
                        },
                        .{
                            .texture = .StickerMainHome,
                            .path = "images/sticker-main.png",
                            .priority = 5,
                        },
                        .{
                            .texture = .SymbolEye,
                            .path = "images/symbol-eye.png",
                            .priority = 5,
                        },
                        .{
                            .texture = .YorstoryCompany,
                            .path = "images/a-yorstory-company.png",
                            .priority = 5,
                        },
                    });
                } else {
                    try texturesToLoad.appendSlice(&[_]TextureLoadInfo {
                        .{
                            .texture = .MobileBackground,
                            .path = "images/mobile/background.png",
                            .priority = 5,
                        },
                        .{
                            .texture = .MobileCrosshair,
                            .path = "images/mobile/crosshair.png",
                            .priority = 5,
                        },
                        .{
                            .texture = .MobileIcons,
                            .path = "images/mobile/icons.png",
                            .priority = 5,
                        },
                        .{
                            .texture = .MobileLogo,
                            .path = "images/mobile/logo-and-stuff.png",
                            .priority = 5,
                        },
                        .{
                            .texture = .MobileYorstoryCompany,
                            .path = "images/mobile/a-yorstory-company.png",
                            .priority = 5,
                        },
                    });
                }
            },
            .Entry => {},
            .Unknown => {},
        }

        const helveticaBoldUrl = "/fonts/HelveticaNeueLTCom-Bd.ttf";
        const helveticaMediumUrl = "/fonts/HelveticaNeueLTCom-Md.ttf";
        const helveticaLightUrl = "/fonts/HelveticaNeueLTCom-Lt.ttf";

        const titleFontSize = if (isVertical) fromRefFontSizePx(180, screenSizeF) else gridSize * 4.0;
        const titleKerning = if (isVertical) -gridSize * 0.12 else -gridSize * 0.15;
        const titleLineHeight = titleFontSize * 0.92;
        try fontsToLoad.append(.{
            .font = .Title,
            .path = helveticaBoldUrl,
            .atlasSize = 2048,
            .size = titleFontSize,
            .scale = 1.0,
            .kerning = titleKerning,
            .lineHeight = titleLineHeight
        });

        const textFontSize = if (isVertical) fromRefFontSizePx(38, screenSizeF) else gridSize * 0.4;
        const textKerning = 0;
        const textLineHeight = if (isVertical) fromRefFontSizePx(48, screenSizeF) else textFontSize * 1.2;
        try fontsToLoad.append(.{
            .font = .Text,
            .path = helveticaMediumUrl,
            .atlasSize = 2048,
            .size = textFontSize,
            .scale = 1.0,
            .kerning = textKerning,
            .lineHeight = textLineHeight,
        });

        if (!isVertical) {
            const categoryFontSize = gridSize * 0.6;
            const categoryKerning = 0;
            const categoryLineHeight = categoryFontSize;
            try fontsToLoad.append(.{
                .font = .Category,
                .path = helveticaBoldUrl,
                .atlasSize = 2048,
                .size = categoryFontSize,
                .scale = 1.0,
                .kerning = categoryKerning,
                .lineHeight = categoryLineHeight,
            });

            const subtitleFontSize = gridSize * 1.25;
            const subtitleKerning = -gridSize * 0.05;
            const subtitleLineHeight = subtitleFontSize;
            try fontsToLoad.append(.{
                .font = .Subtitle,
                .path = helveticaLightUrl,
                .atlasSize = 2048,
                .size = subtitleFontSize,
                .scale = 1.0,
                .kerning = subtitleKerning,
                .lineHeight = subtitleLineHeight,
            });

            const numberFontSize = gridSize * 1.8;
            const numberKerning = 0;
            const numberLineHeight = numberFontSize;
            try fontsToLoad.append(.{
                .font = .Number,
                .path = helveticaBoldUrl,
                .atlasSize = 2048,
                .size = numberFontSize,
                .scale = 1.0,
                .kerning = numberKerning,
                .lineHeight = numberLineHeight,
            });
        } else {
            const subtitleFontSize = fromRefFontSizePx(18, screenSizeF);
            const subtitleKerning = 0.0;
            const subtitleLineHeight = fromRefFontSizePx(26, screenSizeF);
            try fontsToLoad.append(.{
                .font = .Subtitle,
                .path = helveticaMediumUrl,
                .atlasSize = 2048,
                .size = subtitleFontSize,
                .scale = 1.0,
                .kerning = subtitleKerning,
                .lineHeight = subtitleLineHeight,
            });
        }

        for (fontsToLoad.items) |ftl| {
            if (self.assets.getFontLoadState(ftl.font) == .free) {
                try self.assets.loadFont(ftl.font, &.{
                    .path = ftl.path,
                    .atlasSize = ftl.atlasSize,
                    .size = ftl.size,
                    .scale = ftl.scale,
                    .kerning = ftl.kerning,
                    .lineHeight = ftl.lineHeight,
                });
            }
        }
        for (texturesToLoad.items) |t| {
            if (self.assets.getTextureLoadState(.{.static = t.texture}) == .free) {
                try self.assets.loadTexturePriority(.{.static = t.texture}, &.{
                    .path = t.path,
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                }, t.priority);
            }
        }
    }
};

const GridImage = struct {
    uri: []const u8,
    title: ?[]const u8,
    goToUri: ?[]const u8,
};

fn drawImageGrid(images: []const GridImage, indexOffset: usize, itemsPerRow: usize, topLeft: m.Vec2, width: f32, spacing: f32, texPriority: u32, fontData: *const app.asset_data.FontData, fontColor: m.Vec4, state: *App, scrollY: f32, mouseHoverGlobal: *bool, renderQueue: *app.render.RenderQueue, callback: *const fn(*App, GridImage, usize) void) f32
{
    const itemAspect = 1.74;
    const itemWidth = (width - spacing * (@intToFloat(f32, itemsPerRow) - 1)) / @intToFloat(f32, itemsPerRow);
    const itemSize = m.Vec2.init(itemWidth, itemWidth / itemAspect);

    var yMax: f32 = topLeft.y;
    for (images) |img, i| {
        const rowF = @intToFloat(f32, i / itemsPerRow);
        const colF = @intToFloat(f32, i % itemsPerRow);
        const spacingY = if (img.title) |_| spacing * 8 else spacing;
        const itemPos = m.Vec2.init(
            topLeft.x + colF * (itemSize.x + spacing),
            topLeft.y + rowF * (itemSize.y + spacingY)
        );
        if (state.assets.getTextureData(.{.dynamic = img.uri})) |tex| {
            const cornerRadius = 0;
            renderQueue.texQuadColor(
                itemPos, itemSize, DEPTH_GRIDIMAGE, cornerRadius, tex, m.Vec4.white
            );
        } else {
            if (state.assets.getTextureLoadState(.{.dynamic = img.uri}) == .free) {
                state.assets.loadTexturePriority(.{.dynamic = img.uri}, &.{
                    .path = img.uri,
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                }, texPriority) catch |err| {
                    std.log.err("Failed to register {s}, err {}", .{img.uri, err});
                };
            }
        }

        if (img.title) |title| {
            const textPos = m.Vec2.init(
                itemPos.x,
                itemPos.y + itemSize.y + spacing * 4
            );
            renderQueue.text(title, textPos, DEPTH_UI_GENERIC, fontData, fontColor);

            yMax = std.math.max(yMax, textPos.y);
        }

        if (updateButton(itemPos, itemSize, state.inputState.mouseState, scrollY, mouseHoverGlobal)) {
            callback(state, img, indexOffset + i);
        }

        yMax = std.math.max(yMax, itemPos.y + itemSize.y);
    }

    return yMax - topLeft.y;
}

fn getTextureScaledSize(size: m.Vec2usize, screenSize: m.Vec2) m.Vec2
{
    const sizeF = m.Vec2.initFromVec2usize(size);
    const scaleFactor = screenSize.y / refSizeDesktop.y;
    return m.multScalar(sizeF, scaleFactor);
}

fn getImageCount(pf: portfolio.Portfolio, entryData: anytype) usize
{
    const project = pf.projects[entryData.portfolioIndex];
    var i: usize = 0;
    for (project.sections) |section| {
        for (section.images) |_| {
            i += 1;
        }
    }
    return i;
}

fn getImageUrlFromIndex(pf: portfolio.Portfolio, entryData: anytype, index: usize) ?[]const u8
{
    const project = pf.projects[entryData.portfolioIndex];
    var i: usize = 0;
    for (project.sections) |section| {
        for (section.images) |img| {
            if (i == index) {
                return img;
            }
            i += 1;
        }
    }
    return null;
}

fn drawCrosshairCorners(pos: m.Vec2, size: m.Vec2, depth: f32, gridSize: f32, decalTopLeft: *const app.asset_data.TextureData, screenSize: m.Vec2, color: m.Vec4, renderQueue: *app.render.RenderQueue) void
{
    const decalMargin = gridSize * 2;
    const decalSize = getTextureScaledSize(decalTopLeft.size, screenSize);

    const posTL = m.Vec2.init(
        pos.x + decalMargin,
        pos.y + decalMargin,
    );
    const uvOriginTL = m.Vec2.init(0, 0);
    const uvSizeTL = m.Vec2.init(1, 1);
    renderQueue.texQuadColorUvOffset(
        posTL, decalSize, depth, 0, uvOriginTL, uvSizeTL, decalTopLeft, color
    );

    const posTR = m.Vec2.init(
        pos.x + size.x - decalMargin - decalSize.x,
        pos.y + decalMargin,
    );
    const uvOriginTR = m.Vec2.init(1, 0);
    const uvSizeTR = m.Vec2.init(-1, 1);
    renderQueue.texQuadColorUvOffset(
        posTR, decalSize, depth, 0, uvOriginTR, uvSizeTR, decalTopLeft, color
    );

    const posBL = m.Vec2.init(
        pos.x + decalMargin,
        pos.y + size.y - decalMargin - decalSize.y,
    );
    const uvOriginBL = m.Vec2.init(0, 1);
    const uvSizeBL = m.Vec2.init(1, -1);
    renderQueue.texQuadColorUvOffset(
        posBL, decalSize, depth, 0, uvOriginBL, uvSizeBL, decalTopLeft, color
    );

    const posBR = m.Vec2.init(
        pos.x + size.x - decalMargin - decalSize.x,
        pos.y + size.y - decalMargin - decalSize.y,
    );
    const uvOriginBR = m.Vec2.init(1, 1);
    const uvSizeBR = m.Vec2.init(-1, -1);
    renderQueue.texQuadColorUvOffset(
        posBR, decalSize, depth, 0, uvOriginBR, uvSizeBR, decalTopLeft, color
    );
}

fn drawDesktop(state: *App, deltaMs: u64, scrollYF: f32, screenSizeF: m.Vec2, renderQueue: *app.render.RenderQueue, allocator: std.mem.Allocator) i32
{
    const colorUi = blk: {
        switch (state.pageData) {
            .Home => {
                break :blk COLOR_YELLOW_HOME;
            },
            .Entry => |entryData| {
                if (state.portfolio) |pf| {
                    break :blk pf.projects[entryData.portfolioIndex].colorUi;
                } else {
                    break :blk m.Vec4.white;
                }
            },
            .Unknown => {
                break :blk m.Vec4.white;
            },
        }
    };
    const colorRedSticker = m.Vec4.init(234.0 / 255.0, 65.0 / 255.0, 0.0, 1.0);
    const parallaxMotionMax = screenSizeF.x / 8.0;

    const mousePosF = m.Vec2.initFromVec2i(state.inputState.mouseState.pos);
    var mouseHoverGlobal = false;

    const gridSize = getGridSize(screenSizeF);

    const marginX = blk: {
        const maxLandingImageAspect = 2.15;
        const landingImageSize = m.Vec2.init(
            screenSizeF.x - gridSize * 2.0,
            screenSizeF.y - gridSize * 3.0
        );
        const adjustedWidth = std.math.min(landingImageSize.x, landingImageSize.y * maxLandingImageAspect);
        break :blk (landingImageSize.x - adjustedWidth) / 2.0;
    };
    const crosshairMarginX = marginX + gridSize * 5;
    const contentMarginX = marginX + gridSize * 9;

    const decalTopLeft = state.assets.getTextureData(.{.static = .DecalTopLeft});
    const stickerMain = blk: {
        switch (state.pageData) {
            .Home, .Unknown => break :blk state.assets.getTextureData(.{.static = .StickerMainHome}),
            .Entry => |entryData| {
                if (state.portfolio) |pf| {
                    const project = pf.projects[entryData.portfolioIndex];
                    if (state.assets.getTextureData(.{.dynamic = project.sticker})) |tex| {
                        break :blk tex;
                    } else {
                        if (state.assets.getTextureLoadState(.{.dynamic = project.sticker}) == .free) {
                            state.assets.loadTexturePriority(.{.dynamic = project.sticker}, &.{
                                .path = project.sticker,
                                .filter = defaultTextureFilter,
                                .wrapMode = defaultTextureWrap,
                            }, 9) catch |err| {
                                std.log.err("Failed to register {s}, err {}", .{project.sticker, err});
                            };
                        }
                        break :blk null;
                    }
                } else {
                    break :blk null;
                }
            },
        }
    };
    const stickerShiny = state.assets.getTextureData(.{.static = .StickerShiny});

    const allFontsLoaded = blk: {
        var loaded = true;
        inline for (std.meta.tags(asset.Font)) |f| {
            const fontData = state.assets.getFontData(f);
            loaded = loaded and fontData != null;
        }
        break :blk loaded;
    };
    var allLandingAssetsLoaded = decalTopLeft != null and stickerMain != null and stickerShiny != null and allFontsLoaded;
    if (allLandingAssetsLoaded) {
        const parallaxIndex = blk: {
            switch (state.pageData) {
                .Home, .Unknown => break :blk state.activeParallaxSetIndex,
                .Entry => |entryData| {
                    const project = state.portfolio.?.projects[entryData.portfolioIndex];
                    break :blk project.parallaxIndex;
                },
            }
        };

        // Determine whether the active parallax set is loaded
        var activeParallaxSet = parallax.tryLoadAndGetParallaxSet(&state.assets, parallaxIndex, 5, defaultTextureWrap, defaultTextureFilter);

        // Load later sets
        if (state.pageData == .Home and activeParallaxSet != null) {
            state.parallaxIdleTimeMs += deltaMs;
            const nextSetIndex = (parallaxIndex + 1) % parallax.PARALLAX_SETS.len;
            var nextParallaxSet = parallax.tryLoadAndGetParallaxSet(&state.assets, nextSetIndex, 20, defaultTextureWrap, defaultTextureFilter);
            if (nextParallaxSet) |_| {
                if (state.parallaxIdleTimeMs >= App.PARALLAX_SET_SWAP_SECONDS * 1000) {
                    state.parallaxIdleTimeMs = 0;
                    state.activeParallaxSetIndex = nextSetIndex;
                    activeParallaxSet = nextParallaxSet;
                } else {
                    for (parallax.PARALLAX_SETS) |_, i| {
                        if (parallax.tryLoadAndGetParallaxSet(&state.assets, i, 20, defaultTextureWrap, defaultTextureFilter) == null) {
                            break;
                        }
                    }
                }
            }
        }

        const targetParallaxTX = mousePosF.x / screenSizeF.x * 2.0 - 1.0; // -1 to 1
        state.parallaxTX = targetParallaxTX;

        if (activeParallaxSet) |parallaxSet| {
            const landingImagePos = m.Vec2.init(
                marginX + gridSize * 1,
                gridSize * 1
            );
            const landingImageSize = m.Vec2.init(
                screenSizeF.x - marginX * 2 - gridSize * 2,
                screenSizeF.y - gridSize * 3
            );

            switch (parallaxSet.bgColor) {
                .Color => |color| {
                    renderQueue.quad(landingImagePos, landingImageSize, DEPTH_LANDINGBACKGROUND, 0, color);
                },
                .Gradient => |gradient| {
                    renderQueue.quadGradient(
                        landingImagePos, landingImageSize, DEPTH_LANDINGBACKGROUND, 0,
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
                const textureData = state.assets.getTextureData(.{.dynamic = parallaxImage.url}) orelse unreachable;

                const textureDataF = m.Vec2.initFromVec2usize(textureData.size);
                const textureSize = m.Vec2.init(
                    landingImageSize.y * textureDataF.x / textureDataF.y,
                    landingImageSize.y
                );
                const parallaxOffsetX = state.parallaxTX * parallaxMotionMax * parallaxImage.factor;

                const imgPos = m.Vec2.init(
                    screenSizeF.x / 2.0 - textureSize.x / 2.0 + parallaxOffsetX,
                    landingImagePos.y
                );
                renderQueue.texQuad(imgPos, textureSize, DEPTH_LANDINGIMAGE, 0.0, textureData);
            }
        } else {
            allLandingAssetsLoaded = false;
        }
    }

    if (decalTopLeft) |dtl| {
        const crosshairRectPos = m.Vec2.init(marginX, 0);
        const crosshairRectSize = m.Vec2.init(screenSizeF.x - marginX * 2, screenSizeF.y);

        drawCrosshairCorners(
            crosshairRectPos, crosshairRectSize, DEPTH_UI_GENERIC,
            gridSize, dtl, screenSizeF, colorUi, renderQueue
        );
    }

    const stickerCircle = state.assets.getTextureData(.{.static = .StickerCircle});
    const loadingGlyphs = state.assets.getTextureData(.{.static = .LoadingGlyphs});

    if (allLandingAssetsLoaded) {
        const fontCategory = state.assets.getFontData(.Category) orelse unreachable;
        const sMain = stickerMain orelse unreachable;
        const sShiny = stickerShiny orelse unreachable;

        const CategoryInfo = struct {
            name: []const u8,
            uri: ?[]const u8,
        };
        const categories = [_]CategoryInfo {
            .{
                .name = "home",
                .uri = "/",
            },
            .{
                .name = "yorstory",
                .uri = null,
            },
            .{
                .name = "portfolio",
                .uri = null,
            },
            .{
                .name = "contact",
                .uri = null,
            },
        };
        var x = contentMarginX;
        for (categories) |c| {
            const categoryRect = app.render.textRect(c.name, fontCategory, null);
            const categorySize = categoryRect.size();
            const categoryPos = m.Vec2.init(x, gridSize * 5.5);
            renderQueue.text(c.name, categoryPos, DEPTH_UI_GENERIC, fontCategory, colorUi);

            const categoryButtonSize = m.Vec2.init(categorySize.x * 1.2, categorySize.y * 2.0);
            const categoryButtonPos = m.Vec2.init(categoryPos.x - categorySize.x * 0.1, categoryPos.y - categorySize.y);
            if (c.uri) |uri| {
                if (updateButton(categoryButtonPos, categoryButtonSize, state.inputState.mouseState, scrollYF, &mouseHoverGlobal)) {
                    state.changePage(uri);
                }
            }

            x += categorySize.x + gridSize * 1.4;
        }

        // sticker (main)
        const stickerSize = getTextureScaledSize(sMain.size, screenSizeF);
        const stickerPos = m.Vec2.init(
            contentMarginX,
            screenSizeF.y - gridSize * 5 - stickerSize.y
        );
        const colorSticker = blk: {
            switch (state.pageData) {
                .Home, .Unknown => break :blk colorUi,
                .Entry => |entryData| {
                    const project = state.portfolio.?.projects[entryData.portfolioIndex];
                    break :blk project.colorSticker;
                },
            }
        };
        renderQueue.texQuadColor(
            stickerPos, stickerSize, DEPTH_UI_GENERIC, 0, sMain, colorSticker
        );

        // sticker (shiny)
        const stickerShinySize = getTextureScaledSize(sShiny.size, screenSizeF);
        const stickerShinyPos = m.Vec2.init(
            screenSizeF.x - crosshairMarginX - stickerShinySize.x,
            gridSize * 5.0
        );
        renderQueue.texQuadColor(
            stickerShinyPos, stickerShinySize, DEPTH_UI_GENERIC, 0, sShiny, m.Vec4.white
        );
    } else {
        // show loading indicator, if that is loaded
        if (stickerCircle != null and loadingGlyphs != null) {
            const circleSize = getTextureScaledSize(stickerCircle.?.size, screenSizeF);
            const circlePos = m.Vec2.init(
                screenSizeF.x / 2.0 - circleSize.x / 2.0,
                screenSizeF.y / 2.0 - circleSize.y / 2.0 - gridSize * 1,
            );
            renderQueue.texQuadColor(circlePos, circleSize, DEPTH_UI_GENERIC, 0, stickerCircle.?, colorUi);

            const glyphsSize = getTextureScaledSize(loadingGlyphs.?.size, screenSizeF);
            const glyphsPos = m.Vec2.init(
                screenSizeF.x / 2.0 - glyphsSize.x / 2.0,
                screenSizeF.y / 2.0 - glyphsSize.y / 2.0 + gridSize * 1,
            );
            renderQueue.texQuadColor(glyphsPos, glyphsSize, DEPTH_UI_GENERIC, 0, loadingGlyphs.?, colorUi);

            var i: i32 = 0;
            while (i < 3) : (i += 1) {
                const spacing = gridSize * 0.28;
                const dotSize = m.Vec2.init(gridSize * 0.16, gridSize * 0.16);
                const dotOrigin = m.Vec2.init(
                    screenSizeF.x / 2.0 - dotSize.x / 2.0 - spacing * @intToFloat(f32, i - 1),
                    screenSizeF.y / 2.0 - dotSize.y / 2.0 - gridSize * 1,
                );
                renderQueue.quad(dotOrigin, dotSize, DEPTH_UI_GENERIC - 0.01, 0, m.Vec4.black);
            }
        }
    }

    {
        // rounded black frame
        const framePos = m.Vec2.init(marginX + gridSize * 1, gridSize * 1);
        const frameSize = m.Vec2.init(
            screenSizeF.x - marginX * 2 - gridSize * 2,
            screenSizeF.y - gridSize * 3,
        );
        renderQueue.roundedFrame(.{
            .bottomLeft = m.Vec2.zero,
            .size = screenSizeF,
            .depth = DEPTH_UI_OVER1,
            .frameBottomLeft = framePos,
            .frameSize = frameSize,
            .cornerRadius = gridSize,
            .color = m.Vec4.black
        });
    }

    const section1Height = screenSizeF.y;

    if (!allLandingAssetsLoaded) {
        return @floatToInt(i32, section1Height);
    }

    // ==== SECOND FRAME ====

    const fontTitle = state.assets.getFontData(.Title) orelse return @floatToInt(i32, section1Height);
    const fontSubtitle = state.assets.getFontData(.Subtitle) orelse return @floatToInt(i32, section1Height);
    const fontText = state.assets.getFontData(.Text) orelse return @floatToInt(i32, section1Height);
    const sCircle = stickerCircle orelse return @floatToInt(i32, section1Height);

    var section2Height: f32 = 0;
    if (state.pageData == .Home) {
        section2Height = screenSizeF.y * 3.0;
        const secondFrameYScrolling = section1Height;
        const secondFrameYStill = blk: {
            if (scrollYF >= section1Height) {
                if (scrollYF <= section1Height + section2Height - screenSizeF.y) {
                    break :blk scrollYF;
                } else {
                    break :blk section1Height + section2Height - screenSizeF.y;
                }
            } else {
                break :blk section1Height;
            }
        };

        // draw moving gradient
        const gradientColor = m.Vec4.init(86.0 / 255.0, 0.0, 214.0 / 255.0, 1.0);
        const gradientPos = m.Vec2.init(0.0, secondFrameYScrolling);
        const gradientSize = m.Vec2.init(screenSizeF.x, section2Height);
        renderQueue.quadGradient(
            gradientPos, gradientSize, DEPTH_LANDINGBACKGROUND, 0.0,
            [4]m.Vec4 {m.Vec4.black, m.Vec4.black, gradientColor, gradientColor}
        );

        if (decalTopLeft) |dtl| {
            const crosshairRectPos = m.Vec2.init(marginX, secondFrameYStill);
            const crosshairRectSize = m.Vec2.init(screenSizeF.x - marginX * 2, screenSizeF.y);

            drawCrosshairCorners(
                crosshairRectPos, crosshairRectSize, DEPTH_UI_GENERIC,
                gridSize, dtl, screenSizeF, colorUi, renderQueue
            );
        }

        const yorstoryCompany = state.assets.getTextureData(.{.static = .YorstoryCompany});
        if (yorstoryCompany) |yc| {
            const pos = m.Vec2.init(contentMarginX, secondFrameYStill + gridSize * 3.0);
            const size = getTextureScaledSize(yc.size, screenSizeF);
            renderQueue.texQuadColor(pos, size, DEPTH_UI_GENERIC, 0, yc, colorUi);
        }

        const logosAll = state.assets.getTextureData(.{.static = .LogosAll});
        const symbolEye = state.assets.getTextureData(.{.static = .SymbolEye});

        const wasPosYCheckpoint1 = section1Height;
        const wasPosYCheckpoint2 = section1Height + screenSizeF.y * 1.0;
        const wasPosBaseY = blk: {
            if (scrollYF <= wasPosYCheckpoint1) {
                break :blk wasPosYCheckpoint1;
            } else if (scrollYF >= wasPosYCheckpoint2) {
                break :blk wasPosYCheckpoint2;
            } else {
                break :blk scrollYF;
            }
        };
        const wasPos = m.Vec2.init(
            contentMarginX - gridSize * 0.3,
            wasPosBaseY + gridSize * 10.8
        );
        const wasText = "We are\nStorytellers.";
        const wasRect = app.render.textRect(wasText, fontTitle, null);
        renderQueue.text(wasText, wasPos, DEPTH_UI_GENERIC, fontTitle, colorUi);

        const wasTextPos1 = m.Vec2.init(
            contentMarginX - gridSize * 0.3,
            wasPos.y - wasRect.min.y + gridSize * 3.2,
        );
        const wasTextWidth = screenSizeF.x / 2.0 - wasTextPos1.x - gridSize;
        renderQueue.textWithMaxWidth("Yorstory is a creative development studio specializing in sequential art. We are storytellers with over 20 years of experience in the Television, Film, and Video Game industries.", wasTextPos1, DEPTH_UI_GENERIC, wasTextWidth, fontText, colorUi);
        const wasTextPos2 = m.Vec2.init(
            screenSizeF.x / 2.0,
            wasTextPos1.y,
        );
        renderQueue.textWithMaxWidth("Our diverse experience has given us an unparalleled understanding of multiple mediums, giving us the tools to create a cohesive, story-centric vision along with the visuals needed to create a shared understanding between multiple departments and disciplines.", wasTextPos2, DEPTH_UI_GENERIC, wasTextWidth, fontText, colorUi);

        if (symbolEye) |se| {
            const eyeSize = getTextureScaledSize(sCircle.size, screenSizeF);
            const eyePosY = blk: {
                const eyeCheckpoint1 = section1Height + screenSizeF.y * 0.1;
                const eyeCheckpoint2 = section1Height + screenSizeF.y * 0.5;
                const eyeOffset = gridSize * 6.95;

                if (scrollYF <= eyeCheckpoint1) {
                    break :blk scrollYF - eyeSize.y;
                } else if (scrollYF <= eyeCheckpoint2) {
                    const t = (scrollYF - eyeCheckpoint1) / (eyeCheckpoint2 - eyeCheckpoint1);
                    break :blk scrollYF + m.lerpFloat(-eyeSize.y, eyeOffset, t);
                } else {
                    break :blk wasPosBaseY + eyeOffset;
                }
            };
            const eyePos = m.Vec2.init(
                wasPos.x + gridSize * 10.7,
                eyePosY,
            );
            const eyeStickerColor = m.Vec4.init(0.0, 46.0 / 255.0, 226.0 / 255.0, 1.0);
            // TODO change plus to minus once depth/blend shit is fixed
            const eyeDepth = DEPTH_UI_GENERIC + 0.02;
            const eyeSymbolDepth = DEPTH_UI_GENERIC + 0.01;
            renderQueue.texQuadColor(eyePos, eyeSize, eyeDepth, 0, sCircle, eyeStickerColor);
            renderQueue.texQuadColor(eyePos, eyeSize, eyeSymbolDepth, 0, se, colorUi);
        }

        if (logosAll) |la| {
            const logosPosYCheckpoint1 = section1Height + section2Height - screenSizeF.y;
            const logosPosYCheckpoint2 = section1Height + section2Height - screenSizeF.y;
            const logosPosBaseY = blk: {
                if (scrollYF <= logosPosYCheckpoint1) {
                    break :blk logosPosYCheckpoint1;
                } else if (scrollYF >= logosPosYCheckpoint2) {
                    break :blk logosPosYCheckpoint2;
                } else {
                    break :blk scrollYF;
                }
            };
            const logosSize = getTextureScaledSize(la.size, screenSizeF);
            const logosPos = m.Vec2.init(
                (screenSizeF.x - logosSize.x) / 2,
                logosPosBaseY + ((screenSizeF.y - logosSize.y) / 2)
            );
            renderQueue.texQuadColor(logosPos, logosSize, DEPTH_UI_GENERIC, 0, la, colorUi);
        }

        {
            // rounded black frame
            const framePos = m.Vec2.init(marginX + gridSize * 1, secondFrameYStill + gridSize * 1);
            const frameSize = m.Vec2.init(
                screenSizeF.x - marginX * 2 - gridSize * 2,
                screenSizeF.y - gridSize * 3,
            );
            renderQueue.roundedFrame(.{
                .bottomLeft = m.Vec2.init(0.0, secondFrameYStill),
                .size = screenSizeF,
                .depth = DEPTH_UI_OVER1,
                .frameBottomLeft = framePos,
                .frameSize = frameSize,
                .cornerRadius = gridSize,
                .color = m.Vec4.black
            });
        }
    }

    // ==== THIRD FRAME ====

    var yMax = section1Height + section2Height;
    const fontNumber = state.assets.getFontData(.Number) orelse return @floatToInt(i32, yMax);
    const pf = state.portfolio orelse return @floatToInt(i32, yMax);

    const CB = struct {
        fn home(theState: *App, image: GridImage, index: usize) void
        {
            _ = index;

            if (image.goToUri) |uri| {
                theState.changePage(uri);
            }
        }

        fn entry(theState: *App, image: GridImage, index: usize) void
        {
            _ = image;

            if (theState.pageData != .Entry) {
                std.log.err("entry callback, but not an Entry page", .{});
                return;
            }
            if (theState.pageData.Entry.galleryImageIndex == null) {
                theState.pageData.Entry.galleryImageIndex = index;
            }
        }
    };

    const contentSubWidth = screenSizeF.x - contentMarginX * 2;
    switch (state.pageData) {
        .Home, .Unknown => {},
        .Entry => |entryData| {
            // content section
            const project = pf.projects[entryData.portfolioIndex];

            const contentHeaderPos = m.Vec2.init(
                contentMarginX,
                yMax + gridSize * 4.0,
            );
            const contentHeaderRect = app.render.textRect(project.contentHeader, fontTitle, null);
            renderQueue.text(project.contentHeader, contentHeaderPos, DEPTH_UI_GENERIC, fontTitle, colorUi);

            const contentSubPos = m.Vec2.init(
                contentMarginX,
                contentHeaderPos.y - contentHeaderRect.min.y + gridSize * 3.2,
            );
            const contentSubPosWidth = screenSizeF.x - contentMarginX * 2;
            const contentSubRect = app.render.textRect(project.contentDescription, fontText, contentSubPosWidth);
            renderQueue.textWithMaxWidth(project.contentDescription, contentSubPos, DEPTH_UI_GENERIC, contentSubPosWidth, fontText, colorUi);

            yMax = contentSubPos.y + contentSubRect.size().y + gridSize * 3.0;

            var galleryImages = std.ArrayList(GridImage).init(allocator);

            var yGallery = yMax;
            var indexOffset: usize = 0; // TODO eh...
            for (project.sections) |section, i| {
                if (section.name.len > 0 or section.description.len > 0) {
                    const numberSize = getTextureScaledSize(sCircle.size, screenSizeF);
                    const numberPos = m.Vec2.init(
                        contentMarginX - gridSize * 1.4,
                        yGallery - gridSize * 2.4,
                    );
                    // TODO number should be on top, but depth sorting is bad
                    renderQueue.texQuadColor(
                        numberPos, numberSize, DEPTH_UI_GENERIC + 0.02, 0, sCircle, colorRedSticker
                    );
                    const numStr = std.fmt.allocPrint(allocator, "{}", .{i + 1}) catch unreachable;
                    const numberTextPos = m.Vec2.init(
                        numberPos.x + numberSize.x * 0.28,
                        numberPos.y + numberSize.y * 0.75
                    );
                    renderQueue.text(numStr, numberTextPos, DEPTH_UI_GENERIC + 0.01, fontNumber, m.Vec4.black);

                    const subNameRect = app.render.textRect(section.name, fontSubtitle, null);
                    renderQueue.text(section.name, m.Vec2.init(contentMarginX, yGallery), DEPTH_UI_GENERIC, fontSubtitle, colorUi);
                    yGallery += -subNameRect.min.y + gridSize * 2.0;

                    const subDescriptionWidth = screenSizeF.x - contentMarginX * 2;
                    const subDescriptionRect = app.render.textRect(section.description, fontText, subDescriptionWidth);
                    renderQueue.textWithMaxWidth(
                        section.description,
                        m.Vec2.init(contentMarginX, yGallery),
                        DEPTH_UI_GENERIC,
                        subDescriptionWidth,
                        fontText,
                        colorUi
                    );
                    yGallery += -subDescriptionRect.min.y + gridSize * 2.0;
                }

                galleryImages.clearRetainingCapacity();
                for (section.images) |img| {
                    galleryImages.append(GridImage {
                        .uri = img,
                        .title = null,
                        .goToUri = null,
                    }) catch |err| {
                        std.log.err("image append failed {}", .{err});
                    };
                }

                const itemsPerRow = 6;
                const topLeft = m.Vec2.init(contentMarginX, yGallery);
                const spacing = gridSize * 0.25;
                yGallery += drawImageGrid(galleryImages.items, indexOffset, itemsPerRow, topLeft, contentSubWidth, spacing, 9, fontText, colorUi, state, scrollYF, &mouseHoverGlobal, renderQueue, CB.entry);
                yGallery += gridSize * 4.0;
                indexOffset += section.images.len;
            }

            yMax = yGallery + gridSize * 1;

            // TODO
            // video embed
            // if (pf.youtubeId) |youtubeId| {
            //     const embedWidth = screenSizeF.x - contentMarginX * 2;
            //     const embedSize = m.Vec2.init(embedWidth, embedWidth / 2.0);
            //     const embedPos = m.Vec2.init(contentMarginX, yMax);
            //     renderQueue.embedYoutube(embedPos, embedSize, youtubeId);
            //     yMax += embedSize.y + gridSize * 4;
            // }

            yMax += gridSize * 1;

            if (entryData.galleryImageIndex) |ind| {
                const pos = m.Vec2.init(0.0, scrollYF);
                renderQueue.quad(pos, screenSizeF, DEPTH_UI_OVER2, 0, m.Vec4.init(0.0, 0.0, 0.0, 1.0));

                if (getImageUrlFromIndex(pf, entryData, ind)) |imageUrl| {
                    if (state.assets.getTextureData(.{.dynamic = imageUrl})) |imageTex| {
                        const imageRefSizeF = m.Vec2.initFromVec2usize(imageTex.size);
                        const targetHeight = screenSizeF.y - gridSize * 4.0;
                        const imageSize = m.Vec2.init(
                            targetHeight / imageRefSizeF.y * imageRefSizeF.x,
                            targetHeight
                        );
                        const imagePos = m.Vec2.init(
                            (screenSizeF.x - imageSize.x) / 2.0,
                            scrollYF + gridSize * 2.0
                        );
                        // const imagePos = m.Vec2.add(pos, m.Vec2.init(gridSize, gridSize));
                        renderQueue.texQuad(imagePos, imageSize, DEPTH_UI_OVER2 - 0.01, 0, imageTex);

                        const clickEvents = state.inputState.mouseState.clickEvents[0..state.inputState.mouseState.numClickEvents];
                        for (clickEvents) |e| {
                            if (e.clickType == .Left and e.down) {
                                const posF = m.Vec2.initFromVec2i(e.pos);
                                if (posF.x < (screenSizeF.x - imageSize.x) / 2.0
                                    or posF.x > (screenSizeF.x + imageSize.x) / 2.0
                                    or posF.y < (gridSize * 2.0)
                                    or posF.y > (screenSizeF.y - gridSize * 2.0)) {
                                    state.pageData.Entry.galleryImageIndex = null;
                                }
                            }
                        }
                    }
                }
            }
        },
    }

    const section3Start = yMax;
    const section3YScrolling = section3Start;

    if (state.assets.getTextureData(.{.static = .YorstoryCompany})) |yorstoryCompany| {
        const pos = m.Vec2.init(contentMarginX, section3YScrolling + gridSize * 3.0);
        const size = getTextureScaledSize(yorstoryCompany.size, screenSizeF);
        renderQueue.texQuadColor(pos, size, DEPTH_UI_GENERIC, 0, yorstoryCompany, colorUi);
    }

    const contentHeaderPos = m.Vec2.init(
        contentMarginX,
        section3Start + gridSize * (11.5 - 0.33),
    );
    const projectsText = if (state.pageData == .Home) "Projects" else "Other Projects";
    renderQueue.text(projectsText, contentHeaderPos, DEPTH_UI_GENERIC, fontTitle, colorUi);

    var images = std.ArrayList(GridImage).init(allocator);
    for (pf.projects) |project, i| {
        if (state.pageData == .Entry and state.pageData.Entry.portfolioIndex == i) {
            continue;
        }

        const imageTitle = std.fmt.allocPrint(
            allocator, "{s}        {s}", .{project.name, project.company}
        ) catch continue;
        images.append(GridImage {
            .uri = project.cover,
            .title = imageTitle,
            .goToUri = project.uri,
        }) catch |err| {
            std.log.err("image append failed {}", .{err});
        };
    }

    if (state.assets.getTextureData(.{.static = .ProjectSymbols})) |projectSymbols| {
        const symbolsPos = m.Vec2.init(marginX + gridSize * 3.33, section3YScrolling + gridSize * 7.5);
        const symbolsSize = getTextureScaledSize(projectSymbols.size, screenSizeF);
        renderQueue.texQuadColor(symbolsPos, symbolsSize, DEPTH_UI_GENERIC, 0, projectSymbols, colorUi);
    }

    const itemsPerRow = 3;
    const gridTopLeft = m.Vec2.init(
        contentMarginX,
        section3Start + gridSize * 14.0,
    );
    const spacing = gridSize * 0.25;
    const projectGridY = drawImageGrid(images.items, 0, itemsPerRow, gridTopLeft, contentSubWidth, spacing, 8, fontText, colorUi, state, scrollYF, &mouseHoverGlobal, renderQueue, CB.home);

    const section3Height = gridTopLeft.y - section3Start + projectGridY + gridSize * 8.0;

    // draw moving gradient
    const gradientColor = m.Vec4.init(86.0 / 255.0, 0.0, 214.0 / 255.0, 1.0);
    const gradientPos = m.Vec2.init(0.0, section3YScrolling);
    const gradientSize = m.Vec2.init(screenSizeF.x, section3Height * 1.5);
    renderQueue.quadGradient(
        gradientPos, gradientSize, DEPTH_LANDINGBACKGROUND, 0.0,
        [4]m.Vec4 {m.Vec4.black, m.Vec4.black, gradientColor, gradientColor}
    );

    if (decalTopLeft) |dtl| {
        const crosshairRectPos = m.Vec2.init(marginX, section3YScrolling);
        const crosshairRectSize = m.Vec2.init(screenSizeF.x - marginX * 2, section3Height - gridSize);

        drawCrosshairCorners(
            crosshairRectPos, crosshairRectSize, DEPTH_UI_GENERIC,
            gridSize, dtl, screenSizeF, colorUi, renderQueue
        );
    }

    {
        // rounded black frame
        const frameTotalSize = m.Vec2.init(screenSizeF.x, section3Height);
        const framePos = m.Vec2.init(marginX + gridSize * 1, section3YScrolling + gridSize * 1);
        const frameSize = m.Vec2.init(
            screenSizeF.x - marginX * 2 - gridSize * 2,
            section3Height - gridSize * 3,
        );
        renderQueue.roundedFrame(.{
            .bottomLeft = m.Vec2.init(0.0, section3YScrolling),
            .size = frameTotalSize,
            .depth = DEPTH_UI_OVER1,
            .frameBottomLeft = framePos,
            .frameSize = frameSize,
            .cornerRadius = gridSize,
            .color = m.Vec4.black
        });
    }

    yMax += section3Height;

    // TODO don't do all the time
    if (mouseHoverGlobal) {
        w.setCursorZ("pointer");
    } else {
        w.setCursorZ("auto");
    }

    if (state.debug) {
        const colorMain = m.Vec4.white;
        const colorHalf = m.Vec4.init(0.5, 0.5, 0.5, 1.0);
        var yDebug: f32 = 0;
        while (yDebug <= yMax) : (yDebug += gridSize) {
            renderQueue.quad(m.Vec2.init(0, yDebug - gridSize * 0.5), m.Vec2.init(screenSizeF.x, 1), DEPTH_UI_ABOVEALL, 0, colorHalf);
            renderQueue.quad(m.Vec2.init(0, yDebug), m.Vec2.init(screenSizeF.x, 1), DEPTH_UI_ABOVEALL, 0, colorMain);
        }
    }

    return @floatToInt(i32, yMax);
}

fn drawMobile(state: *App, deltaS: f32, scrollY: f32, screenSize: m.Vec2, renderQueue: *app.render.RenderQueue, allocator: std.mem.Allocator) i32
{
    _ = deltaS;
    _ = scrollY;
    _ = allocator;

    const aspect = screenSize.x / screenSize.y;
    const gridSize = getGridSize(screenSize);

    const quat = m.Quat.initFromEulerAngles(state.inputState.deviceState.angles);
    _ = quat;
    const anglesTarget = state.inputState.deviceState.angles;
    // TODO use something more linear
    state.anglesRef = m.lerp(state.anglesRef, anglesTarget, 0.01);

    const fontTitle = state.assets.getFontData(.Title) orelse return @floatToInt(i32, screenSize.y);
    const fontText = state.assets.getFontData(.Text) orelse return @floatToInt(i32, screenSize.y);

    // ==== FIRST FRAME: LANDING ====

    if (state.assets.getTextureData(.{.static = .MobileBackground})) |bgTex| {
        const bgTexSize = m.Vec2.initFromVec2usize(bgTex.size);
        const bgAspect = bgTexSize.x / bgTexSize.y;
        // _ = bgAspect;
        // _ = aspect;
        // const bgUvBottomLeft = m.Vec2.zero;
        // const bgUvSize = m.Vec2.one;
        // renderQueue.texQuadColorUvOffset(m.Vec2.zero, screenSize, DEPTH_LANDINGBACKGROUND, 0.0, bgUvBottomLeft, bgUvSize, bgTex, m.Vec4.white);
        const backgroundSize = if (bgAspect < aspect)
            m.Vec2.init(screenSize.x, screenSize.x / bgAspect)
            else
            m.Vec2.init(screenSize.y / bgTexSize.y * bgTexSize.x, screenSize.y);
        std.log.info("{} vs {}: {}", .{bgAspect, aspect, backgroundSize});
        const backgroundPos = m.Vec2.init(
            (screenSize.x - backgroundSize.x) / 2.0,
            (screenSize.y - backgroundSize.y) / 2.0,
        );
        renderQueue.texQuadColor(backgroundPos, backgroundSize, DEPTH_LANDINGBACKGROUND, 0.0, bgTex, m.Vec4.white);
    }

    if (state.assets.getTextureData(.{.static = .MobileYorstoryCompany})) |yorTex| {
        const yorSize = getTextureScaledSize(yorTex.size, screenSize);
        const yorPos = m.Vec2.init(
            gridSize, gridSize * 5.8
        );
        renderQueue.texQuadColor(yorPos, yorSize, DEPTH_UI_GENERIC, 0.0, yorTex, m.Vec4.white);
    }

    if (state.assets.getTextureData(.{.static = .MobileLogo})) |logoTex| {
        const logoSize = getTextureScaledSize(logoTex.size, screenSize);
        const logoPos = m.Vec2.init(
            gridSize, screenSize.y - gridSize * 3.0 - logoSize.y
        );
        renderQueue.texQuadColor(logoPos, logoSize, DEPTH_UI_GENERIC, 0.0, logoTex, m.Vec4.white);
    }

    if (state.assets.getTextureData(.{.static = .MobileCrosshair})) |crosshairTex| {
        const offsetTest = anglesTarget.z / 90.0 * 100.0;
        const crosshairOffset = gridSize * 0.25;
        const pos = m.Vec2.init(-(gridSize + crosshairOffset) + offsetTest, -(gridSize + crosshairOffset));
        const size = m.Vec2.init(screenSize.x + gridSize * 2.0 + crosshairOffset * 2.0, screenSize.y + gridSize * 2.0 + crosshairOffset * 2.0);
        drawCrosshairCorners(pos, size, DEPTH_UI_GENERIC, gridSize, crosshairTex, screenSize, m.Vec4.white, renderQueue);

        const pos2 = m.Vec2.init(-(gridSize + crosshairOffset) + offsetTest, -(gridSize + crosshairOffset) + screenSize.y);
        drawCrosshairCorners(pos2, size, DEPTH_UI_GENERIC, gridSize, crosshairTex, screenSize, m.Vec4.white, renderQueue);
    }

    if (state.assets.getTextureData(.{.static = .MobileIcons})) |iconsTex| {
        const iconsSize = getTextureScaledSize(iconsTex.size, screenSize);
        const iconsPos = m.Vec2.init(screenSize.x - iconsSize.x - gridSize * 1.0, gridSize * 4.0);
        renderQueue.texQuad(iconsPos, iconsSize, DEPTH_UI_GENERIC, 0.0, iconsTex);
    }

    var y = screenSize.y;

    // ==== SECOND FRAME: WE ARE STORYTELLERS ====

    // slightly offset from the crosshair (aligned with the circle)
    const sideMargin = gridSize * 1.0;

    var yWas = y + gridSize * 8.0;
    const wasText = "We are\nStorytellers";
    const wasPos = m.Vec2.init(sideMargin, yWas);
    const wasRect = app.render.textRect(wasText, fontTitle, null);
    renderQueue.text(wasText, wasPos, DEPTH_UI_GENERIC, fontTitle, COLOR_YELLOW_HOME);
    yWas += wasRect.size().y;

    // TODO what's happening here? why don't I need this extra spacing?
    // yWas += gridSize * 2.0;
    const text1 = "Yorstory is a creative development\nstudio specializing in sequential\nart.";
    const text1Pos = m.Vec2.init(sideMargin, yWas);
    renderQueue.text(text1, text1Pos, DEPTH_UI_GENERIC, fontText, COLOR_YELLOW_HOME);
    const text1Rect = app.render.textRect(text1, fontText, null);
    yWas += text1Rect.size().y;

    yWas += gridSize * 1.0;
    const text2 = "We are storytellers with over\ntwenty years of experience in the\nTelevision, Film, and Video Game\nindustries.";
    const text2Pos = m.Vec2.init(sideMargin, yWas);
    renderQueue.text(text2, text2Pos, DEPTH_UI_GENERIC, fontText, COLOR_YELLOW_HOME);
    const text2Rect = app.render.textRect(text2, fontText, null);
    yWas += text2Rect.size().y;

    y += screenSize.y;

    // ==== THIRD FRAME: PROJECTS ====

    const pf = state.portfolio orelse return @floatToInt(i32, y);

    var yProjects = y + gridSize * 1.0;
    for (pf.projects) |project| {
        const coverAspect = 1.74;
        const coverPos = m.Vec2.init(sideMargin, yProjects);
        const coverWidth = screenSize.x - sideMargin * 2.0;
        const coverSize = m.Vec2.init(coverWidth, coverWidth / coverAspect);
        yProjects += coverSize.y;
        if (state.assets.getTextureData(.{.dynamic = project.cover})) |tex| {
            const cornerRadius = 0;
            renderQueue.texQuadColor(
                coverPos, coverSize, DEPTH_GRIDIMAGE, cornerRadius, tex, m.Vec4.white
            );
        } else {
            if (state.assets.getTextureLoadState(.{.dynamic = project.cover}) == .free) {
                state.assets.loadTexturePriority(.{.dynamic = project.cover}, &.{
                    .path = project.cover,
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                }, 5) catch |err| {
                    std.log.err("Failed to register {s}, err {}", .{project.cover, err});
                };
            }
        }

        yProjects += gridSize * 1.0;
        const coverTextPos = m.Vec2.init(sideMargin, yProjects);
        renderQueue.text(project.name, coverTextPos, DEPTH_UI_GENERIC, fontText, COLOR_YELLOW_HOME);
        yProjects += gridSize * 1.5;
    }

    y = yProjects;

    // draw background gradient
    const gradientColor = m.Vec4.init(86.0 / 255.0, 0.0, 214.0 / 255.0, 1.0);
    const gradientPos = m.Vec2.init(0.0, screenSize.y);
    const gradientSize = m.Vec2.init(screenSize.x, y - screenSize.y);
    renderQueue.quadGradient(
        gradientPos, gradientSize, DEPTH_LANDINGBACKGROUND, 0.0,
        [4]m.Vec4 {m.Vec4.black, m.Vec4.black, gradientColor, gradientColor}
    );

    return @floatToInt(i32, y);
}
