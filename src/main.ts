import "./browser-polyfill.js";

import {
    getRegexFlags,
    parseRegexList,
    isFirefox,
    isChrome,
    isWindows,
    DEFAULT_OPTIONS,
} from "./common.js";

import type { NotifyServerPort, Options } from "./types";

// Previous file opened on any given tab
const previousOpenFile: Map<number, string> = new Map();
// All tabs that have a given file open
const openTabs: Map<string, number[]> = new Map();

const notifyServer = browser.runtime.connectNative(
    "tab_reload_notify_server",
) as NotifyServerPort;

let options: Options = DEFAULT_OPTIONS;
let regex: RegExp | undefined;

const removeFileAssociation = (tabId: number, file: string) => {
    const tabs = openTabs.get(file);
    const tabIndex = tabs?.indexOf(tabId);

    if (tabIndex === undefined || tabIndex === -1) {
        throw new Error();
    }

    if (tabIndex === 0) {
        openTabs.delete(file);

        console.log(`Requesting to stop watching \`${file}'...`);

        notifyServer.postMessage({
            command: "remove",
            file,
        });
    } else {
        tabs?.splice(tabIndex, 1);
    }
};

const getFileFromUrl = (url: string): string | undefined => {
    let result: string;

    if (isFirefox()) {
        // NOTE: Firefox supports jar:file:// URLs as well as
        // regular file:// URLs, allowing for zip file navigation
        const FILE_REGEX = /file:\/\/\/(.*)|jar:file:\/\/\/([^!]+)!\/.+/;
        const matches = url.match(FILE_REGEX);

        if (!matches) {
            return undefined;
        }

        // NOTE: we have to decode the URI after it passes through
        // the regex to handle cases such as a percent-encoded '!'
        result = decodeURI(matches[1]);
    } else if (isChrome()) {
        const FILE_URI_PREFIX = "file:///";

        if (url.startsWith(FILE_URI_PREFIX)) {
            result = decodeURI(url.substring(FILE_URI_PREFIX.length));
        } else {
            return undefined;
        }
    } else {
        throw new Error("Unsupported browser");
    }

    // TODO: handle UNC paths
    if (!isWindows()) {
        result = `/${result}`;
    }

    result = result.replaceAll(/\/+/g, "/").replace(/\/$/, "");

    if (isWindows()) {
        result = result.replaceAll(/\//g, "\\");
    }

    return result;
};

const updateTab = (id: number, tab: browser.tabs.Tab) => {
    const previous = previousOpenFile.get(id);

    if (!tab.url) {
        return;
    }

    const file = getFileFromUrl(tab.url);

    if (file) {
        // To make the code simpler, we will add the relevant entries in the maps
        // even if the commands sent to the inotify server end up erroring out,
        // rolling back the changes when we receive an error response.
        if (!openTabs.has(file)) {
            if (options.regexList.type === "block" && regex?.test(file)) {
                return;
            }

            if (options.regexList.type === "allow" && !regex?.test(file)) {
                return;
            }

            console.log(`Requesting to watch \`${file}'...`);

            notifyServer.postMessage({
                command: "add",
                file,
            });

            openTabs.set(file, [id]);
        } else {
            openTabs.get(file)?.push(id);
        }

        previousOpenFile.set(id, file);
    } else {
        previousOpenFile.delete(id);
    }

    if (previous) {
        if (previous === file) {
            return;
        }

        removeFileAssociation(id, previous);
    }
};

(async () => {
    // All active tabs when the extension is loaded
    const allTabs = await browser.tabs.query({ active: true });

    for (const tab of allTabs) {
        if (tab.id && tab.id !== browser.tabs.TAB_ID_NONE) {
            updateTab(tab.id, tab);
        }
    }
})();

browser.tabs.onUpdated.addListener((id, changeInfo, tab) => {
    if (!changeInfo.url) {
        return;
    }

    updateTab(id, tab);
});

browser.tabs.onRemoved.addListener((id, _) => {
    const file = previousOpenFile.get(id);

    if (!file) {
        return;
    }

    previousOpenFile.delete(id);
    removeFileAssociation(id, file);
});

notifyServer.onMessage.addListener(async event => {
    switch (event.type) {
        case "update": {
            console.log(`Received update event for \`${event.file}'...`);

            const tabs = openTabs.get(event.file) ?? [];

            await Promise.all(
                tabs.map(tab =>
                    browser.tabs.get(tab).then(info => {
                        // Discarded tabs will be reloaded when they're activated
                        if (info.discarded) {
                            return Promise.resolve();
                        } else {
                            return browser.tabs.reload(tab);
                        }
                    }),
                ),
            );

            break;
        }
        case "error": {
            console.error(`Couldn't watch \`${event.file}'!`);

            const tabs = openTabs.get(event.file) ?? [];

            // Roll back changes, since the file couldn't be watched
            for (const tab of tabs) {
                previousOpenFile.delete(tab);
            }

            openTabs.delete(event.file);

            break;
        }
    }
});

const loadOptions = async () => {
    console.log("Loading options...");

    const prevReloadRemoved = options.reloadRemoved;

    await browser.storage.local.get(DEFAULT_OPTIONS).then(x => {
        options = x as Options;
    });

    if (prevReloadRemoved !== options.reloadRemoved) {
        console.log(
            "Sending reconfigure(reloadRemoved) event to the server...",
        );

        notifyServer.postMessage({
            command: "reconfigure",
            reloadRemoved: options.reloadRemoved,
        });
    }

    const regexList = parseRegexList(options.regexList.content).map(
        x => x.text,
    );

    if (regexList.length === 0) {
        regex = undefined;
    } else {
        regex = RegExp(regexList.join("|"), await getRegexFlags());
    }
};

browser.storage.onChanged.addListener(loadOptions);

loadOptions();
