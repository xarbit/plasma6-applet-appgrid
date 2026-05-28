/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for the pure helpers extracted from AppGridPlugin: /etc/shells
    and /etc/os-release parsing, tilde expansion, and the file-browser
    directory listing (exercised against a QTemporaryDir).
*/

#include <QTemporaryDir>
#include <QTest>
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
        QFile fa(d.filePath(QStringLiteral("afile.txt")));
        QVERIFY(fa.open(QIODevice::WriteOnly));
        QFile fb(d.filePath(QStringLiteral("bfile.log")));
        QVERIFY(fb.open(QIODevice::WriteOnly));

        const QVariantList list = listDirectoryAt(tmp.path());
        const QStringList names = entryNames(list);
        QVERIFY(names.contains(QStringLiteral("subdir")));
        QVERIFY(names.contains(QStringLiteral("afile.txt")));
        QVERIFY(names.contains(QStringLiteral("bfile.log")));

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
        QFile fa(d.filePath(QStringLiteral("alpha.txt")));
        QVERIFY(fa.open(QIODevice::WriteOnly));
        QFile fb(d.filePath(QStringLiteral("beta.txt")));
        QVERIFY(fb.open(QIODevice::WriteOnly));

        const QStringList names = entryNames(listDirectoryAt(tmp.path() + QStringLiteral("/alph")));
        QCOMPARE(names, QStringList({QStringLiteral("alpha.txt")}));
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
};

QTEST_GUILESS_MAIN(TestPluginHelpers)
#include "test_pluginhelpers.moc"
