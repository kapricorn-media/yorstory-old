function parallaxImage(url, factor)
{
    return {
        url: url,
        factor: factor,
    };
}

function parallaxImageId(i)
{
    return "parallaxImage" + i.toString();
}

const parallaxImages = [
    parallaxImage("images/parallax1.png", 0.01),
    parallaxImage("images/parallax2.png", 0.05),
    parallaxImage("images/parallax3.png", 0.2),
    parallaxImage("images/parallax4.png", 0.75),
    parallaxImage("images/parallax5.png", 1.0),
];

// offsetX, offsetY is in the range [-1, 1]
function updateParallax(offsetX, offsetY)
{
    for (let i = 0; i < parallaxImages.length; i++) {
        const img = parallaxImages[i];

        const offsetXPixels = offsetX * 100 * img.factor;
        const offsetYPixels = offsetY * 100 * img.factor;
        const el = document.getElementById(parallaxImageId(i));
        el.style.transform = "translate(" + offsetXPixels.toString() + "px, " + offsetYPixels.toString() + "px)";
    }
}

function updateCanvasSize()
{
    const width = window.innerWidth;
    const height = window.innerHeight;
    const margin = Math.round(height * 0.04);
    const imageWidth = width - margin * 2;
    const imageHeight = height - margin * 2;
    const borderRadius = margin * 0.5;

    const landing = document.getElementById("landing");

    const landingBackground = document.getElementById("landingBackground");
    landingBackground.style.width = imageWidth.toString() + "px";
    landingBackground.style.height = imageHeight.toString() + "px";
    landingBackground.style.margin = margin.toString() + "px";
    landingBackground.style.borderRadius = borderRadius.toString() + "px";

    for (let i = 0; i < parallaxImages.length; i++) {
        const id = parallaxImageId(i);
        let el = document.getElementById(id);
        const create = el === null;
        if (create) {
            el = document.createElement("div");
            el.id = id;
        }

        const img = parallaxImages[i];
        el.style.position = "absolute";
        el.style.width = "100%";
        el.style.height = "100%";
        el.style.backgroundImage = "url('" + img.url + "')";
        el.style.backgroundSize = "contain";
        el.style.backgroundRepeat = "no-repeat";
        el.style.backgroundPosition = "bottom center";

        if (create) {
            landingBackground.appendChild(el);
        }
    }
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
        updateParallax(offsetX, offsetY);
    });
};
