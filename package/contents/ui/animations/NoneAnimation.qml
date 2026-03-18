import QtQuick

Item {
    id: root
    property Item target: null
    property bool blurBeforeAnimation: true
    signal openFinished()
    signal closeFinished()

    function open() {
        target.opacity = 1.0
        openFinished()
    }
    function close() { closeFinished() }
    function reset() {}
}
