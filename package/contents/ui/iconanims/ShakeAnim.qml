import QtQuick

SequentialAnimation {
    id: root
    property Item target: null

    NumberAnimation { target: root.target; property: "rotation"; from: 0;  to: 8;  duration: 50;  easing.type: Easing.InOutQuad }
    NumberAnimation { target: root.target; property: "rotation"; from: 8;  to: -7; duration: 90;  easing.type: Easing.InOutQuad }
    NumberAnimation { target: root.target; property: "rotation"; from: -7; to: 5;  duration: 80;  easing.type: Easing.InOutQuad }
    NumberAnimation { target: root.target; property: "rotation"; from: 5;  to: -3; duration: 70;  easing.type: Easing.InOutQuad }
    NumberAnimation { target: root.target; property: "rotation"; from: -3; to: 2;  duration: 60;  easing.type: Easing.InOutQuad }
    NumberAnimation { target: root.target; property: "rotation"; from: 2;  to: 0;  duration: 50;  easing.type: Easing.OutQuad }
}
