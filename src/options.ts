import { parseRegexList, REGEX_FLAGS } from "./common.js";
import type { Options, OptionsFormElement } from "./types";

const form = document.querySelector("form") as OptionsFormElement;
const regexErrors = document.querySelector("#regex-errors");

function loadOptions() {
    const defaults = {
        reloadRemoved: false,
        regexList: {
            type: "block",
            content: "",
        },
    } satisfies Options;

    browser.storage.local.get(defaults).then((options: Options) => {
        form.elements["reload-removed"].checked = options.reloadRemoved;
        form.elements["list-type"].value = options.regexList.type;
        form.elements["regex-list"].value = options.regexList.content;
    });
}

if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", loadOptions);
} else {
    loadOptions();
}

form.addEventListener("submit", async event => {
    event.preventDefault();
    regexErrors.replaceChildren();

    let regexListType = form.elements["list-type"].value;
    const regexListContent = form.elements["regex-list"].value;

    if (!["block", "allow"].includes(regexListType)) {
        regexListType = "block";
    }

    const regexes = parseRegexList(regexListContent);

    // Check that each regex is valid individually, to prevent weird
    // behavior when joining the regexes using string concatenation
    for (const { text: regex, index } of regexes) {
        try {
            RegExp(regex, REGEX_FLAGS);
        } catch (error) {
            if (regexErrors.children.length === 0) {
                const heading = document.createElement("h3");
                heading.innerText = "Invalid regex(es). Errors found:";

                regexErrors.appendChild(heading);
            }

            const element = document.createElement("div");
            element.innerText = `Line ${index + 1}: ${error}`;

            regexErrors.appendChild(element);
        }
    }

    if (regexErrors.children.length > 0) {
        return;
    }

    const options = {
        reloadRemoved: form.elements["reload-removed"].checked,
        regexList: {
            type: regexListType as "block" | "allow",
            content: regexListContent,
        },
    } satisfies Options;

    await browser.storage.local.set(options);
});
