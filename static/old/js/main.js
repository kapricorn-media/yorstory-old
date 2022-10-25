const IS_HOME = window.location.pathname === "/" || window.location.pathname === "/index.html";

let _entry = null;

// entry is null for home page, or if project info is not loaded yet
function updateCanvasSize(entry)
{
    const width = window.innerWidth;
    const height = window.innerHeight;

    // const margin = Math.round(height / 31.0);
    // const marginNumTop = 1;
    // const marginNumBot = 6;
    // const imageHeight = height - margin * marginNumTop - margin * marginNumBot;

    const margin = Math.round(height * 0.04);
    const imageHeight = height - margin * 3 - margin * 3;
    const borderRadius = margin;

    const nGridItems = IS_HOME ? 3 : 6;

    // const imageAspect = 2.0;
    // const imageWidth = imageHeight * imageAspect;
    // const marginX = (width - imageWidth) / 2 - margin;
    // const targetWidth = imageWidth;

    const maxAspect = 2.0;
    let targetWidth = width;
    if (width / height > maxAspect) {
        targetWidth = height * maxAspect;
    }
    let marginX = (width - targetWidth) / 2;

    let fontSizeH1 = margin * 1.6;
    let fontSizeH2 = margin * 1.06;
    let fontSizeP = margin / 2.68;
    let lineHeightP = fontSizeP * 20 / 14;

    Array.from(document.getElementsByTagName("h1")).forEach(function(el) {
        el.style.fontSize = px(fontSizeH1);
        el.style.letterSpacing = px(margin * -0.08);
    });

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

    Array.from(document.getElementsByClassName("bigSticker")).forEach(function(el) {
        el.style.width = px(margin * 15.5);
        el.style.height = px(margin * 3);
    });
    Array.from(document.getElementsByClassName("bigStickerBackground")).forEach(function(el) {
        // el.style.left = px(margin);
        // el.style.right = px(margin);
    });
    Array.from(document.getElementsByClassName("bigStickerTitle")).forEach(function(el) {
        el.style.left = px(margin * 1.4);
        el.style.top = px(margin * 0.25);
        el.style.lineHeight = px(fontSizeH1);
        el.style.fontSize = px(fontSizeH1);
        el.style.letterSpacing = px(-margin * 0.08);
    });
    Array.from(document.getElementsByClassName("bigStickerTextBottom")).forEach(function(el) {
        el.style.left = px(margin * 1.5);
        el.style.top = px(margin * 2.2);
        const fontSize = margin * 0.31;
        el.style.lineHeight = px(fontSize);
        el.style.fontSize = px(fontSize);
        el.style.letterSpacing = px(-margin * 0.01);
    });
    Array.from(document.getElementsByClassName("bigStickerTextRight")).forEach(function(el) {
        el.style.left = px(margin * 8);
        el.style.width = px(margin * 6);
        el.style.top = px(margin * 0.45);
        const fontSize = margin * 0.31;
        el.style.lineHeight = px(fontSize);
        el.style.fontSize = px(fontSize);
        el.style.letterSpacing = px(-margin * 0.01);
    });

    const landingSticker = document.getElementById("landingSticker");
    landingSticker.style.left = px(margin * 3);
    landingSticker.style.bottom = px(margin * 4);

    const landingStickerTitle = document.getElementById("landingStickerTitle");
    if (!IS_HOME && entry !== null) {
        landingStickerTitle.innerHTML = entry.title;
    }
    if (IS_HOME) {
        const landingStickerTitleR = document.getElementById("landingStickerTitleR");
        landingStickerTitleR.style.left = px(margin * 7.25);
        landingStickerTitleR.style.top = px(-margin * 0.15);
        landingStickerTitleR.style.fontSize = px(margin * 0.34);
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
    quickText.style.height = px(margin * 2);
    quickText.style.fontSize = px(fontSizeP);
    quickText.style.lineHeight = px(lineHeightP);
    const quickTextLeft = document.getElementById("quickTextLeft");
    quickTextLeft.style.left = px(margin * 4.5);
    quickTextLeft.style.width = px(margin * 13.5);
    const quickTextRight = document.getElementById("quickTextRight");
    quickTextRight.style.left = px(margin * 19.5);
    quickTextRight.style.width = px(margin * 13.6);

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

    const sectionTitle = document.getElementById("sectionTitle");
    sectionTitle.style.paddingLeft = px(margin * 4.45);
    sectionTitle.style.paddingTop = px(margin * 4.08);

    const sectionQuickText = document.getElementById("sectionQuickText");
    sectionQuickText.style.fontSize = px(fontSizeP);
    sectionQuickText.style.lineHeight = px(lineHeightP);
    sectionQuickText.style.marginLeft = px(margin * 4.5);
    sectionQuickText.style.marginRight = px(margin * 4.5);
    sectionQuickText.style.marginTop = px(margin * 1.5);

    Array.from(document.getElementsByTagName("h2")).forEach(function(el) {
        el.style.fontSize = px(fontSizeH2);
    });

    Array.from(document.getElementsByClassName("subproject")).forEach(function(el) {
        el.style.marginTop = px(margin * 0.8);
    });

    Array.from(document.getElementsByClassName("subprojectNumber")).forEach(function(el) {
        el.style.width = px(margin * 2);
        el.style.height = px(margin * 2);
        el.style.left = px(margin * 1.5);
    });
    Array.from(document.getElementsByClassName("subprojectNumberText")).forEach(function(el) {
        el.style.fontSize = px(margin * 1.6);
    });

    Array.from(document.getElementsByClassName("subprojectTitle")).forEach(function(el) {
        el.style.paddingTop = px(margin * 1.3);
        el.style.marginLeft = px(margin * 4.5);
    });
    Array.from(document.getElementsByClassName("subprojectText")).forEach(function(el) {
        el.style.paddingTop = px(margin * 0.5);
        el.style.marginLeft = px(margin * 4.5);
        el.style.fontSize = px(fontSizeP);
    });

    const gridSpacing = IS_HOME ? margin : margin * 0.25;
    let gridWidth = null;

    Array.from(document.getElementsByClassName("grid")).forEach(function(grid) {
        grid.style.marginLeft = px(margin * 4.5);
        grid.style.marginRight = px(margin * 4.5);
        gridWidth = (grid.offsetWidth - (gridSpacing * (nGridItems - 1))) / nGridItems;

        grid.style.columnGap = px(gridSpacing);
        grid.style.paddingTop = px(margin * 2);
        grid.style.gridTemplateColumns = "auto ".repeat(nGridItems);
    })
    // sectionQuickText.style.width = px(gridWidth * (Math.floor(nGridItems / 2) + 1) + margin - margin * 4);

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
        const galleryImage = document.getElementById("galleryImage");
        galleryImage.style.borderRadius = px(borderRadius);

        const galleryImageLeft = document.getElementById("galleryImageLeft");
        const galleryImageRight = document.getElementById("galleryImageRight");
        [galleryImageLeft, galleryImageRight].forEach(function(el) {
            el.style.paddingLeft = px(margin);
            el.style.paddingRight = px(margin);
            el.style.fontSize = px(fontSizeH1);
            el.addEventListener("click", function(event) {
                console.log(event);
            });
        });
    }

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
        sectionTitle.style.filter = colorFilter;
        sectionQuickText.style.filter = colorFilter;
        Array.from(document.getElementsByClassName("subprojectTitle")).forEach(function(el) {
            el.style.filter = colorFilter;
        });
        Array.from(document.getElementsByClassName("subprojectText")).forEach(function(el) {
            el.style.filter = colorFilter;
        });

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
        for (let i = 0; i < 14 * 2; i++) {
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
            updateCanvasSize(_entry);
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
            generateEntry(_entry);
            updateCanvasSize(_entry);
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
        loadImages(imageSequence, function(i) {
            console.log("loaded list " + i.toString());
        });

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
