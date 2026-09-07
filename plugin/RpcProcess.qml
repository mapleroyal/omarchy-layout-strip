import QtQuick
import Quickshell.Io

// One bounded request. No retries of actions: an interrupted reply is ambiguous.
Item {
  id: root
  visible: false
  property bool busy: false
  property var context: null
  property string output: ""
  property string errorOutput: ""
  property bool timedOut: false
  property int timeoutMs: 3000
  property int requestSerial: 0
  signal completed(var context, string output, string error, int exitCode)

  function start(command, value) {
    if (busy) return false;
    context = value;
    requestSerial++;
    output = "";
    errorOutput = "";
    timedOut = false;
    busy = true;
    process.command = command;
    deadline.restart();
    process.running = true;
    return true;
  }
  function finish(code, serial) {
    if (!busy || serial !== requestSerial) return;
    deadline.stop();
    var saved = context;
    context = null;
    busy = false;
    completed(saved, output, timedOut ? "Layout backend timed out; check its status before retrying" : errorOutput, code);
  }
  Timer {
    id: deadline
    interval: root.timeoutMs
    onTriggered: {
      root.timedOut = true;
      if (process.running) process.signal(9);
      else root.finish(-1, root.requestSerial); // Includes failed-to-start processes without exited().
    }
  }
  Process {
    id: process
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.output = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.errorOutput = text.trim() }
    onExited: function(code) {
      var serial = root.requestSerial;
      Qt.callLater(function() { root.finish(code, serial); });
    }
  }
}
