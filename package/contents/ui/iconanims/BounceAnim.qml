import QtQuick

SequentialAnimation {
    id: root
    property Item target: null

    NumberAnimation { target: root.target; property: "scale"; from: 1.0; to: 0.85; duration: 80;  easing.type: Easing.InQuad }
    NumberAnimation { target: root.target; property: "scale"; from: 0.85; to: 1.15; duration: 120; easing.type: Easing.OutQuad }
    NumberAnimation { target: root.target; property: "scale"; from: 1.15; to: 0.95; duration: 100; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root.target; property: "scale"; from: 0.95; to: 1.0;  duration: 100; easing.type: Easing.OutQuad }
}
