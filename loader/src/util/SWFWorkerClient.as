package util {
	import flash.events.Event;
	import flash.system.MessageChannel;
	import flash.system.MessageChannelState;
	import flash.system.Worker;
	import flash.system.WorkerDomain;
	import flash.system.WorkerState;
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	import flash.utils.clearTimeout;
	import flash.utils.setTimeout;

	public class SWFWorkerClient {

		[Embed(source="../../gamefiles/embed/WorkerMain.swf", mimeType="application/octet-stream")]
		private static const WorkerSWF:Class;

		private static var _instance:SWFWorkerClient;

		public static function get instance():SWFWorkerClient {
			if (_instance == null) {
				_instance = new SWFWorkerClient();
			}

			return _instance;
		}

		private static const POOL_SIZE:int = 4;
		private static const MAX_RESPAWNS:int = 8;

		private var slots:Vector.<Object> = new Vector.<Object>();
		private var swfBytes:ByteArray;
		private var respawns:int = 0;

		private var nextId:uint = 0;
		private var pending:Dictionary = new Dictionary();
		private const TIMEOUT_MS:uint = 30000;
		private var supported:Boolean;

		public function SWFWorkerClient() {
			supported = WorkerDomain.isSupported;

			if (!supported) {
				return;
			}

			try {
				this.swfBytes = new WorkerSWF() as ByteArray;

				for (var i:int = 0; i < POOL_SIZE; i++) {
					slots.push(createSlot());
				}
			} catch (e:Error) {
				supported = false;
			}
		}

		private function createSlot():Object {
			const worker:Worker = WorkerDomain.current.createWorker(this.swfBytes);
			const toWorker:MessageChannel = Worker.current.createMessageChannel(worker);
			const fromWorker:MessageChannel = worker.createMessageChannel(Worker.current);

			worker.setSharedProperty("toWorker", toWorker);
			worker.setSharedProperty("fromWorker", fromWorker);

			const slot:Object = {worker: worker, to: toWorker, from: fromWorker, busy: 0, dead: false};

			fromWorker.addEventListener(Event.CHANNEL_MESSAGE, function (e:Event):void {
				onWorkerMessage(slot);
			});

			worker.addEventListener(Event.WORKER_STATE, function (e:Event):void {
				if (worker.state == WorkerState.TERMINATED) {
					onSlotDead(slot);
				}
			});

			worker.start();

			return slot;
		}

		private function isHealthy(slot:Object):Boolean {
			return !slot.dead
				&& slot.worker.state != WorkerState.TERMINATED
				&& slot.to.state == MessageChannelState.OPEN;
		}

		private function onSlotDead(slot:Object):void {
			if (slot.dead) {
				return;
			}

			slot.dead = true;

			const index:int = slots.indexOf(slot);

			if (index > -1) {
				slots.splice(index, 1);
			}

			for (var key:* in pending) {
				const job:Object = pending[key];

				if (job == null || job.slot != slot) {
					continue;
				}

				delete pending[key];

				clearTimeout(job.timeoutId);

				job.callback(job.originalBytes);
			}

			if (supported && respawns < MAX_RESPAWNS) {
				respawns++;

				try {
					slots.push(createSlot());
				} catch (e:Error) {
				}
			}
		}

		private function pickSlot():Object {
			var best:Object = null;

			for each (var slot:Object in slots) {
				if (!isHealthy(slot)) {
					continue;
				}

				if (best == null || slot.busy < best.busy) {
					best = slot;
				}
			}

			return best;
		}

		public function process(bytes:ByteArray, stripAnimation:Boolean, stripFilters:Boolean, rasterize:Boolean, rasterScale:Number, rasterMaxSide:int, onDone:Function):void {
			const slot:Object = supported ? pickSlot() : null;

			if (slot == null) {
				if (stripAnimation || stripFilters) {
					onDone(SWFStripper.process(bytes, stripAnimation, stripFilters, false));
				} else {
					onDone(bytes);
				}

				return;
			}

			const id:uint = nextId++;
			const job:Object = {callback: onDone, originalBytes: bytes, timeoutId: 0, slot: slot};

			pending[id] = job;

			try {
				slot.to.send({
					id: id,
					bytes: bytes,
					stripAnimation: stripAnimation,
					stripFilters: stripFilters,
					rasterize: rasterize,
					rasterScale: rasterScale,
					rasterMaxSide: rasterMaxSide
				});
			} catch (e:Error) {
				delete pending[id];

				onSlotDead(slot);

				onDone(bytes);

				return;
			}

			slot.busy++;

			job.timeoutId = setTimeout(function ():void {
				if (pending[id] == null) {
					return;
				}

				delete pending[id];

				slot.busy--;

				onDone(bytes);
			}, TIMEOUT_MS);
		}

		private function onWorkerMessage(slot:Object):void {
			const fromWorker:MessageChannel = slot.from;

			while (fromWorker.messageAvailable) {
				const result:Object = fromWorker.receive();
				const job:Object = pending[result.id];

				if (job == null) {
					continue;
				}

				delete pending[result.id];

				slot.busy--;

				clearTimeout(job.timeoutId);

				job.callback(result.error ? job.originalBytes as ByteArray : result.bytes as ByteArray);
			}
		}
	}
}