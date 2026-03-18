import QtQuick

SequentialAnimation {
    id: root
    property Item target: null

    NumberAnimation { target: root.target; property: "scale"; from: 1.0; to: 1.2; duration: 150; easing.type: Easing.OutBack }
    NumberAnimation { target: root.target; property: "scale"; from: 1.2; to: 1.0; duration: 200; easing.type: Easing.InOutQuad }
}
