import {chatWebsocket} from "./chat";
import {questAll} from "./http/quests/quest-all.ts";
import {questMany} from "./http/quests/questMany.ts";
import {questOne} from "./http/quests/questOne.ts";
import type {Server} from "bun";
import {upgradeChat} from "./util/helper.ts";
import type {ChatSession} from "./models/chat-session.model.ts";

Bun.serve<ChatSession>({
	routes: {
		"/status": new Response("OK"),

		"/api/translate/all/quests": questAll,

		"/api/translate/quest/:language/:id": questOne,

		"/api/translate/quests/:language/:ids": questMany,
	},

	fetch(req: Request, server: Server<ChatSession>) {
		if (upgradeChat(req, server)) {
			return;
		}

		return Response.redirect("https://discord.gg/EXS5qM35ff");
	},

	websocket: chatWebsocket,
});