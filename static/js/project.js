function generateProjectImages(projectImages)
{
    const template = document.getElementsByClassName("gridItem")[0].cloneNode(true);

    Array.from(document.getElementsByClassName("gridItem")).forEach(item => {
        item.remove();
    });

    const projectGrid = document.getElementById("grid");

    for (let i = 0; i < projectImages.length; i++) {
        const port = projectImages[i];
        const el = template.cloneNode(true);
        el.id = i.toString();
        for (let j = 0; j < el.childNodes.length; j++) {
            const child = el.childNodes[j];
            if ("classList" in child) {
                if (child.classList.contains("gridItemBackground")) {
                	child.style.backgroundImage = "url('" + projectImages[i] + "')";
                	child.style.backgroundPosition = "center";
                	child.style.backgroundRepeat = "no-repeat";
                	child.style.backgroundSize = "cover";
                }
            }
        }
        projectGrid.appendChild(el);
    }

    template.remove();
}
