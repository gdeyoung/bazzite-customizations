.pragma library

var categoryKeys = ["data", "cache", "config", "state"];

function appsFor(apps, query) {
    var needle = String(query || "").trim().toLocaleLowerCase();
    return (apps || []).filter(function(app) {
        return !needle || String(app.name).toLocaleLowerCase().indexOf(needle) !== -1
            || String(app.id).toLocaleLowerCase().indexOf(needle) !== -1;
    }).sort(function(a, b) {
        return (b.mappedBytes || 0) - (a.mappedBytes || 0)
            || String(a.name).localeCompare(String(b.name)) || String(a.id).localeCompare(String(b.id));
    });
}

function findApp(apps, id) {
    for (var i = 0; i < apps.length; ++i)
        if (apps[i].id === id) return apps[i];
    return null;
}

function indexFor(items, id, key) {
    for (var i = 0; i < items.length; ++i)
        if (items[i][key || "id"] === id) return i;
    return items.length ? 0 : -1;
}

function bytes(value, strings, numbers) {
    if (value === null || value === undefined || !isFinite(value)) return strings.t("size.unknown");
    var n = Math.max(0, Number(value));
    var units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
    var index = 0;
    while (n >= 1024 && index < units.length - 1) { n /= 1024; ++index; }
    return strings.t("size.value").arg(numbers.formatNumber(n, index > 0 && n < 100 ? 1 : 0)).arg(strings.t("unit." + units[index]));
}

function appSize(app, strings, numbers) {
    if (!app || app.status === "unmapped") return strings.t("app.unmapped");
    if (app.status === "pending") return strings.t("status.pending");
    var known = (app.paths || []).filter(function(path) { return path.confidence === "known"; });
    if (!known.length) return strings.t("app.unconfirmed");
    if (!known.some(function(path) { return path.bytes !== null && path.bytes !== undefined; }))
        return strings.t("size.unknown");
    var result = bytes(app.mappedBytes, strings, numbers);
    return app.status === "partial" ? strings.t("size.lowerBound").arg(result) : result;
}

function pathSize(path, strings, numbers) {
    if (path.bytes === null || path.bytes === undefined) {
        switch (path.status) {
        case "pending": return strings.t("status.pending");
        case "denied": case "missing": case "symlink": case "error":
            return strings.t("compact.status." + path.status);
        default: return strings.t("size.unknown");
        }
    }
    var result = bytes(path.bytes, strings, numbers);
    return path.status === "partial" ? strings.t("size.lowerBound").arg(result) : result;
}

function coverage(apps) {
    var mapped = 0;
    var excluded = 0;
    for (var i = 0; i < apps.length; ++i) {
        var known = false;
        var paths = apps[i].paths || [];
        for (var j = 0; j < paths.length; ++j) {
            if (paths[j].confidence === "known") known = true;
            else ++excluded;
        }
        if (known) ++mapped;
    }
    return { mapped: mapped, excluded: excluded };
}

function orderedPaths(paths) {
    var rank = { known: 0, possible: 1, shared: 2 };
    return (paths || []).slice().sort(function(a, b) {
        return rank[a.confidence] - rank[b.confidence]
            || (b.bytes || 0) - (a.bytes || 0) || a.path.localeCompare(b.path);
    });
}

function timestamp(value, locale, format) {
    return value > 0 ? new Date(value).toLocaleString(locale, format) : "";
}

function skippedReasons(counts) {
    return Object.keys(counts || {}).filter(function(reason) {
        return counts[reason] > 0;
    }).sort().map(function(reason) {
        return { reason: reason, count: counts[reason] };
    });
}
