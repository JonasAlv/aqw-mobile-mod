package {
	import flash.desktop.NativeApplication;

	public class Config {

		public static const GAME_BASE_URL:String = "https://game.aq.com/game/";

		public static const API_VERSION_URL:String = GAME_BASE_URL + "api/data/gameversion";
		public static const API_LOGIN_URL:String = GAME_BASE_URL + "api/login/now";

		public static const APP_VERSION:String = getVersion();

		private static function getVersion():String {
			const appDesc:XML = NativeApplication.nativeApplication.applicationDescriptor;
			const ns:Namespace = appDesc.namespace();
			
			return "v" + appDesc.ns::versionNumber;
		}

		public static const GITHUB_RELEASES_URL:String = "https://api.github.com/repos/anthony-hyo/aqw-mobile/releases/latest";
		
		public var option_pagination:Boolean = true;
		public var option_equipped_on_top:Boolean = true;

		public var option_animation_monster_off:Boolean = false;
		public var option_animation_helm_off:Boolean = false;
		public var option_animation_armor_off:Boolean = false;
		public var option_animation_cape_off:Boolean = false;
		public var option_animation_hair_off:Boolean = false;
		public var option_animation_misc_off:Boolean = false;
		public var option_animation_pet_off:Boolean = false;
		public var option_animation_weapon_off:Boolean = false;

		public var option_filter_off:Boolean = false;

		public var option_language:String = "en";
		public var option_skill_tooltips:Boolean = true;
		public var option_disable_cutscenes:Boolean = false;
		public var option_slow_walk:Boolean = false;
		
		public var option_player_animation_skill:Boolean = true;
		public var option_player_animation_aura:Boolean = true;
		
		public var option_monster_animation_skill:Boolean = true;
		public var option_monster_animation_aura:Boolean = true;
		
		public var option_self_animation_skill:Boolean = true;
		public var option_self_animation_aura:Boolean = true;

	}

}