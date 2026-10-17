/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QModelIndex>
#include <QString>

class QAbstractItemModel;

/**
 * Searching apps by the AppModel roles of their rows: which rows a query
 * matches, how well, and what word completes it. SearchRanking scores plain
 * strings; this reads them off a model row.
 */
namespace AppSearch
{
/** A query, folded once for the per-row matching. */
struct Query {
    QString text;
    QString folded;
    // Naive singular of the folded query ("games" → "game"), or empty; a
    // plural query still reaches the singular category.
    QString foldedSingular;

    [[nodiscard]] static Query of(const QString &text);
    [[nodiscard]] bool isEmpty() const
    {
        return text.isEmpty();
    }
    /** Whether a row with @p haystack (see haystack()) matches. An empty
     *  query matches every row. */
    [[nodiscard]] bool matches(const QString &haystack) const;
};

/** The folded text a query is matched against: the name, generic name,
 *  keywords, categories, comment and install source of @p index. */
[[nodiscard]] QString haystack(const QModelIndex &index);

/** SearchRanking::relevance() of the row @p index for @p query. */
[[nodiscard]] int relevance(const QModelIndex &index, const QString &query);

/** The inline completion for @p query from the first @p scanLimit rows of
 *  @p ranked (best first): the first name that starts with it, else the
 *  first word of a name, generic name or keyword that does. Empty if none. */
[[nodiscard]] QString completion(const QAbstractItemModel &ranked, const QString &query, int scanLimit);
}
