import QtQuick
import "Model.js" as Model

// Stable column identities own delegates; representative address, focus, and
// metadata can refresh independently of a pointer grab or popup anchor.
ListModel {
  id: root
  dynamicRoles: true
  property string rowsSignature: ""
  property var signatures: ({})

  function synchronize(rows) {
    var signature = JSON.stringify(rows);
    if (signature === rowsSignature)
      return;
    var nextSignatures = {};
    for (var i = 0; i < rows.length; i++) {
      var key = Model.columnKey(rows[i]);
      var rowSignature = JSON.stringify(rows[i]);
      nextSignatures[key] = rowSignature;
      var found = -1;
      for (var j = i; j < count; j++) {
        if (get(j).columnId === key) {
          found = j;
          break;
        }
      }
      if (found < 0)
        insert(i, {
          columnId: key,
          columnJson: rowSignature
        });
      else {
        if (found !== i)
          move(found, i, 1);
        if (signatures[key] !== rowSignature)
          setProperty(i, "columnJson", rowSignature);
      }
    }
    if (count > rows.length)
      remove(rows.length, count - rows.length);
    signatures = nextSignatures;
    rowsSignature = signature;
  }
}
