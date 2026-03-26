import QtQuick

Item {
    id: root
    property Item target: null
    property bool hovered: false

    function start() {
        // One-shot bounce for shake-on-open
        if (!hovered)
            bounceAnim.start()
    }

    // One-shot bounce (used by shake-on-open)
    SequentialAnimation {
        id: bounceAnim
        NumberAnimation { target: root.target; property: "scale"; from: 1.0; to: 1.2; duration: 150; easing.type: Easing.OutBack }
        NumberAnimation { target: root.target; property: "scale"; from: 1.2; to: 1.0; duration: 200; easing.type: Easing.InOutQuad }
    }

    // Persistent hover scale with smooth transitions
    NumberAnimation {
        id: growIn
        target: root.target; property: "scale"
        to: 1.3; duration: 150; easing.type: Easing.OutBack
    }
    NumberAnimation {
        id: growOut
        target: root.target; property: "scale"
        to: 1.0; duration: 200; easing.type: Easing.InOutQuad
    }

    onHoveredChanged: {
        if (!target) return
        bounceAnim.stop()
        if (hovered) {
            growOut.stop()
            growIn.start()
        } else {
            growIn.stop()
            growOut.start()
        }
    }
}
