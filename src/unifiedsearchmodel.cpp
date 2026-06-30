/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "unifiedsearchmodel.h"

#include "appmodel.h"
#include "pluginhelpers.h"

#include <KRunner/Action>

#include <QUrl>

namespace
{
// Single-digit launch shortcuts: the first 9 results map to Alt+1 .. Alt+9.
constexpr int kMaxShortcutNumber = 9;
}

UnifiedSearchModel::UnifiedSearchModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

void UnifiedSearchModel::connectSourceSignals(QAbstractItemModel *model)
{
    connect(model, &QAbstractItemModel::modelReset, this, &UnifiedSearchModel::onSourceChanged);
    connect(model, &QAbstractItemModel::layoutChanged, this, &UnifiedSearchModel::onSourceChanged);
    connect(model, &QAbstractItemModel::rowsInserted, this, &UnifiedSearchModel::onSourceChanged);
    connect(model, &QAbstractItemModel::rowsRemoved, this, &UnifiedSearchModel::onSourceChanged);
}

void UnifiedSearchModel::setAppModel(AppFilterModel *model)
{
    m_appModel = model;
    connectSourceSignals(model);
}

void UnifiedSearchModel::setRunnerModel(RunnerFilterModel *model)
{
    m_runnerModel = model;
    connectSourceSignals(model);

    const auto roles = model->roleNames();
    m_runnerSubtextRole = roles.key(QByteArrayLiteral("subtext"), -1);
    m_runnerCategoryRole = roles.key(QByteArrayLiteral("category"), -1);
    m_runnerUrlsRole = roles.key(QByteArrayLiteral("urls"), -1);
    m_runnerActionsRole = roles.key(QByteArrayLiteral("actions"), -1);
    m_runnerMultiLineRole = roles.key(QByteArrayLiteral("multiLine"), -1);
}

void UnifiedSearchModel::onSourceChanged()
{
    if (!m_resetPending) {
        m_resetPending = true;
        QMetaObject::invokeMethod(this, &UnifiedSearchModel::doReset, Qt::QueuedConnection);
    }
}

void UnifiedSearchModel::doReset()
{
    m_resetPending = false;
    beginResetModel();
    endResetModel();
    Q_EMIT resultCountsChanged();
}

int UnifiedSearchModel::appResultCount() const
{
    return m_appModel ? m_appModel->rowCount() : 0;
}

int UnifiedSearchModel::runnerResultCount() const
{
    return m_runnerModel ? m_runnerModel->rowCount() : 0;
}

int UnifiedSearchModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return appResultCount() + runnerResultCount();
}

QVariant UnifiedSearchModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount()) {
        return {};
    }
    if (!m_appModel || !m_runnerModel) {
        return {};
    }

    const int row = index.row();
    const int ac = appResultCount();
    const bool isApp = row < ac;

    switch (role) {
    case ResultTypeRole:
        return isApp ? QStringLiteral("app") : QStringLiteral("runner");
    case IsSectionBoundaryRole:
        return !isApp && row == ac && ac > 0;
    case ShortcutNumberRole:
        return (row < kMaxShortcutNumber) ? row + 1 : 0;
    case SourceIndexRole:
        return isApp ? row : (row - ac);
    case RunnerActionsCountRole:
        return isApp ? 0 : runnerActionsCount(index.row());
    case IsRunnerActionRole:
        return isApp ? false : m_runnerModel->rowIsAction(index.row() - appResultCount());
    case MultiLineRole:
        return (isApp || m_runnerMultiLineRole < 0) ? false : m_runnerModel->index(row - ac, 0).data(m_runnerMultiLineRole);
    default:
        break;
    }

    if (isApp) {
        const auto srcIdx = m_appModel->index(row, 0);
        switch (role) {
        case NameRole:
            return srcIdx.data(AppModel::NameRole);
        case IconRole:
            return srcIdx.data(AppModel::IconRole);
        case SubtextRole: {
            auto comment = srcIdx.data(AppModel::CommentRole).toString();
            return comment.isEmpty() ? srcIdx.data(AppModel::GenericNameRole) : comment;
        }
        case CategoryRole:
            // Our app rows share one section. A non-empty sentinel (QML labels it
            // "Applications") — empty would make ListView draw no header at all,
            // and it stays distinct from KRunner's own "Applications" category.
            return QStringLiteral("applications");
        case StorageIdRole:
            return srcIdx.data(AppModel::StorageIdRole);
        case DesktopFileRole:
            return srcIdx.data(AppModel::DesktopFileRole);
        case IsNewRole:
            return m_appModel->isNewApp(srcIdx.data(AppModel::StorageIdRole).toString());
        case IsHiddenRole:
            return m_appModel->isHidden(srcIdx.data(AppModel::StorageIdRole).toString());
        case InstallSourceRole:
            return srcIdx.data(AppModel::InstallSourceRole);
        default:
            return {};
        }
    } else {
        const int runnerRow = row - ac;
        const auto srcIdx = m_runnerModel->index(runnerRow, 0);
        switch (role) {
        case NameRole:
            return srcIdx.data(Qt::DisplayRole);
        case IconRole:
            return srcIdx.data(Qt::DecorationRole);
        case SubtextRole:
            return m_runnerSubtextRole >= 0 ? srcIdx.data(m_runnerSubtextRole) : QVariant();
        case CategoryRole: {
            // Prefix every runner section so it can never share a section with our
            // own apps, whatever KRunner's category string is (its services runner
            // uses "Applications" too). QML strips "plasma:" for the label.
            const QString cat = m_runnerCategoryRole >= 0 ? srcIdx.data(m_runnerCategoryRole).toString() : QString();
            return QString(QStringLiteral("plasma:") + cat);
        }
        case StorageIdRole:
        case DesktopFileRole: {
            if (m_runnerUrlsRole < 0) {
                return QString();
            }
            const QVariant urls = srcIdx.data(m_runnerUrlsRole);
            return role == StorageIdRole ? PluginHelpers::runnerStorageId(urls) : PluginHelpers::desktopPathFromRunnerUrls(urls);
        }
        case IsNewRole:
        case IsHiddenRole:
            return false;
        case InstallSourceRole:
            return QString();
        default:
            return {};
        }
    }
}

