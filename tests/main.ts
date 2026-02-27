import path from "node:path";
import test from "node:test";
import assert from "node:assert";
import fs from "node:fs/promises";
import process from "node:process";

import type { Browser, Page } from "puppeteer";
import puppeteer, { ProtocolError } from "puppeteer";

import type { FileHierarchy } from "./hierarchy.ts";
import { dir, file, makeHierarchy } from "./hierarchy.ts";

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

const browser = await (async () => {
    const EXT_PATH = path.resolve(process.env.EXT_PATH ?? "..");
    const BROWSER_NAME = process.env.BROWSER ?? "firefox";

    let browser: Browser;

    switch (BROWSER_NAME) {
        case "firefox":
            browser = await puppeteer.launch({
                browser: "firefox",
                dumpio: true,
                extraPrefsFirefox: {
                    "devtools.console.stdout.content": true,
                    "devtools.console.stdout.chrome": true,
                },
                enableExtensions: true,
            });

            // Firefox expects a zip file
            browser.installExtension(path.join(EXT_PATH, "extension.zip"));

            return browser;

        case "chrome":
            browser = await puppeteer.launch({
                browser: "chrome",
                pipe: true,
                dumpio: true,
                enableExtensions: true,
                args: ["--enable-unsafe-extension-debugging"],
            });

            // Chrome expects a directory
            browser.installExtension(path.join(EXT_PATH, "extension"));

            return browser;

        default:
            throw new Error(
                "Invalid argument: specify a valid browser (either `firefox` or `chrome`) as argument",
            );
    }
})();

// Wrapper for test functions that creates a new page, creates a file hierarchy following
// `hierarchy`, and then runs the function with the test logic that was passed in.
//
// This function also allows tests to deal with relative paths and have them be converted
// to absolute paths automatically by using the `abs` function.
const withPage = (
    hierarchy: FileHierarchy,
    inner: (
        page: Page,
        loadCount: () => number,
        abs: (path: string) => string,
    ) => Promise<void>,
): (() => Promise<void>) => {
    let dir: string;
    const owd = process.cwd();

    if (process.platform === "win32") {
        if (process.env.TMP === undefined) {
            throw new Error(
                "Invalid argument: set the TMP environment variable",
            );
        }

        dir = path.join(process.env.TMP, "trn-tests-hier");
    } else {
        dir = "/tmp/trn-tests-hier";
    }

    const abs = (name: string) => {
        return path.join(dir, name);
    };

    return async () => {
        try {
            await fs.mkdir(dir);
        } catch (error) {
            if (error.code !== "EEXIST") throw error;
        }

        await makeHierarchy(dir, hierarchy);

        let loadCount = 0;
        const page = await browser.newPage();

        page.on("load", () => loadCount++);

        process.chdir(dir);
        await inner(page, () => loadCount, abs);
        process.chdir(owd);

        page.close();

        await fs.rm(dir, { recursive: true, force: true });
    };
};

await test(
    " non-existent file gets loaded ",
    withPage(file("non-existent"), async (page, loadCount, abs) => {
        await fs.rm("non-existent").catch(() => Promise.resolve());

        await sleep(300);
        await page.goto(`file://${abs("non-existent")}`).then(
            _ => Promise.reject(),
            x => Promise.resolve(assert(x instanceof ProtocolError)),
        );

        await sleep(300);
        assert.strictEqual(loadCount(), 0);

        await fs.writeFile("non-existent", "A");

        await sleep(300);
        assert.strictEqual(loadCount(), 1);
    }),
);

await test(
    " pre-existing file gets reloaded ",
    withPage(file("ok"), async (page, loadCount, abs) => {
        await fs.writeFile("ok", "A");

        await sleep(300);
        await page.goto(`file://${abs("ok")}`);

        await sleep(300);
        assert.strictEqual(loadCount(), 1);

        await fs.appendFile("ok", "B");

        await sleep(300);
        assert.strictEqual(loadCount(), 2);
    }),
);

await test(
    " directory gets reloaded on internal child rename ",
    withPage(
        dir("a", [file("b"), dir("c")]),
        async (page, loadCount, abs) => {},
    ),
);

await browser.close();
