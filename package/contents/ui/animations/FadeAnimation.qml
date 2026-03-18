import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root
    property Item target: null
    property bool blurBeforeAnimation: true
    signal openFinished()
    signal closeFinished()

    function open() {
        target.scale = 1.0
        openAnim.start()
    }
    function close() { closeAnim.start() }
    function reset() { target.opacity = 0.0; target.scale = 1.0 }

    NumberAnimation {
        id: openAnim
        target: root.target; property: "opacity"
        from: 0.0; to: 1.0; duration: Kirigami.Units.longDuration
        easing.type: Easing.OutCubic
        onFinished: root.openFinished()
    }

    NumberAnimation {
        id: closeAnim
        target: root.target; property: "opacity"
        from: 1.0; to: 0.0; duration: Kirigami.Units.shortDuration
        easing.type: Easing.InCubic
        onFinished: root.closeFinished()
    }
}
