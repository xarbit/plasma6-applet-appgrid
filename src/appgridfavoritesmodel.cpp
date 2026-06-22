/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridfavoritesmodel.h"

#include "appactionid.h"
#include "favoriteid.h"

#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenUrlJob>
#include <KSycoca>

#include <PlasmaActivities/Consumer>
#include <PlasmaActivities/Info>
#include <PlasmaActivities/Stats/Query>
#include <PlasmaActivities/Stats/ResultModel>
#include <PlasmaActivities/Stats/ResultSet>
#include <PlasmaActivities/Stats/Terms>

#include <QFileInfo>
#include <QMimeType>
#include <QQmlEngine>

#include <memory>

namespace KAStats = KActivities::Stats;
namespace KASTerms = KActivities::Stats::Terms;

namespace
{
// The shared favourites agents — the same Kicker/Kickoff link to, so AppGrid
// reads and writes one cross-launcher set. Apps go under one, files/images under
// the other; both are read so every favourite type shows.
const QString kAgentApplications = QStringLiteral("org.kde.plasma.favorites.applications");
const QString kAgentDocuments = QStringLiteral("org.kde.plasma.favorites.documents");

// Activity selectors for link/unlink: a favourite is global (shows in every
// activity); removing clears it from any activity it was linked to.
const QString kActivityGlobal = QStringLiteral(":global");
const QString kActivityAny = QStringLiteral(":any");

// Favourites are a small, hand-curated set; the cap only guards against a
// runaway store. Well above any real favourites list.
constexpr int kFavoritesLimit = 1000;

// Which favourites agent a resource is linked under — documents for files/URLs,
// applications for everything else.
QString agentForResource(const QString &resource)
{
    return FavoriteId::isDocument(resource) ? kAgentDocuments : kAgentApplications;
}

// A document favourite id as a URL: a bare local path becomes a file:// URL, an
// already-schemed id is taken as-is.
QUrl urlForId(const QString &id)
{
    return id.startsWith(QLatin1Char('/')) ? QUrl::fromLocalFile(id) : QUrl(id);
}
}

void AppGridFavoritesModel::registerQmlType()
{
    qmlRegisterType<AppGridFavoritesModel>("dev.xarbit.appgrid.models", 1, 0, "AppGridFavoritesModel");
}

AppGridFavoritesModel::AppGridFavoritesModel(QObject *parent)
    : QSortFilterProxyModel(parent)
    , m_consumer(new KActivities::Consumer(this))
{
    connect(m_consumer, &KActivities::Consumer::serviceStatusChanged, this, [this] {
        Q_EMIT enabledChanged();
        // kactivitymanagerd came up after the model was built — rebuild so the
        // query actually returns the stored favourites (Kicker re-inits here too).
        if (m_consumer->serviceStatus() == KActivities::Consumer::Running && !m_clientId.isEmpty()) {
            initForClient(m_clientId);
        }
    });

    // The query re-resolves for the new activity on a switch; drop the optimistic
    // hides made for the previous activity's view so a favourite pinned to the
    // activity we just entered shows up again.
    connect(m_consumer, &KActivities::Consumer::currentActivityChanged, this, [this] {
        if (!m_pendingRemovals.isEmpty()) {
            m_pendingRemovals.clear();
            invalidateFilterCompat();
        }
    });

    // An app installed or removed at runtime flips a favourite's validity; re-run
    // the filter so an uninstalled one drops (and a reinstalled one returns).
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &AppGridFavoritesModel::invalidateFilterCompat);

    // The proxy's own row signals already fold in filtering, so count tracks the
    // visible favourites, not the raw store.
    connect(this, &QAbstractItemModel::rowsInserted, this, &AppGridFavoritesModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &AppGridFavoritesModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &AppGridFavoritesModel::countChanged);

    // Activity-submenu caches: the running-activities list rebuilds when the set
    // changes; the per-resource linked-activities lookup clears whenever the
    // favourite rows change (external link edits surface as row inserts/removals).
    connect(m_consumer, &KActivities::Consumer::activitiesChanged, this, [this] {
        m_activitiesCacheValid = false;
    });
    const auto clearLinked = [this] {
        m_linkedActivitiesCache.clear();
    };
    connect(this, &QAbstractItemModel::rowsInserted, this, clearLinked);
    connect(this, &QAbstractItemModel::rowsRemoved, this, clearLinked);
    connect(this, &QAbstractItemModel::modelReset, this, clearLinked);
}

AppGridFavoritesModel::~AppGridFavoritesModel() = default;

