import { parseRegexList, DEFAULT_OPTIONS, REGEX_FLAGS } from "./common.js";
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

browser.tabs.onUpdated.addListener((id, changeInfo, tab) => {
    if (!changeInfo.url) {
        return;
    }

    // XXX: handle `jar:file://!` URLs (they can have trailing slashes [before the !] too)
    const fileUriPrefix = "file:///";
    const previous = previousOpenFile.get(id);

    let file: string | undefined;

    // To make the code simpler, we will add the relevant entries in the maps
    // even if the commands sent to the inotify server end up erroring out,
    // rolling back the changes when we receive an error response.
    if (tab.url?.startsWith(fileUriPrefix)) {
        // NOTE: the browser already canonicalizes `..` and `.` but we still have
        // to canonicalize repeated and trailing slashes
        file = `/${tab.url.substring(fileUriPrefix.length)}`
            .replaceAll(/\/+/g, "/")
            .replace(/\/$/, "");

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
        // List of all tabs that are currently open on the
        // same file that was previously opened on this tab
        //
        // At this point, the list should also include this tab, so we have to remove it
        const tabs = openTabs.get(previous);
        const tabIndex = tabs?.indexOf(id);

        if (tabIndex === undefined || tabIndex === -1) {
            throw new Error();
        }

        if (previous === file) {
            return;
        }

        if (tabIndex === 0) {
            openTabs.delete(previous);

            console.log(`Requesting to stop watching \`${previous}'...`);

            notifyServer.postMessage({
                command: "remove",
                file: previous,
            });
        } else {
            tabs?.splice(tabIndex, 1);
        }
    }
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

function loadOptions() {
    const prevReloadRemoved = options.reloadRemoved;

    browser.storage.local.get(DEFAULT_OPTIONS).then(x => {
        options = x as Options;
    });

    if (prevReloadRemoved !== options.reloadRemoved) {
        notifyServer.postMessage({
            command: "reconfigure",
            reloadRemoved: options.reloadRemoved,
        });
    }

    const regexList = parseRegexList(options.regexList.content);

    if (regexList.length === 0) {
        regex = undefined;
    } else {
        regex = RegExp(regexList.join("|"), REGEX_FLAGS);
    }
}

browser.storage.onChanged.addListener(loadOptions);

loadOptions();
