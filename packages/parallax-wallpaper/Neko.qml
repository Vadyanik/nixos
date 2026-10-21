import QtQuick

// Port of oneko.js (https://github.com/adryd325/oneko.js): a cat that chases a
// target point and naps or scratches when it catches up.
Item {
    id: neko
    property url sprite
    property real targetX: 0
    property real targetY: 0
    // Vertical extent of the cat's world: all workspaces of the output stacked.
    property real worldHeight: parent.height
    property real cameraY: 0
    property real cell: 64
    property real speed: 10 * cell / 32
    property real posX: cell
    property real posY: cell
    property int frameCount: 0
    property int idleTime: 0
    property string idleAnimation: ""
    property int idleFrame: 0
    property var spriteCell: [-3, -3]

    readonly property var sets: ({
        idle: [[-3, -3]], alert: [[-7, -3]], tired: [[-3, -2]],
        scratchSelf: [[-5, 0], [-6, 0], [-7, 0]],
        scratchWallN: [[0, 0], [0, -1]], scratchWallS: [[-7, -1], [-6, -2]],
        scratchWallE: [[-2, -2], [-2, -3]], scratchWallW: [[-4, 0], [-4, -1]],
        sleeping: [[-2, 0], [-2, -1]],
        N: [[-1, -2], [-1, -3]], NE: [[0, -2], [0, -3]],
        E: [[-3, 0], [-3, -1]], SE: [[-5, -1], [-5, -2]],
        S: [[-6, -3], [-7, -2]], SW: [[-5, -3], [-6, -1]],
        W: [[-4, -2], [-4, -3]], NW: [[-1, 0], [-1, -1]]
    })

    width: cell
    height: cell
    Component.onCompleted: {
        posX = targetX;
        posY = targetY;
    }
    x: posX - cell / 2
    y: posY - cell / 2 - cameraY

    Item {
        anchors.fill: parent
        clip: true
        Image {
            source: neko.sprite
            smooth: false
            width: 8 * neko.cell
            height: 4 * neko.cell
            x: neko.spriteCell[0] * neko.cell
            y: neko.spriteCell[1] * neko.cell
        }
    }

    function setSprite(name, frame) {
        const frames = sets[name];
        spriteCell = frames[frame % frames.length];
    }

    function resetIdle() {
        idleAnimation = "";
        idleFrame = 0;
    }

    function idle() {
        idleTime += 1;
        if (idleTime > 10 && idleAnimation === "" && Math.floor(Math.random() * 200) === 0) {
            const options = ["sleeping", "scratchSelf"];
            if (posX < cell) options.push("scratchWallW");
            if (posY < cell) options.push("scratchWallN");
            if (posX > parent.width - cell) options.push("scratchWallE");
            if (posY > worldHeight - cell) options.push("scratchWallS");
            idleAnimation = options[Math.floor(Math.random() * options.length)];
        }
        if (idleAnimation === "") {
            setSprite("idle", 0);
            return;
        }
        if (idleAnimation === "sleeping") {
            if (idleFrame < 8) setSprite("tired", 0);
            else setSprite("sleeping", Math.floor(idleFrame / 4));
            if (idleFrame > 192) resetIdle();
        } else {
            setSprite(idleAnimation, idleFrame);
            if (idleFrame > 9) resetIdle();
        }
        idleFrame += 1;
    }

    function step() {
        frameCount += 1;
        const dx = posX - targetX;
        const dy = posY - targetY;
        const distance = Math.sqrt(dx * dx + dy * dy);
        if (distance < speed || distance < 1.5 * cell) {
            idle();
            return;
        }
        resetIdle();
        if (idleTime > 1) {
            setSprite("alert", 0);
            idleTime = Math.min(idleTime, 7) - 1;
            return;
        }
        let dir = (dy / distance > 0.5 ? "N" : "") + (dy / distance < -0.5 ? "S" : "");
        dir += (dx / distance > 0.5 ? "W" : "") + (dx / distance < -0.5 ? "E" : "");
        setSprite(dir, frameCount);
        posX = Math.min(Math.max(cell / 2, posX - dx / distance * speed), parent.width - cell / 2);
        posY = Math.min(Math.max(cell / 2, posY - dy / distance * speed), worldHeight - cell / 2);
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: neko.step()
    }
}
