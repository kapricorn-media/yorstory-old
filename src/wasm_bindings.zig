const std = @import("std");

// Debug
pub extern fn consoleMessage(isError: bool, messagePtr: *const u8, messageLen: c_uint) void;

// browser / DOM
pub extern fn clearAllText() void;
pub extern fn addTextLine(
    textPtr: *const u8, textLen: c_uint,
    left: c_int, baselineFromTop: c_int, fontSize: c_int, letterSpacing: f32,
    hexColorPtr: *const u8, hexColorLen: c_uint,
    fontFamilyPtr: *const u8, fontFamilyLen: c_uint) void;
pub extern fn addTextBox(
    textPtr: *const u8, textLen: c_uint,
    left: c_int, top: c_int, width: c_int, fontSize: c_int, lineHeight: c_int, letterSpacing: f32,
    hexColorPtr: *const u8, hexColorLen: c_uint,
    fontFamilyPtr: *const u8, fontFamilyLen: c_uint) void;
pub extern fn setCursor(cursorPtr: *const u8, cursorLen: c_uint) void;
pub extern fn getUri(outUriPtr: *u8, outUriLen: c_uint) c_uint;
pub extern fn setUri(uriPtr: *const u8, uriLen: c_uint) void;

// GL
pub extern fn compileShader(source: *const u8 , len: c_uint, type: c_uint) c_uint;
pub extern fn linkShaderProgram(vertexShaderId: c_uint, fragmentShaderId: c_uint) c_uint;
pub extern fn createTexture(imgUrlPtr: *const u8, imgUrlLen: c_uint, wrapMode: c_uint, filter: c_uint) c_uint;

pub extern fn glClear(_: c_uint) void;
pub extern fn glClearColor(_: f32, _: f32, _: f32, _: f32) void;

pub extern fn glEnable(_: c_uint) void;

pub extern fn glBlendFunc(_: c_uint, _: c_uint) void;
pub extern fn glDepthFunc(_: c_uint) void;

pub extern fn glGetAttribLocation(_: c_uint, _: *const u8, _: c_uint) c_int;
pub extern fn glGetUniformLocation(_: c_uint, _: *const u8, _: c_uint) c_int;

pub extern fn glUniform1i(_: c_int, _: c_int) void;
pub extern fn glUniform1fv(_: c_int, _: f32) void;
pub extern fn glUniform2fv(_: c_int, _: f32, _: f32) void;
pub extern fn glUniform3fv(_: c_int, _: f32, _: f32, _: f32) void;
pub extern fn glUniform4fv(_: c_int, _: f32, _: f32, _: f32, _: f32) void;

pub extern fn glCreateBuffer() c_uint;
pub extern fn glBindBuffer(_: c_uint, _: c_uint) void;
pub extern fn glBufferData(_: c_uint, _: *const f32,  _: c_uint, _: c_uint) void;

pub extern fn glUseProgram(_: c_uint) void;

pub extern fn glEnableVertexAttribArray(_: c_uint) void;
pub extern fn glVertexAttribPointer(_: c_uint, _: c_uint, _: c_uint, _: c_uint, _: c_uint, _: c_uint) void;

pub extern fn glActiveTexture(_: c_uint) void;
pub extern fn glBindTexture(_: c_uint, _: c_uint) void;

pub extern fn glDrawArrays(_: c_uint, _: c_uint, _: c_uint) void;

// Identifier constants pulled from WebGLRenderingContext
pub const GL_VERTEX_SHADER: c_uint = 35633;
pub const GL_FRAGMENT_SHADER: c_uint = 35632;
pub const GL_ARRAY_BUFFER: c_uint = 34962;
pub const GL_TRIANGLES: c_uint = 4;
pub const GL_STATIC_DRAW: c_uint = 35044;
pub const GL_f32: c_uint = 5126;

pub const GL_DEPTH_TEST: c_uint = 2929;
pub const GL_LESS: c_uint = 513;
pub const GL_LEQUAL: c_uint = 515;

pub const GL_BLEND: c_uint = 3042;
pub const GL_SRC_ALPHA: c_uint = 770;
pub const GL_ONE_MINUS_SRC_ALPHA: c_uint = 771;

pub const GL_COLOR_BUFFER_BIT: c_uint = 16384;
pub const GL_DEPTH_BUFFER_BIT: c_uint = 256;

pub const GL_TEXTURE_2D: c_uint = 3553;
pub const GL_TEXTURE0: c_uint = 33984;

pub const GL_REPEAT: c_uint = 10497;
pub const GL_CLAMP_TO_EDGE: c_uint = 33071;

pub const GL_NEAREST: c_uint = 9728;
pub const GL_LINEAR: c_uint = 9729;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype) void
{
    _ = scope;

    var buf: [2048]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, format, args) catch {
        const errMsg = "bufPrint failed for format: " ++ format;
        consoleMessage(true, &errMsg[0], errMsg.len);
        return;
    };

    const isError = switch (message_level) {
        .err, .warn => true, 
        .info, .debug => false,
    };
    consoleMessage(isError, &message[0], message.len);
}
