/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QStringList>

/**
 * The "key=value" StringList on-disk form AppGrid persists small maps in
 * (launch counts, first-seen dates). One definition of the format so the
 * stores that use it can't drift: split on the LAST '=' (values may contain
 * '='), drop entries with no key, and drop values the parser rejects.
 */
namespace KeyValueList
{

/** Parse @p list into a map. @p parseValue maps the value string to an
 *  std::optional<V>; std::nullopt drops the entry (e.g. an invalid date). The
 *  map type is explicit: @c fromList<QVariantMap>(list, parse). */
template<typename Map, typename ParseValue>
[[nodiscard]] Map fromList(const QStringList &list, ParseValue parseValue)
{
    Map map;
    for (const QString &entry : list) {
        const int sep = entry.lastIndexOf(QLatin1Char('='));
        if (sep <= 0) {
            continue;
        }
        if (const auto value = parseValue(entry.mid(sep + 1))) {
            map.insert(entry.left(sep), *value);
        }
    }
    return map;
}

/** Format @p map back to a "key=value" StringList. @p formatValue turns one
 *  mapped value into its string form. Order follows the map; sort the result
 *  if a stable on-disk order matters. */
template<typename Map, typename FormatValue>
[[nodiscard]] QStringList toList(const Map &map, FormatValue formatValue)
{
    QStringList list;
    list.reserve(map.size());
    for (auto it = map.cbegin(); it != map.cend(); ++it) {
        list << it.key() + QLatin1Char('=') + formatValue(it.value());
    }
    return list;
}

} // namespace KeyValueList
