const IS_HOME = window.location.pathname === "/" || window.location.pathname === "/index.html";

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

function updateCanvasSize()
{
    const width = window.innerWidth;
    const height = window.innerHeight;
    const margin = Math.round(height * 0.04);
    const imageHeight = height - margin * 3;
    const borderRadius = margin;

    const landing = document.getElementById("landing");

    const landingBackground = document.getElementById("landingBackground");
    landingBackground.style.height = px(imageHeight);
    landingBackground.style.margin = px(margin);
    landingBackground.style.marginBottom = (margin * 2).toString() + "px";
    landingBackground.style.borderRadius = borderRadius.toString() + "px";

    const landingDecalTopLeft = document.getElementById("landingDecalTopLeft");
    landingDecalTopLeft.style.left = "0px";
    landingDecalTopLeft.style.top = "0px";
    landingDecalTopLeft.style.width = (margin * 6).toString() + "px";
    landingDecalTopLeft.style.height = (margin * 6).toString() + "px";
    const landingDecalTopRight = document.getElementById("landingDecalTopRight");
    landingDecalTopRight.style.right = "0px";
    landingDecalTopRight.style.top = "0px";
    landingDecalTopRight.style.width = (margin * 6).toString() + "px";
    landingDecalTopRight.style.height = (margin * 6).toString() + "px";
    landingDecalTopRight.style.transform = "rotate(90deg)";
    const landingDecalBottomLeft = document.getElementById("landingDecalBottomLeft");
    landingDecalBottomLeft.style.left = "0px";
    landingDecalBottomLeft.style.bottom = "0px";
    landingDecalBottomLeft.style.width = (margin * 6).toString() + "px";
    landingDecalBottomLeft.style.height = (margin * 6).toString() + "px";
    landingDecalBottomLeft.style.transform = "rotate(270deg)";
    const landingDecalBottomRight = document.getElementById("landingDecalBottomRight");
    landingDecalBottomRight.style.right = "0px";
    landingDecalBottomRight.style.bottom = "0px";
    landingDecalBottomRight.style.width = (margin * 6).toString() + "px";
    landingDecalBottomRight.style.height = (margin * 6).toString() + "px";
    landingDecalBottomRight.style.transform = "rotate(180deg)";

    const landingText = document.getElementById("landingText");
    landingText.style.left = "0px";
    landingText.style.top = "0px";
    landingText.style.width = (margin * 18).toString() + "px";
    landingText.style.height = (margin * 3).toString() + "px";

    if (!IS_HOME) {
        const landingBackground = document.getElementById("landingBackground");

        const el = document.createElement("img");
        el.id = "landingProjectImage";
        el.style.position = "absolute";
        el.style.width = "100%";
        el.onload = function() {
            const left = (landingBackground.offsetWidth / 2) - (this.width / 2);
            this.style.left = left.toString() + "px";
        };
        el.src = "images/halo/17.png";
        landingBackground.appendChild(el);
    }

    const landingSticker = document.getElementById("landingSticker");
    landingSticker.style.left = (margin * 4).toString() + "px";
    landingSticker.style.bottom = (margin * 4).toString() + "px";
    landingSticker.style.width = (margin * 14).toString() + "px";
    landingSticker.style.height = (margin * 3).toString() + "px";

    const landingStickerTitle = document.getElementById("landingStickerTitle");
    landingStickerTitle.style.left = px(margin * 0.4);
    landingStickerTitle.style.top = px(margin * 0.25);
    const fontSize = margin * 1.6;
    landingStickerTitle.style.lineHeight = px(fontSize);
    landingStickerTitle.style.fontSize = px(fontSize);
    landingStickerTitle.style.letterSpacing = px(-2.5);
    if (!IS_HOME) {
        landingStickerTitle.innerHTML = "HALO";
    }

    const landingStickerShiny = document.getElementById("landingStickerShiny");
    landingStickerShiny.style.right = (margin * 6).toString() + "px";
    landingStickerShiny.style.top = (margin * 2).toString() + "px";
    landingStickerShiny.style.width = (margin * 5).toString() + "px";
    landingStickerShiny.style.height = (margin * 3).toString() + "px";

    const content = document.getElementById("content");
    content.style.marginLeft = margin.toString() + "px";
    content.style.marginRight = margin.toString() + "px";

    const quickText = document.getElementById("quickText");
    quickText.style.height = (margin * 4).toString() + "px";
    const quickTextLeft = document.getElementById("quickTextLeft");
    quickTextLeft.style.left = (margin).toString() + "px";
    quickTextLeft.style.width = (margin * 17).toString() + "px";
    const quickTextRight = document.getElementById("quickTextRight");
    quickTextRight.style.left = "50%";
    quickTextRight.style.width = (margin * 17).toString() + "px";

    const sections = document.getElementsByClassName("section");
    for (let i = 0; i < sections.length; i++) {
        sections[i].style.borderRadius = borderRadius.toString() + "px";
    }

    const grid = document.getElementById("grid");
    grid.style.columnGap = margin.toString() + "px";
    const gridItems = Array.from(document.getElementsByClassName("gridItem"));
    gridItems.forEach(gridItem => {
        const height = IS_HOME ? margin * 12 : margin * 10;
        gridItem.style.height = height.toString() + "px";
    });
    const gridItemBackgrounds = Array.from(document.getElementsByClassName("gridItemBackground"));
    gridItemBackgrounds.forEach(bg => {
        bg.style.height = (margin * 9).toString() + "px";
        bg.style.borderRadius = margin.toString() + "px";
    });
    const gridItemTitles = Array.from(document.getElementsByClassName("gridItemTitle"));
    gridItemTitles.forEach(title => {
        title.style.marginLeft = margin.toString() + "px";
        title.style.height = margin.toString() + "px";
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

    updateCanvasSize();
    if (IS_HOME) {
        httpGet("/portfolio", function(status, data) {
            if (status !== 200) {
                console.error("failed to get portfolios");
                return;
            }
            const portfolioList = JSON.parse(data);
            generatePortfolio(portfolioList);
        });

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
        let projectImages = [];
        for (let i = 1; i <= 24; i++) {
            projectImages.push("images/halo/" + i.toString() + ".png");
        }
        generateProjectImages(projectImages);
    }

    addEventListener("resize", function(event) {
        updateCanvasSize();
        if (IS_HOME) {
            updateParallaxImages();
        }
    });
}

window.onload = function() {
    console.log("window.onload");
};
