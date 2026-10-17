/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Key parity for the settings pages. A shared *Content.qml page edits an
    injected `configuration` object; in the plasmoid dialog that object is the
    wrapper's buffer, and Plasma only loads and saves keys the wrapper exposes as
    `cfg_<key>`. A key the Content page uses but the wrapper lacks silently never
    loads or saves (enableActivities in the panel dialog). Every key a page
    touches, directly or through the config helpers it embeds, must be a
    property of its wrapper's buffer and an entry in main.xml; every key it
    writes must also have a `cfg_` alias so Plasma saves it. (A key only read,
    like the Appearance page's showCategoryBar gate, is a plain buffer property
    owned and saved by another page.)
*/

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSet>
#include <QTest>

namespace
{
const QString kConfigDir = QStringLiteral(APPGRID_SOURCE_DIR "/package/contents/ui/config");
const QString kSchema = QStringLiteral(APPGRID_SOURCE_DIR "/package/contents/config/main.xml");

QString readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromUtf8(file.readAll());
}

QSet<QString> matches(const QString &text, const QRegularExpression &re)
{
    QSet<QString> result;
    auto it = re.globalMatch(text);
    while (it.hasNext()) {
        result.insert(it.next().captured(1));
    }
    return result;
}

// Keys a page uses through `configuration.<key>` (any access, or only writes
// when @p writesOnly), including the config-dir helper components it
// instantiates (IconPickerButton, ...).
QSet<QString> keysUsedBy(const QString &pageFile, bool writesOnly)
{
    static const QRegularExpression anyRe(QStringLiteral("\\bconfiguration\\.([A-Za-z]+)"));
    static const QRegularExpression writeRe(QStringLiteral("\\bconfiguration\\.([A-Za-z]+)\\s*=(?!=)"));
    const QRegularExpression &keyRe = writesOnly ? writeRe : anyRe;
    const QString page = readFile(pageFile);
    QSet<QString> keys = matches(page, keyRe);

    const QStringList helpers = QDir(kConfigDir).entryList({QStringLiteral("*.qml")}, QDir::Files);
    for (const QString &helper : helpers) {
        const QString type = QFileInfo(helper).completeBaseName();
        if (type == QFileInfo(pageFile).completeBaseName()) {
            continue;
        }
        const QRegularExpression useRe(QStringLiteral("\\b%1\\s*\\{").arg(type));
        if (useRe.match(page).hasMatch()) {
            keys.unite(matches(readFile(kConfigDir + QLatin1Char('/') + helper), keyRe));
        }
    }
    return keys;
}
}

class TestConfigKeys : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void wrapperExposesEveryKey_data()
    {
        QTest::addColumn<QString>("page");
        QTest::addColumn<QString>("wrapper");
        const QStringList contents = QDir(kConfigDir).entryList({QStringLiteral("Config*Content.qml")}, QDir::Files);
        QVERIFY(!contents.isEmpty());
        for (const QString &content : contents) {
            QString wrapper = content;
            wrapper.replace(QLatin1String("Content.qml"), QLatin1String(".qml"));
            QTest::newRow(qPrintable(content)) << content << wrapper;
        }
        // The button page is its own wrapper and embeds the same helpers.
        QTest::newRow("ConfigButton.qml") << QStringLiteral("ConfigButton.qml") << QStringLiteral("ConfigButton.qml");
    }

    void wrapperExposesEveryKey()
    {
        QFETCH(QString, page);
        QFETCH(QString, wrapper);

        const QString wrapperText = readFile(kConfigDir + QLatin1Char('/') + wrapper);
        QVERIFY2(!wrapperText.isEmpty(), qPrintable(QStringLiteral("missing wrapper ") + wrapper));
        static const QRegularExpression cfgRe(QStringLiteral("\\bproperty\\s+alias\\s+cfg_([A-Za-z]+)"));
        static const QRegularExpression propRe(QStringLiteral("\\bproperty\\s+[\\w<>]+\\s+([A-Za-z]+)\\b"));
        const QSet<QString> saved = matches(wrapperText, cfgRe);
        const QSet<QString> provided = matches(wrapperText, propRe);
        const QString schema = readFile(kSchema);
        const QString pagePath = kConfigDir + QLatin1Char('/') + page;

        for (const QString &key : keysUsedBy(pagePath, false)) {
            QVERIFY2(provided.contains(key), qPrintable(QStringLiteral("%1 uses configuration.%2 but %3 provides no such property").arg(page, key, wrapper)));
            QVERIFY2(schema.contains(QStringLiteral("<entry name=\"%1\"").arg(key)),
                     qPrintable(QStringLiteral("%1 uses %2, missing in main.xml").arg(page, key)));
        }
        for (const QString &key : keysUsedBy(pagePath, true)) {
            QVERIFY2(saved.contains(key),
                     qPrintable(QStringLiteral("%1 writes configuration.%2 but %3 has no cfg_%2, so it is never saved").arg(page, key, wrapper)));
        }
    }
};

QTEST_GUILESS_MAIN(TestConfigKeys)
#include "test_configkeys.moc"
