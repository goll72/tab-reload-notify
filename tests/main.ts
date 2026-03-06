import path from "node:path";
import test from "node:test";
import assert from "node:assert";
import fs from "node:fs/promises";
import process from "node:process";
import crypto from "node:crypto";

import type { Browser, Page, WebWorker } from "puppeteer";
import puppeteer from "puppeteer";

import type { FileHierarchy } from "./hierarchy.ts";
import { dir, file, makeHierarchy } from "./hierarchy.ts";

import type { Options } from "./extension/types.d.ts";
import { DEFAULT_OPTIONS } from "./extension/common.ts";

process.loadEnvFile();

let browser: Browser;
let extHandle: Page | WebWorker;

// "Slowness factor", can be adjusted to circumvent race
// conditions in the test code when running on slow machines
const F: number = Math.abs(Number(process.env.F)) || 1;

const EXT_PATH = path.resolve(process.env.EXT_PATH ?? "..");
const BROWSER_NAME = process.env.BROWSER ?? "firefox";

const sleep = (ms: number) =>
    new Promise(resolve => setTimeout(resolve, F * ms));

switch (BROWSER_NAME) {
    case "firefox": {
        const extUUID = crypto.randomUUID();

        browser = await puppeteer.launch({
            browser: "firefox",
            dumpio: true,
            extraPrefsFirefox: {
                "devtools.console.stdout.content": true,
                // "devtools.console.stdout.chrome": true,
                "extensions.webextensions.uuids": JSON.stringify({
                    [process.env.FF_EXT_ID as string]: extUUID,
                }),
            },
            enableExtensions: true,
        });

        // Firefox expects a zip file
        await browser.installExtension(path.join(EXT_PATH, "extension.zip"));

        extHandle = await browser.newPage();

        // XXX: using `await` here blocks for some reason, so sleep instead
        //
        // NOTE: we navigate to an extension page because Firefox doesn't seem
        // to fire a "targetcreated" event when the extension gets loaded
        extHandle.goto(`moz-extension://${extUUID}/options.html`);
        await sleep(3000);

        break;
    }

    case "chrome": {
        browser = await puppeteer.launch({
            browser: "chrome",
            pipe: true,
            dumpio: true,
            enableExtensions: true,
            args: ["--enable-unsafe-extension-debugging"],
        });

        // Chrome expects a directory
        await browser.installExtension(path.join(EXT_PATH, "extension"));

        const target = await browser
            .waitForTarget(
                x =>
                    x.type() === "service_worker" &&
                    x.url().startsWith("chrome-extension://"),
            )
            .then(x => x.worker());

        extHandle = target as WebWorker;

        break;
    }

    default:
        throw new Error(
            "Invalid argument: specify a valid browser (either `firefox` or `chrome`) as argument",
        );
}

const setOptions = async (options: Options) => {
    await extHandle.evaluate(async options => {
        await (browser as any).storage.local.set(options);
    }, options);
};

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

        await page.close();

        await fs.rm(dir, { recursive: true, force: true });
    };
};

await test(
    " non-existent file gets loaded ",
    withPage(file("non-existent"), async (page, loadCount, abs) => {
        await fs.rm("non-existent").catch(() => Promise.resolve());

        await sleep(400);
        await page.goto(`file://${abs("non-existent")}`).then(
            _ => Promise.reject(),
            _ => Promise.resolve(),
        );

        await sleep(400);
        const prevCount = loadCount();

        await fs.writeFile("non-existent", "A");

        await sleep(400);
        assert.strictEqual(loadCount(), prevCount + 1);
    }),
);

await test(
    " pre-existing file gets reloaded ",
    withPage(file("ok"), async (page, loadCount, abs) => {
        await fs.writeFile("ok", "A");

        await sleep(400);
        await page.goto(`file://${abs("ok")}`);

        await sleep(400);
        const prevCount = loadCount();

        await fs.appendFile("ok", "B");

        await sleep(400);
        assert.strictEqual(loadCount(), prevCount + 1);
    }),
);

await test(
    " directory gets reloaded on internal child rename ",
    withPage(dir("a", [file("b"), dir("c")]), async (page, loadCount, abs) => {
        await page.goto(`file://${abs("a")}`);

        await sleep(400);
        const prevCount = loadCount();

        await fs.rename("a/b", "a/d");

        await sleep(400);
        assert.strictEqual(loadCount(), prevCount + 1);
    }),
);

await test(
    " directory gets reloaded on external child rename ",
    withPage(
        dir("a", [dir("b", [file("c")])]),
        async (page, loadCount, abs) => {
            await page.goto(`file://${abs("a/b")}`);

            await sleep(400);
            const prevCount = loadCount();

            await fs.rename("a/b/c", "a/d");

            await sleep(400);
            assert.strictEqual(loadCount(), prevCount + 1);
        },
    ),
);

await test(
    " removed file does NOT get reloaded (when config option is NOT set) ",
    withPage(dir("a", [file("b")]), async (page, loadCount, abs) => {
        await page.goto(`file://${abs("a/b")}`);

        await sleep(400);
        const prevCount = loadCount();

        await fs.rm("a/b");

        await sleep(400);
        assert.strictEqual(loadCount(), prevCount);
    }),
);

await test(
    " removed file gets reloaded (when config option is set) ",
    withPage(dir("a", [file("b")]), async (page, loadCount, abs) => {
        await setOptions({ ...DEFAULT_OPTIONS, reloadRemoved: true });

        await sleep(400);
        await page.goto(`file://${abs("a/b")}`);

        await sleep(400);
        const prevCount = loadCount();

        await fs.rm("a/b");

        await sleep(400);
        assert.strictEqual(loadCount(), prevCount + 1);

        await setOptions(DEFAULT_OPTIONS);
    }),
);

await test(
    " file on blocklist does NOT get reloaded ",
    withPage(
        dir("foo", [file("bar"), file("baz"), file("quux")]),
        async (page, loadCount, abs) => {
            await setOptions({
                ...DEFAULT_OPTIONS,
                regexList: { type: "block", content: ".*/foo/bar\n" },
            });

            await sleep(400);
            await page.goto(`file://${abs("foo/bar")}`);

            await sleep(400);
            const prevCount = loadCount();

            await fs.appendFile("foo/bar", "A");

            await sleep(400);
            assert.strictEqual(loadCount(), prevCount);

            await setOptions(DEFAULT_OPTIONS);
        },
    ),
);

await extHandle.close();
await browser.close();
