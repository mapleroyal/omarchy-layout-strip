import QtQuick

// Stable addresses own delegate identity; title, focus, width, and camera
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
      var address = rows[i].address;
      var rowSignature = JSON.stringify(rows[i]);
      nextSignatures[address] = rowSignature;
      var found = -1;
      for (var j = i; j < count; j++) {
        if (get(j).columnData.address === address) {
          found = j;
          break;
        }
      }
      if (found < 0)
        insert(i, {
          columnData: rows[i]
        });
      else {
        if (found !== i)
          move(found, i, 1);
        if (signatures[address] !== rowSignature)
          setProperty(i, "columnData", rows[i]);
      }
    }
    if (count > rows.length)
      remove(rows.length, count - rows.length);
    signatures = nextSignatures;
    rowsSignature = signature;
  }
}
