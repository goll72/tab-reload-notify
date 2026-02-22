export type NotifyServerMessage =
    | {
          command: "add" | "remove";
          file: string;
      }
    | {
          command: "reconfigure";
          reloadRemoved?: boolean;
      };

export type NotifyServerEvent = {
    type: "update" | "error";
    file: string;
};

export interface NotifyServerPort extends browser.runtime.Port {
    postMessage: (message: NotifyServerMessage) => void;
    onMessage: WebExtEvent<(response: NotifyServerEvent) => void>;
}

// Types related to extension options

export interface OptionsFormControlsCollection
    extends HTMLFormControlsCollection {
    "reload-removed": HTMLInputElement;
    "list-type": RadioNodeList;
    "regex-list": HTMLTextAreaElement;
}

export interface OptionsFormElement extends HTMLFormElement {
    readonly elements: OptionsFormControlsCollection;
}

export type Options = {
    reloadRemoved: boolean;
    regexList: {
        type: "block" | "allow";
        content: string;
    };
};
