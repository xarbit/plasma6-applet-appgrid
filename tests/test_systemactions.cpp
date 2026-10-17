/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    SystemActions: the parts that need no running desktop — the shell list,
    empty commands doing nothing, the directory listing and the system info a
    bug report carries.
*/

#include "systemactions.h"

#include <QFile>
#include <QTemporaryDir>
#include <QTest>

class TestSystemActions : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void availableShellsExist()
    {
        SystemActions actions;
        const QStringList shells = actions.availableShells();
        for (const QString &shell : shells) {
            QVERIFY2(QFile::exists(shell), qPrintable(shell));
            QVERIFY(shell.startsWith(QLatin1Char('/')));
        }
    }

    void emptyCommandsDoNothing()
    {
        // Nothing to assert beyond not starting a process or crashing.
        SystemActions actions;
        actions.runCommand(QStringLiteral("   "));
        actions.runInTerminal(QString());
        actions.addToDesktop(QString());
        actions.openInDiscover(QString());
        QVERIFY(!actions.canManageInDiscover(QString()));
    }

    void listsDirectory()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile file(dir.filePath(QStringLiteral("note.txt")));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.close();

        SystemActions actions;
        QStringList names;
        const QVariantList entries = actions.listDirectory(dir.path());
        for (const QVariant &entry : entries) {
            names.append(entry.toMap().value(QStringLiteral("name")).toString());
        }
        QVERIFY(names.contains(QStringLiteral("note.txt")));
    }

    void systemInfoForReports()
    {
        SystemActions actions;
        const QVariantMap info = actions.systemInfo(QStringLiteral("Standalone"));
        QCOMPARE(info.value(QStringLiteral("variant")).toString(), QStringLiteral("Standalone"));
        QCOMPARE(info.value(QStringLiteral("appgridVersion")).toString(), QStringLiteral(APPGRID_VERSION));
        for (const char *key : {"plasmaVersion", "kfVersion", "qtVersion", "sessionType", "installType"}) {
            QVERIFY2(!info.value(QLatin1String(key)).toString().isEmpty(), key);
        }
    }
};

QTEST_MAIN(TestSystemActions)
#include "test_systemactions.moc"
