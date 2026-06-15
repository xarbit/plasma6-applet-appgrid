/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Regression guard for issue #103: AppModel must not refresh icons via
    QIcon::setThemeName(QIcon::themeName()). That was the old fix for #86
    (icon file replaced on disk), but it sets a *global* override on Qt's
    icon engine, locking the theme name across the whole plasmashell process
    and blocking subsequent system icon-theme switches from propagating.

    The icon-theme / icon-file refresh now lives in AppFilterModel (an
    iconGeneration counter the delegates watch to force an in-place reload);
    see tst_appfiltermodel. This file only guards that the discarded
    setThemeName hammer doesn't return.
*/

#include "appmodel.h"

#include <QFile>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QTest>

class AppModelTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    /// Issue #103 regression guard: appmodel.cpp must not call
    /// QIcon::setThemeName again. The bug it caused — global theme-name
    /// override locking the whole plasmashell process — is not directly
    /// observable from a unit test (platform theme detection is not
    /// mockable here), so we guard the source rather than the
    /// behaviour. Comments are stripped before matching so the
    /// explanatory comment that mentions the removed API by name does
    /// not register as a re-introduction.
    void sourceDoesNotCallSetThemeName();
};

void AppModelTest::sourceDoesNotCallSetThemeName()
{
    const QString path = QFINDTESTDATA("../src/appmodel.cpp");
    QVERIFY2(!path.isEmpty(), "Could not locate appmodel.cpp via QFINDTESTDATA");
    QFile f(path);
    QVERIFY(f.open(QIODevice::ReadOnly));
    QString src = QString::fromUtf8(f.readAll());
    // Strip comments before grepping so the explanatory comment that
    // references the removed API by name doesn't count as a call.
    src.remove(QRegularExpression(QStringLiteral("//[^\n]*")));
    src.remove(QRegularExpression(QStringLiteral("/\\*.*?\\*/"), QRegularExpression::DotMatchesEverythingOption));

    QVERIFY2(!src.contains(QLatin1String("setThemeName")),
             "appmodel.cpp must not call QIcon::setThemeName — it sets a "
             "global override that blocks subsequent system icon-theme "
             "changes from propagating to this process (issue #103). "
             "Subscribe to KIconLoader::iconChanged instead.");
}

// Custom main because QTEST_MAIN selects QApplication when QtWidgets is
// linked; we only need QGuiApplication (KIconLoader requires Gui, not
// Widgets) and want zero link-time dependency on QtWidgets.
int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    AppModelTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_appmodel.moc"
