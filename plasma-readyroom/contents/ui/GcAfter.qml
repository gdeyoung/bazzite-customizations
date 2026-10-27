import QtQuick

// A Timer whose body is a callback property, so any number of these can be
// used in one file without duplicate onTriggered handlers (which would fail
// the whole applet with "Property value set multiple times").
Timer {
    property var action: function() {}
    onTriggered: action()
}
