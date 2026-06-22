/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KService>
#include <KServiceAction>

#include <QMimeDatabase>
#include <QSet>
#include <QSortFilterProxyModel>
#include <QUrl>

#include <optional>

namespace KActivities
{
class Consumer;
namespace Stats
{
class ResultModel;
}
}

/**
 * @brief AppGrid's own KActivities favourites model.
 *
 * A thin proxy over KActivities::Stats::ResultModel (the public lib Kicker's
 * KAStatsFavoritesModel is built on), reading and writing the SAME shared
 * favourites store — the applications and documents favourites agents, the
 * global activity, ordered by the AppGrid client id — so favourites stay in
 * lockstep with Kickoff/Kicker and need no migration.
 *
 * Owning the model (rather than importing org.kde.plasma.private.kicker) buys
 * two things: it drops the private QML dependency, and it lets us decide how an
 * id is stored. KAStatsFavoritesModel normalises "applications:<id>?action=<a>"
 * down to the bare app, which is why a jump-list action favourite never
 * persisted; here we keep the action id verbatim (see FavoriteId::normalized),
 * so it survives reloads as its own resource (#64).
 *
 * The QML surface mirrors what the favourites UI already called on the Kicker
 * model — including answering @c favoriteId at Kicker's role number (259) — so
 * the consumers (FavoritesManager, favoritevisual.js, GridPanel) are unchanged.
 *
 * A favourite whose app is gone (uninstalled) is filtered out of the view, the
 * same way Kicker hides it. The KActivities link is left in place — the favourite
 * comes back if the app is reinstalled — so this is non-destructive.
 */
class AppGridFavoritesModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool enabled READ enabled NOTIFY enabledChanged)
    Q_PROPERTY(int favoriteIdRole READ favoriteIdRole CONSTANT)

public:
    enum Roles {
        // Kicker::FavoriteIdRole. Kept identical so the existing QML reads our
        // favourite id at the same role it probed on the Kicker model.
        FavoriteIdRole = 259,
    };

    explicit AppGridFavoritesModel(QObject *parent = nullptr);
    ~AppGridFavoritesModel() override;

    /** Register the type for QML instantiation (SharedFavoritesProvider.qml).
     *  Idempotent; safe to call from every controller instance. */
    static void registerQmlType();

    [[nodiscard]] int count() const;
    /** True once kactivitymanagerd is running and the store is readable. */
    [[nodiscard]] bool enabled() const;
    // A Q_PROPERTY READ accessor: must stay a non-static member for moc/QML.
    // cppcheck-suppress functionStatic
    [[nodiscard]] int favoriteIdRole() const
    {
        return FavoriteIdRole;
    }

    /** Build (or rebuild) the backing query for @p clientId — the ordering
     *  scope shared across AppGrid variants. */
    Q_INVOKABLE void initForClient(const QString &clientId);

    [[nodiscard]] Q_INVOKABLE bool isFavorite(const QString &id) const;
    /** Add @p id as a favourite. @p index >= 0 places it at that row once the
     *  asynchronous link surfaces (best effort); -1 appends. */
    Q_INVOKABLE void addFavorite(const QString &id, int index = -1);
    Q_INVOKABLE void removeFavorite(const QString &id);
    Q_INVOKABLE void moveRow(int from, int to);
    /** Launch the favourite at @p row — an app (with its jump-list action when
     *  the id carried one), or a document opened with its default app. The grid's
     *  fallback for rows it can't resolve through the app model (KCMs, files).
     *  @p actionId / @p argument exist for Kicker-model call compatibility and are
     *  unused — what to launch comes from the favourite id itself. */
    Q_INVOKABLE bool trigger(int row, const QString &actionId, const QVariant &argument);

    [[nodiscard]] QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

Q_SIGNALS:
    void countChanged();
    void enabledChanged();

protected:
    // Hide favourites whose app no longer resolves (uninstalled).
    [[nodiscard]] bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    // A favourite resolved to what it displays and launches as. Either an
    // application (service, plus the jump-list action when the id carried one)
    // or a document (a file/URL opened with its default app). @c valid is false
    // for a favourite whose target is gone (uninstalled app, deleted file).
    struct ResolvedFavorite {
        bool valid = false;
        QString name;
        QString icon;
        KService::Ptr service;
        std::optional<KServiceAction> action;
        QUrl documentUrl;
    };

    // Re-run the filter across Qt versions (6.13 replaced invalidateFilter()).
    void invalidateFilterCompat();
    [[nodiscard]] QString resourceAt(const QModelIndex &index) const;
    [[nodiscard]] QString resourceForSourceRow(int sourceRow, const QModelIndex &sourceParent) const;
    [[nodiscard]] ResolvedFavorite resolve(const QString &favoriteId) const;
    // Stored form of @p id: action ids verbatim, plain apps canonicalised.
    [[nodiscard]] QString storeId(const QString &id) const;
    [[nodiscard]] static KService::Ptr serviceFor(const QString &storageId);

    KActivities::Consumer *const m_consumer;
    KActivities::Stats::ResultModel *m_results = nullptr;
    QString m_clientId;
    // Reused across data()/resolve() calls — constructing one per row on every
    // view refresh is wasteful (its methods are const, so resolve() stays const).
    QMimeDatabase m_mimeDb;
    // Resources hidden the instant removeFavorite() runs. KActivities' ResultModel
    // does not reliably drop a linked row when it is unlinked (Kicker rolled its
    // own model for the same reason), so the view would otherwise only refresh on
    // reload. Filtered out until the real removal lands or the id is re-added.
    QSet<QString> m_pendingRemovals;
};
