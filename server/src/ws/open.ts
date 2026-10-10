import type {ServerWebSocket} from "bun";
import type {ChatSession} from "../models/chat-session.model.ts";
import {history} from "../consts/history.ts";

export function open(ws: ServerWebSocket<ChatSession>) {
	ws.subscribe("global");

	ws.send(JSON.stringify({
		t: "history",
		items: history
	}));
}
