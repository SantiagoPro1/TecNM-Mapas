import 'package:flutter/material.dart';
import 'package:navia/data/repositories/place_repository.dart';

class DatabaseSeeder {
  static Future<void> run() async {
    debugPrint('--- Iniciando Seeding de Firestore ---');
    final repository = PlaceRepository();
    try {
      await repository.seedBundledVenuesFromAssets();
      debugPrint('--- Seeding completado con éxito ---');
    } catch (e) {
      debugPrint('--- Error en Seeding: $e ---');
    }
  }
}
