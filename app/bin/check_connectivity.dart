import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/maps/tec_colima_map.json');
  final data = jsonDecode(file.readAsStringSync());

  final nodes = data['nodes'] as List;
  final edges = data['edges'] as List;

  final adjacency = <String, List<Map>>{};
  final nodeNames = <String, String>{};

  for (final node in nodes) {
    final id = node['id'] as String;
    adjacency[id] = [];
    nodeNames[id] = node['name'] as String;
  }

  for (final edge in edges) {
    final from = edge['from'] as String;
    final to = edge['to'] as String;
    if (adjacency.containsKey(from) && adjacency.containsKey(to)) {
      adjacency[from]!.add(edge);
      // add reverse
      adjacency[to]!.add({'from': to, 'to': from});
    }
  }

  // BFS to check connectivity from tec_entrada
  final visited = <String>{};
  final queue = ['tec_entrada'];
  visited.add('tec_entrada');

  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    final neighbors = adjacency[current] ?? [];
    for (final neighbor in neighbors) {
      final to = neighbor['to'] as String;
      if (!visited.contains(to)) {
        visited.add(to);
        queue.add(to);
      }
    }
  }

  // ignore: avoid_print
  print('Nodes unreachable from tec_entrada:');
  for (final node in nodes) {
    final id = node['id'] as String;
    if (!visited.contains(id)) {
      final name = node['name'] as String;
      // ignore: avoid_print
      print('- $id ($name)');
    }
  }
}
