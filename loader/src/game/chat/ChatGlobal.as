package game.chat {

	import air.net.WebSocket;

	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.display.Stage;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.KeyboardEvent;
	import flash.events.MouseEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.TimerEvent;
	import flash.events.WebSocketEvent;
	import flash.text.TextField;
	import flash.ui.Keyboard;
	import flash.utils.Timer;
	import flash.utils.getTimer;

	import util.Helper;

	public class ChatGlobal {

		private static const MAX_LENGTH:int = 200;
		private static const RECONNECT_MS:int = 5000;
		private static const MAX_PENDING:int = 100;
		
		private const timer:Timer = new Timer(1000);

		public function ChatGlobal(pocket:Pocket) {
			this.pocket = pocket;

			this.stage = pocket.game.stage;

			this.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown, true, 1000, true);
			this.stage.addEventListener(MouseEvent.CLICK, onClick, true, 1000, true);

			this.timer.addEventListener(TimerEvent.TIMER, onTick);
			this.timer.start();
		}
		
		private var pocket:Pocket;
		private var stage:Stage;
		private var socket:WebSocket;
		private var connected:Boolean = false;
		private var connecting:Boolean = false;
		private var nextAttempt:int = 0;
		private var channelReady:Boolean = false;
		private var pending:Vector.<Object> = new Vector.<Object>();

		private function get enabled():Boolean {
			return Config.GLOBAL_CHAT_URL != "" && this.pocket.config.option_global_chat;
		}

		private function registerChannel():void {
			const chn:Object = this.pocket.game.chatF.chn;

			if (this.channelReady || chn == null || chn.zone == null) {
				return;
			}

			chn.global = {};
			chn.global.col = "FF9933";
			chn.global.str = "global";
			chn.global.typ = "message";
			chn.global.tag = "Global";
			chn.global.rid = 0;
			chn.global.act = 1;

			this.channelReady = true;
		}

		private function connect():void {
			this.connecting = true;

			try {
				this.socket = new WebSocket();

				this.socket.addEventListener(Event.CONNECT, onConnect);
				this.socket.addEventListener(WebSocketEvent.DATA, onData);
				this.socket.addEventListener(Event.CLOSE, onClose);
				this.socket.addEventListener(IOErrorEvent.IO_ERROR, onError);
				this.socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);

				this.socket.connect(Config.GLOBAL_CHAT_URL);
			} catch (error:Error) {
				onClosed();
			}
		}

		private function disconnect():void {
			if (this.socket != null) {
				try {
					this.socket.close();
				} catch (error:Error) {
				}
			}

			onClosed();
		}

		private function onError(e:*):void {
			onClosed();
		}

		private function onClosed():void {
			if (this.socket != null) {
				this.socket.removeEventListener(Event.CONNECT, onConnect);
				this.socket.removeEventListener(WebSocketEvent.DATA, onData);
				this.socket.removeEventListener(Event.CLOSE, onClose);
				this.socket.removeEventListener(IOErrorEvent.IO_ERROR, onError);
				this.socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);

				this.socket = null;
			}

			this.connected = false;
			this.connecting = false;
			this.nextAttempt = getTimer() + RECONNECT_MS;
		}

		private function enqueue(name:String, text:String):void {
			if (text == null || text == "") {
				return;
			}

			if (this.pending.length >= MAX_PENDING) {
				this.pending.shift();
			}

			this.pending.push({name: name, text: text});
		}

		private function flush():void {
			if (!this.channelReady || this.pending.length == 0) {
				return;
			}

			var entry:Object;

			while (this.pending.length > 0) {
				entry = this.pending[0];

				try {
					if (entry.name == null) {
						this.pocket.game.chatF.pushMsg("warning", Helper.escapeHtml(entry.text), "SERVER", "", 0);
					} else {
						this.pocket.game.chatF.pushMsg("global", Helper.escapeHtml(entry.text), Helper.escapeHtml(entry.name), "", 0);
					}
				} catch (error:Error) {
					return;
				}

				this.pending.shift();
			}
		}

		private function send(text:String):void {
			const message:String = text.length > MAX_LENGTH ? text.substr(0, MAX_LENGTH) : text;

			if (!this.enabled || !this.connected) {
				enqueue(null, "Global chat is not connected.");
				flush();
				return;
			}

			this.socket.sendMessage(WebSocket.fmtTEXT, JSON.stringify({
				t: "msg",
				name: this.pocket.game.sfc.myUserName,
				text: message
			}));
		}

		private function consume():Boolean {
			if (!this.pocket.game || !this.pocket.game.ui || !this.pocket.game.ui.mcInterface) {
				return false;
			}

			const ui:* = this.pocket.game.ui.mcInterface;
			const field:TextField = (this.pocket.game.intChatMode ? ui.ncText : ui.te) as TextField;

			if (field == null) {
				return false;
			}

			var text:String = null;

			const chatF:* = this.pocket.game.chatF;

			if (chatF != null && chatF.chn != null && chatF.chn.global != null && chatF.chn.cur === chatF.chn.global) {
				const typed:String = field.text.replace(/^\s+|\s+$/g, "");

				if (typed != "" && typed.charAt(0) != "/") {
					text = typed;
				}
			}

			if (text == null) {
				return false;
			}

			send(text.replace(/\s+/g, " "));

			field.text = "";

			this.stage.focus = null;

			return true;
		}

		private function onTick(e:TimerEvent):void {
			if (!this.enabled) {
				if (this.connected || this.connecting) {
					disconnect();
				}

				return;
			}

			if (!this.pocket.game || !this.pocket.game.chatF) {
				return;
			}

			registerChannel();

			if (!this.connected && !this.connecting && getTimer() >= this.nextAttempt) {
				connect();
			}

			flush();
		}

		private function onConnect(e:Event):void {
			this.connecting = false;
			this.connected = true;
		}

		private function onClose(e:Event):void {
			onClosed();
		}

		private function onData(e:WebSocketEvent):void {
			var payload:Object;

			try {
				payload = JSON.parse(e.stringData);
			} catch (error:Error) {
				return;
			}

			switch (payload.t) {
				case "msg":
					enqueue(payload.name, payload.text);
					break;
				case "history":
					for each (var item:Object in payload.items) {
						enqueue(item.name, item.text);
					}
					break;
				case "error":
					enqueue(null, String(payload.text));
					break;
			}

			flush();
		}

		private function onKeyDown(e:KeyboardEvent):void {
			if (e.keyCode != Keyboard.ENTER) {
				return;
			}

			if (consume()) {
				e.stopImmediatePropagation();
			}
		}

		private function onClick(e:MouseEvent):void {
			if (!this.pocket.game || !this.pocket.game.ui || !this.pocket.game.ui.mcInterface) {
				return;
			}

			const button:DisplayObject = this.pocket.game.ui.mcInterface.bsend as DisplayObject;
			const target:DisplayObject = e.target as DisplayObject;

			if (button == null || target == null) {
				return;
			}

			if (target != button && !(button is DisplayObjectContainer && DisplayObjectContainer(button).contains(target))) {
				return;
			}

			if (consume()) {
				e.stopImmediatePropagation();
			}
		}

	}
}
