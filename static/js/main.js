const IS_HOME = window.location.pathname === "/" || window.location.pathname === "/index.html";

let _entry = null;
let _preloadedImages = {};

// Takes an array of arrays of images to load, in sequence
function preloadImages(imageSequence)
{
    for (let i = 0; i < imageSequence.length; i++) {
        let loaded = false;
        if (imageSequence[i][0] in _preloadedImages) {
            loaded = true;
            for (let j = 0; j < imageSequence[i].length; j++) {
                const imgSrc = imageSequence[i][j];
                if (!_preloadedImages[imgSrc].complete) {
                    loaded = false;
                    break;
                }
            }
        } else {
            for (let j = 0; j < imageSequence[i].length; j++) {
                const imgSrc = imageSequence[i][j];
                _preloadedImages[imgSrc] = new Image();
                _preloadedImages[imgSrc].onload = function() {
                    preloadImages(imageSequence);
                };
                _preloadedImages[imgSrc].src = imgSrc;
            }
        }

        if (!loaded) {
            break;
        }
    }
}

// entry is null for home page, or if project info is not loaded yet
function updateCanvasSize(entry)
{
    const width = window.innerWidth;
    const height = window.innerHeight;
    const margin = Math.round(height * 0.04);
    const imageHeight = height - margin * 3;
    const borderRadius = margin;

    const nGridItems = IS_HOME ? 3 : 6;

    const maxAspect = 2.0;
    let targetWidth = width;
    if (width / height > maxAspect) {
        targetWidth = height * maxAspect;
    }
    let marginX = (width - targetWidth) / 2;

    let fontSizeP = targetWidth / 180;
    fontSizeP = margin / 3.5;
    let lineHeightP = fontSizeP * 20 / 12;

    const landing = document.getElementById("landing");

    const landingBackground = document.getElementById("landingBackground");
    landingBackground.style.height = px(imageHeight);
    landingBackground.style.marginLeft = px(margin + marginX);
    landingBackground.style.marginRight = px(margin + marginX);
    landingBackground.style.marginTop = px(margin);
    landingBackground.style.marginBottom = px(margin * 2);
    landingBackground.style.borderRadius = px(borderRadius);

    const landingDecalTopLeft = document.getElementById("landingDecalTopLeft");
    landingDecalTopLeft.style.left = px(0);
    landingDecalTopLeft.style.top = px(0);
    landingDecalTopLeft.style.width = px(margin * 6);
    landingDecalTopLeft.style.height = px(margin * 6);
    const landingDecalTopRight = document.getElementById("landingDecalTopRight");
    landingDecalTopRight.style.right = px(0);
    landingDecalTopRight.style.top = px(0);
    landingDecalTopRight.style.width = px(margin * 6);
    landingDecalTopRight.style.height = px(margin * 6);
    landingDecalTopRight.style.transform = "rotate(90deg)";
    const landingDecalBottomLeft = document.getElementById("landingDecalBottomLeft");
    landingDecalBottomLeft.style.left = px(0);
    landingDecalBottomLeft.style.bottom = px(0);
    landingDecalBottomLeft.style.width = px(margin * 6);
    landingDecalBottomLeft.style.height = px(margin * 6);
    landingDecalBottomLeft.style.transform = "rotate(270deg)";
    const landingDecalBottomRight = document.getElementById("landingDecalBottomRight");
    landingDecalBottomRight.style.right = px(0);
    landingDecalBottomRight.style.bottom = px(0);
    landingDecalBottomRight.style.width = px(margin * 6);
    landingDecalBottomRight.style.height = px(margin * 6);
    landingDecalBottomRight.style.transform = "rotate(180deg)";

    const iconStartX = margin * 4;
    const iconSpacingX = margin * 2.5;
    const iconSize = margin * 2.162;
    const landingIconHome = document.getElementById("landingIconHome");
    landingIconHome.style.left = px(margin * 4);
    landingIconHome.style.top = px(margin * 4);
    landingIconHome.style.width = px(iconSize);
    landingIconHome.style.height = px(iconSize);
    const landingIconWork = document.getElementById("landingIconWork");
    landingIconWork.style.left = px(margin * 4 + iconSpacingX);
    landingIconWork.style.top = px(margin * 4);
    landingIconWork.style.width = px(iconSize);
    landingIconWork.style.height = px(iconSize);
    const landingIconPortfolio = document.getElementById("landingIconPortfolio");
    landingIconPortfolio.style.left = px(margin * 4 + iconSpacingX * 2);
    landingIconPortfolio.style.top = px(margin * 4);
    landingIconPortfolio.style.width = px(iconSize);
    landingIconPortfolio.style.height = px(iconSize);
    const landingIconContact = document.getElementById("landingIconContact");
    landingIconContact.style.left = px(margin * 4 + iconSpacingX * 3);
    landingIconContact.style.top = px(margin * 4);
    landingIconContact.style.width = px(iconSize);
    landingIconContact.style.height = px(iconSize);

    if (!IS_HOME) {
        const landingBackground = document.getElementById("landingBackground");

        let prevEl = document.getElementById("landingProjectImage");
        if (prevEl) {
            prevEl.remove();
        }

        const el = document.createElement("img");
        el.id = "landingProjectImage";
        el.style.position = "absolute";
        el.style.width = "100%";
        el.onload = function() {
            const left = (landingBackground.offsetWidth / 2) - (this.width / 2);
            this.style.left = px(left);
        };
        if (entry !== null) {
            el.src = entry.images[entry.landingIndex];
        }
        landingBackground.appendChild(el);
    }

    Array.from(document.getElementsByClassName("bigSticker")).forEach(function(sticker) {
        sticker.style.width = px(margin * 14);
        sticker.style.height = px(margin * 3);
    });
    Array.from(document.getElementsByClassName("bigStickerTitle")).forEach(function(title) {
        title.style.left = px(margin * 0.4);
        title.style.top = px(margin * 0.25);
        const fontSize = margin * 1.6;
        title.style.lineHeight = px(fontSize);
        title.style.fontSize = px(fontSize);
        title.style.letterSpacing = px(-2.5);
    });

    const landingSticker = document.getElementById("landingSticker");
    landingSticker.style.left = px(margin * 4);
    landingSticker.style.bottom = px(margin * 4);

    const landingStickerTitle = document.getElementById("landingStickerTitle");
    if (!IS_HOME && entry !== null) {
        landingStickerTitle.innerHTML = entry.title;
    }

    const landingStickerShiny = document.getElementById("landingStickerShiny");
    landingStickerShiny.style.right = px(margin * 4);
    landingStickerShiny.style.top = px(margin * 4);
    landingStickerShiny.style.width = px(margin * 5);
    landingStickerShiny.style.height = px(margin * 3);

    const content = document.getElementById("content");
    content.style.paddingLeft = px(margin + marginX);
    content.style.paddingRight = px(margin + marginX);

    const quickText = document.getElementById("quickText");
    quickText.style.height = px(margin);
    quickText.style.fontSize = px(fontSizeP);
    quickText.style.lineHeight = px(lineHeightP);
    const quickTextLeft = document.getElementById("quickTextLeft");
    quickTextLeft.style.left = px(margin * 4);
    quickTextLeft.style.width = px(margin * 17);

    const sections = document.getElementsByClassName("section");
    for (let i = 0; i < sections.length; i++) {
        sections[i].style.borderRadius = px(borderRadius);
    }

    const portfolioDecalTopLeft = document.getElementById("portfolioDecalTopLeft");
    portfolioDecalTopLeft.style.left = px(0);
    portfolioDecalTopLeft.style.top = px(0);
    portfolioDecalTopLeft.style.width = px(margin * 6);
    portfolioDecalTopLeft.style.height = px(margin * 6);
    const portfolioDecalTopRight = document.getElementById("portfolioDecalTopRight");
    portfolioDecalTopRight.style.right = px(0);
    portfolioDecalTopRight.style.top = px(0);
    portfolioDecalTopRight.style.width = px(margin * 6);
    portfolioDecalTopRight.style.height = px(margin * 6);
    portfolioDecalTopRight.style.transform = "rotate(90deg)";

    const sectionSticker = document.getElementById("sectionSticker");
    sectionSticker.style.left = px(margin * 4);
    sectionSticker.style.top = px(margin * 4);
    const sectionStickerTitle = document.getElementById("sectionStickerTitle");

    const sectionQuickText = document.getElementById("sectionQuickText");
    sectionQuickText.style.fontSize = px(fontSizeP);
    sectionQuickText.style.lineHeight = px(lineHeightP);
    sectionQuickText.style.left = px(margin * 4);
    sectionQuickText.style.top = px(margin * 8);

    const grid = document.getElementById("grid");
    const gridSpacing = IS_HOME ? margin : margin * 0.25;
    const gridWidth = (grid.offsetWidth - (gridSpacing * (nGridItems - 1))) / nGridItems;
    sectionQuickText.style.width = px(gridWidth * (Math.floor(nGridItems / 2) + 1) + margin - margin * 4);

    grid.style.columnGap = px(gridSpacing);
    grid.style.paddingTop = px(margin * 11);
    grid.style.gridTemplateColumns = "auto ".repeat(nGridItems);

    const gridItemAspect = 1.82;
    const gridItems = Array.from(document.getElementsByClassName("gridItem"));
    gridItems.forEach(gridItem => {
        const extraHeight = IS_HOME ? margin : 0;
        // const height = IS_HOME ? margin * 12 : margin * 10;
        gridItem.style.width = px(gridWidth);
        gridItem.style.height = px(gridWidth / gridItemAspect + gridSpacing + extraHeight);
    });
    const gridItemBackgrounds = Array.from(document.getElementsByClassName("gridItemBackground"));
    gridItemBackgrounds.forEach(bg => {
        bg.style.height = px(gridWidth / gridItemAspect);
        bg.style.borderRadius = px(gridSpacing);
    });
    const gridItemTitles = Array.from(document.getElementsByClassName("gridItemTitle"));
    gridItemTitles.forEach(title => {
        title.style.marginTop = px(margin * 0.6);
        title.style.marginLeft = px(margin);
        title.style.height = px(margin);
    });

    const footer = document.getElementById("footer");
    footer.style.height = px(margin * 8);

    const footerDecalBottomLeft = document.getElementById("footerDecalBottomLeft");
    footerDecalBottomLeft.style.left = px(0);
    footerDecalBottomLeft.style.bottom = px(0);
    footerDecalBottomLeft.style.width = px(margin * 6);
    footerDecalBottomLeft.style.height = px(margin * 6);
    footerDecalBottomLeft.style.transform = "rotate(270deg)";
    const footerDecalBottomRight = document.getElementById("footerDecalBottomRight");
    footerDecalBottomRight.style.right = px(0);
    footerDecalBottomRight.style.bottom = px(0);
    footerDecalBottomRight.style.width = px(margin * 6);
    footerDecalBottomRight.style.height = px(margin * 6);
    footerDecalBottomRight.style.transform = "rotate(180deg)";

    if (!IS_HOME) {
        const colorFilter = "hue-rotate(75deg)";
        const landingStickerBackground = document.getElementById("landingStickerBackground");
        landingStickerBackground.style.filter = colorFilter;
        landingDecalTopLeft.style.filter = colorFilter;
        landingDecalTopRight.style.filter = colorFilter;
        landingDecalBottomLeft.style.filter = colorFilter;
        landingDecalBottomRight.style.filter = colorFilter;
        landingIconHome.style.filter = colorFilter;
        landingIconWork.style.filter = colorFilter;
        landingIconPortfolio.style.filter = colorFilter;
        landingIconContact.style.filter = colorFilter;

        quickText.style.filter = colorFilter;

        portfolioDecalTopLeft.style.filter = colorFilter;
        portfolioDecalTopRight.style.filter = colorFilter;
        sectionStickerTitle.style.filter = colorFilter;
        sectionQuickText.style.filter = colorFilter;

        footerDecalBottomLeft.style.filter = colorFilter;
        footerDecalBottomRight.style.filter = colorFilter;

        content.style.backgroundImage = "linear-gradient(#000, #013620)";
    }

    // DEBUG
    const debugGrid = document.getElementById("debugGrid");
    if (debugGrid) {
        debugGrid.style.left = px(marginX);
        debugGrid.style.right = px(marginX);
        const hs = Array.from(document.getElementsByClassName("debugGridHorizontal"));
        hs.forEach(h => {
            h.remove();
        });
        const vs = Array.from(document.getElementsByClassName("debugGridVertical"));
        vs.forEach(v => {
            v.remove();
        });

        for (let i = 0; i < 20 * 2; i++) {
            const el = document.createElement("div");
            el.classList.add("debugGridHorizontal");
            if (i % 2 == 1) {
                el.classList.add("debugGridHalfStep");
            }
            el.style.left = px(i * margin * 0.5);
            debugGrid.appendChild(el);
        }
        for (let i = 0; i < 10; i++) {
            const el = document.createElement("div");
            el.classList.add("debugGridHorizontal");
            el.style.right = px(i * margin);
            debugGrid.appendChild(el);
        }
        for (let i = 0; i < 8; i++) {
            const el = document.createElement("div");
            el.classList.add("debugGridVertical");
            el.style.top = px(i * margin);
            debugGrid.appendChild(el);
        }
        for (let i = 0; i < 12 * 2; i++) {
            const el = document.createElement("div");
            el.classList.add("debugGridVertical");
            if (i % 2 == 1) {
                el.classList.add("debugGridHalfStep");
            }
            el.style.bottom = px(i * margin * 0.5);
            debugGrid.appendChild(el);
        }
    }
}

