const std = @import("std");

const m = @import("math.zig");

// Shaders
extern fn consoleLog(messagePtr: *const u8, messageLen: c_uint) void;
extern fn compileShader(source: *const u8 , len:  c_uint, type: c_uint) c_uint;
extern fn linkShaderProgram(vertexShaderId: c_uint, fragmentShaderId: c_uint) c_uint;
extern fn createTexture(imgUrlPtr: *const u8, imgUrlLen: c_uint, wrapMode: c_uint) c_uint;

// GL
extern fn glClear(_: c_uint) void;
extern fn glClearColor(_: f32, _: f32, _: f32, _: f32) void;

extern fn glEnable(_: c_uint) void;

extern fn glBlendFunc(_: c_uint, _: c_uint) void;
extern fn glDepthFunc(_: c_uint) void;

extern fn glGetAttribLocation(_: c_uint, _: *const u8, _: c_uint) c_int;
extern fn glGetUniformLocation(_: c_uint, _: *const u8, _: c_uint) c_int;

extern fn glUniform1i(_: c_int, _: c_int) void;
extern fn glUniform2fv(_: c_int, _: f32, _: f32) void;
extern fn glUniform3fv(_: c_int, _: f32, _: f32, _: f32) void;
extern fn glUniform4fv(_: c_int, _: f32, _: f32, _: f32, _: f32) void;

extern fn glCreateBuffer() c_uint;
extern fn glBindBuffer(_: c_uint, _: c_uint) void;
extern fn glBufferData(_: c_uint, _: *const f32,  _: c_uint, _: c_uint) void;

extern fn glUseProgram(_: c_uint) void;

extern fn glEnableVertexAttribArray(_: c_uint) void;
extern fn glVertexAttribPointer(_: c_uint, _: c_uint, _: c_uint, _: c_uint, _: c_uint, _: c_uint) void;

extern fn glActiveTexture(_: c_uint) void;
extern fn glBindTexture(_: c_uint, _: c_uint) void;

extern fn glDrawArrays(_: c_uint, _: c_uint, _: c_uint) void;

// Identifier constants pulled from WebGLRenderingContext
const GL_VERTEX_SHADER: c_uint = 35633;
const GL_FRAGMENT_SHADER: c_uint = 35632;
const GL_ARRAY_BUFFER: c_uint = 34962;
const GL_TRIANGLES: c_uint = 4;
const GL_STATIC_DRAW: c_uint = 35044;
const GL_f32: c_uint = 5126;

const GL_DEPTH_TEST: c_uint = 2929;
const GL_LEQUAL: c_uint = 515;

const GL_BLEND: c_uint = 3042;
const GL_SRC_ALPHA: c_uint = 770;
const GL_ONE_MINUS_SRC_ALPHA: c_uint = 771;

const GL_COLOR_BUFFER_BIT: c_uint = 16384;
const GL_DEPTH_BUFFER_BIT: c_uint = 256;

const GL_TEXTURE_2D: c_uint = 3553;
const GL_TEXTURE0: c_uint = 33984;

const GL_REPEAT: c_uint = 10497;
const GL_CLAMP_TO_EDGE: c_uint = 33071;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    _ = message_level; _ = scope;

    var buf: [2048]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, format, args) catch {
        const errMsg = "bufPrint failed for format: " ++ format;
        consoleLog(&errMsg[0], errMsg.len);
        return;
    };
    consoleLog(&message[0], message.len);
}

var _state: State = undefined;

fn createTextureNice(url: []const u8, wrapMode: c_uint) c_uint
{
    return createTexture(&url[0], url.len, wrapMode);
}

fn floatPosToNdc(pos: f32, canvas: f32) f32
{
    return pos / canvas * 2.0 - 1.0;
}

fn floatSizeToNdc(size: f32, canvas: f32) f32
{
    return size / canvas * 2.0;
}

fn posToNdc(comptime T: type, pos: T, canvas: T) T
{
    switch (T) {
        f32 => {
            return floatPosToNdc(pos, canvas);
        },
        m.Vec2 => {
            return m.Vec2.init(
                floatPosToNdc(pos.x, canvas.x),
                floatPosToNdc(pos.y, canvas.y)
            );
        },
        m.Vec3 => {
            return m.Vec3.init(
                floatPosToNdc(pos.x, canvas.x),
                floatPosToNdc(pos.y, canvas.y),
                floatPosToNdc(pos.z, canvas.z)
            );
        },
        else => @compileError("nope"),
    }
}

fn sizeToNdc(comptime T: type, size: T, canvas: T) T
{
    switch (T) {
        f32 => {
            return floatSizeToNdc(size, canvas);
        },
        m.Vec2 => {
            return m.Vec2.init(
                floatSizeToNdc(size.x, canvas.x),
                floatSizeToNdc(size.y, canvas.y)
            );
        },
        m.Vec3 => {
            return m.Vec3.init(
                floatSizeToNdc(size.x, canvas.x),
                floatSizeToNdc(size.y, canvas.y),
                floatSizeToNdc(size.z, canvas.z)
            );
        },
        else => @compileError("nope"),
    }
}

