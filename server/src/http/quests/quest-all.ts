import {languages} from "../../consts/languages.ts";
import type {Quest} from "../../models/quest.model.ts";
import {database} from "../../consts/database.ts";
import {Translator} from "google-translate-api-x";

export async function questAll(_: Request) {
	for (const language of languages) {
		const quests: Quest[] = database
			.query<Quest, [string]>("SELECT quest_id, name, description, end_text FROM quests WHERE quest_id NOT IN (SELECT quest_id FROM quests_translations WHERE language = ?1)")
			.all(language);

		const insertQuest = database.query("INSERT INTO quests_translations (quest_id, language, name, description, end_text) VALUES ($quest_id, $language, $name, $description, $end_text)");

		const translator = new Translator({
			from: "en",
			to: language
		});

		for (const quest of quests) {
			try {
				const [nameRes, descRes, endRes] = await translator.translate([
					quest.name,
					quest.description,
					quest.end_text,
				]);

				insertQuest.run({
					$quest_id: quest.quest_id,
					$language: language,
					$name: nameRes!.text,
					$description: descRes!.text,
					$end_text: endRes!.text,
				});
			} catch (err) {
				return Response.json(err);
			}
		}
	}

	return Response.json("Ok");
}