function parallaxImage(url, factor)
{
    return {
        url: url,
        factor: factor,
    };
}

const PARALLAX_IMAGE_SETS = [
    {
        color: "#101010",
        images: [
            parallaxImage("images/parallax1-1.png", 0.01),
            parallaxImage("images/parallax1-2.png", 0.05),
            parallaxImage("images/parallax1-3.png", 0.2),
            parallaxImage("images/parallax1-4.png", 0.5),
            parallaxImage("images/parallax1-5.png", 0.9),
            parallaxImage("images/parallax1-6.png", 1.2),
        ]
    },
    {
        color: "#000000",
        images: [
            parallaxImage("images/parallax2-1.png", 0.05),
            parallaxImage("images/parallax2-2.png", 0.1),
            parallaxImage("images/parallax2-3.png", 0.25),
            parallaxImage("images/parallax2-4.png", 1.0),
        ]
    },
    {
        color: "#212121",
        images: [
            parallaxImage("images/parallax3-1.png", 0.05),
            parallaxImage("images/parallax3-2.png", 0.2),
            parallaxImage("images/parallax3-3.png", 0.3),
            parallaxImage("images/parallax3-4.png", 0.8),
            parallaxImage("images/parallax3-5.png", 1.1),
        ]
    },
    {
        colorTop: "#1a1b1a",
        colorBottom: "#ffffff",
        images: [
            parallaxImage("images/parallax4-1.png", 0.05),
            parallaxImage("images/parallax4-2.png", 0.1),
            parallaxImage("images/parallax4-3.png", 0.25),
            parallaxImage("images/parallax4-4.png", 0.6),
            parallaxImage("images/parallax4-5.png", 0.75),
            parallaxImage("images/parallax4-6.png", 1.2),
        ]
    }
];

const parallaxMotionMax = 100;
const parallaxImageSwapSeconds = 6;

let _parallaxImageSetCurrent = 3;

let _preloadedImages = {};

function httpGet(url, callback)
{
    const Http = new XMLHttpRequest();
    Http.open("GET", url);
    Http.responseType = "text";
    Http.send();
    Http.onreadystatechange = function() {
        if (this.readyState == 4) {
            const responseOk = this.status === 200;
            callback(this.status, responseOk ? Http.responseText : null);
        }
    };
}

function httpPost(url, data, callback)
{
    const Http = new XMLHttpRequest();
    Http.open("POST", url);
    Http.responseType = "text";
    Http.send(data);
    Http.onreadystatechange = function() {
        if (this.readyState == 4) {
            const responseOk = this.status === 200;
            callback(this.status, responseOk ? Http.responseText : null);
        }
    };
}

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

        console.log(i.toString() + loaded);
        if (!loaded) {
            break;
        }
    }
}

function getCurrentParallaxImageSet()
{
    return PARALLAX_IMAGE_SETS[_parallaxImageSetCurrent];
}

function parallaxImageId(i)
{
    return "parallaxImage" + i.toString();
}

function clearParallaxImages()
{
    const parallaxImages = Array.from(document.getElementsByClassName("parallaxImage"));
    parallaxImages.forEach(img => {
        img.remove();
    });
}

// offsetX, offsetY is in the range [-1, 1]
function updateParallax(offsetX, offsetY)
{
    const imageSet = getCurrentParallaxImageSet();
    for (let i = 0; i < imageSet.images.length; i++) {
        const img = imageSet.images[i];

        const offsetXPixels = offsetX * parallaxMotionMax * img.factor;
        const offsetYPixels = offsetY * parallaxMotionMax * img.factor;
        const el = document.getElementById(parallaxImageId(i));
        el.style.transform = "translate(" + offsetXPixels.toString() + "px, " + offsetYPixels.toString() + "px)";
    }
}