const State = struct {
    timestampMsPrev: c_int,

    quad: QuadState,

    textureLogo: c_uint,
    textureScrollingText: c_uint,
    textureIcons: c_uint,

    scrollingTextY: f32,

    const Self = @This();

    const logoSize = m.Vec2i.init(4096, 1024);
    const scrollingTextSize = m.Vec2i.init(512, 2048);

    pub fn init() Self
    {
        return Self {
            .timestampMsPrev = 0,

            .quad = QuadState.init(),

            .textureLogo = createTextureNice("images/logo.png", GL_CLAMP_TO_EDGE),
            .textureScrollingText = createTextureNice("images/scrolling-text.png", GL_REPEAT),
            .textureIcons = createTextureNice("images/icons.png", GL_CLAMP_TO_EDGE),

            .scrollingTextY = 0.0,
        };
    }

    pub fn deinit(self: Self) void
    {
        self.gpa.deinit();
    }
};

const QuadState = struct {
    positionBuffer: c_uint,
    uvBuffer: c_uint,

    programId: c_uint,

    positionAttrLoc: c_int,
    uvAttrLoc: c_int,

    offsetPosUniLoc: c_int,
    scalePosUniLoc: c_int,
    offsetUvUniLoc: c_int,
    scaleUvUniLoc: c_int,
    samplerUniLoc: c_int,

    const positions = [6]m.Vec2 {
        m.Vec2.init(0.0, 0.0),
        m.Vec2.init(0.0, 1.0),
        m.Vec2.init(1.0, 1.0),
        m.Vec2.init(1.0, 1.0),
        m.Vec2.init(1.0, 0.0),
        m.Vec2.init(0.0, 0.0),
    };

    const vertQuad = @embedFile("shaders/quad.vert");
    const fragQuad = @embedFile("shaders/quad.frag");

    const Self = @This();

    pub fn init() Self
    {
        std.log.info("init", .{});

        const vertQuadId = compileShader(&vertQuad[0], vertQuad.len, GL_VERTEX_SHADER);
        const fragQuadId = compileShader(&fragQuad[0], fragQuad.len, GL_FRAGMENT_SHADER);

        const positionBuffer = glCreateBuffer();
        glBindBuffer(GL_ARRAY_BUFFER, positionBuffer);
        glBufferData(GL_ARRAY_BUFFER, &positions[0].x, positions.len * 2, GL_STATIC_DRAW);

        const uvBuffer = glCreateBuffer();
        glBindBuffer(GL_ARRAY_BUFFER, uvBuffer);
        // UVs are the same as positions
        glBufferData(GL_ARRAY_BUFFER, &positions[0].x, positions.len * 2, GL_STATIC_DRAW);

        const programId = linkShaderProgram(vertQuadId, fragQuadId);

        const a_position = "a_position";
        const positionAttrLoc = glGetAttribLocation(programId, &a_position[0], a_position.len);
        const a_uv = "a_uv";
        const uvAttrLoc = glGetAttribLocation(programId, &a_uv[0], a_uv.len);

        const u_offsetPos = "u_offsetPos";
        const offsetPosUniLoc = glGetUniformLocation(programId, &u_offsetPos[0], u_offsetPos.len);
        const u_scalePos = "u_scalePos";
        const scalePosUniLoc = glGetUniformLocation(programId, &u_scalePos[0], u_scalePos.len);
        const u_offsetUv = "u_offsetUv";
        const offsetUvUniLoc = glGetUniformLocation(programId, &u_offsetUv[0], u_offsetUv.len);
        const u_scaleUv = "u_scaleUv";
        const scaleUvUniLoc = glGetUniformLocation(programId, &u_scaleUv[0], u_scaleUv.len);
        const u_sampler = "u_sampler";
        const samplerUniLoc = glGetUniformLocation(programId, &u_sampler[0], u_sampler.len);

        return Self {
            .positionBuffer = positionBuffer,
            .uvBuffer = uvBuffer,

            .programId = programId,

            .positionAttrLoc = positionAttrLoc,
            .uvAttrLoc = uvAttrLoc,

            .offsetPosUniLoc = offsetPosUniLoc,
            .scalePosUniLoc = scalePosUniLoc,
            .offsetUvUniLoc = offsetUvUniLoc,
            .scaleUvUniLoc = scaleUvUniLoc,
            .samplerUniLoc = samplerUniLoc,
        };
    }

    pub fn drawQuadNdc(
        self: Self,
        posNdc: m.Vec2,
        scaleNdc: m.Vec2,
        uvOffset: m.Vec2,
        uvScale: m.Vec2,
        texture: c_uint) void
    {
        glUseProgram(self.programId);

        glEnableVertexAttribArray(@intCast(c_uint, self.positionAttrLoc));
        glBindBuffer(GL_ARRAY_BUFFER, self.positionBuffer);
        glVertexAttribPointer(@intCast(c_uint, self.positionAttrLoc), 2, GL_f32, 0, 0, 0);
        glEnableVertexAttribArray(@intCast(c_uint, self.uvAttrLoc));
        glBindBuffer(GL_ARRAY_BUFFER, self.uvBuffer);
        glVertexAttribPointer(@intCast(c_uint, self.uvAttrLoc), 2, GL_f32, 0, 0, 0);

        glUniform2fv(self.offsetPosUniLoc, posNdc.x, posNdc.y);
        glUniform2fv(self.scalePosUniLoc, scaleNdc.x, scaleNdc.y);
        glUniform2fv(self.offsetUvUniLoc, uvOffset.x, uvOffset.y);
        glUniform2fv(self.scaleUvUniLoc, uvScale.x, uvScale.y);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture);
        glUniform1i(self.samplerUniLoc, 0);

        glDrawArrays(GL_TRIANGLES, 0, positions.len);
    }

    pub fn drawQuadUvOffset(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        uvOffset: m.Vec2,
        uvScale: m.Vec2,
        texture: c_uint,
        screenSize: m.Vec2) void
    {
        const posNdc = posToNdc(m.Vec2, posPixels, screenSize);
        const scaleNdc = sizeToNdc(m.Vec2, scalePixels, screenSize);
        self.drawQuadNdc(posNdc, scaleNdc, uvOffset, uvScale, texture);
    }

    pub fn drawQuad(
        self: Self,
        posPixels: m.Vec2,
        scalePixels: m.Vec2,
        texture: c_uint,
        screenSize: m.Vec2) void
    {
        self.drawQuadUvOffset(posPixels, scalePixels, m.Vec2.zero, m.Vec2.one, texture, screenSize);
    }
};

