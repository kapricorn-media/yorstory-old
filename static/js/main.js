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
    landingDecalTopLeft.style.left = "0px";
    landingDecalTopLeft.style.top = "0px";
    landingDecalTopLeft.style.width = px(margin * 6);
    landingDecalTopLeft.style.height = px(margin * 6);
    const landingDecalTopRight = document.getElementById("landingDecalTopRight");
    landingDecalTopRight.style.right = "0px";
    landingDecalTopRight.style.top = "0px";
    landingDecalTopRight.style.width = px(margin * 6);
    landingDecalTopRight.style.height = px(margin * 6);
    landingDecalTopRight.style.transform = "rotate(90deg)";
    const landingDecalBottomLeft = document.getElementById("landingDecalBottomLeft");
    landingDecalBottomLeft.style.left = "0px";
    landingDecalBottomLeft.style.bottom = "0px";
    landingDecalBottomLeft.style.width = px(margin * 6);
    landingDecalBottomLeft.style.height = px(margin * 6);
    landingDecalBottomLeft.style.transform = "rotate(270deg)";
    const landingDecalBottomRight = document.getElementById("landingDecalBottomRight");
    landingDecalBottomRight.style.right = "0px";
    landingDecalBottomRight.style.bottom = "0px";
    landingDecalBottomRight.style.width = px(margin * 6);
    landingDecalBottomRight.style.height = px(margin * 6);
    landingDecalBottomRight.style.transform = "rotate(180deg)";

    const landingText = document.getElementById("landingText");
    landingText.style.left = "0px";
    landingText.style.top = "0px";
    landingText.style.width = px(margin * 18);
    landingText.style.height = px(margin * 3);

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

    const landingSticker = document.getElementById("landingSticker");
    landingSticker.style.left = px(margin * 4);
    landingSticker.style.bottom = px(margin * 4);
    landingSticker.style.width = px(margin * 14);
    landingSticker.style.height = px(margin * 3);

    const landingStickerTitle = document.getElementById("landingStickerTitle");
    landingStickerTitle.style.left = px(margin * 0.4);
    landingStickerTitle.style.top = px(margin * 0.25);
    const fontSize = margin * 1.6;
    landingStickerTitle.style.lineHeight = px(fontSize);
    landingStickerTitle.style.fontSize = px(fontSize);
    landingStickerTitle.style.letterSpacing = px(-2.5);
    if (!IS_HOME && entry !== null) {
        landingStickerTitle.innerHTML = entry.title;
    }

    if (!IS_HOME) {
        const colorFilter = "hue-rotate(75deg)";
        const landingStickerBackground = document.getElementById("landingStickerBackground");
        landingStickerBackground.style.filter = colorFilter;
        const landingDecalTopLeft = document.getElementById("landingDecalTopLeft");
        landingDecalTopLeft.style.filter = colorFilter;
        const landingDecalTopRight = document.getElementById("landingDecalTopRight");
        landingDecalTopRight.style.filter = colorFilter;
        const landingDecalBottomLeft = document.getElementById("landingDecalBottomLeft");
        landingDecalBottomLeft.style.filter = colorFilter;
        const landingDecalBottomRight = document.getElementById("landingDecalBottomRight");
        landingDecalBottomRight.style.filter = colorFilter;
        const landingText = document.getElementById("landingText");
        landingText.style.filter = colorFilter;
    }

    const landingStickerShiny = document.getElementById("landingStickerShiny");
    landingStickerShiny.style.right = px(margin * 6);
    landingStickerShiny.style.top = px(margin * 2);
    landingStickerShiny.style.width = px(margin * 5);
    landingStickerShiny.style.height = px(margin * 3);

    const content = document.getElementById("content");
    content.style.marginLeft = px(margin + marginX);
    content.style.marginRight = px(margin + marginX);

    const quickText = document.getElementById("quickText");
    quickText.style.height = px(margin * 4);
    quickText.style.fontSize = px(fontSizeP);
    quickText.style.lineHeight = px(lineHeightP);
    const quickTextLeft = document.getElementById("quickTextLeft");
    quickTextLeft.style.left = px(margin);
    quickTextLeft.style.width = px(margin * 17);
    const quickTextRight = document.getElementById("quickTextRight");
    quickTextRight.style.left = "50%";
    quickTextRight.style.width = px(margin * 17);

    const sections = document.getElementsByClassName("section");
    for (let i = 0; i < sections.length; i++) {
        sections[i].style.borderRadius = px(borderRadius);
    }

    const grid = document.getElementById("grid");
    grid.style.columnGap = px(margin);
    const gridItems = Array.from(document.getElementsByClassName("gridItem"));
    gridItems.forEach(gridItem => {
        const height = IS_HOME ? margin * 12 : margin * 10;
        gridItem.style.height = px(height);
    });
    const gridItemBackgrounds = Array.from(document.getElementsByClassName("gridItemBackground"));
    gridItemBackgrounds.forEach(bg => {
        bg.style.height = px(margin * 9);
        bg.style.borderRadius = px(margin);
    });
    const gridItemTitles = Array.from(document.getElementsByClassName("gridItemTitle"));
    gridItemTitles.forEach(title => {
        title.style.marginLeft = px(margin);
        title.style.height = px(margin);
    });

    // DEBUG
    const debugGrid = document.getElementById("debugGrid");
    if (debugGrid) {
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
