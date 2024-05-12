const std = @import("std");

const app = @import("zigkm-app");
const m = @import("zigkm-math");
const w = app.wasm_bindings;

const App = @import("app_main.zig").App;

pub const Data = struct {
    driveReqInFlight: bool = false,
};

pub fn updateAndRender(state: *App, deltaS: f64, scrollY: f32, screenSize: m.Vec2, renderQueue: *app.render.RenderQueue, allocator: std.mem.Allocator) i32
{
    _ = deltaS;
    _ = scrollY;
    _ = screenSize;
    _ = allocator;
    var pageData = &state.pageData.Admin;

    if (!pageData.driveReqInFlight and state.inputState.keyboardState.keyDown('Z')) {
        w.httpRequestZ(.POST, "/drive", "", "", "");
        pageData.driveReqInFlight = true;
    }
    if (!pageData.driveReqInFlight and state.inputState.keyboardState.keyDown('X')) {
        w.httpRequestZ(.POST, "/save", "", "", "");
        pageData.driveReqInFlight = true;
    }

    const fontTitle = state.assets.getFontData(.Title) orelse return 0;
    const fontText = state.assets.getFontData(.Text) orelse return 0;
    const msgDepth = 0.5;

    const titlePos = m.Vec2.init(50, 50 + fontTitle.lineHeight);
    renderQueue.text("Admin Page", titlePos, msgDepth, fontTitle, m.Vec4.black);

    const msg = if (pageData.driveReqInFlight) "[ Updating from Google Drive ]" else "[ Idle ]";
    const msgPos = m.add(titlePos, m.Vec2.init(0, 50 + fontText.lineHeight));
    renderQueue.text(msg, msgPos, msgDepth, fontText, m.Vec4.black);

    return 0;
}

pub fn onHttp(state: *App, method: std.http.Method, code: u32, uri: []const u8, data: []const u8, tempAllocator: std.mem.Allocator) void
{
    _ = data;
    _ = tempAllocator;
    var pageData = &state.pageData.Admin;

    if (method == .POST and code == 200 and (std.mem.eql(u8, uri, "/drive") or std.mem.eql(u8, uri, "/save"))) {
        pageData.driveReqInFlight = false;
    }
}