export fn onInit() void
{
    _state = State.init();
    std.log.info("{}", .{_state});

    glClearColor(1.0, 1.0, 1.0, 1.0);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
}

export fn onAnimationFrame(width: c_int, height: c_int, timestampMs: c_int) void
{
    const screenSizeI = m.Vec2i.init(@intCast(i32, width), @intCast(i32, height));
    const screenSizeF = m.Vec2.initFromVec2i(screenSizeI);
    const halfScreenSizeF = m.Vec2.divScalar(screenSizeF, 2.0);

    const deltaMs = if (_state.timestampMsPrev > 0) (timestampMs - _state.timestampMsPrev) else 0;
    const deltaS = @intToFloat(f32, deltaMs) / 1000.0;

    const speed = 0.2;
    _state.scrollingTextY += speed * deltaS;
    while (_state.scrollingTextY < -1.0) {
        _state.scrollingTextY += 1.0;
    }

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    const logoSizeF = m.Vec2.initFromVec2i(State.logoSize); // original pixel size
    const logoWidthPixels = screenSizeF.x * 0.34;
    const logoAspect = logoSizeF.x / logoSizeF.y;
    const logoSizePixels = m.Vec2.init(logoWidthPixels, logoWidthPixels / logoAspect);
    const logoPosPixels = m.Vec2.sub(halfScreenSizeF, m.Vec2.divScalar(logoSizePixels, 2.0));

    const textSizeF = m.Vec2.initFromVec2i(State.scrollingTextSize); // original pixel size
    const textWidthPixels = logoWidthPixels * textSizeF.x / logoSizeF.x;
    const textAspect = textSizeF.x / textSizeF.y;
    const textSizePixels = m.Vec2.init(textWidthPixels, textWidthPixels / textAspect);
    const textPosPixels = m.Vec2.init(
        halfScreenSizeF.x + logoSizePixels.x * 0.07,
        halfScreenSizeF.y - logoSizePixels.y * 0.15
    );

    const fracSize = (screenSizeF.y - textPosPixels.y) / textSizePixels.y;
    const num = @floatToInt(u32, fracSize) + 1;
    var i: u32 = 0;
    while (i < num) : (i += 1) {
        const offsetY = textSizePixels.y * @intToFloat(f32, i);
        const pos = m.Vec2.add(textPosPixels, m.Vec2.init(0.0, offsetY));
        const uvOffset = m.Vec2.init(0.0, _state.scrollingTextY);
        const uvScale = m.Vec2.one;
        _state.quad.drawQuadUvOffset(
            pos, textSizePixels, uvOffset, uvScale, _state.textureScrollingText, screenSizeF
        );
    }

    // _state.quad.drawQuad(logoPosPixels, logoSizePixels, _state.textureLogo, screenSizeF);

    _state.quad.drawQuad(logoPosPixels, logoSizePixels, _state.textureLogo, screenSizeF);

    _state.timestampMsPrev = timestampMs;
}
