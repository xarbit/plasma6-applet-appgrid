import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root
    property Item target: null
    property bool blurBeforeAnimation: false
    signal openFinished()
    signal closeFinished()

    function open() { openAnim.start() }
    function close() { closeAnim.start() }
    function reset() { target.opacity = 0.0; target.scale = 1.0; target.rotation = 0 }

    SequentialAnimation {
        id: openAnim
        // Buzz in — rapid micro-shakes while fading in
        ParallelAnimation {
            NumberAnimation {
                target: root.target; property: "opacity"
                from: 0.0; to: 1.0; duration: Kirigami.Units.longDuration * 0.3
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root.target; property: "scale"
                from: 0.92; to: 1.0; duration: Kirigami.Units.longDuration * 0.3
                easing.type: Easing.OutCubic
            }
        }
        // Buzz sequence
        NumberAnimation { target: root.target; property: "rotation"; from: 0; to: 1.2; duration: Kirigami.Units.longDuration * 0.08; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root.target; property: "rotation"; from: 1.2; to: -1.0; duration: Kirigami.Units.longDuration * 0.1; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root.target; property: "rotation"; from: -1.0; to: 0.7; duration: Kirigami.Units.longDuration * 0.1; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root.target; property: "rotation"; from: 0.7; to: -0.4; duration: Kirigami.Units.longDuration * 0.1; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root.target; property: "rotation"; from: -0.4; to: 0.2; duration: Kirigami.Units.longDuration * 0.08; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root.target; property: "rotation"; from: 0.2; to: 0; duration: Kirigami.Units.longDuration * 0.06; easing.type: Easing.OutQuad }
        onFinished: root.openFinished()
    }

    SequentialAnimation {
        id: closeAnim
        // Quick buzz out
        NumberAnimation { target: root.target; property: "rotation"; from: 0; to: 0.8; duration: Kirigami.Units.shortDuration * 0.15; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root.target; property: "rotation"; from: 0.8; to: -0.5; duration: Kirigami.Units.shortDuration * 0.15; easing.type: Easing.InOutQuad }
        ParallelAnimation {
            NumberAnimation {
                target: root.target; property: "opacity"
                from: 1.0; to: 0.0; duration: Kirigami.Units.shortDuration * 0.7
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: root.target; property: "scale"
                from: 1.0; to: 0.95; duration: Kirigami.Units.shortDuration * 0.7
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: root.target; property: "rotation"
                from: -0.5; to: 0; duration: Kirigami.Units.shortDuration * 0.7
                easing.type: Easing.InCubic
            }
        }
        onFinished: root.closeFinished()
    }
}