function _documentOnLoad()
{
    console.log("_documentOnLoad");

    httpGet("/portfolio", function(status, data) {
        if (status !== 200) {
            console.error("failed to get portfolios");
            return;
        }

        const portfolioList = JSON.parse(data);

        if (IS_HOME) {
            generatePortfolio(portfolioList);
        } else {
            for (let i = 0; i < portfolioList.length; i++) {
                let e = portfolioList[i];
                if (window.location.pathname === "/" + e.uri) {
                    _entry = e;
                    break;
                }
            }

            if (_entry === null) {
                console.error("Invalid entry page");
                return;
            }

            updateCanvasSize(_entry);
            generateProjectImages(_entry.images);
        }
    });

    updateCanvasSize(_entry);
    if (IS_HOME) {
        updateParallaxImages();
        addEventListener("mousemove", function(event) {
            const offsetX = event.clientX / window.innerWidth * 2.0 - 1.0;
            const offsetY = (event.clientY / window.innerWidth * 2.0 - 0.25) * 0.75;
            updateParallax(offsetX, 0.0);
        });

        // preload images
        let imageSequence = [];
        for (let i = 0; i < PARALLAX_IMAGE_SETS.length; i++) {
            const imageSet = PARALLAX_IMAGE_SETS[i];
            let list = [];
            for (let j = 0; j < imageSet.images.length; j++) {
                list.push(imageSet.images[j].url);
            }
            imageSequence.push(list);
        }
        preloadImages(imageSequence);

        setInterval(function() {
            _parallaxImageSetCurrent = (_parallaxImageSetCurrent + 1) % PARALLAX_IMAGE_SETS.length;
            clearParallaxImages();
            updateParallaxImages();
            updateParallax(0.0, 0.0);
        }, parallaxImageSwapSeconds * 1000);
    } else {
    }

    addEventListener("resize", function(event) {
        updateCanvasSize(_entry);
        if (IS_HOME) {
            updateParallaxImages();
        }
    });
}

window.onload = function() {
    console.log("window.onload");
};
