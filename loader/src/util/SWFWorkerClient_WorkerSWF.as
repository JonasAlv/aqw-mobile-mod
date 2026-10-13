package util {
	import mx.core.ByteArrayAsset;

	[Embed(source="../../libs/WorkerMain.swf", mimeType="application/octet-stream")]
	public class SWFWorkerClient_WorkerSWF extends ByteArrayAsset {
		public function SWFWorkerClient_WorkerSWF() {
			super();
		}
	}
}
