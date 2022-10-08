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
            parallaxImage("images/parallax/parallax1-1.png", 0.01),
            parallaxImage("images/parallax/parallax1-2.png", 0.05),
            parallaxImage("images/parallax/parallax1-3.png", 0.2),
            parallaxImage("images/parallax/parallax1-4.png", 0.5),
            parallaxImage("images/parallax/parallax1-5.png", 0.9),
            parallaxImage("images/parallax/parallax1-6.png", 1.2),
        ]
    },
    {
        color: "#000000",
        images: [
            parallaxImage("images/parallax/parallax2-1.png", 0.05),
            parallaxImage("images/parallax/parallax2-2.png", 0.1),
            parallaxImage("images/parallax/parallax2-3.png", 0.25),
            parallaxImage("images/parallax/parallax2-4.png", 1.0),
        ]
    },
    {
        color: "#212121",
        images: [
            parallaxImage("images/parallax/parallax3-1.png", 0.05),
            parallaxImage("images/parallax/parallax3-2.png", 0.2),
            parallaxImage("images/parallax/parallax3-3.png", 0.3),
            parallaxImage("images/parallax/parallax3-4.png", 0.8),
            parallaxImage("images/parallax/parallax3-5.png", 1.1),
        ]
    },
    {
        colorTop: "#1a1b1a",
        colorBottom: "#ffffff",
        images: [
            parallaxImage("images/parallax/parallax4-1.png", 0.05),
            parallaxImage("images/parallax/parallax4-2.png", 0.1),
            parallaxImage("images/parallax/parallax4-3.png", 0.25),
            parallaxImage("images/parallax/parallax4-4.png", 0.6),
            parallaxImage("images/parallax/parallax4-5.png", 0.75),
            parallaxImage("images/parallax/parallax4-6.png", 1.2),
        ]
    },
    {
        color: "#111111",
        images: [
            parallaxImage("images/parallax/parallax5-1.png", 0.0),
            parallaxImage("images/parallax/parallax5-2.png", 0.05),
            parallaxImage("images/parallax/parallax5-3.png", 0.1),
            parallaxImage("images/parallax/parallax5-4.png", 0.2),
            parallaxImage("images/parallax/parallax5-5.png", 0.4),
            parallaxImage("images/parallax/parallax5-6.png", 0.7),
            parallaxImage("images/parallax/parallax5-7.png", 1.2),
        ]
    },
    {
        color: "#111111",
        images: [
            parallaxImage("images/parallax/parallax6-1.png", 0.05),
            parallaxImage("images/parallax/parallax6-2.png", 0.1),
            parallaxImage("images/parallax/parallax6-3.png", 0.4),
            parallaxImage("images/parallax/parallax6-4.png", 0.7),
            parallaxImage("images/parallax/parallax6-5.png", 1.5),
        ]
    },
    // {
    //     color: "#111111",
    //     images: [
    //         parallaxImage("images/parallax/parallax7-1.png", 0.0),
    //         parallaxImage("images/parallax/parallax7-2.png", 0.1),
    //         parallaxImage("images/parallax/parallax7-3.png", 0.25),
    //         parallaxImage("images/parallax/parallax7-4.png", 0.4),
    //         parallaxImage("images/parallax/parallax7-5.png", 1.0),
    //     ]
    // }
];

const parallaxMotionMax = 100;
const parallaxImageSwapSeconds = 6;

let _parallaxImageSetCurrent = 3;

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

function updateParallaxImages()
{
    const imageSet = getCurrentParallaxImageSet();

    const landingBackground = document.getElementById("landingBackground");
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
}

function generatePortfolio(portfolioList)
{
    Array.from(document.getElementsByClassName("grid")).forEach(function(el) {
        el.remove();
    });
    Array.from(document.getElementsByClassName("gridItem")).forEach(function(el) {
        el.remove();
    });

    const portfolio = document.getElementById("portfolio");

    const grid = document.createElement("div");
    grid.classList.add("grid");

    for (let i = 0; i < portfolioList.length; i++) {
        const port = portfolioList[i];
        const gridItem = document.createElement("div");
        gridItem.id = port.uri;
        gridItem.classList.add("gridItem");

        const gridItemBackground = document.createElement("div");
        gridItemBackground.classList.add("gridItemBackground");
        gridItemBackground.style.backgroundImage = "url('" + port.cover + "')";
        gridItemBackground.style.backgroundPosition = "center";
        gridItemBackground.style.backgroundRepeat = "no-repeat";
        gridItemBackground.style.backgroundSize = "cover";
        gridItem.appendChild(gridItemBackground);

        const gridItemTitle = document.createElement("div");
        gridItemTitle.classList.add("gridItemTitle");
        gridItemTitle.innerHTML = port.title;
        gridItem.appendChild(gridItemTitle);

        grid.appendChild(gridItem);
    }

    portfolio.appendChild(grid);

    Array.from(document.getElementsByClassName("gridItem")).forEach(item => {
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
