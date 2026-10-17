/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appsearch.h"

#include "appmodel.h"
#include "searchranking.h"

#include <QAbstractItemModel>

namespace AppSearch
{
Query Query::of(const QString &text)
{
    Query query;
    query.text = text;
    query.folded = text.toCaseFolded();
    query.foldedSingular = SearchRanking::singularize(query.folded);
    return query;
}

bool Query::matches(const QString &rowText) const
{
    // The row text is folded already, so a case-sensitive contains() does.
    return folded.isEmpty() || rowText.contains(folded) || (!foldedSingular.isEmpty() && rowText.contains(foldedSingular));
}

QString haystack(const QModelIndex &index)
{
    const QStringList parts{
        index.data(AppModel::NameRole).toString(),
        index.data(AppModel::GenericNameRole).toString(),
        index.data(AppModel::KeywordsRole).toStringList().join(QLatin1Char('\n')),
        index.data(AppModel::CategoriesRole).toStringList().join(QLatin1Char('\n')),
        index.data(AppModel::CommentRole).toString(),
        index.data(AppModel::InstallSourceRole).toString(),
    };
    return parts.join(QLatin1Char('\n')).toCaseFolded();
}

int relevance(const QModelIndex &index, const QString &query)
{
    return SearchRanking::relevance(index.data(AppModel::NameRole).toString(),
                                    index.data(AppModel::GenericNameRole).toString(),
                                    index.data(AppModel::CommentRole).toString(),
                                    index.data(AppModel::KeywordsRole).toStringList(),
                                    index.data(AppModel::CategoriesRole).toStringList(),
                                    query);
}

QString completion(const QAbstractItemModel &ranked, const QString &query, int scanLimit)
{
    if (query.isEmpty()) {
        return {};
    }
    const QString folded = query.toCaseFolded();
    const int limit = qMin(ranked.rowCount(), scanLimit);

    // Pass 1: an app whose *name* starts with the query — complete the whole
    // name (e.g. "vi" → "Visual Studio Code"), highest-ranked first.
    for (int i = 0; i < limit; ++i) {
        const QString name = ranked.index(i, 0).data(AppModel::NameRole).toString();
        if (name.size() > query.size() && name.toCaseFolded().startsWith(folded)) {
            return name;
        }
    }

    // Pass 2: no name prefix-matched — complete to the best matching *word*
    // across name / generic name / keywords, so a fuzzy top hit (a terminal
    // named "Ghostty") still completes "te" → "terminal" from its term.
    for (int i = 0; i < limit; ++i) {
        const auto index = ranked.index(i, 0);
        QStringList fields{
            index.data(AppModel::NameRole).toString(),
            index.data(AppModel::GenericNameRole).toString(),
        };
        fields += index.data(AppModel::KeywordsRole).toStringList();
        for (const auto &field : std::as_const(fields)) {
            const QString word = SearchRanking::completionWord(field, query);
            if (!word.isEmpty()) {
                return word;
            }
        }
    }
    return {};
}
}
