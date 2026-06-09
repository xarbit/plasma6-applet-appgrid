/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for the pure helpers extracted from AppGridPlugin: /etc/shells
    and /etc/os-release parsing, tilde expansion, and the file-browser
    directory listing (exercised against a QTemporaryDir).
*/

#include <KConfigGroup>
#include <KSharedConfig>

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
    static QStringList entryNames(const QVariantList &list)
    {
        QStringList names;
        for (const auto &v : list)
            names << v.toMap().value(QStringLiteral("name")).toString();
        return names;
    }

private Q_SLOTS:
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

    void parseOsPrettyName_unquotes()
    {
        const QString contents = QStringLiteral("NAME=Arch\nPRETTY_NAME=\"Arch Linux\"\nID=arch\n");
        QCOMPARE(parseOsPrettyName(contents), QStringLiteral("Arch Linux"));
    }

    void parseOsPrettyName_unquotedValue()
    {
        QCOMPARE(parseOsPrettyName(QStringLiteral("PRETTY_NAME=Fedora\n")), QStringLiteral("Fedora"));
    }

    void parseOsPrettyName_missing()
    {
        QCOMPARE(parseOsPrettyName(QStringLiteral("NAME=Foo\nID=foo\n")), QString());
    }

    // CRLF endings (e.g. an os-release file written or copied via Windows
    // tooling) used to leak a trailing \r into the value because the
    // closing quote-strip didn't see endsWith('"').
    void parseOsPrettyName_handlesCrlf()
    {
        QCOMPARE(parseOsPrettyName(QStringLiteral("PRETTY_NAME=\"Foo\"\r\n")),
                 QStringLiteral("Foo"));
        QCOMPARE(parseOsPrettyName(QStringLiteral("PRETTY_NAME=Bar\r\n")),
                 QStringLiteral("Bar"));
    }

    // Comment lines must not be matched as the key.
    void parseOsPrettyName_skipsCommentLines()
    {
        const QString contents = QStringLiteral(
            "# generated header\n"
            "NAME=Foo\n"
            "# PRETTY_NAME=\"NOT THIS\"\n"
            "PRETTY_NAME=\"Real\"\n");
        QCOMPARE(parseOsPrettyName(contents), QStringLiteral("Real"));
    }

    // An indented line is tolerated thanks to the per-line trim;
    // documents that current behavior rather than relying on it.
    void parseOsPrettyName_toleratesLeadingWhitespace()
    {
        QCOMPARE(parseOsPrettyName(QStringLiteral("    PRETTY_NAME=Indented\n")),
                 QStringLiteral("Indented"));
    }

    // The first matching key wins; later definitions are ignored
    // (matches how shell `source` evaluation would treat the file).
    void parseOsPrettyName_returnsFirstMatch()
    {
        const QString contents = QStringLiteral(
            "PRETTY_NAME=First\n"
            "PRETTY_NAME=Second\n");
        QCOMPARE(parseOsPrettyName(contents), QStringLiteral("First"));
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
            if (list.at(i).toMap().value(QStringLiteral("isDir")).toBool())
                lastDir = i;
            else if (firstFile == list.size())
                firstFile = i;
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
            if (map.value(QStringLiteral("isDir")).toBool())
                QCOMPARE(map.value(QStringLiteral("icon")).toString(), QStringLiteral("folder"));
        }
    }

    void parseMimeAppsDefaults_extractsDefaultSection()
    {
        const QString contents = QStringLiteral(
            "[Added Associations]\n"
            "text/plain=ignored.desktop;\n"
            "[Default Applications]\n"
            "text/html=firefox.desktop;chromium.desktop\n"
            "# comment line\n"
            "application/pdf=okular.desktop\n"
            "[Removed Associations]\n"
            "text/html=alsoignored.desktop\n");
        QStringList ids = parseMimeAppsDefaults(contents);
        ids.sort();
        QCOMPARE(ids, QStringList({QStringLiteral("chromium.desktop"),
                                   QStringLiteral("firefox.desktop"),
                                   QStringLiteral("okular.desktop")}));
    }

    void parseMimeAppsDefaults_emptyOnNoDefaultSection()
    {
        QVERIFY(parseMimeAppsDefaults(QString()).isEmpty());
        QVERIFY(parseMimeAppsDefaults(QStringLiteral(
                    "[Added Associations]\ntext/plain=foo.desktop\n"))
                    .isEmpty());
    }

    void desktopPathFromRunnerUrls_findsFirstDesktop()
    {
        const QList<QUrl> urls{QUrl::fromLocalFile(QStringLiteral("/tmp/note.txt")),
                               QUrl::fromLocalFile(QStringLiteral("/usr/share/applications/org.kde.kate.desktop"))};
        QCOMPARE(desktopPathFromRunnerUrls(QVariant::fromValue(urls)),
                 QStringLiteral("/usr/share/applications/org.kde.kate.desktop"));
    }

    void desktopPathFromRunnerUrls_emptyWhenNoDesktop()
    {
        const QList<QUrl> urls{QUrl::fromLocalFile(QStringLiteral("/tmp/note.txt"))};
        QVERIFY(desktopPathFromRunnerUrls(QVariant::fromValue(urls)).isEmpty());
        QVERIFY(desktopPathFromRunnerUrls(QVariant()).isEmpty());
    }

    void parseKdeTerminalDefaults_readsTerminalKeysOnly()
    {
        // TerminalApplication (exec line) + TerminalService (.desktop id, current
        // Plasma 6) are both read. Browser keys are NOT — the browser default
        // comes from KApplicationTrader, so a stale kdeglobals copy can't shadow
        // it. Keys outside [General] are ignored.
        const QString contents = QStringLiteral(
            "[General]\n"
            "TerminalApplication=/usr/bin/ghostty --gtk-single-instance=true\n"
            "TerminalService=org.kde.konsole.desktop\n"
            "BrowserApplication=firefox.desktop\n"
            "BrowserService=vivaldi-stable.desktop\n"
            "[KDE]\n"
            "TerminalApplication=should-be-ignored\n");
        const QStringList v = parseKdeTerminalDefaults(contents);
        QVERIFY(v.contains(QStringLiteral("/usr/bin/ghostty --gtk-single-instance=true")));
        QVERIFY(v.contains(QStringLiteral("org.kde.konsole.desktop")));
        QVERIFY(!v.contains(QStringLiteral("firefox.desktop")));
        QVERIFY(!v.contains(QStringLiteral("vivaldi-stable.desktop")));
        QVERIFY(!v.contains(QStringLiteral("should-be-ignored")));
    }

    void parseKdeTerminalDefaults_emptyOutsideGeneral()
    {
        QVERIFY(parseKdeTerminalDefaults(QString()).isEmpty());
        QVERIFY(parseKdeTerminalDefaults(QStringLiteral("[KDE]\nTerminalApplication=x\n")).isEmpty());
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
        const QStringList arrangement{QStringLiteral("windows"),
                                      QStringLiteral("krunner_services"),
                                      QStringLiteral("krunner_systemsettings")};
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

QTEST_GUILESS_MAIN(TestPluginHelpers)
#include "test_pluginhelpers.moc"
