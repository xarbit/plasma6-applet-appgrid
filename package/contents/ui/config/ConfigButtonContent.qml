/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasmoid-free body for the launcher BUTTON's appearance: the panel icon and
    its text label. These are properties of the plasmoid placed in the panel, not
    of the launcher window, so they live in the Plasma applet config (both
    variants) and are deliberately ABSENT from the daemon's settings window.

    Hosted nested inside ConfigGeneralContent (panel variant, full General page)
    and standalone by ConfigButton.qml (center variant's trimmed config). As a
    Kirigami.FormLayout nested in another it auto-aligns its label column with the
    host (twin form layouts).

    Value-reading bindings depend on `revision` so a host can force a re-read of
    `configuration` after a revert / load-defaults.
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.draganddrop as DragDrop
import org.kde.iconthemes as KIconThemes
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.core as PlasmaCore

Kirigami.FormLayout {
    id: root

    // Span the host's width so, nested inside another FormLayout (the General
    // page / the daemon window), the twin label columns align left with the rest
    // of the form instead of the icon + text-label rows drifting right (#191).
    Layout.fillWidth: true

    // -- Injected context --------------------------------------------------
    property var configuration
    property int formFactor: 0          // PlasmaCore.Types.FormFactor
    property int location: 0            // PlasmaCore.Types.Location (icon preview frame)
    property string defaultIcon: "dev.xarbit.appgrid"
    // Bumped by the host to force the value bindings below to re-read.
    property int revision: 0

    QQC2.Button {
        id: iconButton
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icon:")
        implicitWidth: previewFrame.width + Kirigami.Units.smallSpacing * 2
        implicitHeight: previewFrame.height + Kirigami.Units.smallSpacing * 2
        checkable: true
        checked: dropArea.containsAcceptableDrag
        onPressed: iconMenu.opened ? iconMenu.close() : iconMenu.open()

        QQC2.ToolTip.text: i18ndc("dev.xarbit.appgrid",
                                  "@info:tooltip %1 is the icon-theme name or, if an image was dropped in, the file path of the configured launcher icon",
                                  "Icon name is \"%1\"",
                                  (root.revision, root.configuration.useCustomButtonImage)
                                      ? root.configuration.customButtonImage
                                      : root.configuration.icon)
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
                root.configuration.customButtonImage = image || root.configuration.icon || root.defaultIcon
                root.configuration.useCustomButtonImage = true;
            }
            onIconNameChanged: iconName => setCustomButtonImage(iconName)
        }

        KSvg.FrameSvgItem {
            id: previewFrame
            anchors.centerIn: parent
            imagePath: root.location === PlasmaCore.Types.Vertical
                       || root.location === PlasmaCore.Types.Horizontal
                       ? "widgets/panel-background" : "widgets/background"
            width: Kirigami.Units.iconSizes.large + fixedMargins.left + fixedMargins.right
            height: Kirigami.Units.iconSizes.large + fixedMargins.top + fixedMargins.bottom

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.large
                height: width
                source: (root.revision, root.configuration.useCustomButtonImage)
                        ? root.configuration.customButtonImage
                        : root.configuration.icon
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
                    root.configuration.icon = root.defaultIcon
                    root.configuration.customButtonImage = ""
                    root.configuration.useCustomButtonImage = false
                }
            }
        }
    }

    Kirigami.ActionTextField {
        id: menuLabel
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Text label:")
        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        placeholderText: i18nd("dev.xarbit.appgrid", "Type here to add a text label")
        text: (root.revision, root.configuration.menuLabel)
        onTextChanged: root.configuration.menuLabel = text
        enabled: root.formFactor !== PlasmaCore.Types.Vertical
        rightActions: Kirigami.Action {
            icon.name: "edit-clear"
            visible: menuLabel.text.length > 0
            onTriggered: root.configuration.menuLabel = ""
        }
    }
}
