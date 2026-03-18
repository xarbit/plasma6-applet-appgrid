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
    function reset() { target.opacity = 0.0; target.scale = 0.8 }

    ParallelAnimation {
        id: openAnim
        SequentialAnimation {
            NumberAnimation {
                target: root.target; property: "scale"
                from: 0.8; to: 1.05; duration: Kirigami.Units.longDuration * 0.7
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root.target; property: "scale"
                from: 1.05; to: 1.0; duration: Kirigami.Units.longDuration * 0.3
                easing.type: Easing.InOutQuad
            }
        }
        NumberAnimation {
            target: root.target; property: "opacity"
            from: 0.0; to: 1.0; duration: Kirigami.Units.longDuration * 0.5
            easing.type: Easing.OutCubic
        }
        onFinished: root.openFinished()
    }

    ParallelAnimation {
        id: closeAnim
        NumberAnimation {
            target: root.target; property: "scale"
            from: 1.0; to: 0.85; duration: Kirigami.Units.shortDuration
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
