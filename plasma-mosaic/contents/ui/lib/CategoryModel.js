.pragma library

function compareApps(a, b) {
    if (a.bytes === null && b.bytes !== null) return 1;
    if (b.bytes === null && a.bytes !== null) return -1;
    return (b.bytes || 0) - (a.bytes || 0)
        || String(a.name).localeCompare(String(b.name))
        || String(a.id).localeCompare(String(b.id));
}

// Overview paths are protocol-validated. Completeness belongs to this category,
// not the app's aggregate status or measurements from another category.
function summary(apps, category) {
    var result = {
        key: category, bytes: null, partial: false, knownPaths: 0,
        measuredPaths: 0, completePaths: 0, unknownPaths: 0,
        apps: [], excluded: []
    };
    var source = apps || [];
    for (var i = 0; i < source.length; ++i) {
        var app = source[i];
        var row = {id: app.id, name: app.name, icon: app.icon, bytes: null, partial: false, paths: []};
        var paths = app.paths || [];
        for (var j = 0; j < paths.length; ++j) {
            var entry = paths[j];
            if (entry.category !== category) continue;
            if (entry.confidence !== "known") {
                result.excluded.push({appId: app.id, appName: app.name, entry: entry});
                continue;
            }
            row.paths.push(entry);
            ++result.knownPaths;
            var measured = entry.bytes !== null && entry.bytes !== undefined;
            if (measured) {
                row.bytes = (row.bytes === null ? 0 : row.bytes) + entry.bytes;
                result.bytes = (result.bytes === null ? 0 : result.bytes) + entry.bytes;
                ++result.measuredPaths;
            } else {
                ++result.unknownPaths;
            }
            if (entry.status === "complete") ++result.completePaths;
            if (!measured || entry.status !== "complete") row.partial = true;
        }
        if (row.paths.length) {
            result.apps.push(row);
            if (row.partial) result.partial = true;
        }
    }
    result.apps.sort(compareApps);
    return result;
}

// Weighted binary partition: split near half the weight along the longer edge.
// Work depends only on the bounded visible tile count, never pixels or bytes.
function partition(cells, start, end, x, y, width, height) {
    if (end - start === 1) {
        var cell = cells[start];
        cell.x = x;
        cell.y = y;
        cell.width = width;
        cell.height = height;
        return;
    }
    var scale = 0;
    var i;
    for (i = start; i < end; ++i) scale = Math.max(scale, cells[i].bytes);
    var total = 0;
    for (i = start; i < end; ++i) total += cells[i].bytes / scale;
    var left = 0;
    var split = start + 1;
    var closest = Infinity;
    for (i = start; i < end - 1; ++i) {
        left += cells[i].bytes / scale;
        var distance = Math.abs(total / 2 - left);
        if (distance < closest) {
            closest = distance;
            split = i + 1;
        }
    }
    // Sum both groups directly: total - dominant would erase tiny weights.
    left = 0;
    var right = 0;
    for (i = start; i < split; ++i) left += cells[i].bytes / scale;
    for (i = split; i < end; ++i) right += cells[i].bytes / scale;
    var firstStart = left <= right ? start : split;
    var firstEnd = left <= right ? split : end;
    var secondStart = left <= right ? split : start;
    var secondEnd = left <= right ? end : split;
    var fraction = Math.min(left, right) / (left + right);
    // Place the smaller region first so its extent is never a subtraction of
    // nearly equal dimensions. No minimum area or weight is introduced.
    if (width >= height) {
        var firstWidth = width * fraction;
        partition(cells, firstStart, firstEnd, x, y, firstWidth, height);
        partition(cells, secondStart, secondEnd, x + firstWidth, y, width - firstWidth, height);
    } else {
        var firstHeight = height * fraction;
        partition(cells, firstStart, firstEnd, x, y, width, firstHeight);
        partition(cells, secondStart, secondEnd, x, y + firstHeight, width, height - firstHeight);
    }
}

function tiles(appRows, width, height, maxApps) {
    if (typeof width !== "number" || typeof height !== "number"
        || !isFinite(width) || !isFinite(height) || width <= 0 || height <= 0) return [];
    var limit = typeof maxApps === "number" && isFinite(maxApps) ? Math.max(0, Math.floor(maxApps)) : 7;
    var positive = (appRows || []).filter(function(row) {
        return typeof row.bytes === "number" && isFinite(row.bytes) && row.bytes > 0;
    }).sort(compareApps);
    var cells = [];
    var other = null;
    for (var i = 0; i < positive.length; ++i) {
        var row = positive[i];
        if (i < limit) {
            cells.push({kind: "app", appId: row.id, name: row.name, icon: row.icon,
                bytes: row.bytes, partial: !!row.partial, members: [row.id],
                x: 0, y: 0, width: 0, height: 0});
        } else {
            if (!other) {
                other = {kind: "other", appId: "", name: "", icon: "", bytes: 0,
                    partial: false, members: [], x: 0, y: 0, width: 0, height: 0};
                cells.push(other);
            }
            other.bytes += row.bytes;
            other.partial = other.partial || !!row.partial;
            other.members.push(row.id);
        }
    }
    if (cells.length) partition(cells, 0, cells.length, 0, 0, width, height);
    return cells;
}
