import QtQuick

SequentialAnimation {
    id: root
    property Item target: null

    NumberAnimation { target: root.target; property: "rotation"; from: 0; to: 360; duration: 400; easing.type: Easing.InOutCubic }
    ScriptAction { script: root.target.rotation = 0 }
}
