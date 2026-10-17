/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The standalone daemon's start-up parts: the command line it understands,
    and saving its settings shortly after the launcher changes them.
*/

#include "configautosave.h"
#include "standaloneoptions.h"

#include <KConfigGroup>
#include <KCoreConfigSkeleton>
#include <KSharedConfig>

#include <QTemporaryDir>
#include <QTest>

namespace
{
// A settings schema like the generated AppGridConfig: one property whose
// setter changes the setting in memory and emits its NOTIFY signal.
class TestConfig : public KCoreConfigSkeleton
{
    Q_OBJECT
    Q_PROPERTY(int value READ value WRITE setValue NOTIFY valueChanged)

public:
    explicit TestConfig(const KSharedConfig::Ptr &config)
        : KCoreConfigSkeleton(config)
    {
        setCurrentGroup(QStringLiteral("General"));
        m_item = addItemInt(QStringLiteral("value"), m_value, 0);
    }

    int value() const
    {
        return m_value;
    }
    void setValue(int value)
    {
        m_item->setValue(value);
        Q_EMIT valueChanged();
    }

Q_SIGNALS:
    void valueChanged();

private:
    int m_value = 0;
    KCoreConfigSkeleton::ItemInt *m_item = nullptr;
};
}

class TestStandaloneOptions : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void parsesEveryFlag()
    {
        const StandaloneOptions options = StandaloneOptions::parse({QStringLiteral("appgrid"),
                                                                    QStringLiteral("--daemon"),
                                                                    QStringLiteral("--configure"),
                                                                    QStringLiteral("--compact"),
                                                                    QStringLiteral("--replace"),
                                                                    QStringLiteral("--plasmoid-id=42")});
        QVERIFY(options.daemon);
        QVERIFY(options.configure);
        QVERIFY(options.compact);
        QVERIFY(options.replace);
        QCOMPARE(options.plasmoidId, QStringLiteral("42"));
    }

    void plainLaunchAsksForNothing()
    {
        const StandaloneOptions options = StandaloneOptions::parse({QStringLiteral("appgrid")});
        QVERIFY(!options.daemon);
        QVERIFY(!options.configure);
        QVERIFY(!options.compact);
        QVERIFY(!options.replace);
        QVERIFY(options.plasmoidId.isEmpty());
    }

    void savesShortlyAfterAChange()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.filePath(QStringLiteral("testrc"));
        TestConfig config(KSharedConfig::openConfig(path, KConfig::SimpleConfig));
        ConfigAutosave::install(&config, 10);

        config.setValue(7);
        config.setValue(8);
        QTRY_COMPARE(KConfigGroup(KSharedConfig::openConfig(path, KConfig::SimpleConfig), QStringLiteral("General")).readEntry("value", 0), 8);
    }
};

QTEST_GUILESS_MAIN(TestStandaloneOptions)

#include "test_standaloneoptions.moc"
