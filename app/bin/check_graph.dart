import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/maps/tec_colima_map.json');
  final data = jsonDecode(file.readAsStringSync());
  
  final nodes = data['nodes'] as List;
  final edges = data['edges'] as List;
  
  final nodeIds = nodes.map((n) => n['id'] as String).toSet();
  
  final connectedNodes = <String>{};
  
  for (final edge in edges) {
    connectedNodes.add(edge['from']);
    connectedNodes.add(edge['to']);
    
    if (!nodeIds.contains(edge['from'])) {
      final f = edge['from'];
      print('Edge references missing node (from): ' + f);
    }
    if (!nodeIds.contains(edge['to'])) {
      final t = edge['to'];
      print('Edge references missing node (to): ' + t);
    }
  }
  
  final disconnectedNodes = nodeIds.difference(connectedNodes);
  print('Disconnected nodes:');
  for (final node in disconnectedNodes) {
    print('- ' + node);
  }
}
