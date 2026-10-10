package rasterize {

	import com.codeazur.as3swf.SWF;
	import com.codeazur.as3swf.data.*;
	import com.codeazur.as3swf.data.consts.BitmapFormat;
	import com.codeazur.as3swf.exporters.AS3GraphicsDataShapeExporter;
	import com.codeazur.as3swf.tags.*;

	import flash.display.BitmapData;
	import flash.display.Shape;
	import flash.geom.Matrix;
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	import flash.utils.getTimer;

	public class Rasterize {

		private static const MIN_EFFECTIVE:Number = 0.25;
		private static const MAX_EFFECTIVE:Number = 4;

		private static const TIME_BUDGET_MS:int = 6000;

		private var _maxSide:int = 2048;
		private var _deadline:int = 0;
		private var _scaleMap:Dictionary = new Dictionary();
		private var _sprites:Dictionary = new Dictionary();

		private var _nextCharId:uint = 0;
		private var _totalShapes:int = 0;
		private var _doneShapes:int = 0;

		public function convert(inputBytes:ByteArray, scale:Number = 1.5, maxSide:int = 2048):ByteArray {
			_maxSide = maxSide;
			_deadline = getTimer() + TIME_BUDGET_MS;

			inputBytes.position = 0;

			const src:SWF = new SWF();
			src.loadBytes(inputBytes);

			_nextCharId = findMaxCharId(src.tags);
			_totalShapes = countShapes(src.tags);
			_doneShapes = 0;

			const dst:SWF = new SWF();
			dst.version = src.version;
			dst.compressed = src.compressed;
			dst.frameSize = src.frameSize;
			dst.frameRate = src.frameRate;
			dst.frameCount = src.frameCount;

			_scaleMap = new Dictionary();
			_sprites = new Dictionary();

			for each (var t:* in src.tags) {
				if (t is TagDefineSprite) {
					_sprites[(t as TagDefineSprite).characterId] = t;
				}
			}

			collectScales(src.tags, 1.0);

			transcodeTagList(src.tags, dst.tags, scale);

			const result:ByteArray = new ByteArray();
			dst.publish(result);
			result.position = 0;

			return result;
		}

		private function transcodeTagList(inTags:Vector.<ITag>, outTags:Vector.<ITag>, scale:Number):void {
			for each (var tag:* in inTags) {
				if (tag is TagDefineShape) {
					transcodeShape(tag as TagDefineShape, outTags, scale);

				} else if (tag is TagDefineSprite) {
					var srcSprite:TagDefineSprite = tag as TagDefineSprite;
					var dstSprite:TagDefineSprite = new TagDefineSprite();

					dstSprite.characterId = srcSprite.characterId;
					dstSprite.frameCount = srcSprite.frameCount;

					transcodeTagList(srcSprite.tags, dstSprite.tags, scale);

					outTags.push(dstSprite);
				}/* else if (tag is TagPlaceObject) {
					var po:TagPlaceObject = tag as TagPlaceObject;

					if (po.hasFilterList && po.surfaceFilterList.length > 0) {
						po.surfaceFilterList.length = 0;
						po.hasFilterList = false;
					}

					outTags.push(po);
				}*/ else {
					outTags.push(tag);
				}
			}
		}

		private function transcodeShape(shapeTag:TagDefineShape, outTags:Vector.<ITag>, scale:Number):void {
			var shapeId:uint = shapeTag.characterId;
			var bounds:SWFRectangle = shapeTag.shapeBounds;

			if (getTimer() > _deadline || usesBitmapFill(shapeTag)) {
				outTags.push(shapeTag);
				return;
			}

			var wPx:Number = (bounds.xmax - bounds.xmin) / 20;
			var hPx:Number = (bounds.ymax - bounds.ymin) / 20;

			if (wPx <= 0 || hPx <= 0) {
				outTags.push(shapeTag);
				return;
			}

			var eff:Number = _scaleMap[shapeId];

			if (!(eff > 0)) {
				eff = 1;
			}

			eff = Math.max(MIN_EFFECTIVE, Math.min(MAX_EFFECTIVE, eff));

			var s:Number = scale * eff;
			s = Math.min(s, (_maxSide - 2) / wPx, (_maxSide - 2) / hPx, Math.sqrt(_maxSide * _maxSide / 2 / (wPx * hPx)));

			var w:int = Math.max(1, Math.ceil(wPx * s)) + 2;
			var h:int = Math.max(1, Math.ceil(hPx * s)) + 2;

			var bmd:BitmapData = new BitmapData(w, h, true, 0x00000000);
			var shape:Shape = new Shape();

			var exporter:AS3GraphicsDataShapeExporter = new AS3GraphicsDataShapeExporter(null);
			shapeTag.export(exporter);
			var gfxData:* = exporter.graphicsData;
			shape.graphics.drawGraphicsData(gfxData);

			var sx:Number = (w - 2) / wPx;
			var sy:Number = (h - 2) / hPx;

			var m:Matrix = new Matrix();
			m.a = sx;
			m.d = sy;
			m.tx = -bounds.xmin / 20 * sx + 1;
			m.ty = -bounds.ymin / 20 * sy + 1;

			bmd.draw(shape, m, null, null, null, true);
			shape.graphics.clear();

			_nextCharId++;
			var bitmapId:uint = _nextCharId;

			var bitsTag:TagDefineBitsLossless2 = new TagDefineBitsLossless2();
			bitsTag.characterId = bitmapId;
			bitsTag.bitmapFormat = BitmapFormat.BIT_24;
			bitsTag.bitmapWidth = w;
			bitsTag.bitmapHeight = h;

			var raw:ByteArray = new ByteArray();
			var pixels:Vector.<uint> = bmd.getVector(bmd.rect);
			var count:int = pixels.length;
			var argb:uint;
			var a:uint;
			var r:uint;
			var g:uint;
			var b:uint;

			for (var i:int = 0; i < count; i++) {
				argb = pixels[i];
				a = argb >>> 24;

				if (a == 0xFF || a == 0) {
					raw.writeUnsignedInt(a == 0 ? 0 : argb);
					continue;
				}

				r = (((argb >>> 16) & 0xFF) * a + 127) / 255;
				g = (((argb >>> 8) & 0xFF) * a + 127) / 255;
				b = ((argb & 0xFF) * a + 127) / 255;

				raw.writeUnsignedInt((a << 24) | (r << 16) | (g << 8) | b);
			}
			bmd.dispose();
			raw.compress();
			bitsTag.zlibBitmapData.writeBytes(raw);
			raw.clear();

			outTags.push(bitsTag);

			outTags.push(buildBitmapWrapper(shapeId, bitmapId, bounds, w, h));

			_doneShapes++;
		}

		private function collectScales(tags:Vector.<ITag>, parentScale:Number):void {
			for each (var tag:* in tags) {
				if (!(tag is TagPlaceObject)) {
					continue;
				}

				var po:TagPlaceObject = tag as TagPlaceObject;

				if (!po.hasCharacter) {
					continue;
				}

				var s:Number = parentScale * matrixScale(po.hasMatrix ? po.matrix : null);

				if (!(s > 0)) {
					continue;
				}

				var known:Number = _scaleMap[po.characterId];

				if (known > 0 && s <= known) {
					continue;
				}

				_scaleMap[po.characterId] = s;

				var sprite:TagDefineSprite = _sprites[po.characterId] as TagDefineSprite;

				if (sprite != null) {
					collectScales(sprite.tags, s);
				}
			}
		}

		private function matrixScale(m:SWFMatrix):Number {
			if (m == null) {
				return 1;
			}

			var sx:Number = Math.sqrt(m.scaleX * m.scaleX + m.rotateSkew0 * m.rotateSkew0);
			var sy:Number = Math.sqrt(m.rotateSkew1 * m.rotateSkew1 + m.scaleY * m.scaleY);

			return Math.max(sx, sy);
		}

		private function usesBitmapFill(shapeTag:TagDefineShape):Boolean {
			var styles:Vector.<SWFFillStyle> = shapeTag.shapes.initialFillStyles;
			var i:int;

			for (i = 0; i < styles.length; i++) {
				if (styles[i].type >= 0x40 && styles[i].type <= 0x43)
					return true;
			}

			for each (var rec:* in shapeTag.shapes.records) {
				if (rec is SWFShapeRecordStyleChange && (rec as SWFShapeRecordStyleChange).stateNewStyles) {
					var fs:Vector.<SWFFillStyle> = (rec as SWFShapeRecordStyleChange).fillStyles;
					for (i = 0; i < fs.length; i++) {
						if (fs[i].type >= 0x40 && fs[i].type <= 0x43)
							return true;
					}
				}
			}

			return false;
		}

		private function buildBitmapWrapper(shapeId:uint, bitmapId:uint, bounds:SWFRectangle, bw:int, bh:int):TagDefineShape4 {
			var a:Number = (bounds.xmax - bounds.xmin) / (bw - 2);
			var d:Number = (bounds.ymax - bounds.ymin) / (bh - 2);
			var tx:Number = bounds.xmin - a;
			var ty:Number = bounds.ymin - d;

			var fillMatrix:SWFMatrix = new SWFMatrix();
			fillMatrix.scaleX = a;
			fillMatrix.scaleY = d;
			fillMatrix.translateX = Math.round(tx);
			fillMatrix.translateY = Math.round(ty);

			var fill:SWFFillStyle = new SWFFillStyle();

			// 0x41 = Smoothed Clipped Bitmap (Slow when animating)
			// 0x43 = Non-Smoothed Clipped Bitmap (Hardware optimized, fast)
			fill.type = 0x41;

			fill.bitmapId = bitmapId;
			fill.bitmapMatrix = fillMatrix;

			var wrapper:TagDefineShape4 = new TagDefineShape4();
			wrapper.characterId = shapeId;
			wrapper.shapeBounds = bounds;
			wrapper.edgeBounds = bounds;
			wrapper.shapes = new SWFShapeWithStyle();

			wrapper.shapes.initialFillStyles.push(fill);

			var sc:SWFShapeRecordStyleChange = new SWFShapeRecordStyleChange();
			sc.stateMoveTo = true;
			sc.stateFillStyle1 = true;
			sc.stateLineStyle = true;
			sc.moveDeltaX = bounds.xmin;
			sc.moveDeltaY = bounds.ymin;
			sc.fillStyle1 = 1;
			sc.lineStyle = 0;
			wrapper.shapes.records.push(sc);

			var w_tw:int = bounds.xmax - bounds.xmin;
			var h_tw:int = bounds.ymax - bounds.ymin;

			wrapper.shapes.records.push(makeStraightEdge(w_tw, 0));
			wrapper.shapes.records.push(makeStraightEdge(0, h_tw));
			wrapper.shapes.records.push(makeStraightEdge(-w_tw, 0));
			wrapper.shapes.records.push(makeStraightEdge(0, -h_tw));
			wrapper.shapes.records.push(new SWFShapeRecordEnd());

			return wrapper;
		}

		private function makeStraightEdge(dx:int, dy:int):SWFShapeRecordStraightEdge {
			var e:SWFShapeRecordStraightEdge = new SWFShapeRecordStraightEdge();
			e.deltaX = dx;
			e.deltaY = dy;
			if (dx != 0 && dy != 0) {
				e.generalLineFlag = true;
			} else {
				e.generalLineFlag = false;
				e.vertLineFlag = (dx == 0);
			}
			return e;
		}

		private function findMaxCharId(tags:Vector.<ITag>):uint {
			var max:uint = 0;
			for each (var tag:* in tags) {
				if (tag is IDefinitionTag) {
					var id:uint = (tag as IDefinitionTag).characterId;
					if (id > max)
						max = id;
				}
				if (tag is TagDefineSprite) {
					var inner:uint = findMaxCharId((tag as TagDefineSprite).tags);
					if (inner > max)
						max = inner;
				}
			}
			return max;
		}

		private function countShapes(tags:Vector.<ITag>):int {
			var n:int = 0;
			for each (var tag:* in tags) {
				if (tag is TagDefineShape)
					n++;
				if (tag is TagDefineSprite)
					n += countShapes((tag as TagDefineSprite).tags);
			}
			return n;
		}
	}
}