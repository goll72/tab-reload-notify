export const REGEX_FLAGS: string = await (async () => {
    if ((await browser.runtime.getPlatformInfo()).os === "win") {
        return "i";
    } else {
        return "";
    }
})();

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
