/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    RunnerResults: the app a services-runner result stands for, and the
    favourite runners read from krunnerrc.
*/

#include <KConfigGroup>
#include <KSharedConfig>

#include <QFile>
#include <QList>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

#include "runnerresults.h"

using namespace RunnerResults;

class TestRunnerResults : public QObject
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
    void desktopPathFromRunnerUrls_findsFirstDesktop()
    {
        const QList<QUrl> urls{QUrl::fromLocalFile(QStringLiteral("/tmp/note.txt")),
                               QUrl::fromLocalFile(QStringLiteral("/usr/share/applications/org.kde.kate.desktop"))};
        QCOMPARE(desktopPathFromRunnerUrls(QVariant::fromValue(urls)), QStringLiteral("/usr/share/applications/org.kde.kate.desktop"));
    }

    void desktopPathFromRunnerUrls_emptyWhenNoDesktop()
    {
        const QList<QUrl> urls{QUrl::fromLocalFile(QStringLiteral("/tmp/note.txt"))};
        QVERIFY(desktopPathFromRunnerUrls(QVariant::fromValue(urls)).isEmpty());
        QVERIFY(desktopPathFromRunnerUrls(QVariant()).isEmpty());
    }

    void readRunnerFavorites_readsOrderedPluginList()
    {
        QTemporaryDir dir;
        auto cfg = KSharedConfig::openConfig(dir.filePath(QStringLiteral("krunnerrc")), KConfig::SimpleConfig);
        const QStringList arrangement{QStringLiteral("windows"), QStringLiteral("krunner_services"), QStringLiteral("krunner_systemsettings")};
        cfg->group(QStringLiteral("Plugins")).group(QStringLiteral("Favorites")).writeEntry("plugins", arrangement);

        // Order must be preserved exactly — it is the plugin arrangement.
        QCOMPARE(readRunnerFavorites(cfg), arrangement);
    }

    void readRunnerFavorites_emptyWhenUnsetOrNull()
    {
        QTemporaryDir dir;
        auto cfg = KSharedConfig::openConfig(dir.filePath(QStringLiteral("empty")), KConfig::SimpleConfig);
        QVERIFY(readRunnerFavorites(cfg).isEmpty()); // group/key absent
        QVERIFY(readRunnerFavorites(KSharedConfig::Ptr()).isEmpty()); // null config
    }
};

QTEST_GUILESS_MAIN(TestRunnerResults)
#include "test_runnerresults.moc"
