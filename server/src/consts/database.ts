import {Database} from "bun:sqlite";

export const database: Database = new Database("quests.sqlite");