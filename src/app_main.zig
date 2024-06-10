const builtin = @import("builtin");
const std = @import("std");

const app = @import("zigkm-app");
const m = @import("zigkm-math");
const w = app.wasm_bindings;

pub usingnamespace app.exports;
pub usingnamespace @import("zigkm-stb").exports; // for stb linking

pub const MEMORY_PERMANENT = 1 * 1024 * 1024;
const MEMORY_TRANSIENT = 31 * 1024 * 1024;
pub const MEMORY_FOOTPRINT = MEMORY_PERMANENT + MEMORY_TRANSIENT;

const asset = @import("asset.zig");
const page_admin = @import("page_admin.zig");
const parallax = @import("parallax.zig");
const portfolio = @import("portfolio.zig");

pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe => .info,
    .ReleaseFast => .info,
    .ReleaseSmall => .info,
};

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
const COLOR_RED_STICKER = m.Vec4.init(234.0 / 255.0, 65.0 / 255.0, 0.0, 1.0);

const IMAGES_PER_ZOOM = 6;

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
fn updateButton(topLeft: m.Vec2, size: m.Vec2, mouseState: *const app.input.MouseState, scrollY: f32, mouseHoverGlobal: *bool) bool
{
    const mousePosF = m.Vec2.initFromVec2i(mouseState.pos);
    const topLeftScroll = m.add(topLeft, m.Vec2.init(0, -scrollY));
    const buttonRect = m.Rect.initOriginSize(topLeftScroll, size);
    if (m.isInsideRect(mousePosF, buttonRect)) {
        mouseHoverGlobal.* = true;
        for (mouseState.clickEvents.slice()) |clickEvent| {
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
    Admin,
    Home,
    Entry,
    Unknown,
};

const PageData = union(PageType) {
    Admin: page_admin.Data,
    Home: void,
    Entry: struct {
        portfolioIndex: usize,
        gallerySelection: ?m.Vec2usize,
    },
    Unknown: void,
};

fn hostUriToPageData(host: []const u8, uri: []const u8, pf: ?portfolio.Portfolio) PageData
{
    if (std.mem.startsWith(u8, host, "admin.")) {
        return PageData {
            .Admin = .{},
        };
    }

    if (std.mem.eql(u8, uri, "/")) {
        return PageData {
            .Home = {},
        };
    }
    if (pf) |pfpf| {
        for (pfpf.projects, 0..) |p, i| {
            if (std.mem.eql(u8, uri, p.uri)) {
                return PageData {
                    .Entry = .{
                        .portfolioIndex = i,
                        .gallerySelection = null,
                    }
                };
            }
        }
    }
    return PageData {
        .Unknown = {},
    };
}

fn updateGallerySelection(prev: m.Vec2usize, increment: bool, project: portfolio.Project) m.Vec2usize
{
    var newSelection: m.Vec2i = prev.toVec2i();
    if (increment) {
        newSelection.y += 1;
    } else {
        newSelection.y -= 1;
    }

    var section = project.sections[@intCast(newSelection.x)];
    if (newSelection.y < 0) {
        newSelection.x = @mod(newSelection.x - 1, @as(i32, @intCast(project.sections.len)));
        section = project.sections[@intCast(newSelection.x)];
        newSelection.y = @intCast((section.images.len - 1) / IMAGES_PER_ZOOM);
    }
    if (newSelection.y > (section.images.len - 1) / IMAGES_PER_ZOOM) {
        newSelection.x = @mod(newSelection.x + 1, @as(i32, @intCast(project.sections.len)));
        newSelection.y = 0;
    }

    return newSelection.toVec2usize();
}

pub const App = struct {
    memory: app.memory.Memory,
    inputState: app.input.InputState,
    renderState: app.render.RenderState,
    assets: asset.AssetsType,

    fbTexture: c_uint = 0,
    fbDepthRenderbuffer: c_uint = 0,
    fb: c_uint = 0,

    portfolio: ?portfolio.Portfolio = null,
    pageData: PageData = .{.Home = {}},
    shouldUpdatePage: bool = false,
    screenSizePrev: m.Vec2usize = .{.x = 0, .y = 0},
    scrollYPrev: i32 = 0,
    timestampUsPrev: i64 = 0,
    activeParallaxSetIndex: usize = 0,
    parallaxTX: f32 = 0,
    parallaxIdleTimeS: f64 = 0,
    yMaxPrev: i32 = 0,

    // mobile
    anglesRef: m.Vec3 = .{.x = 0, .y = 0, .z = 0},

    debug: bool = false,

    const Self = @This();
    pub const PARALLAX_SET_SWAP_SECONDS = 6;
    const PARALLAX_SET_INDEX_START = 1;
    comptime {
        if (PARALLAX_SET_INDEX_START >= parallax.PARALLAX_SETS.len) {
            @compileError("start parallax index out of bounds");
        }
    }

    pub fn load(self: *Self, screenSize: m.Vec2usize, scale: f32) !void
    {
        std.log.info("App load ({}x{}, {})", .{screenSize.x, screenSize.y, scale});

        // self.memory = app.memory.Memory.init(memory, MEMORY_PERMANENT, @sizeOf(Self));

        const permanentAllocator = self.memory.permanentAllocator();
        var tempBufferAllocator = self.memory.tempBufferAllocator();
        const tempAllocator = tempBufferAllocator.allocator();

        try self.renderState.load();
        try self.assets.load(permanentAllocator);

        w.glClearColor(0.0, 0.0, 0.0, 0.0);
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

        w.httpRequestZ(.GET, "/portfolio", "", "", ""); // Load portfolio data ASAP

        self.portfolio = null;
        const host = try w.getHostAlloc(tempAllocator);
        const uri = try w.getUriAlloc(tempAllocator);
        self.pageData = hostUriToPageData(host, uri, self.portfolio);
        self.shouldUpdatePage = false;
        self.screenSizePrev = m.Vec2usize.zero;
        self.scrollYPrev = -1;
        self.timestampUsPrev = 0;
        self.activeParallaxSetIndex = PARALLAX_SET_INDEX_START;
        self.parallaxTX = 0;
        self.parallaxIdleTimeS = 0;
        self.yMaxPrev = 0;

        self.debug = false;

        try self.loadRelevantAssets(screenSize, tempAllocator);
    }

    pub fn updateAndRender(self: *Self, screenSize: m.Vec2usize, timestampUs: i64, scrollY: i32) i32
    {
        const screenSizeI = screenSize.toVec2i();
        const screenSizeF = screenSize.toVec2();
        const scrollYF: f32 = @floatFromInt(scrollY);
        defer {
            self.timestampUsPrev = timestampUs;
            self.scrollYPrev = scrollY;
            self.screenSizePrev = screenSize;
        }

        const keyCodeEscape = 27;
        const keyCodeArrowLeft = 37;
        const keyCodeArrowRight = 39;
        const keyCodeG = 71;

        if (self.pageData == .Entry and self.pageData.Entry.gallerySelection != null and self.portfolio != null) {
            if (self.inputState.keyboardState.keyDown(keyCodeEscape)) {
                self.pageData.Entry.gallerySelection = null;
            } else {
                const project = self.portfolio.?.projects[self.pageData.Entry.portfolioIndex];
                if (self.inputState.keyboardState.keyDown(keyCodeArrowLeft)) {
                    self.pageData.Entry.gallerySelection.? = updateGallerySelection(
                        self.pageData.Entry.gallerySelection.?, false, project
                    );
                }
                if (self.inputState.keyboardState.keyDown(keyCodeArrowRight)) {
                    self.pageData.Entry.gallerySelection.? = updateGallerySelection(
                        self.pageData.Entry.gallerySelection.?, true, project
                    );
                }
            }
        }
        if (self.inputState.keyboardState.keyDown(keyCodeG)) {
            self.debug = !self.debug;
        }

        const deltaUs = if (self.timestampUsPrev > 0) (timestampUs - self.timestampUsPrev) else 0;
        const deltaS = @as(f64, @floatFromInt(deltaUs)) / 1000.0 / 1000.0;

        var tempBufferAllocator = self.memory.tempBufferAllocator();
        const tempAllocator = tempBufferAllocator.allocator();

        var renderQueue = tempAllocator.create(app.render.RenderQueue) catch {
            std.log.warn("Failed to allocate RenderQueue", .{});
            return -1;
        };
        renderQueue.clear();
        renderQueue.setOffsetScaleAnchor(
            m.Vec2.init(0, scrollYF + screenSizeF.y),
            m.Vec2.init(1.0, -1.0),
            m.Vec2.init(0.0, 1.0)
        );

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

        var yMax: i32 = 0;
        defer {
            self.yMaxPrev = yMax;
        }
        switch (self.pageData) {
            .Home, .Entry, .Unknown => {
                renderQueue.quad(m.Vec2.init(0, scrollYF), screenSizeF, 1.0, 0.0, m.Vec4.black);
                const isVertical = isVerticalAspect(screenSizeF);
                if (isVertical) {
                    yMax = drawMobile(self, deltaS, scrollYF, screenSizeF, renderQueue, tempAllocator);
                } else {
                    yMax = drawDesktop(self, deltaS, scrollYF, screenSizeF, renderQueue, tempAllocator);
                }
            },
            .Admin => {
                yMax = page_admin.updateAndRender(self, deltaS, scrollYF, screenSizeF, renderQueue, tempAllocator);
            },
        }

        renderQueue.render(&self.renderState, screenSizeF, tempAllocator);
        if (!m.eql(self.screenSizePrev, screenSize) or yMax != self.yMaxPrev) {
            std.log.info("resize, clearing HTML elements", .{});
            // w.clearAllEmbeds();
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

    pub fn onHttp(self: *Self, method: std.http.Method, code: u32, uri: []const u8, data: []const u8, tempAllocator: std.mem.Allocator) void
    {
        if (method == .GET and std.mem.eql(u8, uri, "/portfolio") and code == 200) {
            const pf = portfolio.Portfolio.init(data, self.memory.permanentAllocator()) catch |err| {
                std.log.err("Error {} while parsing /portfolio response", .{err});
                std.log.err("Response:\n{s}", .{data});
                return;
            };
            self.portfolio = pf;
            std.log.info("Loaded portfolio ({} projects)", .{pf.projects.len});
        }

        switch (self.pageData) {
            .Admin => page_admin.onHttp(self, method, code, uri, data, tempAllocator),
            .Entry => {},
            .Home => {},
            .Unknown => {},
        }
    }

    fn updatePageData(self: *Self, allocator: std.mem.Allocator) void
    {
        const host = w.getHostAlloc(allocator) catch {
            std.log.err("getHostAlloc failed", .{});
            return;
        };
        const uri = w.getUriAlloc(allocator) catch {
            std.log.err("getUriAlloc failed", .{});
            return;
        };
        self.pageData = hostUriToPageData(host, uri, self.portfolio);
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
        });

        const helveticaBoldUrl = "/fonts/HelveticaNeueLTCom-Bd.ttf";
        const helveticaMediumUrl = "/fonts/HelveticaNeueLTCom-Md.ttf";
        const helveticaLightUrl = "/fonts/HelveticaNeueLTCom-Lt.ttf";

        const titleFontSize = if (isVertical) fromRefFontSizePx(180, screenSizeF) else gridSize * 4.0;
        const titleKerning = if (isVertical) -gridSize * 0.12 else -gridSize * 0.15;
        const titleLineHeight = titleFontSize * 0.92;
        try fontsToLoad.append(.{
            .font = .Title,
            .path = helveticaBoldUrl,
            .atlasSize = 4096,
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

        if (!isVertical) {
            try texturesToLoad.appendSlice(&[_]TextureLoadInfo {
                .{
                    .texture = .ArrowRight,
                    .path = "images/arrow-right.png",
                    .priority = 8,
                },
                .{
                    .texture = .StickerCircleX,
                    .path = "images/sticker-circle-x.png",
                    .priority = 8,
                },
            });

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
        } else {
            try texturesToLoad.appendSlice(&[_]TextureLoadInfo {
                // .{
                //     .texture = .MobileBackground,
                //     .path = "images/mobile/background.png",
                //     .priority = 5,
                // },
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

        switch (self.pageData) {
            .Admin => {},
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
                }
            },
            .Entry => {},
            .Unknown => {},
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
                }, allocator);
            }
        }
        for (texturesToLoad.items) |t| {
            if (self.assets.getTextureLoadState(.{.static = t.texture}) == .free) {
                try self.assets.loadTexturePriority(.{.static = t.texture}, &.{
                    .path = t.path,
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                }, t.priority, allocator);
            }
        }
    }
};

const GridImage = struct {
    uri: []const u8,
    title: ?[]const u8,
    goToUri: ?[]const u8,
};

fn drawImageGrid(images: []const GridImage, itemsPerRow: usize, topLeft: m.Vec2, width: f32, spacing: f32, depthTex: f32, texPriority: u32, fontData: *const app.asset_data.FontData, fontColor: m.Vec4, state: *App, scrollY: f32, mouseHoverGlobal: *bool, renderQueue: *app.render.RenderQueue, callback: *const fn(*App, GridImage, usize, anytype) void, callbackData: anytype) f32
{
    const itemAspect = 1.74;
    const itemWidth = (width - spacing * (@as(f32, @floatFromInt(itemsPerRow)) - 1)) / @as(f32, @floatFromInt(itemsPerRow));
    const itemSize = m.Vec2.init(itemWidth, itemWidth / itemAspect);

    var yMax: f32 = topLeft.y;
    for (images, 0..) |img, i| {
        const rowF: f32 = @floatFromInt(i / itemsPerRow);
        const colF: f32 = @floatFromInt(i % itemsPerRow);
        const spacingY = if (img.title) |_| spacing * 8 else spacing;
        const itemPos = m.Vec2.init(
            topLeft.x + colF * (itemSize.x + spacing),
            topLeft.y + rowF * (itemSize.y + spacingY)
        );
        if (state.assets.getTextureData(.{.dynamic = img.uri})) |tex| {
            const cornerRadius = 0;
            renderQueue.texQuadColor(
                itemPos, itemSize, depthTex, cornerRadius, tex, m.Vec4.white
            );
        } else {
            if (state.assets.getTextureLoadState(.{.dynamic = img.uri}) == .free) {
                state.assets.loadTexturePriority(.{.dynamic = img.uri}, &.{
                    .path = img.uri,
                    .filter = defaultTextureFilter,
                    .wrapMode = defaultTextureWrap,
                }, texPriority, undefined) catch |err| {
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

            yMax = @max(yMax, textPos.y);
        }

        if (updateButton(itemPos, itemSize, &state.inputState.mouseState, scrollY, mouseHoverGlobal)) {
            callback(state, img, i, callbackData);
        }

        yMax = @max(yMax, itemPos.y + itemSize.y);
    }

    return yMax - topLeft.y;
}

fn getTextureScaledSize(size: m.Vec2usize, screenSize: m.Vec2) m.Vec2
{
    const sizeF = m.Vec2.initFromVec2usize(size);
    const scaleFactor = screenSize.y / refSizeDesktop.y;
    return m.multScalar(sizeF, scaleFactor);
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

fn drawDesktop(state: *App, deltaS: f64, scrollYF: f32, screenSizeF: m.Vec2, renderQueue: *app.render.RenderQueue, allocator: std.mem.Allocator) i32
{
    const colorUi = blk: {
        switch (state.pageData) {
            .Admin => unreachable,
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

    const mousePosF = state.inputState.mouseState.pos.toVec2();
    var mouseHoverGlobal = false;

    const gridSize = getGridSize(screenSizeF);

    const marginX = blk: {
        const maxLandingImageAspect = 2.15;
        const landingImageSize = m.Vec2.init(
            screenSizeF.x - gridSize * 2.0,
            screenSizeF.y - gridSize * 3.0
        );
        const adjustedWidth = @min(landingImageSize.x, landingImageSize.y * maxLandingImageAspect);
        break :blk (landingImageSize.x - adjustedWidth) / 2.0;
    };
    // const crosshairMarginX = marginX + gridSize * 5;
    const contentMarginX = marginX + gridSize * 9;

    const decalTopLeft = state.assets.getTextureData(.{.static = .DecalTopLeft});
    const stickerMain = blk: {
        switch (state.pageData) {
            .Admin => unreachable,
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
                            }, 9, allocator) catch |err| {
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

    const allFontsLoaded = blk: {
        var loaded = true;
        inline for (std.meta.tags(asset.Font)) |f| {
            const fontData = state.assets.getFontData(f);
            loaded = loaded and fontData != null;
        }
        break :blk loaded;
    };
    var allLandingAssetsLoaded = decalTopLeft != null and stickerMain != null and allFontsLoaded;
    if (allLandingAssetsLoaded) {
        const targetParallaxTX = mousePosF.x / screenSizeF.x * 2.0 - 1.0; // -1 to 1
        state.parallaxTX = targetParallaxTX;

        const landingImageMarginX = marginX + gridSize * 1;
        const landingImagePos = m.Vec2.init(landingImageMarginX, gridSize * 1);
        const landingImageSize = m.Vec2.init(
            screenSizeF.x - landingImageMarginX * 2,
            screenSizeF.y - gridSize * 3
        );
        if (!parallax.loadAndDrawParallax(landingImagePos, landingImageSize, DEPTH_LANDINGBACKGROUND, state, renderQueue, screenSizeF, deltaS, defaultTextureWrap, defaultTextureFilter)) {
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
                if (updateButton(categoryButtonPos, categoryButtonSize, &state.inputState.mouseState, scrollYF, &mouseHoverGlobal)) {
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
        const colorSticker = switch (state.pageData) {
            .Admin => unreachable,
            .Home, .Unknown => colorUi,
            .Entry => m.Vec4.white,
        };
        renderQueue.texQuadColor(
            stickerPos, stickerSize, DEPTH_UI_GENERIC, 0, sMain, colorSticker
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
                    screenSizeF.x / 2.0 - dotSize.x / 2.0 - spacing * @as(f32, @floatFromInt(i - 1)),
                    screenSizeF.y / 2.0 - dotSize.y / 2.0 - gridSize * 1,
                );
                renderQueue.quad(dotOrigin, dotSize, DEPTH_UI_GENERIC - 0.01, 0, m.Vec4.black);
            }
        }
    }

    {
        // TODO hm
        // rounded black frame
        // const framePos = m.Vec2.init(marginX + gridSize * 1, gridSize * 1);
        // const frameSize = m.Vec2.init(
        //     screenSizeF.x - marginX * 2 - gridSize * 2,
        //     screenSizeF.y - gridSize * 3,
        // );
        // renderQueue.roundedFrame(.{
        //     .bottomLeft = m.Vec2.zero,
        //     .size = screenSizeF,
        //     .depth = DEPTH_UI_OVER1,
        //     .frameBottomLeft = framePos,
        //     .frameSize = frameSize,
        //     .cornerRadius = gridSize,
        //     .color = m.Vec4.black
        // });
    }

    const section1Height = screenSizeF.y;

    if (!allLandingAssetsLoaded) {
        return @intFromFloat(section1Height);
    }

    // ==== SECOND FRAME ====

    const fontTitle = state.assets.getFontData(.Title) orelse return @intFromFloat(section1Height);
    const fontSubtitle = state.assets.getFontData(.Subtitle) orelse return @intFromFloat(section1Height);
    const fontText = state.assets.getFontData(.Text) orelse return @intFromFloat(section1Height);
    const sCircle = stickerCircle orelse return @intFromFloat(section1Height);

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
        renderQueue.textMaxWidth("Yorstory is a creative development studio specializing in sequential art. We are storytellers with over 20 years of experience in the Television, Film, and Video Game industries.", wasTextPos1, DEPTH_UI_GENERIC, wasTextWidth, fontText, colorUi);
        const wasTextPos2 = m.Vec2.init(
            screenSizeF.x / 2.0,
            wasTextPos1.y,
        );
        renderQueue.textMaxWidth("Our diverse experience has given us an unparalleled understanding of multiple mediums, giving us the tools to create a cohesive, story-centric vision along with the visuals needed to create a shared understanding between multiple departments and disciplines.", wasTextPos2, DEPTH_UI_GENERIC, wasTextWidth, fontText, colorUi);

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
                    break :blk scrollYF + std.math.lerp(-eyeSize.y, eyeOffset, t);
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
            const eyeDepth = DEPTH_UI_GENERIC - 0.01;
            const eyeSymbolDepth = DEPTH_UI_GENERIC - 0.02;
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
            // TODO
            // rounded black frame
            // const framePos = m.Vec2.init(marginX + gridSize * 1, secondFrameYStill + gridSize * 1);
            // const frameSize = m.Vec2.init(
            //     screenSizeF.x - marginX * 2 - gridSize * 2,
            //     screenSizeF.y - gridSize * 3,
            // );
            // renderQueue.roundedFrame(.{
            //     .bottomLeft = m.Vec2.init(0.0, secondFrameYStill),
            //     .size = screenSizeF,
            //     .depth = DEPTH_UI_OVER1,
            //     .frameBottomLeft = framePos,
            //     .frameSize = frameSize,
            //     .cornerRadius = gridSize,
            //     .color = m.Vec4.black
            // });
        }
    }

    // ==== THIRD FRAME ====

    const CB = struct {
        fn home(theState: *App, image: GridImage, index: usize, args: anytype) void
        {
            _ = index;
            _ = args;
            if (image.goToUri) |uri| {
                theState.changePage(uri);
            }
        }

        fn entry(theState: *App, image: GridImage, index: usize, args: anytype) void
        {
            _ = image;
            if (theState.pageData != .Entry) {
                std.log.err("entry callback, but not an Entry page", .{});
                return;
            }
            if (theState.pageData.Entry.gallerySelection == null) {
                theState.pageData.Entry.gallerySelection = m.Vec2usize.init(args.sectionIndex, index / IMAGES_PER_ZOOM);
            }
        }

        fn noop(theState: *App, image: GridImage, index: usize, args: anytype) void
        {
            _ = theState;
            _ = image;
            _ = index;
            _ = args;
        }
    };

    var yMax = section1Height + section2Height;
    const fontNumber = state.assets.getFontData(.Number) orelse return @intFromFloat(yMax);
    const pf = state.portfolio orelse return @intFromFloat(yMax);

    const contentSubWidth = screenSizeF.x - contentMarginX * 2;
    switch (state.pageData) {
        .Admin => unreachable,
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
            renderQueue.textMaxWidth(project.contentDescription, contentSubPos, DEPTH_UI_GENERIC, contentSubPosWidth, fontText, colorUi);

            yMax = contentSubPos.y + contentSubRect.size().y + gridSize * 3.0;

            var galleryImages = std.ArrayList(GridImage).init(allocator);

            var yGallery = yMax;
            var indexOffset: usize = 0;
            for (project.sections, 0..) |section, i| {
                if (section.name.len > 0 or section.description.len > 0) {
                    const numberSize = getTextureScaledSize(sCircle.size, screenSizeF);
                    const numberPos = m.Vec2.init(
                        contentMarginX - gridSize * 1.4,
                        yGallery - gridSize * 2.4,
                    );
                    // TODO number should be on top, but depth sorting is bad
                    renderQueue.texQuadColor(
                        numberPos, numberSize, DEPTH_UI_GENERIC + 0.02, 0, sCircle, COLOR_RED_STICKER
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
                    renderQueue.textMaxWidth(
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
                yGallery += drawImageGrid(galleryImages.items, itemsPerRow, topLeft, contentSubWidth, spacing, DEPTH_GRIDIMAGE, 9, fontText, colorUi, state, scrollYF, &mouseHoverGlobal, renderQueue, CB.entry, .{.sectionIndex = i});
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

            if (entryData.gallerySelection) |gallerySelection| {
                const pos = m.Vec2.init(0.0, scrollYF);
                renderQueue.quad(pos, screenSizeF, DEPTH_UI_OVER2, 0, m.Vec4.init(0.0, 0.0, 0.0, 1.0));

                galleryImages.clearRetainingCapacity();
                const section = project.sections[gallerySelection.x];
                const imageIndexStart = gallerySelection.y * IMAGES_PER_ZOOM;
                const imageIndexEnd = @min(
                    (gallerySelection.y + 1) * IMAGES_PER_ZOOM,
                    section.images.len
                );
                const images = section.images[imageIndexStart..imageIndexEnd];
                for (images) |img| {
                    galleryImages.append(GridImage {
                        .uri = img,
                        .title = null,
                        .goToUri = null,
                    }) catch unreachable;
                }

                const galleryMarginX = gridSize * 4.0;
                const galleryWidth = screenSizeF.x - (galleryMarginX * 2);

                const spacing = gridSize * 0.25;
                const aspect = 1.74; // TODO Copied from imagegrid
                const perRow: usize = IMAGES_PER_ZOOM / 2;
                const galleryHeight = galleryWidth / @as(f32, @floatFromInt(perRow)) / aspect * 2;
                const yOffset = (screenSizeF.y - galleryHeight) / 2;
                const pospos = m.Vec2.init(galleryMarginX, scrollYF + yOffset);
                _ = drawImageGrid(galleryImages.items, perRow, pospos, galleryWidth, spacing, DEPTH_UI_OVER2 - 0.01, 9, fontText, colorUi, state, scrollYF, &mouseHoverGlobal, renderQueue, CB.noop, {});

                if (state.assets.getTextureData(.{.static = .StickerCircleX})) |circleX| {
                    const circleXPos = m.Vec2.init(gridSize * 1.0, scrollYF + gridSize * 1.0);
                    const circleXSize = getTextureScaledSize(circleX.size, screenSizeF);
                    renderQueue.texQuadColor(
                        circleXPos, circleXSize,
                        DEPTH_UI_OVER2 - 0.01, 0,
                        circleX, m.Vec4.white
                    );
                    if (updateButton(circleXPos, circleXSize, &state.inputState.mouseState, scrollYF, &mouseHoverGlobal)) {
                        state.pageData.Entry.gallerySelection = null;
                    }
                }
                if (state.assets.getTextureData(.{.static = .ArrowRight})) |arrowRight| {
                    const arrowSize = getTextureScaledSize(arrowRight.size, screenSizeF);
                    const arrowLeftPos = m.Vec2.init(
                        (galleryMarginX - arrowSize.x) / 2.0,
                        scrollYF + (screenSizeF.y - arrowSize.y) / 2.0
                    );
                    renderQueue.texQuadColorUvOffset(
                        arrowLeftPos, arrowSize, DEPTH_UI_OVER2 - 0.01, 0,
                        m.Vec2.init(1.0, 0.0),
                        m.Vec2.init(-1.0, 1.0),
                        arrowRight, m.Vec4.white
                    );

                    const arrowRightPos = m.Vec2.init(
                        screenSizeF.x - (galleryMarginX - arrowSize.x) / 2.0 - arrowSize.x,
                        scrollYF + (screenSizeF.y - arrowSize.y) / 2.0
                    );
                    renderQueue.texQuad(arrowRightPos, arrowSize, DEPTH_UI_OVER2 - 0.01, 0, arrowRight);

                    const arrowLeftClickPos = m.Vec2.init(0, scrollYF + yOffset);
                    const arrowRightClickPos = m.Vec2.init(screenSizeF.x - galleryMarginX, scrollYF + yOffset);
                    const arrowClickSize = m.Vec2.init(galleryMarginX, screenSizeF.y - yOffset * 2);
                    if (updateButton(arrowLeftClickPos, arrowClickSize, &state.inputState.mouseState, scrollYF, &mouseHoverGlobal)) {
                        state.pageData.Entry.gallerySelection.? = updateGallerySelection(gallerySelection, false, project);
                    }
                    if (updateButton(arrowRightClickPos, arrowClickSize, &state.inputState.mouseState, scrollYF, &mouseHoverGlobal)) {
                        state.pageData.Entry.gallerySelection.? = updateGallerySelection(gallerySelection, true, project);
                    }
                }
            }
        },
    }

    const section3Start = yMax;
    const section3YScrolling = section3Start;

    // draw moving gradient (estimate based on previous frame)
    const gradientColor = m.Vec4.init(86.0 / 255.0, 0.0, 214.0 / 255.0, 1.0);
    const gradientPos = m.Vec2.init(0.0, section3YScrolling);
    // const gradientSize = m.Vec2.init(screenSizeF.x, section3Height * 1.5);
    const gradientSize = m.Vec2.init(screenSizeF.x, @as(f32, @floatFromInt(state.yMaxPrev)) - section3Start);
    renderQueue.quadGradient(
        gradientPos, gradientSize, DEPTH_LANDINGBACKGROUND, 0.0,
        [4]m.Vec4 {m.Vec4.black, m.Vec4.black, gradientColor, gradientColor}
    );

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
    for (pf.projects, 0..) |project, i| {
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
    const projectGridY = drawImageGrid(images.items, itemsPerRow, gridTopLeft, contentSubWidth, spacing, DEPTH_GRIDIMAGE, 8, fontText, colorUi, state, scrollYF, &mouseHoverGlobal, renderQueue, CB.home, {});

    const section3Height = gridTopLeft.y - section3Start + projectGridY + gridSize * 8.0;

    if (decalTopLeft) |dtl| {
        const crosshairRectPos = m.Vec2.init(marginX, section3YScrolling);
        const crosshairRectSize = m.Vec2.init(screenSizeF.x - marginX * 2, section3Height - gridSize);

        drawCrosshairCorners(
            crosshairRectPos, crosshairRectSize, DEPTH_UI_GENERIC,
            gridSize, dtl, screenSizeF, colorUi, renderQueue
        );
    }

    {
        // TODO
        // rounded black frame
        // const frameTotalSize = m.Vec2.init(screenSizeF.x, section3Height);
        // const framePos = m.Vec2.init(marginX + gridSize * 1, section3YScrolling + gridSize * 1);
        // const frameSize = m.Vec2.init(
        //     screenSizeF.x - marginX * 2 - gridSize * 2,
        //     section3Height - gridSize * 3,
        // );
        // renderQueue.roundedFrame(.{
        //     .bottomLeft = m.Vec2.init(0.0, section3YScrolling),
        //     .size = frameTotalSize,
        //     .depth = DEPTH_UI_OVER1,
        //     .frameBottomLeft = framePos,
        //     .frameSize = frameSize,
        //     .cornerRadius = gridSize,
        //     .color = m.Vec4.black
        // });
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

    return @intFromFloat(yMax);
}

fn drawMobile(state: *App, deltaS: f64, scrollY: f32, screenSize: m.Vec2, renderQueue: *app.render.RenderQueue, allocator: std.mem.Allocator) i32
{
    const colorUi = blk: {
        switch (state.pageData) {
            .Admin => unreachable,
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

    // const aspect = screenSize.x / screenSize.y;
    const gridSize = getGridSize(screenSize);

    const quat = m.Quat.initFromEulerAngles(state.inputState.deviceState.angles);
    _ = quat;
    const anglesTarget = state.inputState.deviceState.angles;
    // TODO use something more linear
    state.anglesRef = m.lerp(state.anglesRef, anglesTarget, 0.01);

    const fontTitle = state.assets.getFontData(.Title) orelse return @intFromFloat(screenSize.y);
    const fontText = state.assets.getFontData(.Text) orelse return @intFromFloat(screenSize.y);

    var mouseHoverGlobal = false;

    // ==== FIRST FRAME: LANDING ====

    {
        const offsetTest = anglesTarget.z / 90.0 * 10.0;
        state.parallaxTX = offsetTest;

        const parallaxReady = parallax.loadAndDrawParallax(m.Vec2.zero, screenSize, DEPTH_LANDINGBACKGROUND, state, renderQueue, screenSize, deltaS, defaultTextureWrap, defaultTextureFilter);
        _ = parallaxReady;
    }
    // if (state.assets.getTextureData(.{.static = .MobileBackground})) |bgTex| {
    //     const bgTexSize = m.Vec2.initFromVec2usize(bgTex.size);
    //     const bgAspect = bgTexSize.x / bgTexSize.y;
    //     // _ = bgAspect;
    //     // _ = aspect;
    //     // const bgUvBottomLeft = m.Vec2.zero;
    //     // const bgUvSize = m.Vec2.one;
    //     // renderQueue.texQuadColorUvOffset(m.Vec2.zero, screenSize, DEPTH_LANDINGBACKGROUND, 0.0, bgUvBottomLeft, bgUvSize, bgTex, m.Vec4.white);
    //     const backgroundSize = if (bgAspect < aspect)
    //         m.Vec2.init(screenSize.x, screenSize.x / bgAspect)
    //         else
    //         m.Vec2.init(screenSize.y / bgTexSize.y * bgTexSize.x, screenSize.y);
    //     std.log.info("{} vs {}: {}", .{bgAspect, aspect, backgroundSize});
    //     const backgroundPos = m.Vec2.init(
    //         (screenSize.x - backgroundSize.x) / 2.0,
    //         (screenSize.y - backgroundSize.y) / 2.0,
    //     );
    //     renderQueue.texQuadColor(backgroundPos, backgroundSize, DEPTH_LANDINGBACKGROUND, 0.0, bgTex, m.Vec4.white);
    // }

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
        // const offsetTest = anglesTarget.z / 90.0 * 100.0;
        const offsetTest = 0;
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

    if (state.pageData == .Unknown) {
        return @intFromFloat(y);
    }

    // slightly offset from the crosshair (aligned with the circle)
    const sideMargin = gridSize * 1.0;
    const contentWidth = screenSize.x - sideMargin * 2;

    var yWas = y + gridSize * 8.0;
    const wasText = blk: {
        switch (state.pageData) {
            .Home => break :blk "We are\nStorytellers",
            .Entry => |entryData| {
                const project = state.portfolio.?.projects[entryData.portfolioIndex];
                break :blk project.name;
            },
            .Admin, .Unknown => unreachable,
        }
    };
    const wasPos = m.Vec2.init(sideMargin, yWas);
    const wasRect = app.render.textRect(wasText, fontTitle, null);
    renderQueue.text(wasText, wasPos, DEPTH_UI_GENERIC, fontTitle, colorUi);
    yWas += wasRect.size().y;

    switch (state.pageData) {
        .Home => {
            // TODO what's happening here? why don't I need this extra spacing?
            // yWas += gridSize * 2.0;
            const text1 = "Yorstory is a creative development\nstudio specializing in sequential\nart.";
            const text1Pos = m.Vec2.init(sideMargin, yWas);
            renderQueue.text(text1, text1Pos, DEPTH_UI_GENERIC, fontText, colorUi);
            const text1Rect = app.render.textRect(text1, fontText, null);
            yWas += text1Rect.size().y;

            yWas += gridSize * 1.0;
            const text2 = "We are storytellers with over\ntwenty years of experience in the\nTelevision, Film, and Video Game\nindustries.";
            const text2Pos = m.Vec2.init(sideMargin, yWas);
            renderQueue.text(text2, text2Pos, DEPTH_UI_GENERIC, fontText, colorUi);
            const text2Rect = app.render.textRect(text2, fontText, null);
            yWas += text2Rect.size().y;
        },
        .Entry => |entryData| {
            const project = state.portfolio.?.projects[entryData.portfolioIndex];

            const text1Pos = m.Vec2.init(sideMargin, yWas);
            renderQueue.textMaxWidth(project.contentDescription, text1Pos, DEPTH_UI_GENERIC, contentWidth, fontText, colorUi);
            const text1Rect = app.render.textRect(project.contentDescription, fontText, contentWidth);
            yWas += text1Rect.size().y;
        },
        .Admin => unreachable,
        .Unknown => unreachable,
    }

    y += screenSize.y;

    // ==== THIRD FRAME: GALLERY (ENTRY ONLY) ====

    const CB = struct {
        fn entry(theState: *App, image: GridImage, index: usize, args: anytype) void
        {
            _ = theState;
            _ = image;
            _ = index;
            _ = args;
        }
    };

    const pf = state.portfolio orelse return @intFromFloat(y);

    var y3 = y;
    switch (state.pageData) {
        .Home => {},
        .Admin => unreachable,
        .Unknown => unreachable,
        .Entry => |entryData| {
            const project = pf.projects[entryData.portfolioIndex];
            const fontNumber = state.assets.getFontData(.Number) orelse return @intFromFloat(y3);
            const fontSubtitle = state.assets.getFontData(.Subtitle) orelse return @intFromFloat(y3);
            const sCircle = state.assets.getTextureData(.{.static = .StickerCircle}) orelse return @intFromFloat(y3);

            y3 += gridSize * 2.0;

            var galleryImages = std.ArrayList(GridImage).init(allocator);

            var yGallery = y3;
            var indexOffset: usize = 0; // TODO eh...
            for (project.sections, 0..) |section, i| {
                if (section.name.len > 0 or section.description.len > 0) {
                    const numberSize = getTextureScaledSize(sCircle.size, screenSize);
                    const numberPos = m.Vec2.init(
                        sideMargin - gridSize * 1.4,
                        yGallery - gridSize * 2.4,
                    );
                    // TODO number should be on top, but depth sorting is bad
                    renderQueue.texQuadColor(
                        numberPos, numberSize, DEPTH_UI_GENERIC + 0.02, 0, sCircle, COLOR_RED_STICKER
                    );
                    const numStr = std.fmt.allocPrint(allocator, "{}", .{i + 1}) catch unreachable;
                    const numberTextPos = m.Vec2.init(
                        numberPos.x + numberSize.x * 0.28,
                        numberPos.y + numberSize.y * 0.75
                    );
                    renderQueue.text(numStr, numberTextPos, DEPTH_UI_GENERIC + 0.01, fontNumber, m.Vec4.black);

                    const subNameRect = app.render.textRect(section.name, fontSubtitle, null);
                    renderQueue.text(section.name, m.Vec2.init(sideMargin, yGallery), DEPTH_UI_GENERIC, fontSubtitle, colorUi);
                    yGallery += -subNameRect.min.y + gridSize * 2.0;

                    const subDescriptionWidth = screenSize.x - sideMargin * 2;
                    const subDescriptionRect = app.render.textRect(section.description, fontText, subDescriptionWidth);
                    renderQueue.textMaxWidth(
                        section.description,
                        m.Vec2.init(sideMargin, yGallery),
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

                const itemsPerRow = 1;
                const topLeft = m.Vec2.init(sideMargin, yGallery);
                const spacing = gridSize * 0.25;
                yGallery += drawImageGrid(galleryImages.items, itemsPerRow, topLeft, contentWidth, spacing, DEPTH_GRIDIMAGE, 9, fontText, colorUi, state, scrollY, &mouseHoverGlobal, renderQueue, CB.entry, {});
                yGallery += gridSize * 4.0;
                indexOffset += section.images.len;
            }

            y3 = yGallery + gridSize * 1;

            // TODO
            // video embed
            // if (pf.youtubeId) |youtubeId| {
            //     const embedWidth = screenSizeF.x - contentMarginX * 2;
            //     const embedSize = m.Vec2.init(embedWidth, embedWidth / 2.0);
            //     const embedPos = m.Vec2.init(contentMarginX, yMax);
            //     renderQueue.embedYoutube(embedPos, embedSize, youtubeId);
            //     yMax += embedSize.y + gridSize * 4;
            // }

            y3 += gridSize * 1;
        },
    }

    y = y3;

    // ==== FOURTH FRAME: PROJECTS ====

    if (state.pageData == .Entry) {
        y += gridSize;
        renderQueue.text("Other\nProjects", m.Vec2.init(sideMargin, y), DEPTH_UI_GENERIC, fontTitle, colorUi);
        y += fontTitle.lineHeight + gridSize;
    }

    var yProjects = y + gridSize * 1.0;
    for (pf.projects, 0..) |project, i| {
        if (state.pageData == .Entry and state.pageData.Entry.portfolioIndex == i) {
            continue;
        }

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
                }, 5, allocator) catch |err| {
                    std.log.err("Failed to register {s}, err {}", .{project.cover, err});
                };
            }
        }
        if (updateButton(coverPos, coverSize, &state.inputState.mouseState, scrollY, &mouseHoverGlobal)) {
            state.changePage(project.uri);
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

    // TODO don't do all the time
    if (mouseHoverGlobal) {
        w.setCursorZ("pointer");
    } else {
        w.setCursorZ("auto");
    }

    return @intFromFloat(y);
}
