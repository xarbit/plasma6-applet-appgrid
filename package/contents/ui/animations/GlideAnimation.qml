import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root
    property Item target: null
    property bool blurBeforeAnimation: false
    signal openFinished()
    signal closeFinished()

    readonly property real glideDistance: Kirigami.Units.gridUnit * 2

    function open() { openAnim.start() }
    function close() { closeAnim.start() }
    function reset() { target.opacity = 0.0; target.scale = 1.0; target.anchors.verticalCenterOffset = glideDistance }

    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: root.target; property: "anchors.verticalCenterOffset"
            from: root.glideDistance; to: 0; duration: Kirigami.Units.longDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root.target; property: "opacity"
            from: 0.0; to: 1.0; duration: Kirigami.Units.longDuration
            easing.type: Easing.OutCubic
        }
        onFinished: root.openFinished()
    }

    ParallelAnimation {
        id: closeAnim
        NumberAnimation {
            target: root.target; property: "anchors.verticalCenterOffset"
            from: 0; to: root.glideDistance; duration: Kirigami.Units.shortDuration
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root.target; property: "opacity"
            from: 1.0; to: 0.0; duration: Kirigami.Units.shortDuration
            easing.type: Easing.InCubic
        }
        onFinished: root.closeFinished()
    }
}
