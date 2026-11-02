.pragma library

// Keep slots aligned with the category/legend arrays, including unmeasured slots.
function build(values) {
    var input = Array.isArray(values) ? values : [];
    var maximum = 0;
    var known = [];
    for (var i = 0; i < input.length; ++i) {
        known.push(typeof input[i] === "number" && isFinite(input[i]) && input[i] >= 0);
        if (known[i]) maximum = Math.max(maximum, input[i]);
    }
    // Scaling before summing also keeps very large finite byte counts usable.
    var total = 0;
    if (maximum > 0) {
        for (var j = 0; j < input.length; ++j)
            if (known[j]) total += input[j] / maximum;
    }
    var segments = [];
    var shares = [];
    var start = -Math.PI / 2;
    for (var k = 0; k < input.length; ++k) {
        var share = known[k] && total > 0 ? input[k] / maximum / total : 0;
        var sweep = share * Math.PI * 2;
        var gap = Math.min(0.035, sweep * 0.15);
        segments.push({ start: start + gap / 2, end: start + sweep - gap / 2,
            middle: start + sweep / 2, drawable: sweep > 0 });
        shares.push(known[k] && total > 0 ? share : null);
        start += sweep;
    }
    return { segments: segments, shares: shares };
}

// Coordinates must first be mapped into the actual transformed arc item.
function contains(segment, x, y, cx, cy, radius, stroke) {
    if (!segment || !segment.drawable || radius <= 0 || stroke <= 0) return false;
    var dx = x - cx;
    var dy = y - cy;
    var distanceSquared = dx * dx + dy * dy;
    var inner = Math.max(0, radius - stroke / 2);
    var outer = radius + stroke / 2;
    if (distanceSquared < inner * inner || distanceSquared > outer * outer) return false;
    var angle = Math.atan2(dy, dx);
    if (angle < -Math.PI / 2) angle += Math.PI * 2;
    return angle >= segment.start && angle <= segment.end;
}