function updateCanvasSize()
{
    const imageSet = getCurrentParallaxImageSet();

    const width = window.innerWidth;
    const height = window.innerHeight;
    const margin = Math.round(height * 0.04);
    const imageHeight = height - margin * 3;
    const borderRadius = margin;

    const landing = document.getElementById("landing");

    const landingBackground = document.getElementById("landingBackground");
    landingBackground.style.height = imageHeight.toString() + "px";
    landingBackground.style.margin = margin.toString() + "px";
    landingBackground.style.marginBottom = (margin * 2).toString() + "px";
    landingBackground.style.borderRadius = borderRadius.toString() + "px";
    if ("color" in imageSet) {
        landingBackground.style.backgroundColor = imageSet.color;
        landingBackground.style.backgroundImage = "";
    } else if (("colorTop" in imageSet) && ("colorBottom" in imageSet)) {
        landingBackground.style.backgroundColor = "";
        landingBackground.style.backgroundImage = "linear-gradient(" + imageSet.colorTop + ", " + imageSet.colorBottom + ")";
    } else {
        console.error("no color info");
    }

    for (let i = 0; i < imageSet.images.length; i++) {
        const id = parallaxImageId(i);
        let el = document.getElementById(id);
        const create = el === null;
        if (create) {
            el = document.createElement("img");
            el.id = id;
            el.classList.add("parallaxImage");
        }

        const img = imageSet.images[i];
        el.style.position = "absolute";
        el.style.height = "100%";
        el.onload = function() {
            const left = (landingBackground.offsetWidth / 2) - (this.width / 2);
            this.style.left = left.toString() + "px";
        };
        el.src = img.url;
        const blur = 2 * img.factor;

        if (create) {
            landingBackground.appendChild(el);
        }
    }

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

    const landingSticker = document.getElementById("landingSticker");
    landingSticker.style.left = (margin * 4).toString() + "px";
    landingSticker.style.bottom = (margin * 4).toString() + "px";
    landingSticker.style.width = (margin * 16).toString() + "px";
    landingSticker.style.height = (margin * 4).toString() + "px";

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

    const grid = document.getElementById("portfolioGrid");
    grid.style.columnGap = margin.toString() + "px";
    const gridItems = Array.from(document.getElementsByClassName("portfolioGridItem"));
    gridItems.forEach(gridItem => {
        gridItem.style.height = (margin * 12).toString() + "px";
    });
    const gridItemBackgrounds = Array.from(document.getElementsByClassName("portfolioGridItemBackground"));
    gridItemBackgrounds.forEach(bg => {
        bg.style.height = (margin * 9).toString() + "px";
        bg.style.borderRadius = margin.toString() + "px";
    });
    const gridItemTitles = Array.from(document.getElementsByClassName("portfolioGridItemTitle"));
    gridItemTitles.forEach(title => {
        title.style.marginLeft = margin.toString() + "px";
        title.style.height = margin.toString() + "px";
    });
}

function generatePortfolio(portfolioList)
{
    const template = document.getElementsByClassName("portfolioGridItem")[0].cloneNode(true);

    Array.from(document.getElementsByClassName("portfolioGridItem")).forEach(item => {
        item.remove();
    });

    const portfolioGrid = document.getElementById("portfolioGrid");

    for (let i = 0; i < portfolioList.length; i++) {
        const port = portfolioList[i];
        const el = template.cloneNode(true);
        el.id = port.uri;
        for (let j = 0; j < el.childNodes.length; j++) {
            const child = el.childNodes[j];
            if ("classList" in child) {
                if (child.classList.contains("portfolioGridItemTitle")) {
                    child.innerHTML = port.title;
                }
            }
        }
        portfolioGrid.appendChild(el);
    }

    template.remove();

    Array.from(document.getElementsByClassName("portfolioGridItem")).forEach(item => {
        item.addEventListener("click", function(event) {
            let el = event.target;
            let tries = 0;
            while (true) {
                const id = el.id;
                if (id.length > 0) {
                    break;
                }
                el = el.parentElement;
                tries += 1;
                if (tries > 100) {
                    console.error("too many parent calls, giving up");
                    return;
                }
            }

            const uri = el.id;
            window.location.href = "/" + uri;
        })
    });
}

window.onload = function() {
    console.log("window.onload");

    httpGet("/portfolio", function(status, data) {
        if (status !== 200) {
            console.error("failed to get portfolios");
            return;
        }
        const portfolioList = JSON.parse(data);
        generatePortfolio(portfolioList);
    });

    updateCanvasSize();
    addEventListener("resize", function(event) {
        updateCanvasSize();
    });

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
        updateCanvasSize();
        updateParallax(0.0, 0.0);
    }, parallaxImageSwapSeconds * 1000);
};