int AppGridFavoritesModel::count() const
{
    return rowCount();
}

bool AppGridFavoritesModel::enabled() const
{
    return m_consumer->serviceStatus() == KActivities::Consumer::Running;
}

void AppGridFavoritesModel::initForClient(const QString &clientId)
{
    m_clientId = clientId;
    if (clientId.isEmpty()) {
        return;
    }

    // LinkedResources (favourites), the applications agent, current + global
    // activity (a global favourite shows in every activity) — the same scope
    // KAStatsFavoritesModel reads. Ordering is the ResultModel's own, keyed by
    // the client id.
    const auto query = KAStats::Query(KASTerms::LinkedResources) | KASTerms::Agent({kAgentApplications, kAgentDocuments}) | KASTerms::Type::any()
        | KASTerms::Activity::current() | KASTerms::Activity::global() | KASTerms::Limit(kFavoritesLimit);

    auto *model = new KAStats::ResultModel(query, clientId, this);
    setSourceModel(model);
    if (m_results) {
        m_results->deleteLater();
    }
    m_results = model;
    m_pendingRemovals.clear();

    // When a row genuinely leaves the source (the unlink finally propagated, or an
    // external change), drop any matching optimistic-removal entry so the set stays
    // bounded and a later re-link isn't wrongly hidden.
    connect(model, &QAbstractItemModel::rowsAboutToBeRemoved, this, [this, model](const QModelIndex &parent, int first, int last) {
        for (int row = first; row <= last; ++row) {
            m_pendingRemovals.remove(model->index(row, 0, parent).data(KAStats::ResultModel::ResourceRole).toString());
        }
    });
    Q_EMIT countChanged();
}

bool AppGridFavoritesModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    const QString resource = resourceForSourceRow(sourceRow, sourceParent);
    // Just-removed favourite, hidden until the async unlink propagates (the
    // ResultModel may not drop the row itself — see m_pendingRemovals).
    if (m_pendingRemovals.contains(resource)) {
        return false;
    }
    // Drop dead favourites — an uninstalled app or a deleted file. Non-destructive:
    // the KActivities link stays, so reinstalling the app or restoring the file
    // brings the favourite back, matching Kicker, which also hides rather than unlinks.
    return resolve(resource).valid;
}

void AppGridFavoritesModel::invalidateFilterCompat()
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 13, 0)
    beginFilterChange();
    endFilterChange();
#else
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    invalidateFilter();
    QT_WARNING_POP
#endif
}

QString AppGridFavoritesModel::resourceForSourceRow(int sourceRow, const QModelIndex &sourceParent) const
{
    if (!sourceModel()) {
        return {};
    }
    return sourceModel()->index(sourceRow, 0, sourceParent).data(KAStats::ResultModel::ResourceRole).toString();
}

QString AppGridFavoritesModel::resourceAt(const QModelIndex &index) const
{
    return QSortFilterProxyModel::data(index, KAStats::ResultModel::ResourceRole).toString();
}

QString AppGridFavoritesModel::storeId(const QString &id) const
{
    if (FavoriteId::isDocument(id)) {
        const QUrl url = urlForId(id);
        // KActivities stores a local file as a bare canonical path (not a file://
        // URL), so key on that — otherwise isFavorite/removeFavorite never match
        // the stored row. Canonicalising also dedupes two paths to the same file.
        if (url.isLocalFile()) {
            const QFileInfo file(url.toLocalFile());
            return file.exists() ? file.canonicalFilePath() : url.toLocalFile();
        }
        return url.toString();
    }
    return FavoriteId::normalized(id, [](const QString &storageId) -> QString {
        const KService::Ptr service = serviceFor(storageId);
        return service ? service->menuId() : QString();
    });
}

KService::Ptr AppGridFavoritesModel::serviceFor(const QString &storageId)
{
    if (storageId.isEmpty()) {
        return {};
    }
    if (KService::Ptr service = KService::serviceByMenuId(storageId)) {
        return service;
    }
    if (KService::Ptr service = KService::serviceByStorageId(storageId)) {
        return service;
    }
    return KService::serviceByDesktopPath(storageId);
}

