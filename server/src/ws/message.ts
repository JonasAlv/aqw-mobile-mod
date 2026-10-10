import type {ChatSession} from "../models/chat-session.model.ts";
import type {ServerWebSocket} from "bun";
import {clean, webhookContent, webhookUsername} from "../util/helper.ts";
import type {Entry} from "../models/entry.model.ts";
import {history} from "../consts/history.ts";

const NAME_PATTERN = /^[A-Za-z0-9 _-]{1,32}$/;

const WEBHOOK = process.env.DISCORD_WEBHOOK_CHAT_GLOBAL;

export function message(ws: ServerWebSocket<ChatSession>, raw: string | Buffer<ArrayBuffer>) {
	let payload: any;

	try {
		payload = JSON.parse(typeof raw === "string" ? raw : raw.toString());
	} catch {
		return;
	}

	if (payload?.t !== "msg") {
		return;
	}

	const name = clean(payload.name);
	const text = clean(payload.text).slice(0, 150);

	if (!NAME_PATTERN.test(name) || text === "") {
		return;
	}

	const now = Date.now();

	if (now - ws.data.lastSent < 1500) {
		ws.send(JSON.stringify({
			t: "error",
			text: "You are sending messages too fast."
		}));
		return;
	}

	if (text === ws.data.lastText) {
		return;
	}

	ws.data.lastSent = now;
	ws.data.lastText = text;

	const entry: Entry = {name, text, ts: now};

	history.push(entry);

	if (history.length > 50) {
		history.shift();
	}

	const message = JSON.stringify({t: "msg", ...entry});

	ws.publish("global", message);
	ws.send(message);

	if (WEBHOOK) {
		fetch(WEBHOOK, {
			method: "POST",
			headers: {
				"Content-Type": "application/json"
			},
			body: JSON.stringify({
				username: webhookUsername(name),
				content: webhookContent(text),
				allowed_mentions: {
					parse: []
				}
			})
		}).catch(console.error);
	}
}