package game {

	import flash.display.MovieClip;
	import flash.display.SimpleButton;
	import flash.events.MouseEvent;

	import ui.util.Pagination;

	public class ItemPagination {

		private static const ITEMS_PER_PAGE:int = 9;

		public function ItemPagination(pocket:Pocket) {
			this.pocket = pocket;
		}

		private var pocket:Pocket;

		/**
		 * Patch freezing when opening Bank, Inventory etc.
		 *
		 * @param state
		 * @param lpf
		 * @param reset
		 * @return
		 */
		public function fDraw(state:Object, lpf:Object, reset:Boolean):Object {
			var listA:Array = [];
			var sortedGroup:Array = [];
			var filteredItems:Array = [];
			var i:int;
			var itemData:Object;

			const tSel:Object = state.tSel;
			const iSel:Object = state.iSel;
			const filterMap:Object = state.filterMap;
			const itemList:Array = state.itemList;
			const sortOrder:Array = state.sortOrder;
			const onDemand:Boolean = state.onDemand;
			const bLimited:Boolean = state.bLimited;
			const itemEventType:String = state.itemEventType;
			const allowDesel:Boolean = state.allowDesel;
			const multiSelect:Boolean = state.multiSelect;

			const iList:MovieClip = lpf.iList;
			const bgTabs:MovieClip = lpf.bgTabs;
			const listMask:MovieClip = lpf.listMask;
			const scr:Object = lpf.scr;

			const lpfElementListItemItemCls:Class = this.pocket.game.world.getClass("LPFElementListItemItem");

			while (iList.numChildren > 0) {
				MovieClip(iList.getChildAt(0)).fClose();
			}

			if (reset || iList.curPage == undefined) {
				iList.curPage = 0;
			}

			if (reset) {
				iList.y = bgTabs.height - 1;
			}

			if (tSel == null) {
				state.setMessage("No Tab Selected");

				scr.fOpen({
					"subject": iList,
					"subjectMask": listMask,
					"reset": reset
				});

				return {
					listA: listA
				};
			}

			state.setMessage("");

			if (tSel.filter != "*") {
				for each (itemData in itemList) {
					var matchesFilter:Boolean = filterMap[tSel.filter].indexOf(itemData.sType) > -1 || itemData.sType == "Enhancement" && itemData.sES.indexOf(tSel.filter) > -1;

					var isExcludedPot:Boolean =
						tSel.filter == "pots" &&
						itemData.sLink != "potion" &&
						itemData.sLink != "elixir" &&
						itemData.sLink != "tonic" &&
						itemData.sLink != "scroll";

					if (matchesFilter && !isExcludedPot) {
						filteredItems.push(itemData);
					}
				}
			} else {
				filteredItems = itemList;
			}

			if (onDemand && filteredItems.length == 0) {
				state.setMessage("No items of this type");

				scr.fOpen({
					"subject": iList,
					"subjectMask": listMask,
					"reset": reset
				});

				return {
					listA: listA
				};
			}

			for (i = 0; i < sortOrder.length; i++) {
				sortedGroup = [];

				for each (itemData in filteredItems) {
					if (itemData.sType == sortOrder[i]) {
						sortedGroup.push(itemData);
					}
				}

				if (sortedGroup.length > 0) {
					sortedGroup.sortOn(
						["sName", "iLvl"],
						[undefined, Array.DESCENDING | Array.NUMERIC]
					);

					listA = listA.concat(sortedGroup);
				}
			}

			sortedGroup = [];

			for each (itemData in filteredItems) {
				if (listA.indexOf(itemData) == -1) {
					sortedGroup.push(itemData);
				}
			}

			if (sortedGroup.length > 0) {
				sortedGroup.sortOn(["sType", "sName"]);
				listA = listA.concat(sortedGroup);
			}

			if (true) {
				const pinnedItems:Array = [];
				const unpinnedItems:Array = [];

				for each (itemData in listA) {
					if (itemData.bEquip) {
						pinnedItems.push(itemData);
					} else {
						unpinnedItems.push(itemData);
					}
				}

				listA = pinnedItems.concat(unpinnedItems);
			}

			const itemConfig:Object = {};

			itemConfig.eventType = itemEventType;
			itemConfig.allowDesel = allowDesel;
			itemConfig.multiSelect = multiSelect;
			itemConfig.bLimited = bLimited && state.getLayout().sMode == "shopBuy";

			const listLength:int = listA.length;
			const totalPages:int = Math.max(1, Math.ceil(listLength / ITEMS_PER_PAGE));

			if (iList.curPage >= totalPages) {
				iList.curPage = totalPages - 1;
			}

			if (iList.curPage < 0) {
				iList.curPage = 0;
			}

			const curPage:int = iList.curPage;
			const startIndex:int = curPage * ITEMS_PER_PAGE;
			const endIndex:int = Math.min(startIndex + ITEMS_PER_PAGE, listLength);

			for (i = startIndex; i < endIndex; i++) {
				addListItem(iList, lpf, lpfElementListItemItemCls, itemConfig, listA, iSel, i - startIndex);
			}

			if (totalPages > 1) {
				const pagination:Pagination = Pagination(iList.addChild(new Pagination()));

				pagination.y = iList.height + 6.5;

				pagination.fOpen({
					"page": curPage + 1,
					"totalPages": totalPages,
					"canPrev": curPage > 0,
					"canNext": curPage < totalPages - 1,
					"state": state,
					"lpf": lpf
				});

				if (pagination.btnPrev) {
					pagination.btnPrev.addEventListener(MouseEvent.CLICK, this.onPrevClick, false, 0, false);
				}

				if (pagination.btnNext) {
					pagination.btnNext.addEventListener(MouseEvent.CLICK, this.onNextClick, false, 0, false);
				}
			}

			scr.fOpen({
				"subject": iList,
				"subjectMask": listMask,
				"reset": true
			});

			return {
				listA: listA
			};
		}

		private function onPrevClick(e:MouseEvent):void {
			const pagination:Pagination = Pagination(SimpleButton(e.currentTarget).parent);
			const data:Object = pagination.fData;
			const iList:MovieClip = data.lpf.iList;

			if (iList.curPage > 0) {
				iList.curPage--;
				fDraw(data.state, data.lpf, false);
			}
		}

		private function onNextClick(e:MouseEvent):void {
			const pagination:Pagination = Pagination(SimpleButton(e.currentTarget).parent);
			const data:Object = pagination.fData;
			const iList:MovieClip = data.lpf.iList;

			if (iList.curPage < data.totalPages - 1) {
				iList.curPage++;
				fDraw(data.state, data.lpf, false);
			}
		}

		private function addListItem(iList:Object, lpf:Object, cls:Class, itemConfig:Object, listA:Array, iSel:Object, key:int):void {
			itemConfig.fData = listA[key + iList.curPage * ITEMS_PER_PAGE];

			const listItem:Object = iList.addChild(new cls());

			listItem.subscribeTo(lpf);
			listItem.fOpen(itemConfig);

			if (listItem.fData == iSel) {
				listItem.select();
			}

			if (key != 0) {
				listItem.y = iList.height;
			}
		}

	}
}