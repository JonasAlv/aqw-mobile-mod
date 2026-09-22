package controller.gamepad {

    import flash.display.Stage;
    import flash.events.Event;
    import flash.events.KeyboardEvent;
    import flash.events.GameInputEvent;
    import flash.ui.GameInput;
    import flash.ui.GameInputDevice;
    import flash.ui.GameInputControl;
    import flash.text.TextField;
    import flash.display.MovieClip;
    import flash.display.Sprite;
    import flash.geom.Point;
    import flash.utils.getTimer;

    public class DesktopInputManager {
        private var stage:Stage;
        private var pocket:*;
        
        private var gameInput:GameInput;
        private var activeDevice:GameInputDevice;
        
        private var xAxis:GameInputControl;
        private var yAxis:GameInputControl;
        
        private var isWDown:Boolean = false;
        private var isADown:Boolean = false;
        private var isSDown:Boolean = false;
        private var isDDown:Boolean = false;

        private var lastSendTime:int = 0;
        private var isWalking:Boolean = false;

        private static const SEND_INTERVAL_MS:int = 250;
        private static const MOVE_SPEED_MULTIPLIER:Number = 15;
        
        public function DesktopInputManager(pocket:*) {
            this.pocket = pocket;
            this.stage = pocket.stage;
            
            if (GameInput.isSupported) {
                gameInput = new GameInput();
                gameInput.addEventListener(GameInputEvent.DEVICE_ADDED, onDeviceAdded);
                gameInput.addEventListener(GameInputEvent.DEVICE_REMOVED, onDeviceRemoved);
                
                for (var i:int = 0; i < GameInput.numDevices; i++) {
                    var device:GameInputDevice = GameInput.getDeviceAt(i);
                    if (device) setupDevice(device);
                }
            }
            
            stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
            stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
            stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
        }
        
        private function onDeviceAdded(e:GameInputEvent):void {
            setupDevice(e.device);
        }
        
        private function onDeviceRemoved(e:GameInputEvent):void {
            if (activeDevice == e.device) {
                activeDevice = null;
                xAxis = null;
                yAxis = null;
            }
        }
        
        private function setupDevice(device:GameInputDevice):void {
            device.enabled = true;
            activeDevice = device;
            
            var axesFound:int = 0;
            for (var i:int = 0; i < device.numControls; i++) {
                var control:GameInputControl = device.getControlAt(i);
                if (control.id.indexOf("AXIS_") != -1) {
                    if (axesFound == 0) xAxis = control;
                    if (axesFound == 1) yAxis = control;
                    axesFound++;
                }
            }
        }
        
        private function onEnterFrame(e:Event):void {
            var dirX:Number = 0;
            var dirY:Number = 0;
            
            if (activeDevice && xAxis && yAxis) {
                var xVal:Number = xAxis.value;
                var yVal:Number = yAxis.value;
                if (Math.abs(xVal) > 0.2) dirX = xVal;
                if (Math.abs(yVal) > 0.2) dirY = yVal;
            }
            
            if (isWDown) dirY = -1;
            if (isSDown) dirY = 1;
            if (isADown) dirX = -1;
            if (isDDown) dirX = 1;
            
            if (dirX == 0 && dirY == 0) {
                stopWalking();
                return;
            }

            isWalking = true;

            if (!pocket.game || !pocket.game.world || !pocket.game.world.myAvatar) return;

            const pMC:MovieClip = MovieClip(pocket.game.world.myAvatar.pMC);
            if (pMC == null) return;
            if (!pocket.game.world.isMoveOK(pocket.game.world.myAvatar.dataLeaf) || !Boolean(pocket.game.world.bitWalk)) return;
            
            const angle:Number = Math.atan2(dirY, dirX);
            const baseSpeed:Number = Number(pocket.game.world.WALKSPEED);
            const moveSpeed:Number = baseSpeed;

            pocket.game.world.speed2 = moveSpeed;

            var currentTime:int = getTimer();
            if (currentTime - lastSendTime >= SEND_INTERVAL_MS) {
                lastSendTime = currentTime;

                var localX:Number = pMC.x + Math.cos(angle) * MOVE_SPEED_MULTIPLIER * 15;
                var localY:Number = pMC.y + Math.sin(angle) * MOVE_SPEED_MULTIPLIER * 15;

                var mvPT:Point = pMC.simulateTo(localX, localY, moveSpeed);
                if (mvPT == null) return;

                pMC.walkTo(mvPT.x, mvPT.y, moveSpeed);

                pocket.game.world.moveRequest({
                    mc: pMC,
                    tx: mvPT.x,
                    ty: mvPT.y,
                    sp: moveSpeed
                });
            }
        }
        
        private function stopWalking():void {
            if (!isWalking) return;
            isWalking = false;
            lastSendTime = 0;
            if (pocket.game && pocket.game.world && pocket.game.world.myAvatar && pocket.game.world.myAvatar.pMC) {
                pocket.game.world.myAvatar.pMC.stopWalking();
            }
        }
        
        private function onKeyDown(e:KeyboardEvent):void {
            if (stage.focus is TextField) return;
            if (e.keyCode == 87) isWDown = true;
            if (e.keyCode == 83) isSDown = true;
            if (e.keyCode == 65) isADown = true;
            if (e.keyCode == 68) isDDown = true;
        }
        
        private function onKeyUp(e:KeyboardEvent):void {
            if (e.keyCode == 87) isWDown = false;
            if (e.keyCode == 83) isSDown = false;
            if (e.keyCode == 65) isADown = false;
            if (e.keyCode == 68) isDDown = false;
        }
    }
}
