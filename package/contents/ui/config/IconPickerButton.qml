/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The launcher button's icon picker as a SINGLE form control: a framed icon
    preview that opens the icon chooser (or accepts a dropped image file). Placed
    directly in the host's Kirigami.FormLayout (the host sets FormData.label), so
    it aligns with every other row — no nested FormLayout, which would render in a
    different wide/wrap mode and misalign (#191).

    Value-reading bindings depend on `revision` so a host can force a re-read of
    `configuration` after a revert / load-defaults.
*/

import QtQuick
import QtQuick.Controls as QQC2

import org.kde.draganddrop as DragDrop
import org.kde.iconthemes as KIconThemes
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.core as PlasmaCore

QQC2.Button {
    id: iconButton

    property var configuration
    property int location: 0            // PlasmaCore.Types.Location (preview frame)
    property string defaultIcon: "dev.xarbit.appgrid"
    property int revision: 0
    // The configured icon: its theme name, or the dropped image's path.
    readonly property string _iconText: {
        void iconButton.revision
        return iconButton.configuration.useCustomButtonImage
            ? iconButton.configuration.customButtonImage : iconButton.configuration.icon
    }

    implicitWidth: previewFrame.width + Kirigami.Units.smallSpacing * 2
    implicitHeight: previewFrame.height + Kirigami.Units.smallSpacing * 2
    checkable: true
    checked: dropArea.containsAcceptableDrag
    onPressed: iconMenu.opened ? iconMenu.close() : iconMenu.open()

    QQC2.ToolTip.text: i18ndc("dev.xarbit.appgrid",
                              "@info:tooltip %1 is the icon-theme name or, if an image was dropped in, the file path of the configured launcher icon",
                              "Icon name is \"%1\"",
                              iconButton._iconText)
    QQC2.ToolTip.visible: iconButton.hovered
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

    DragDrop.DropArea {
        id: dropArea
        property bool containsAcceptableDrag: false
        anchors.fill: parent

        onDragEnter: event => {
            const urlString = event.mimeData.url.toString();
            const extensions = [".png", ".xpm", ".svg", ".svgz"];
            containsAcceptableDrag = urlString.startsWith("file:///")
                && extensions.some(ext => urlString.endsWith(ext));
            if (!containsAcceptableDrag) event.ignore();
        }
        onDragLeave: containsAcceptableDrag = false
        onDrop: event => {
            if (containsAcceptableDrag)
                iconDialog.setCustomButtonImage(event.mimeData.url.toString().substr("file://".length));
            containsAcceptableDrag = false;
        }
    }

    KIconThemes.IconDialog {
        id: iconDialog
        function setCustomButtonImage(image) {
            iconButton.configuration.customButtonImage = image || iconButton.configuration.icon || iconButton.defaultIcon
            iconButton.configuration.useCustomButtonImage = true;
        }
        onIconNameChanged: iconName => setCustomButtonImage(iconName)
    }

    KSvg.FrameSvgItem {
        id: previewFrame
        anchors.centerIn: parent
        imagePath: iconButton.location === PlasmaCore.Types.Vertical
                   || iconButton.location === PlasmaCore.Types.Horizontal
                   ? "widgets/panel-background" : "widgets/background"
        width: Kirigami.Units.iconSizes.large + fixedMargins.left + fixedMargins.right
        height: Kirigami.Units.iconSizes.large + fixedMargins.top + fixedMargins.bottom

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: width
            source: iconButton._iconText
        }
    }

    QQC2.Menu {
        id: iconMenu
        y: parent.height
        onClosed: iconButton.checked = false

        QQC2.MenuItem {
            text: i18ndc("dev.xarbit.appgrid", "@item:inmenu Open icon chooser dialog", "Choose…")
            icon.name: "document-open-folder"
            onClicked: iconDialog.open()
        }
        QQC2.MenuItem {
            text: i18ndc("dev.xarbit.appgrid", "@item:inmenu Reset icon to default", "Clear Icon")
            icon.name: "edit-clear"
            onClicked: {
                iconButton.configuration.icon = iconButton.defaultIcon
                iconButton.configuration.customButtonImage = ""
                iconButton.configuration.useCustomButtonImage = false
            }
        }
    }
}
