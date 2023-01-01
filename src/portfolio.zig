const std = @import("std");

const m = @import("math.zig");

pub const Subproject = struct {
    name: []const u8,
    description: []const u8,
    images: []const []const u8,
};

pub const Portfolio = struct {
    title: []const u8,
    uri: []const u8,
    cover: []const u8,
    landing: []const u8,
    sticker: []const u8,
    parallaxIndex: usize,
    colorUi: m.Vec4,
    colorSticker: m.Vec4,
    youtubeId: ?[]const u8,
    contentHeader: []const u8,
    contentDescription: []const u8,
    subprojects: []const Subproject,
};

pub const PORTFOLIO_LIST = [_]Portfolio {
    .{
        .title = "HALO",
        .uri = "/halo",
        .cover = "/images/HALO/cover.png",
        .landing = "/images/HALO/landing.png",
        .sticker = "/images/HALO/sticker-main.png",
        .parallaxIndex = 4,
        .colorUi = m.Vec4.init(0.0, 220.0 / 255.0, 164.0 / 255.0, 1.0),
        .colorSticker = m.Vec4.init(0.0, 220.0 / 255.0, 164.0 / 255.0, 1.0),
        .youtubeId = null,
        .contentHeader = "boarding the mechanics ***",
        .contentDescription = "In 2010, Yorstory partnered with Microsoft/343 Studios to join one of the video game industry's most iconic franchises - Halo. Working with the team's weapons and mission designers, we were tasked with helping visualize some of the game's weapons and idealized gameplay scenarios. The result was an exciting blend of enthusiasm sci-fi mayhem, starring the infamous Master Chief.",
        .subprojects = &[_]Subproject {
            .{
                .name = "ATTACH BEAM",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "/images/HALO/attachbeam1/1.png",
                    "/images/HALO/attachbeam1/2.png",
                    "/images/HALO/attachbeam1/3.png",
                    "/images/HALO/attachbeam1/4.png",
                    "/images/HALO/attachbeam1/5.png",
                    "/images/HALO/attachbeam1/6.png",
                    "/images/HALO/attachbeam1/7.png",
                    "/images/HALO/attachbeam1/8.png",
                    "/images/HALO/attachbeam1/9.png",
                    "/images/HALO/attachbeam1/10.png",
                    "/images/HALO/attachbeam1/11.png",
                    "/images/HALO/attachbeam1/12.png",
                },
            },
            .{
                .name = "ATTACH BEAM II",
                .description = "Anyone who has played Halo knows that there's a lot of vehicular combat. Using the Attach Beam, a player connects a tether to their opponent's vehicle. Once connected, a player is able to deliver a series of pulses to destroy their enemy's vehicle.",
                .images = &[_][]const u8{
                    "/images/HALO/attachbeam2/1.png",
                    "/images/HALO/attachbeam2/2.png",
                    "/images/HALO/attachbeam2/3.png",
                    "/images/HALO/attachbeam2/4.png",
                    "/images/HALO/attachbeam2/5.png",
                    "/images/HALO/attachbeam2/6.png",
                    "/images/HALO/attachbeam2/7.png",
                    "/images/HALO/attachbeam2/8.png",
                    "/images/HALO/attachbeam2/9.png",
                    "/images/HALO/attachbeam2/10.png",
                    "/images/HALO/attachbeam2/11.png",
                    "/images/HALO/attachbeam2/12.png",
                },
            },
            .{
                .name = "BISHOP BEAM",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "/images/HALO/bishopbeam/1.png",
                    "/images/HALO/bishopbeam/2.png",
                    "/images/HALO/bishopbeam/3.png",
                    "/images/HALO/bishopbeam/4.png",
                    "/images/HALO/bishopbeam/5.png",
                    "/images/HALO/bishopbeam/6.png",
                },
            },
            .{
                .name = "FORERUNNER",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "/images/HALO/Forerunner/1.png",
                    "/images/HALO/Forerunner/2.png",
                    "/images/HALO/Forerunner/3.png",
                    "/images/HALO/Forerunner/4.png",
                    "/images/HALO/Forerunner/5.png",
                    "/images/HALO/Forerunner/6.png",
                    "/images/HALO/Forerunner/7.png",
                    "/images/HALO/Forerunner/8.png",
                    "/images/HALO/Forerunner/9.png",
                },
            },
            .{
                .name = "FORERUNNER II",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "/images/HALO/Forerunner2/1.png",
                    "/images/HALO/Forerunner2/2.png",
                    "/images/HALO/Forerunner2/3.png",
                    "/images/HALO/Forerunner2/4.png",
                    "/images/HALO/Forerunner2/5.png",
                    "/images/HALO/Forerunner2/6.png",
                },
            },
            .{
                .name = "GRAPPLE ARMOR",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "/images/HALO/GrappleArmor/1.png",
                    "/images/HALO/GrappleArmor/2.png",
                    "/images/HALO/GrappleArmor/3.png",
                    "/images/HALO/GrappleArmor/4.png",
                    "/images/HALO/GrappleArmor/5.png",
                    "/images/HALO/GrappleArmor/6.png",
                },
            },
            .{
                .name = "GRAPPLE BEAM",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "/images/HALO/GrappleBeam/1.png",
                    "/images/HALO/GrappleBeam/2.png",
                    "/images/HALO/GrappleBeam/3.png",
                    "/images/HALO/GrappleBeam/4.png",
                    "/images/HALO/GrappleBeam/5.png",
                    "/images/HALO/GrappleBeam/6.png",
                    "/images/HALO/GrappleBeam/7.png",
                    "/images/HALO/GrappleBeam/8.png",
                    "/images/HALO/GrappleBeam/9.png",
                    "/images/HALO/GrappleBeam/10.png",
                    "/images/HALO/GrappleBeam/11.png",
                },
            },
            .{
                .name = "MORTAR",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "/images/HALO/Mortar/1.png",
                    "/images/HALO/Mortar/2.png",
                    "/images/HALO/Mortar/3.png",
                    "/images/HALO/Mortar/4.png",
                    "/images/HALO/Mortar/5.png",
                    "/images/HALO/Mortar/6.png",
                    "/images/HALO/Mortar/7.png",
                    "/images/HALO/Mortar/8.png",
                },
            },
            .{
                .name = "PELICAN",
                .description = "By attaching a tether to an opponent, the player is able to deliver a series of devastating pulses to further damage their enemy.",
                .images = &[_][]const u8{
                    "/images/HALO/Pelican/1.png",
                    "/images/HALO/Pelican/2.png",
                    "/images/HALO/Pelican/3.png",
                    "/images/HALO/Pelican/4.png",
                    "/images/HALO/Pelican/5.png",
                    "/images/HALO/Pelican/6.png",
                    "/images/HALO/Pelican/7.png",
                    "/images/HALO/Pelican/8.png",
                    "/images/HALO/Pelican/9.png",
                    "/images/HALO/Pelican/10.png",
                    "/images/HALO/Pelican/11.png",
                },
            },
        },
    },
    .{
        .title = "Marvel: Contest of Champions",
        .uri = "/marvel-contest-of-champions",
        .cover = "/images/marvel/all/Mad_Titan_0025_26.png",
        .landing = "/images/HALO/landing.png",
        .sticker = "/images/marvel/sticker-main.png",
        .parallaxIndex = 5,
        .colorUi = m.Vec4.init(165.0 / 255.0, 56.0 / 255.0, 1.0, 1.0),
        .colorSticker = m.Vec4.init(165.0 / 255.0, 56.0 / 255.0, 1.0, 1.0),
        .youtubeId = "Bilb5i7tCk0",
        .contentHeader = "Mad Titan's Wrath",
        .contentDescription = "This trailer was to celebrate the 3rd anniversary of Marvel Contest of Champions.  It features a huge cast of Marvel characters in an all-out war, set to The Sword's \"Apocryphon.\"",
        .subprojects = &[_]Subproject {
            .{
                .name = "Act 1",
                .description = "Spiderman is on the run in the Battlerealm, and quickly we realize that his pursuer is none other than the Mad Titan himself, Thanos, wielding the power of 3 of the 6 infinity stones.",
                .images = &[_][]const u8{
                    "/images/marvel/all/Mad_Titan_0001_02.png",
                    "/images/marvel/all/Mad_Titan_0002_03.png",
                    "/images/marvel/all/Mad_Titan_0003_04.png",
                    "/images/marvel/all/Mad_Titan_0005_06.png",
                    "/images/marvel/all/Mad_Titan_0008_09.png",
                    "/images/marvel/all/Mad_Titan_0010_11.png",
                    "/images/marvel/all/Mad_Titan_0011_12.png",
                    "/images/marvel/all/Mad_Titan_0014_15.png",
                    "/images/marvel/all/Mad_Titan_0017_18.png",
                    "/images/marvel/all/Mad_Titan_0020_21.png",
                    "/images/marvel/all/Mad_Titan_0025_26.png",
                    "/images/marvel/all/Mad_Titan_0026_27.png",
                },
            },
            .{
                .name = "Act 2",
                .description = "Just in the nick of time, a series of heroes arrives to save Spidey, but despite him being able to flee, Thanos is able to harness the power of the Infinity Stones to turn his attackers to stone.",
                .images = &[_][]const u8{
                    "/images/marvel/all/Mad_Titan_0029_30.png",
                    "/images/marvel/all/Mad_Titan_0030_31.png",
                    "/images/marvel/all/Mad_Titan_0035_36.png",
                    "/images/marvel/all/Mad_Titan_0037_38.png",
                    "/images/marvel/all/Mad_Titan_0038_39.png",
                    "/images/marvel/all/Mad_Titan_0041_42.png",
                    "/images/marvel/all/Mad_Titan_0045_46.png",
                    "/images/marvel/all/Mad_Titan_0049_50.png",
                    "/images/marvel/all/Mad_Titan_0051_52.png",
                    "/images/marvel/all/Mad_Titan_0055_56.png",
                    "/images/marvel/all/Mad_Titan_0058_59.png",
                    "/images/marvel/all/Mad_Titan_0061_62.png",
                },
            },
            .{
                .name = "Act 3",
                .description = "Thanos catches up with Spiderman, wounded and now on his last legs. Before the killing blow can be struck, the Civil Warrior arrives with the cavalry.  Spiderman reveals that he has been carrying one of the lost infinity stones this entire time!  As the team of heroes are able to push Thanos back, Spiderman flees with the stone, inciting the Mad Titan's Wrath!",
                .images = &[_][]const u8{
                    "/images/marvel/all/Mad_Titan_0071_72.png",
                    "/images/marvel/all/Mad_Titan_0073_74.png",
                    "/images/marvel/all/Mad_Titan_0076_77.png",
                    "/images/marvel/all/Mad_Titan_0078_79.png",
                    "/images/marvel/all/Mad_Titan_0084_85.png",
                    "/images/marvel/all/Mad_Titan_0086_87.png",
                    "/images/marvel/all/Mad_Titan_0093_94.png",
                    "/images/marvel/all/Mad_Titan_0095_96.png",
                    "/images/marvel/all/Mad_Titan_0098_99.png",
                    "/images/marvel/all/Mad_Titan_0105_106.png",
                    "/images/marvel/all/Mad_Titan_0109_110.png",
                    "/images/marvel/all/Mad_Titan_0118_119.png",
                },
            },
        },
    },
};
