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
		private var _pendingMessages:Vector.<String>;

		public function ApiNotificationManager() {
			_notifications = new Vector.<ApiNotification>();
			_pendingMessages = new Vector.<String>();
			AqwApi.dispatcher.addEventListener(ApiEvent.NOTIFICATION, onApiNotification);
		}

		public function init(container:Sprite):void {
			if (_initialized) return;
			_initialized = true;
			_container = container;
			for each (var msg:String in _pendingMessages) {
				showNotification(msg);
			}
			_pendingMessages.length = 0;
		}

		private function onApiNotification(e:ApiEvent):void {
			if (_initialized) {
				showNotification(e.message);
			} else {
				_pendingMessages.push(e.message);
			}
		}

		private function showNotification(message:String):void {
			var notif:ApiNotification = new ApiNotification(message);
			notif.setOnDismiss(onDismiss);
			_notifications.push(notif);
			_container.addChild(notif);
			positionNotifications();
		}

		private function onDismiss(notif:ApiNotification):void {
			var idx:int = _notifications.indexOf(notif);
			if (idx != -1) { _notifications.splice(idx, 1); }
			positionNotifications();
		}

		private function positionNotifications():void {
			var currentY:Number = 10;
			for each (var notif:ApiNotification in _notifications) {
				notif.y = currentY;
				currentY += notif.height + 8;
			}
			if (_container != null && _container.stage != null && _container.numChildren > 0) {
				var firstNotif:ApiNotification = _notifications[0];
				if (firstNotif != null) {
					_container.x = _container.stage.stageWidth - firstNotif.width - 10;
					_container.y = 10;
				}
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
