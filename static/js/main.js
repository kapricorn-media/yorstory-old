function parallaxImage(url, factor)
{
    return {
        url: url,
        factor: factor,
    };
}

const parallaxImageSets = [
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

function getCurrentParallaxImageSet()
{
    return parallaxImageSets[_parallaxImageSetCurrent];
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
    content.style.paddingTop = (margin * 4).toString() + "px";

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

window.onload = function() {
    console.log("window.onload");

    updateCanvasSize();
    addEventListener("resize", function(event) {
        updateCanvasSize();
    });

    addEventListener("mousemove", function(event) {
        const offsetX = event.clientX / window.innerWidth * 2.0 - 1.0;
        const offsetY = (event.clientY / window.innerWidth * 2.0 - 0.25) * 0.75;
        updateParallax(offsetX, 0.0);
    });

    setInterval(function() {
        _parallaxImageSetCurrent = (_parallaxImageSetCurrent + 1) % parallaxImageSets.length;
        clearParallaxImages();
        updateCanvasSize();
        updateParallax(0.0, 0.0);
    }, parallaxImageSwapSeconds * 1000);
};