AppGridFavoritesModel::ResolvedFavorite AppGridFavoritesModel::resolve(const QString &favoriteId) const
{
    ResolvedFavorite resolved;
    if (favoriteId.isEmpty()) {
        return resolved;
    }

    if (FavoriteId::isDocument(favoriteId)) {
        const QUrl url = urlForId(favoriteId);
        // A deleted local file is a dead favourite (filtered out like an
        // uninstalled app); a remote URL is assumed reachable.
        if (url.isLocalFile() && !QFileInfo::exists(url.toLocalFile())) {
            return resolved;
        }
        const QMimeType mime = url.isLocalFile() ? m_mimeDb.mimeTypeForFile(url.toLocalFile()) : m_mimeDb.mimeTypeForUrl(url);
        resolved.valid = true;
        resolved.documentUrl = url;
        resolved.name = url.fileName().isEmpty() ? url.toString() : url.fileName();
        resolved.icon = mime.iconName();
        return resolved;
    }

    const AppActionId::Parsed parsed = AppActionId::parse(favoriteId);
    const KService::Ptr service = serviceFor(parsed.storageId);
    if (!service) {
        return resolved;
    }
    resolved.valid = true;
    resolved.service = service;
    if (!parsed.actionName.isEmpty()) {
        resolved.action = AppActionId::resolveAction(service, parsed.actionName);
    }
    if (resolved.action) {
        resolved.name = resolved.action->text();
        resolved.icon = resolved.action->icon();
    } else {
        resolved.name = service->name();
        resolved.icon = service->icon();
    }
    return resolved;
}

QVariant AppGridFavoritesModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || !sourceModel()) {
        return {};
    }

    if (role == FavoriteIdRole) {
        return resourceAt(index);
    }
    if (role != Qt::DisplayRole && role != Qt::DecorationRole) {
        return QSortFilterProxyModel::data(index, role);
    }

    const ResolvedFavorite resolved = resolve(resourceAt(index));
    if (!resolved.valid) {
        return role == Qt::DisplayRole ? resourceAt(index) : QString();
    }
    return role == Qt::DisplayRole ? resolved.name : resolved.icon;
}

QHash<int, QByteArray> AppGridFavoritesModel::roleNames() const
{
    QHash<int, QByteArray> roles = QSortFilterProxyModel::roleNames();
    roles.insert(FavoriteIdRole, QByteArrayLiteral("favoriteId"));
    roles.insert(Qt::DisplayRole, QByteArrayLiteral("display"));
    roles.insert(Qt::DecorationRole, QByteArrayLiteral("decoration"));
    return roles;
}

bool AppGridFavoritesModel::isFavorite(const QString &id) const
{
    const QString target = storeId(id);
    if (target.isEmpty()) {
        return false;
    }
    for (int row = 0, rows = rowCount(); row < rows; ++row) {
        if (data(index(row, 0), FavoriteIdRole).toString() == target) {
            return true;
        }
    }
    return false;
}

void AppGridFavoritesModel::addFavorite(const QString &id, int index)
{
    if (!m_results) {
        return;
    }
    const QString resource = storeId(id);
    if (resource.isEmpty()) {
        return;
    }
    // Re-adding something just optimistically removed: un-hide it.
    setResourceHidden(resource, false);
    if (index >= 0) {
        // linkToActivity is asynchronous; place the row once it surfaces. Watch
        // the model the link targets (not the member, which initForClient may
        // swap) and act only on the batch that actually carries this resource,
        // then disconnect — so racing adds don't each fire on the first insert.
        auto *model = m_results;
        const auto connection = std::make_shared<QMetaObject::Connection>();
        *connection = connect(model, &QAbstractItemModel::rowsInserted, this, [model, resource, index, connection](const QModelIndex &, int first, int last) {
            for (int row = first; row <= last; ++row) {
                if (model->index(row, 0).data(KAStats::ResultModel::ResourceRole).toString() == resource) {
                    model->setResultPosition(resource, index);
                    QObject::disconnect(*connection);
                    return;
                }
            }
        });
    }
    m_results->linkToActivity(urlForId(resource), KASTerms::Activity(kActivityGlobal), KASTerms::Agent(agentForResource(resource)));
}

QVariantList AppGridFavoritesModel::activities() const
{
    if (m_activitiesCacheValid) {
        return m_activitiesCache;
    }
    m_activitiesCache.clear();
    const QStringList ids = m_consumer->activities();
    m_activitiesCache.reserve(ids.size());
    for (const QString &id : ids) {
        KActivities::Info info(id);
        m_activitiesCache.append(QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), info.name()}});
    }
    m_activitiesCacheValid = true;
    return m_activitiesCache;
}

bool AppGridFavoritesModel::isLinkedTo(const QString &resource, const QString &agent, const QString &activity)
{
    const auto results = KAStats::ResultSet(KAStats::Query(KASTerms::LinkedResources) | KASTerms::Agent({agent}) | KASTerms::Activity(activity)
                                            | KASTerms::Type::any() | KASTerms::Limit(kFavoritesLimit));
    for (const auto &result : results) {
        if (result.resource() == resource) {
            return true;
        }
    }
    return false;
}

