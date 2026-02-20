export type NotifyServerMessage = {
	command: "add" | "remove";
	file: string;
};

export type NotifyServerEvent = {
	type: "update" | "error";
	file: string;
};

export interface NotifyServerPort extends browser.runtime.Port {
	postMessage: (message: NotifyServerMessage) => void;
	onMessage: WebExtEvent<(response: NotifyServerEvent) => void>;
}
