const std = @import("std");

// Shaders
extern fn consoleLog(messagePtr: *const u8, messageLen: c_uint) void;
extern fn compileShader(source: *const u8 , len:  c_uint, type: c_uint) c_uint;
extern fn linkShaderProgram(vertexShaderId: c_uint, fragmentShaderId: c_uint) c_uint;
extern fn createTexture(imgUrlPtr: *const u8, imgUrlLen: c_uint) c_uint;

// GL
extern fn glClearColor(_: f32, _: f32, _: f32, _: f32) void;
extern fn glEnable(_: c_uint) void;
extern fn glDepthFunc(_: c_uint) void;
extern fn glClear(_: c_uint) void;

extern fn glGetAttribLocation(_: c_uint, _: *const u8, _: c_uint) c_int;
extern fn glGetUniformLocation(_: c_uint, _: *const u8, _: c_uint) c_int;

extern fn glUniform1i(_: c_int, _: c_int) void;
extern fn glUniform2fv(_: c_int, _: f32, _: f32) void;
extern fn glUniform3fv(_: c_int, _: f32, _: f32, _: f32) void;
extern fn glUniform4fv(_: c_int, _: f32, _: f32, _: f32, _: f32) void;

extern fn glCreateBuffer() c_uint;
extern fn glBindBuffer(_: c_uint, _: c_uint) void;
extern fn glBufferData(_: c_uint, _: *align(1) const f32,  _: c_uint, _: c_uint) void;

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
const GL_COLOR_BUFFER_BIT: c_uint = 16384;
const GL_DEPTH_BUFFER_BIT: c_uint = 256;

const GL_TEXTURE_2D: c_uint = 3553;
const GL_TEXTURE0: c_uint = 33984;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    _ = message_level; _ = scope;

    const message = std.fmt.allocPrint(_state.allocator, format, args) catch {
        const errMsg = "allocPrint failed for format: " ++ format;
        consoleLog(&errMsg[0], errMsg.len);
        return;
    };
    consoleLog(&message[0], message.len);
}

var _state: State = undefined;

fn createTextureNice(url: []const u8) c_uint
{
    return createTexture(&url[0], url.len);
}

const Vec2 = packed struct {
    x: f32,
    y: f32,
};

const Vec3 = packed struct {
    x: f32,
    y: f32,
    z: f32,
};

const State = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    allocator: std.mem.Allocator,

    timestampMsPrev: c_int,
    quad: QuadState,
    texture: c_uint,

    const Self = @This();

    pub fn init() Self
    {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const texture = createTextureNice("images/test.png");

        return Self {
            .gpa = gpa,
            .allocator = gpa.allocator(),
            .timestampMsPrev = 0,
            .quad = QuadState.init(),
            .texture = texture,
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
    positionAttributeLocation: c_int,
    uvAttributeLocation: c_int,
    offsetUniformLocation: c_int,
    scaleUniformLocation: c_int,
    samplerUniformLocation: c_int,

    const positions = [6]Vec2 {
        .{.x = 0.0, .y = 0.0},
        .{.x = 0.0, .y = 1.0},
        .{.x = 1.0, .y = 1.0},
        .{.x = 1.0, .y = 1.0},
        .{.x = 1.0, .y = 0.0},
        .{.x = 0.0, .y = 0.0},
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
        const positionAttributeLocation = glGetAttribLocation(programId, &a_position[0], a_position.len);
        const a_uv = "a_uv";
        const uvAttributeLocation = glGetAttribLocation(programId, &a_uv[0], a_uv.len);

        const u_offset = "u_offset";
        const offsetUniformLocation = glGetUniformLocation(programId, &u_offset[0], u_offset.len);
        const u_scale = "u_scale";
        const scaleUniformLocation = glGetUniformLocation(programId, &u_scale[0], u_scale.len);
        const u_sampler = "u_sampler";
        const samplerUniformLocation = glGetUniformLocation(programId, &u_sampler[0], u_sampler.len);

        return Self {
            .positionBuffer = positionBuffer,
            .uvBuffer = uvBuffer,
            .programId = programId,
            .positionAttributeLocation = positionAttributeLocation,
            .uvAttributeLocation = uvAttributeLocation,
            .offsetUniformLocation = offsetUniformLocation,
            .scaleUniformLocation = scaleUniformLocation,
            .samplerUniformLocation = samplerUniformLocation,
        };
    }

    pub fn drawQuad(self: Self, pos: Vec2, scale: Vec2, texture: c_uint) void
    {
        glUseProgram(self.programId);
        glEnableVertexAttribArray(@intCast(c_uint, self.positionAttributeLocation));
        glBindBuffer(GL_ARRAY_BUFFER, self.positionBuffer);
        glVertexAttribPointer(@intCast(c_uint, self.positionAttributeLocation), 2, GL_f32, 0, 0, 0);
        glEnableVertexAttribArray(@intCast(c_uint, self.uvAttributeLocation));
        glBindBuffer(GL_ARRAY_BUFFER, self.uvBuffer);
        glVertexAttribPointer(@intCast(c_uint, self.uvAttributeLocation), 2, GL_f32, 0, 0, 0);
        glUniform2fv(self.offsetUniformLocation, pos.x, pos.y);
        glUniform2fv(self.scaleUniformLocation, scale.x, scale.y);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture);
        glUniform1i(self.samplerUniformLocation, 0);

        glDrawArrays(GL_TRIANGLES, 0, positions.len);
    }
};

export fn onInit() void
{
    _state = State.init();

    glClearColor(1.0, 1.0, 1.0, 1.0);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
}

export fn onAnimationFrame(width: c_int, height: c_int, timestampMs: c_int) void
{
    _ = width; _ = height;

    const deltaMs = if (_state.timestampMsPrev > 0) (timestampMs - _state.timestampMsPrev) else 0;
    _ = deltaMs;

    // const speed = 1.0;
    // x += @intToFloat(f32, deltaMs) / 1000.0 * speed;
    // if (x > 1) {
    //     x = -2;
    // }

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    const pos = Vec2 { .x = 0.0, .y = 0.0, };
    const scale = Vec2 { .x = 1.0, .y = 0.9, };
    _state.quad.drawQuad(pos, scale, _state.texture);

    _state.timestampMsPrev = timestampMs;
}
