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
    function reset() {}

    SequentialAnimation {
        id: openAnim
        // Fade in while pulsing
        ParallelAnimation {
            NumberAnimation {
                target: root.target; property: "opacity"
                from: 0.0; to: 1.0; duration: Kirigami.Units.longDuration * 0.4
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root.target; property: "scale"
                from: 0.9; to: 1.06; duration: Kirigami.Units.longDuration * 0.3
                easing.type: Easing.OutQuad
            }
        }
        // Wave oscillations
        ParallelAnimation {
            NumberAnimation { target: root.target; property: "scale"; from: 1.06; to: 0.97; duration: Kirigami.Units.longDuration * 0.15; easing.type: Easing.InOutSine }
            NumberAnimation { target: root.target; property: "rotation"; from: 0; to: 0.8; duration: Kirigami.Units.longDuration * 0.15; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
            NumberAnimation { target: root.target; property: "scale"; from: 0.97; to: 1.03; duration: Kirigami.Units.longDuration * 0.15; easing.type: Easing.InOutSine }
            NumberAnimation { target: root.target; property: "rotation"; from: 0.8; to: -0.5; duration: Kirigami.Units.longDuration * 0.15; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
            NumberAnimation { target: root.target; property: "scale"; from: 1.03; to: 0.99; duration: Kirigami.Units.longDuration * 0.1; easing.type: Easing.InOutSine }
            NumberAnimation { target: root.target; property: "rotation"; from: -0.5; to: 0.2; duration: Kirigami.Units.longDuration * 0.1; easing.type: Easing.InOutSine }
        }
        // Settle
        ParallelAnimation {
            NumberAnimation { target: root.target; property: "scale"; from: 0.99; to: 1.0; duration: Kirigami.Units.longDuration * 0.1; easing.type: Easing.OutQuad }
            NumberAnimation { target: root.target; property: "rotation"; from: 0.2; to: 0; duration: Kirigami.Units.longDuration * 0.1; easing.type: Easing.OutQuad }
        }
        onFinished: root.openFinished()
    }

    SequentialAnimation {
        id: closeAnim
        // Quick wave out
        ParallelAnimation {
            NumberAnimation { target: root.target; property: "scale"; from: 1.0; to: 1.04; duration: Kirigami.Units.shortDuration * 0.2; easing.type: Easing.OutQuad }
            NumberAnimation { target: root.target; property: "rotation"; from: 0; to: -0.6; duration: Kirigami.Units.shortDuration * 0.2; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: root.target; property: "scale"; from: 1.04; to: 0.9; duration: Kirigami.Units.shortDuration * 0.8; easing.type: Easing.InCubic }
            NumberAnimation { target: root.target; property: "opacity"; from: 1.0; to: 0.0; duration: Kirigami.Units.shortDuration * 0.8; easing.type: Easing.InCubic }
            NumberAnimation { target: root.target; property: "rotation"; from: -0.6; to: 0; duration: Kirigami.Units.shortDuration * 0.8; easing.type: Easing.InCubic }
        }
        onFinished: root.closeFinished()
    }
}
