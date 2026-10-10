import type {ServerWebSocket} from "bun";
import type {ChatSession} from "../models/chat-session.model.ts";

export function close(ws: ServerWebSocket<ChatSession>) {
	ws.unsubscribe("global");
}