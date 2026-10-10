import type {Server} from "bun";

import type {ChatSession} from "../models/chat-session.model.ts";

export function clean(value: unknown): string {
	return typeof value === "string"
		? value.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim()
		: "";
}

export function webhookUsername(name: string): string {
	const safe = name.replace(/discord|clyde|everyone|here/gi, match => match.split("").join("​"));

	return safe.length >= 2 ? safe : `${safe}_`;
}

export function webhookContent(text: string): string {
	return text.replace(/@/g, "@​");
}

export function upgradeChat(req: Request, server: Server<ChatSession>): boolean {
	return server.upgrade(req, {
		data: {
			lastSent: 0,
			lastText: ""
		}
	});
}