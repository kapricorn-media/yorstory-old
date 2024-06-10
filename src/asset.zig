const app = @import("zigkm-app");

pub const Font = enum {
    Title,
    Subtitle,
    Text,
    Number,
    Category,
};

pub const Texture = enum {
    DecalTopLeft,
    RoundedCorner,
    LoadingGlyphs,
    LogosAll,
    Lut1,
    ProjectSymbols,
    StickerCircle,
    StickerCircleX,
    ArrowRight,
    SymbolEye,
    YorstoryCompany,

    MobileBackground,
    MobileCrosshair,
    MobileIcons,
    MobileLogo,
    MobileYorstoryCompany,

    StickerMainHome,
};

pub const AssetsType = app.asset.AssetsWithIds(Font, Texture, 512);
