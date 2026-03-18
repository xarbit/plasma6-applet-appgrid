import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root
    property Item target: null
    property bool blurBeforeAnimation: false
    signal openFinished()
    signal closeFinished()

    // Slide from bottom of screen to center
    readonly property real slideDistance: target ? (target.parent ? target.parent.height : 800) : 800

    function open() {
        target.opacity = 1.0
        openAnim.start()
    }
    function close() { closeAnim.start() }
    function reset() {}

    NumberAnimation {
        id: openAnim
        target: root.target; property: "anchors.verticalCenterOffset"
        from: root.slideDistance; to: 0; duration: Kirigami.Units.longDuration * 1.5
        easing.type: Easing.OutCubic
        onFinished: root.openFinished()
    }

    NumberAnimation {
        id: closeAnim
        target: root.target; property: "anchors.verticalCenterOffset"
        from: 0; to: root.slideDistance; duration: Kirigami.Units.shortDuration * 1.5
        easing.type: Easing.InCubic
        onFinished: root.closeFinished()
    }
}
