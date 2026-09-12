import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navia/presentation/screens/map/place_visuals.dart';

void main() {
  PlaceCategory cat(String name, [String type = '']) =>
      PlaceVisuals.categoryFor(name: name, type: type);

  group('Categoría por nombre — los nombres reales del dataset', () {
    test('deportes con nombre explícito', () {
      expect(cat('Alberca Olímpica Unidad Morelos'), PlaceCategory.swimming);
      expect(cat('Fosa de Clavados'), PlaceCategory.swimming);
      expect(cat('Cancha de Básquetbol 3'), PlaceCategory.basketball);
      expect(cat('Estadio de Béisbol de Colima'), PlaceCategory.baseball);
      expect(cat('Cancha de Voleibol de Playa'), PlaceCategory.volleyball);
      expect(cat('Cancha de Tenis'), PlaceCategory.tennis);
      expect(cat('Pista de Atletismo Colima'), PlaceCategory.athletics);
      expect(cat('Pista De Ciclismo'), PlaceCategory.cycling);
      expect(
          cat('Tezcatl Club de Arqueria Tradicional'), PlaceCategory.archery);
    });

    test('lo específico gana sobre lo genérico', () {
      // "Cancha de Fútbol Rápido" no debe caer en fútbol normal ni en
      // "cancha" genérica.
      expect(cat('Cancha de Futbol Rápido Los Almendros'),
          PlaceCategory.soccerSmall);
      expect(cat('Sintético de La Villa'), PlaceCategory.soccerSmall);
      expect(cat('Cancha de Fútbol 2'), PlaceCategory.football);
      // "Voleibol y Handball de Playa" es voleibol, no área genérica.
      expect(cat('Estadio de Voleibol y Handball de Playa'),
          PlaceCategory.volleyball);
    });

    test('acentos y mayúsculas no cambian el resultado', () {
      expect(cat('CANCHA DE BASQUETBOL'), PlaceCategory.basketball);
      expect(cat('cancha de básquetbol'), PlaceCategory.basketball);
      expect(cat('BEISBOL'), cat('Béisbol'));
    });

    test('frontón y frontenis cuentan como deporte de raqueta', () {
      expect(cat('Cancha de Frontón'), PlaceCategory.tennis);
      expect(cat('Canchas Frontenis'), PlaceCategory.tennis);
    });

    test('sin pista deportiva, cae a área deportiva o genérico', () {
      expect(cat('Unidad Deportiva Gil Cabrera'), PlaceCategory.generalSport);
      expect(cat('Zamesta Stadium'), PlaceCategory.generic);
    });
  });

  group('Categoría por type (respaldo cuando el nombre no dice nada)', () {
    test('usa el type de Firestore', () {
      expect(cat('Punto 4', 'Primeros Auxilios'), PlaceCategory.medical);
      expect(cat('Punto 5', 'Hidratación'), PlaceCategory.water);
      expect(cat('Punto 6', 'Estacionamiento'), PlaceCategory.parking);
      expect(cat('Punto 7', 'Edificio'), PlaceCategory.building);
    });

    test('el nombre tiene prioridad sobre el type', () {
      // El editor guarda todo lo deportivo como type "Cancha"; el nombre es
      // lo único que distingue alberca de básquetbol.
      expect(cat('Alberca Semiolímpica', 'Cancha'), PlaceCategory.swimming);
    });
  });

  group('Cada categoría tiene ícono y color', () {
    test('sin huecos en los switch', () {
      for (final c in PlaceCategory.values) {
        expect(PlaceVisuals.iconFor(c), isA<IconData>());
        expect(PlaceVisuals.colorFor(c), isA<Color>());
      }
    });
  });

  group('Ilustración por categoría', () {
    test('cada categoría tiene su ilustración empaquetada', () {
      // Si falta una, la ficha de ese tipo de lugar aparece vacía. El archivo
      // lo genera scripts/build_category_art.py.
      final faltan = <String>[];
      for (final c in PlaceCategory.values) {
        if (!File('assets/categories/${c.name}.png').existsSync()) {
          faltan.add(c.name);
        }
      }
      expect(faltan, isEmpty, reason: 'sin ilustración: $faltan');
    });

    test('ninguna ilustración pesa de más', () {
      // Van todas dentro del APK; si una se dispara, engorda la descarga
      // para 4,000 personas sin que nadie lo note.
      for (final f in Directory('assets/categories').listSync().whereType<File>()) {
        expect(f.lengthSync(), lessThan(60 * 1024),
            reason: '${f.path} pesa ${f.lengthSync() ~/ 1024} KB');
      }
    });
  });
}
