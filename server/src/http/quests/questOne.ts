import type {QuestTranslation} from "../../models/quest-translation.model.ts";
import {database} from "../../consts/database.ts";
import {languages} from "../../consts/languages.ts";

export function questOne(req: Request) {
	const language: string = (req as any).params.language;

	if (!languages.includes(language)) {
		return Response.json({
			error: `invalid language`
		}, {
			status: 400
		});
	}

	const id: number = Number((req as any).params.id);

	if (!Number.isInteger(id) || id <= 0 || id >= 100000) {
		return Response.json({
			error: `invalid id`
		}, {
			status: 400
		});
	}

	const quest_translation: QuestTranslation | null = database.query<QuestTranslation, any>("SELECT quest_id, name, description, end_text FROM quests_translations WHERE quest_id = $quest_id AND language = $language").get({
		$quest_id: id,
		$language: language,
	});

	return Response.json(quest_translation);
}