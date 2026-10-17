/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    DefaultAppsResolver's parts: the defaults read from mimeapps.list, the
    files the XDG spec lists, the terminal from kdeglobals, and exec names.
*/

#include <KConfig>
#include <KConfigGroup>
#include <KSharedConfig>

#include <QFile>
#include <QTemporaryDir>
#include <QTest>

#include "defaultappsresolver.h"

using namespace DefaultAppsResolver;

class TestDefaultAppsResolver : public QObject
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

    void mimeAppsListPaths_followsTheSpec()
    {
        const QStringList paths = mimeAppsListPaths({QStringLiteral("/home/u/.config"), QStringLiteral("/etc/xdg")},
                                                    {QStringLiteral("/home/u/.local/share"), QStringLiteral("/usr/share")},
                                                    {QStringLiteral("KDE")});
        QCOMPARE(paths,
                 QStringList({
                     QStringLiteral("/home/u/.config/kde-mimeapps.list"),
                     QStringLiteral("/home/u/.config/mimeapps.list"),
                     QStringLiteral("/etc/xdg/kde-mimeapps.list"),
                     QStringLiteral("/etc/xdg/mimeapps.list"),
                     QStringLiteral("/home/u/.local/share/applications/kde-mimeapps.list"),
                     QStringLiteral("/home/u/.local/share/applications/mimeapps.list"),
                     QStringLiteral("/usr/share/applications/kde-mimeapps.list"),
                     QStringLiteral("/usr/share/applications/mimeapps.list"),
                 }));
        QCOMPARE(mimeAppsListPaths({QStringLiteral("/c")}, {}, {}), QStringList{QStringLiteral("/c/mimeapps.list")});
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
};

QTEST_GUILESS_MAIN(TestDefaultAppsResolver)
#include "test_defaultappsresolver.moc"
