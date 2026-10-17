/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "qmltypes.h"

#include <QObject>
#include <QtQuickTest>

// The shared QML imports dev.xarbit.appgrid.models for the C++ enums, which
// the applets and the daemon register at startup; do the same here.
class Setup : public QObject
{
    Q_OBJECT

public Q_SLOTS:
    void applicationAvailable()
    {
        AppGridQml::registerTypes();
    }
};

QUICK_TEST_MAIN_WITH_SETUP(appgrid_qml, Setup)

#include "main.moc"
