import type {WebSocketHandler} from "bun";
import {open} from "./ws/open.ts";
import {message} from "./ws/message.ts";
import {close} from "./ws/close.ts";
import type {ChatSession} from "./models/chat-session.model.ts";

export const chatWebsocket: WebSocketHandler<ChatSession> = {
	maxPayloadLength: 4096,
	idleTimeout: 120,

	open: open,
	message: message,
	close: close
};