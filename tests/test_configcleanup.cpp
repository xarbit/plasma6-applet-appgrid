/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    ConfigCleanup: only the keys no current code reads are dropped.
*/

#include <KConfig>
#include <KConfigGroup>
#include <KSharedConfig>

#include <QFile>
#include <QTemporaryDir>
#include <QTest>

#include "configcleanup.h"

using namespace ConfigCleanup;

class TestConfigCleanup : public QObject
{
    Q_OBJECT

private:
    // Write @p contents to a file in @p dir and return its path.
    static QString writeFile(const QTemporaryDir &dir, const QString &contents)
    {
        const QString path = dir.filePath(QStringLiteral("config"));
        QFile file(path);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(contents.toUtf8());
        }
        return path;
    }

private Q_SLOTS:
    void pruneObsoleteKeys_dropsDeadFieldsOnly()
    {
        QTemporaryDir dir;
        auto cfg = KSharedConfig::openConfig(dir.filePath(QStringLiteral("appgridrc")), KConfig::SimpleConfig);
        KConfigGroup g = cfg->group(QStringLiteral("General"));
        g.writeEntry(QStringLiteral("favoritesPortedToKAstats"), true); // dead migration flag
        g.writeEntry(QStringLiteral("enableBlur"), false); // dead appearance key
        g.writeEntry(QStringLiteral("gridColumns"), 6); // live schema key
        g.writeEntry(QStringLiteral("hiddenApps"), QStringList{QStringLiteral("a.desktop")}); // launch-state key

        pruneObsoleteKeys(g);

        QVERIFY(!g.hasKey(QStringLiteral("favoritesPortedToKAstats")));
        QVERIFY(!g.hasKey(QStringLiteral("enableBlur")));
        QVERIFY(g.hasKey(QStringLiteral("gridColumns")));
        QVERIFY(g.hasKey(QStringLiteral("hiddenApps")));
    }
};

QTEST_GUILESS_MAIN(TestConfigCleanup)
#include "test_configcleanup.moc"
