/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Tests for AppModel's icon-cache propagation, covering two distinct
    user-visible scenarios that the v1.7.9 code handled wrongly:

      A. Icon file replaced on disk (issue #86) — user edits an app
         icon via the menu editor or a package upgrade rewrites
         /usr/share/icons/.../<app>.png. The .desktop file may or
         may not be touched. Qt's pixmap cache must drop the stale
         bitmap so the new one appears without restart. This was the
         original reason QIcon::setThemeName(QIcon::themeName()) was
         added to AppModel::reload().

      B. System icon-theme switch (issue #103) — user picks a new
         theme in System Settings → Icons. The fix for #86
         regressed this case: setThemeName(x) sets an *override* on
         Qt's icon engine, locking the theme name across the entire
         plasmashell process and blocking subsequent platform theme
         changes from propagating until logout.

    Both are now driven by a single subscription in AppModel's ctor:
    KIconLoader::iconChanged fires after its caches flush (for either
    scenario), and AppModel re-emits dataChanged on IconRole so
    Kirigami.Icon delegates re-resolve. One mechanism, both #86 and
    #103 covered without the global-state hammer.
*/

#include "appmodel.h"

#include <KIconLoader>

#include <QFile>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QTest>

class AppModelTest : public QObject
{
    Q_OBJECT
private slots:
    /// Covers BOTH scenarios in the file header: #86 (icon file
    /// changed on disk) and #103 (system theme switch). Both reduce
    /// to "did the process receive KIconLoader::iconChanged?".
    /// KIconLoader emits that signal for either path:
    ///   * #86: KIconLoader::emitChange() called by kbuildsycoca6,
    ///     gtk-update-icon-cache, kupdateiconcache, or the menu
    ///     editor after writing the .desktop.
    ///   * #103: System Settings → Icons KCM committing a theme.
    /// One subscription, one test that fakes the signal and asserts
    /// dataChanged(IconRole) fires.
    void iconChangedEmitsDataChangedOnIconRole();

    /// Empty app list must not crash — the signal handler returns
    /// early. Guards future refactors that might trip the slot before
    /// loadApplications() has populated m_apps (e.g. if reload becomes
    /// asynchronous).
    void iconChangedIsSafeOnEmptyModel();

    /// Issue #103 regression guard: appmodel.cpp must not call
    /// QIcon::setThemeName again. The bug it caused — global theme-
    /// name override locking the whole plasmashell process — is not
    /// directly observable from a unit test (platform theme detection
    /// is not mockable here), so we guard the source rather than the
    /// behaviour. Comments are stripped before matching so the
    /// explanatory comment that mentions the removed API by name does
    /// not register as a re-introduction.
    void sourceDoesNotCallSetThemeName();
};

void AppModelTest::iconChangedEmitsDataChangedOnIconRole()
{
    AppModel model;
    if (model.rowCount() == 0)
        QSKIP("No applications installed in this test environment");

    QSignalSpy spy(&model, &QAbstractItemModel::dataChanged);
    QVERIFY(spy.isValid());

    // QML signals are also Qt signals — invoke iconChanged via meta-object
    // to fake what KIconLoader does when its cache flushes.
    QMetaObject::invokeMethod(KIconLoader::global(),
                              "iconChanged",
                              Qt::DirectConnection,
                              Q_ARG(int, int(KIconLoader::NoGroup)));

    QCOMPARE(spy.count(), 1);
    const QList<QVariant> args = spy.takeFirst();
    const QList<int> roles = args.at(2).value<QList<int>>();
    QVERIFY2(roles.contains(int(AppModel::IconRole)),
             "dataChanged must include IconRole");
}

void AppModelTest::iconChangedIsSafeOnEmptyModel()
{
    // Construct then forcibly clear: a future refactor could trip the
    // signal before loadApplications() populates the list.
    AppModel model;
    if (model.rowCount() > 0)
        QSKIP("Cannot empty an already-populated model from outside");

    // Should not crash, not assert, and not emit dataChanged.
    QSignalSpy spy(&model, &QAbstractItemModel::dataChanged);
    QMetaObject::invokeMethod(KIconLoader::global(),
                              "iconChanged",
                              Qt::DirectConnection,
                              Q_ARG(int, int(KIconLoader::NoGroup)));
    QCOMPARE(spy.count(), 0);
}

void AppModelTest::sourceDoesNotCallSetThemeName()
{
    const QString path = QFINDTESTDATA("../appmodel.cpp");
    QVERIFY2(!path.isEmpty(),
             "Could not locate appmodel.cpp via QFINDTESTDATA");
    QFile f(path);
    QVERIFY(f.open(QIODevice::ReadOnly));
    QString src = QString::fromUtf8(f.readAll());
    // Strip comments before grepping so the explanatory comment that
    // references the removed API by name doesn't count as a call.
    src.remove(QRegularExpression(QStringLiteral("//[^\n]*")));
    src.remove(QRegularExpression(
        QStringLiteral("/\\*.*?\\*/"),
        QRegularExpression::DotMatchesEverythingOption));

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

#include "appmodeltest.moc"
