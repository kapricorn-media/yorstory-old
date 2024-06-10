const builtin = @import("builtin");
const std = @import("std");

const google = @import("zigkm-google");
const app = @import("zigkm-app");
const bigdata = app.bigdata;

fn addIfNewOrUpdatedDrive(
    path: []const u8,
    file: google.drive.FileMetadata,
    authData: google.auth.AuthData,
    data: *bigdata.Data,
    allocator: std.mem.Allocator) !void
{
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const tempAllocator = arena.allocator();

    std.debug.assert(file.typeData == .file);
    const fileData = file.typeData.file;

    var md5FromMetadata: [16]u8 = undefined;
    _ = try std.fmt.hexToBytes(&md5FromMetadata, fileData.md5Checksum);
    if (data.fileExists(path, &md5FromMetadata)) {
        std.log.info("Already in bigdata: {s}", .{path});
        return;
    }

    std.log.info("Inserting {s} ({s})", .{path, file.id});
    var downloadResponse = try google.drive.downloadFile(file.id, authData, tempAllocator);
    defer downloadResponse.deinit();
    if (downloadResponse.status != .ok) {
        std.log.err("File download failed with status {}", .{downloadResponse.status});
        return error.downloadFile;
    }
    const body = downloadResponse.body orelse return error.downloadFileNoBody;
    const md5 = bigdata.calculateMd5Checksum(body);
    if (!std.mem.eql(u8, &md5FromMetadata, &md5)) {
        return error.mismatchedChecksums;
    }

    std.log.info("Put {s} {} bytes", .{path, body.len});
    // try data.put(path, body, tempAllocator);
}

pub fn fillFromGoogleDrive(folderId: []const u8, data: *bigdata.Data, key: []const u8, allocator: std.mem.Allocator) !void
{
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const tempAllocator = arena.allocator();

    const authData = google.auth.AuthData {.apiKey = key};

    var projects = try google.drive.listFiles(folderId, authData, tempAllocator);
    defer projects.deinit();
    for (projects.files) |f| {
        if (f.typeData == .folder) {
            if (std.mem.eql(u8, f.name, "PARALLAX")) {
                var listParallax = try google.drive.listFiles(f.id, authData, tempAllocator);
                defer listParallax.deinit();
                for (listParallax.files) |ff| {
                    if (ff.typeData != .file) {
                        continue;
                    }
                    const path = try std.fmt.allocPrint(
                        tempAllocator, "/DRIVE/PARALLAX/{s}", .{ff.name}
                    );
                    try addIfNewOrUpdatedDrive(path, ff, authData, data, allocator);
                }
            } else {
                std.debug.print("Project: {s}\n", .{f.name});

                var coverFound = false;
                var stickerFound = false;
                var galleryFound = false;
                const listProject = try google.drive.listFiles(f.id, authData, tempAllocator);
                for (listProject.files) |ff| {
                    switch (ff.typeData) {
                        .file => {
                            const path = try std.fmt.allocPrint(
                                tempAllocator, "/DRIVE/{s}/{s}", .{f.name, ff.name}
                            );
                            if (std.mem.eql(u8, ff.name, "cover.png")) {
                                coverFound = true;
                                try addIfNewOrUpdatedDrive(path, ff, authData, data, allocator);
                            }
                            if (std.mem.eql(u8, ff.name, "sticker-main.png")) {
                                stickerFound = true;
                                try addIfNewOrUpdatedDrive(path, ff, authData, data, allocator);
                            }
                        },
                        .folder => {
                            if (std.mem.eql(u8, ff.name, "GALLERY")) {
                                galleryFound = true;
                                var sections: ?bool = null;
                                const listGallery = try google.drive.listFiles(ff.id, authData, tempAllocator);
                                for (listGallery.files) |fff| {
                                    switch (fff.typeData) {
                                        .file => {
                                            if (sections != null and sections.?) {
                                                return error.BadGallery;
                                            }
                                            sections = false;

                                            const path = try std.fmt.allocPrint(
                                                tempAllocator, "/DRIVE/{s}/{s}/{s}", .{f.name, ff.name, fff.name}
                                            );
                                            try addIfNewOrUpdatedDrive(path, fff, authData, data, allocator);
                                        },
                                        .folder => {
                                            if (sections != null and !sections.?) {
                                                return error.BadGallery;
                                            }
                                            sections = true;

                                            const listGallery2 = try google.drive.listFiles(fff.id, authData, tempAllocator);
                                            for (listGallery2.files) |ffff| {
                                                if (ffff.typeData != .file) {
                                                    continue;
                                                }
                                                const path = try std.fmt.allocPrint(
                                                    tempAllocator, "/DRIVE/{s}/{s}/{s}/{s}", .{f.name, ff.name, fff.name, ffff.name}
                                                );
                                                try addIfNewOrUpdatedDrive(path, ffff, authData, data, allocator);
                                            }
                                        },
                                    }
                                }
                            }
                        },
                    }
                }
                if (!coverFound) {
                    std.log.err("Project {s} missing cover.png", .{f.name});
                }
                if (!stickerFound) {
                    std.log.err("Project {s} missing sticker-main.png", .{f.name});
                }
                if (!galleryFound) {
                    std.log.err("Project {s} missing GALLERY", .{f.name});
                }
            }
        }
    }
}