void AppGridFavoritesModel::setResourceHidden(const QString &resource, bool hidden)
{
    bool changed = false;
    if (hidden) {
        if (!m_pendingRemovals.contains(resource)) {
            m_pendingRemovals.insert(resource);
            changed = true;
        }
    } else {
        changed = m_pendingRemovals.remove(resource);
    }
    if (changed) {
        invalidateFilterCompat();
    }
}

QStringList AppGridFavoritesModel::linkedActivitiesFor(const QString &id) const
{
    const QString resource = storeId(id);
    if (resource.isEmpty()) {
        return {};
    }
    const auto cached = m_linkedActivitiesCache.constFind(resource);
    if (cached != m_linkedActivitiesCache.constEnd()) {
        return cached.value();
    }
    const QString agent = agentForResource(resource);
    QStringList linked;
    // A global link means "every activity"; report that as an empty list (the
    // contract setLinkedActivities() takes) so callers never handle the sentinel.
    if (!isLinkedTo(resource, agent, kActivityGlobal)) {
        for (const QString &activity : m_consumer->activities()) {
            if (isLinkedTo(resource, agent, activity)) {
                linked.append(activity);
            }
        }
    }
    m_linkedActivitiesCache.insert(resource, linked);
    return linked;
}

void AppGridFavoritesModel::setLinkedActivities(const QString &id, const QStringList &activityIds)
{
    if (!m_results) {
        return;
    }
    const QString resource = storeId(id);
    if (resource.isEmpty()) {
        return;
    }
    const QUrl url = urlForId(resource);
    const auto agent = KASTerms::Agent({agentForResource(resource)});
    // Replace the whole link set: clear every link, then re-link to the target.
    // An empty set means "all activities" → a single global link.
    m_results->unlinkFromActivity(url, KASTerms::Activity(kActivityAny), agent);
    if (activityIds.isEmpty()) {
        m_results->linkToActivity(url, KASTerms::Activity(kActivityGlobal), agent);
    } else {
        for (const QString &activity : activityIds) {
            m_results->linkToActivity(url, KASTerms::Activity(activity), agent);
        }
    }
    // The favourite still covers this view when it's global or pinned to the
    // current activity; otherwise it left, so hide it ahead of the async drop.
    const bool stillVisible = activityIds.isEmpty() || activityIds.contains(m_consumer->currentActivity());
    setResourceHidden(resource, !stillVisible);
    // The links just changed — drop the stale lookup (its row may not move).
    m_linkedActivitiesCache.remove(resource);
}

void AppGridFavoritesModel::removeFavorite(const QString &id)
{
    if (!m_results) {
        return;
    }
    const QString resource = storeId(id);
    if (resource.isEmpty()) {
        return;
    }
    m_results->unlinkFromActivity(urlForId(resource), KASTerms::Activity(kActivityAny), KASTerms::Agent(agentForResource(resource)));
    // Hide it now; the ResultModel doesn't reliably drop the row on unlink, so the
    // view would otherwise look unchanged until reload.
    setResourceHidden(resource, true);
}

void AppGridFavoritesModel::moveRow(int from, int to)
{
    if (!m_results || from < 0 || to < 0 || from >= rowCount() || to >= rowCount() || from == to) {
        return;
    }
    const QString resource = data(index(from, 0), FavoriteIdRole).toString();
    if (resource.isEmpty()) {
        return;
    }
    // setResultPosition orders the underlying store; map the target proxy row to
    // its source position so hidden (filtered) rows don't skew the placement.
    const int sourcePosition = mapToSource(index(to, 0)).row();
    m_results->setResultPosition(resource, sourcePosition);
}

bool AppGridFavoritesModel::trigger(int row, const QString &actionId, const QVariant &argument)
{
    Q_UNUSED(actionId);
    Q_UNUSED(argument);
    if (row < 0 || row >= rowCount()) {
        return false;
    }
    const ResolvedFavorite resolved = resolve(data(index(row, 0), FavoriteIdRole).toString());
    if (!resolved.valid) {
        return false;
    }
    if (resolved.service) {
        auto *job = resolved.action ? new KIO::ApplicationLauncherJob(*resolved.action) : new KIO::ApplicationLauncherJob(resolved.service);
        job->start();
        return true;
    }
    auto *job = new KIO::OpenUrlJob(resolved.documentUrl);
    job->start();
    return true;
}
