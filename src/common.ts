import type { Options } from "./types";

export const DEFAULT_OPTIONS: Options = {
    reloadRemoved: false,
    regexList: {
        type: "block",
        content: "",
    },
};

export async function getRegexFlags() {
    if ((await browser.runtime.getPlatformInfo()).os === "win") {
        return "i";
    } else {
        return "";
    }
}

export function parseRegexList(
    regexList: string,
): { text: string; index: number }[] {
    return regexList
        .split("\n")
        .map((line, index) => ({ text: line, index: index }))
        .filter(
            ({ text, index: _ }) =>
                text.trim().length > 0 && !text.startsWith("#"),
        );
}

export function isFirefox() {
    return navigator.userAgent.includes("Firefox");
}

export function isChrome() {
    return navigator.userAgent.includes("Chrome");
}
