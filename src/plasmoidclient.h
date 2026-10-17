/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QVariantMap>

/**
 * @brief What the launcher asks of the center plasmoid.
 *
 * Pinning to the Task Manager needs a live applet and corona. Hosted by an
 * applet (setInProcessPin) the pin goes back to that applet's QML through
 * addToTaskManagerRequested; the standalone daemon has neither, so it asks a
 * center plasmoid over dev.xarbit.appgrid.Plasmoid instead. The daemon's
 * settings window also reads and writes the panel button of the plasmoid it
 * was opened from (#191).
 */
class PlasmoidClient : public QObject
{
    Q_OBJECT

public:
    explicit PlasmoidClient(QObject *parent = nullptr);

    /** Pin in-process through addToTaskManagerRequested instead of over
     *  D-Bus. Set by a hosting applet; off for the daemon. */
    void setInProcessPin(bool inProcess);

    /** Pin @p desktopFile (an absolute .desktop path) to the Task Manager. */
    Q_INVOKABLE void addToTaskManager(const QString &desktopFile);
    /** True if pinning is possible: in-process, or a center plasmoid is on the
     *  bus. The menu hides the action otherwise. */
    [[nodiscard]] Q_INVOKABLE bool canPinToTaskManager() const;

    /** Edit the button of the center plasmoid @p plasmoidId (its D-Bus object
     *  path). Empty means no origin plasmoid, so nothing to edit. */
    void setButtonTargetId(const QString &plasmoidId);
    /** True when the settings window has a button to edit: it was opened from
     *  a center plasmoid that is still on the bus. */
    [[nodiscard]] Q_INVOKABLE bool canConfigureButton() const;
    /** The button appearance as last fetched (icon, customButtonImage,
     *  useCustomButtonImage, menuLabel). */
    [[nodiscard]] Q_INVOKABLE QVariantMap buttonAppearance() const;
    /** Fetch the button appearance; buttonAppearanceChanged() follows. */
    Q_INVOKABLE void requestButtonAppearance();
    /** Apply a new button appearance on the plasmoid. */
    Q_INVOKABLE void setButtonAppearance(const QVariantMap &values);

Q_SIGNALS:
    /** Pin @p desktopFile in-process (only with setInProcessPin). */
    void addToTaskManagerRequested(const QString &desktopFile);
    /** The settings were opened from another plasmoid while open; re-read its
     *  button. */
    void buttonTargetChanged();
    /** A requestButtonAppearance() reply arrived. */
    void buttonAppearanceChanged();

private:
    [[nodiscard]] static bool plasmoidPresent();

    bool m_inProcessPin = false;
    // Object path of the plasmoid whose button the settings edit; empty for none.
    QString m_buttonTargetPath;
    QVariantMap m_buttonAppearance;
};
