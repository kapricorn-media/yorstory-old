const IMAGE_CHANGE_SPEED_MS = 300;

function generateEntry(entry)
{
    const landingBackground = document.getElementById("landingBackground");
    Array.from(document.getElementsByClassName("landingProjectImage")).forEach(el => {
        el.remove();
    });

    const el = document.createElement("img");
    el.classList.add("landingProjectImage");
    el.style.position = "absolute";
    el.style.width = "100%";
    el.src = entry.landing;
    landingBackground.appendChild(el);

    const subprojectTemplate = document.getElementsByClassName("subproject")[0];

    const portfolio = document.getElementById("portfolio");
    for (let i = 0; i < entry.subprojects.length; i++) {
        const subproject = entry.subprojects[i];
        const el = subprojectTemplate.cloneNode(true);
        el.querySelector(".subprojectNumberText").innerHTML = (i + 1).toString();
        el.querySelector(".subprojectTitle").innerHTML = subproject.name;
        el.querySelector(".subprojectText").innerHTML = subproject.description;

        const grid = document.createElement("div");
        grid.classList.add("grid");
        for (let i = 0; i < subproject.images.length; i++) {
            const img = subproject.images[i];
            const gridItem = document.createElement("div");
            // gridItem.id = i.toString();
            gridItem.classList.add("gridItem");
            const gridItemBackground = document.createElement("div");
            gridItemBackground.classList.add("gridItemBackground");
            gridItemBackground.style.backgroundImage = "url('" + img + "')";
            gridItemBackground.style.backgroundPosition = "center";
            gridItemBackground.style.backgroundRepeat = "no-repeat";
            gridItemBackground.style.backgroundSize = "cover";
            gridItem.appendChild(gridItemBackground);
            grid.appendChild(gridItem);

            gridItem.addEventListener("click", function(event) {
                console.log(event);
            });
        }

        el.appendChild(grid);
        portfolio.appendChild(el);
    }

    subprojectTemplate.remove();
}
