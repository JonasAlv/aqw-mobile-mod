package ui {

	import flash.display.Sprite;
	import flash.events.Event;
	import com.aqwapi.AqwApi;
	import com.aqwapi.events.ApiEvent;

	public class ApiNotificationManager {

		private static var _instance:ApiNotificationManager;
		public static function get instance():ApiNotificationManager {
			if (_instance == null) { _instance = new ApiNotificationManager(); }
			return _instance;
		}

		private var _container:Sprite;
		private var _notifications:Vector.<ApiNotification>;
		private var _initialized:Boolean = false;
		private var _pendingMessages:Vector.<Object>;

		public function ApiNotificationManager() {
			_notifications = new Vector.<ApiNotification>();
			_pendingMessages = new Vector.<Object>();
			AqwApi.dispatcher.addEventListener(ApiEvent.NOTIFICATION, onApiNotification);
			AqwApi.dispatcher.addEventListener(ApiEvent.STICKY_NOTIFICATION, onStickyNotification);
			AqwApi.dispatcher.addEventListener(ApiEvent.REMOVE_STICKY, onRemoveSticky);
		}

		public function init(container:Sprite):void {
			if (_initialized) return;
			_initialized = true;
			_container = container;
			for each (var item:Object in _pendingMessages) {
				showNotification(item.id, item.message, item.sticky);
			}
			_pendingMessages.length = 0;
		}

		private function onApiNotification(e:ApiEvent):void {
			if (_initialized) {
				showNotification(null, e.message, false);
			} else {
				_pendingMessages.push({ id: null, message: e.message, sticky: false });
			}
		}

		private function onStickyNotification(e:ApiEvent):void {
			// ID is stored in e.data.id
			var id:String = e.data && e.data.id ? e.data.id : "default_sticky";
			if (_initialized) {
				createSticky(id, e.message);
			} else {
				_pendingMessages.push({ id: id, message: e.message, sticky: true });
			}
		}

		private function onRemoveSticky(e:ApiEvent):void {
			var id:String = e.data && e.data.id ? e.data.id : "default_sticky";
			if (_initialized) {
				removeSticky(id);
			} else {
				// Remove it from pending if it hasn't shown yet
				for (var i:int = _pendingMessages.length - 1; i >= 0; i--) {
					if (_pendingMessages[i].id == id) {
						_pendingMessages.splice(i, 1);
					}
				}
			}
		}

		public function createSticky(id:String, message:String):void {
			if (id != null) {
				removeSticky(id);
			}
			showNotification(id, message, true);
		}

		public function removeSticky(id:String):void {
			for (var i:int = _notifications.length - 1; i >= 0; i--) {
				var notif:ApiNotification = _notifications[i];
				if (notif.id == id) {
					notif.destroy();
					_notifications.splice(i, 1);
					positionNotifications();
					return;
				}
			}
		}

		private function showNotification(id:String, message:String, sticky:Boolean):void {
			var notif:ApiNotification = new ApiNotification(id, message, sticky);
			notif.setOnDismiss(onDismiss);
			_notifications.push(notif);
			_container.addChild(notif);
			positionNotifications();
		}

		private function onDismiss(notif:ApiNotification):void {
			var idx:int = _notifications.indexOf(notif);
			if (idx != -1) { _notifications.splice(idx, 1); }
			// notif removes itself from parent in onFadeOut, no need to do it here
			positionNotifications();
		}

		private function positionNotifications():void {
			var currentY:Number = 0;
			for each (var notif:ApiNotification in _notifications) {
				notif.y = currentY;
				currentY += notif.height + 6;
			}
			// Only center if we have active notifications
			if (_container != null && _container.stage != null && _notifications.length > 0) {
				_container.x = (_container.stage.stageWidth - 280) / 2;
				_container.y = 10;
			}
		}

		public function destroy():void {
			for each (var notif:ApiNotification in _notifications) {
				notif.destroy();
			}
			_notifications.length = 0;
			if (_container != null && _container.parent != null) {
				_container.parent.removeChild(_container);
			}
			_container = null;
			_initialized = false;
		}
	}
}
