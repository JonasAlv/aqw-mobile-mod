import {languages} from "../../consts/languages.ts";
import type {QuestTranslation} from "../../models/quest-translation.model.ts";
import {database} from "../../consts/database.ts";

export function questMany(req: Request) {
	const language: string = (req as any).params.language;

	if (!languages.includes(language)) {
		return Response.json({
			error: `invalid language`
		}, {
			status: 400
		});
	}

	const ids: number[] = (req as any).params.ids
		.split(",")
		.map((i: string) => Number(i))
		.filter((i: number) => Number.isInteger(i) && i > 0 && i < 100000);

	if (ids.length <= 0 || ids.length > 50) {
		return Response.json({
			error: `invalid ids`
		}, {
			status: 400
		});
	}

	const placeholders: string = ids.map((_, i) => `$id${i}`).join(",");

	const params: Record<string, string | number> = {$language: language};

	ids.forEach((id, i) => params[`$id${i}`] = id);

	const quest_translation: QuestTranslation[] = database.query<QuestTranslation, any>(`SELECT quest_id, name, description, end_text FROM quests_translations WHERE quest_id IN (${placeholders})AND language = $language`).all(params);

	return Response.json(quest_translation);
}