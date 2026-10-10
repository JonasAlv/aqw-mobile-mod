import type {Quest} from "./quest.model.ts";

export interface QuestTranslation extends Quest {
	language: string;
}