QHash<int, QByteArray> UnifiedSearchModel::roleNames() const
{
    // Qt calls roleNames() once per delegate role read from QML — across a
    // 20-row search-results view that's ~120 calls per keystroke. Hand back
    // a reference to a static map so we don't allocate a fresh QHash each
    // time. Roles are compile-time constant so the table never changes.
    static const QHash<int, QByteArray> kRoleNames = {
        {ResultTypeRole, "resultType"},
        {NameRole, "name"},
        {IconRole, "iconName"},
        {SubtextRole, "subtext"},
        {CategoryRole, "category"},
        {StorageIdRole, "storageId"},
        {DesktopFileRole, "desktopFile"},
        {IsNewRole, "isNew"},
        {IsHiddenRole, "isHidden"},
        {ShortcutNumberRole, "shortcutNumber"},
        {IsSectionBoundaryRole, "isSectionBoundary"},
        {SourceIndexRole, "sourceIndex"},
        {InstallSourceRole, "installSource"},
        {RunnerActionsCountRole, "runnerActionsCount"},
        {IsRunnerActionRole, "isRunnerAction"},
        {MultiLineRole, "multiLine"},
    };
    return kRoleNames;
}

QVariantList UnifiedSearchModel::rawRunnerActions(int row) const
{
    if (!m_runnerModel || m_runnerActionsRole < 0) {
        return {};
    }
    const int ac = appResultCount();
    if (row < ac || row >= rowCount()) {
        return {};
    }
    // ResultsModel exposes ActionsRole as a QVariantList of QVariant-wrapped
    // KRunner::Action — *not* as a typed QList<KRunner::Action>. The caller
    // unwraps each element individually rather than .value<KRunner::Actions>(),
    // which silently returns empty on the type mismatch.
    return m_runnerModel->index(row - ac, 0).data(m_runnerActionsRole).toList();
}

QVariantList UnifiedSearchModel::runnerActions(int row) const
{
    const auto rawList = rawRunnerActions(row);
    QVariantList result;
    result.reserve(rawList.size());
    for (const auto &item : rawList) {
        const auto action = item.value<KRunner::Action>();
        if (action.id().isEmpty() && action.text().isEmpty()) {
            continue;
        }
        QVariantMap map;
        map[QStringLiteral("id")] = action.id();
        map[QStringLiteral("icon")] = action.iconSource();
        map[QStringLiteral("text")] = action.text();
        result.append(map);
    }
    return result;
}

int UnifiedSearchModel::runnerActionsCount(int row) const
{
    const auto rawList = rawRunnerActions(row);
    int count = 0;
    for (const auto &item : rawList) {
        const auto action = item.value<KRunner::Action>();
        if (!action.id().isEmpty() || !action.text().isEmpty()) {
            ++count;
        }
    }
    return count;
}

QVariantMap UnifiedSearchModel::get(int row) const
{
    QVariantMap map;
    if (row < 0 || row >= rowCount()) {
        return map;
    }
    const auto idx = index(row, 0);
    const auto roles = roleNames();
    for (auto it = roles.begin(); it != roles.end(); ++it) {
        map[QString::fromLatin1(it.value())] = data(idx, it.key());
    }
    return map;
}

QString UnifiedSearchModel::iconNameAt(int row) const
{
    if (row < 0 || row >= rowCount()) {
        return {};
    }
    return data(index(row, 0), IconRole).toString();
}
