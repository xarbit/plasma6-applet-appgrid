/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for the pure helpers extracted from AppGridPlugin: /etc/shells
    parsing, tilde expansion, the file-browser directory listing (exercised
    against a QTemporaryDir), and the default apps read from mimeapps.list
    and kdeglobals.
*/

#include <KConfig>
#include <KConfigGroup>
#include <KSharedConfig>

#include <QFile>
#include <QList>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>
#include <QVariantMap>

#include "pluginhelpers.h"

using namespace PluginHelpers;

class TestPluginHelpers : public QObject
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

    static QStringList entryNames(const QVariantList &list)
    {
        QStringList names;
        for (const auto &v : list) {
            names << v.toMap().value(QStringLiteral("name")).toString();
        }
        return names;
    }

private Q_SLOTS:
    void toFavoriteId_prefixesAppsKeepsTheRest()
    {
        // Bare app storage id → gets the applications: scheme.
        QCOMPARE(toFavoriteId(QStringLiteral("org.kde.dolphin.desktop")), QStringLiteral("applications:org.kde.dolphin.desktop"));
        // An app action id (carries a query, no scheme) still prefixes.
        QCOMPARE(toFavoriteId(QStringLiteral("org.kde.spectacle.desktop?action=Record")),
                 QStringLiteral("applications:org.kde.spectacle.desktop?action=Record"));
        // Already-schemed ids are untouched.
        QCOMPARE(toFavoriteId(QStringLiteral("applications:org.kde.dolphin.desktop")), QStringLiteral("applications:org.kde.dolphin.desktop"));
        QCOMPARE(toFavoriteId(QStringLiteral("preferred://browser")), QStringLiteral("preferred://browser"));
        // A file favourite is stored as a bare path — it must NOT be prefixed,
        // or isFavorite/remove never match the stored row.
        QCOMPARE(toFavoriteId(QStringLiteral("/home/u/pic.png")), QStringLiteral("/home/u/pic.png"));
    }

    void parseShells_keepsValidLines()
    {
        const QString contents = QStringLiteral(
            "# /etc/shells: valid login shells\n"
            "/bin/bash\n"
            "\n"
            "   /usr/bin/zsh   \n"
            "#/bin/disabled\n"
            "/bin/sh\n");
        const QStringList shells = parseShells(contents);
        QCOMPARE(shells, QStringList({QStringLiteral("/bin/bash"), QStringLiteral("/usr/bin/zsh"), QStringLiteral("/bin/sh")}));
    }

    void parseShells_emptyOnBlank()
    {
        QVERIFY(parseShells(QString()).isEmpty());
        QVERIFY(parseShells(QStringLiteral("# only a comment\n\n")).isEmpty());
    }

    void expandTilde_expandsLeading()
    {
        QCOMPARE(expandTilde(QStringLiteral("~/Documents")), QDir::homePath() + QStringLiteral("/Documents"));
        QCOMPARE(expandTilde(QStringLiteral("~")), QDir::homePath());
    }

    void expandTilde_leavesAbsoluteAndRelative()
    {
        QCOMPARE(expandTilde(QStringLiteral("/etc/hosts")), QStringLiteral("/etc/hosts"));
        QCOMPARE(expandTilde(QStringLiteral("relative/path")), QStringLiteral("relative/path"));
    }

    void listDirectoryAt_listsDirsFirst()
    {
        QTemporaryDir tmp;
        QVERIFY(tmp.isValid());
        QDir d(tmp.path());
        QVERIFY(d.mkdir(QStringLiteral("subdir")));
        QFile fa(d.filePath(QStringLiteral("first.txt")));
        QVERIFY(fa.open(QIODevice::WriteOnly));
        QFile fb(d.filePath(QStringLiteral("second.log")));
        QVERIFY(fb.open(QIODevice::WriteOnly));

        const QVariantList list = listDirectoryAt(tmp.path());
        const QStringList names = entryNames(list);
        QVERIFY(names.contains(QStringLiteral("subdir")));
        QVERIFY(names.contains(QStringLiteral("first.txt")));
        QVERIFY(names.contains(QStringLiteral("second.log")));

        // Every directory entry must precede every file entry (DirsFirst).
        int lastDir = -1;
        int firstFile = list.size();
        for (int i = 0; i < list.size(); ++i) {
            if (list.at(i).toMap().value(QStringLiteral("isDir")).toBool()) {
                lastDir = i;
            } else if (firstFile == list.size()) {
                firstFile = i;
            }
        }
        QVERIFY(lastDir < firstFile);
    }

    void listDirectoryAt_partialPathFilters()
    {
        QTemporaryDir tmp;
        QVERIFY(tmp.isValid());
        QDir d(tmp.path());
        QFile fa(d.filePath(QStringLiteral("first.txt")));
        QVERIFY(fa.open(QIODevice::WriteOnly));
        QFile fb(d.filePath(QStringLiteral("second.log")));
        QVERIFY(fb.open(QIODevice::WriteOnly));

        const QStringList names = entryNames(listDirectoryAt(tmp.path() + QStringLiteral("/fir")));
        QCOMPARE(names, QStringList({QStringLiteral("first.txt")}));
    }

    void listDirectoryAt_missingReturnsEmpty()
    {
        QVERIFY(listDirectoryAt(QStringLiteral("/nonexistent-appgrid-xyz/sub")).isEmpty());
    }

    void listDirectoryAt_classifiesIcons()
    {
        QTemporaryDir tmp;
        QVERIFY(tmp.isValid());
        QDir d(tmp.path());
        QVERIFY(d.mkdir(QStringLiteral("folder1")));

        for (const auto &v : listDirectoryAt(tmp.path())) {
            const auto map = v.toMap();
            if (map.value(QStringLiteral("isDir")).toBool()) {
                QCOMPARE(map.value(QStringLiteral("icon")).toString(), QStringLiteral("folder"));
            }
        }
    }

    void mimeAppsDefaults_readsDefaultGroup()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = writeFile(dir,
                                       QStringLiteral("[Added Associations]\n"
                                                      "text/plain=ignored.desktop;\n"
                                                      "[Default Applications]\n"
                                                      "text/html=firefox.desktop;chromium.desktop\n"
                                                      "# comment line\n"
                                                      "application/pdf=okular.desktop\n"
                                                      "[Removed Associations]\n"
                                                      "text/html=alsoignored.desktop\n"));
        QStringList ids = mimeAppsDefaults(KConfig(path, KConfig::SimpleConfig));
        ids.sort();
        QCOMPARE(ids, QStringList({QStringLiteral("chromium.desktop"), QStringLiteral("firefox.desktop"), QStringLiteral("okular.desktop")}));
    }

    void mimeAppsDefaults_emptyWithoutDefaultGroup()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QVERIFY(mimeAppsDefaults(KConfig(dir.filePath(QStringLiteral("missing.list")), KConfig::SimpleConfig)).isEmpty());
        const QString path = writeFile(dir, QStringLiteral("[Added Associations]\ntext/plain=foo.desktop\n"));
        QVERIFY(mimeAppsDefaults(KConfig(path, KConfig::SimpleConfig)).isEmpty());
    }

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

    void kdeTerminalDefaults_readsTerminalKeysOnly()
    {
        // TerminalApplication (exec line) + TerminalService (.desktop id, current
        // Plasma 6) are both read. Browser keys are NOT — the browser default
        // comes from KApplicationTrader, so a stale kdeglobals copy can't shadow
        // it.
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = writeFile(dir,
                                       QStringLiteral("[General]\n"
                                                      "TerminalApplication=/usr/bin/ghostty --gtk-single-instance=true\n"
                                                      "TerminalService=org.kde.konsole.desktop\n"
                                                      "BrowserApplication=firefox.desktop\n"
                                                      "BrowserService=vivaldi-stable.desktop\n"
                                                      "[KDE]\n"
                                                      "TerminalApplication=should-be-ignored\n"));
        const KConfig config(path, KConfig::SimpleConfig);
        const QStringList v = kdeTerminalDefaults(config.group(QStringLiteral("General")));
        QCOMPARE(v, (QStringList{QStringLiteral("/usr/bin/ghostty --gtk-single-instance=true"), QStringLiteral("org.kde.konsole.desktop")}));
    }

    void kdeTerminalDefaults_emptyWithoutTerminal()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = writeFile(dir, QStringLiteral("[KDE]\nTerminalApplication=x\n"));
        const KConfig config(path, KConfig::SimpleConfig);
        QVERIFY(kdeTerminalDefaults(config.group(QStringLiteral("General"))).isEmpty());
    }

    void execBinaryName_stripsPathAndArgs()
    {
        QCOMPARE(execBinaryName(QStringLiteral("/usr/bin/ghostty --gtk-single-instance=true")), QStringLiteral("ghostty"));
        QCOMPARE(execBinaryName(QStringLiteral("konsole")), QStringLiteral("konsole"));
        QCOMPARE(execBinaryName(QStringLiteral("firefox.desktop")), QStringLiteral("firefox.desktop"));
        QCOMPARE(execBinaryName(QStringLiteral("  /opt/x/bin/foo -e ")), QStringLiteral("foo"));
        QCOMPARE(execBinaryName(QStringLiteral("\"/usr/bin/ghostty\"")), QStringLiteral("ghostty"));
        QVERIFY(execBinaryName(QString()).isEmpty());
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

QTEST_GUILESS_MAIN(TestPluginHelpers)
#include "test_pluginhelpers.moc"
