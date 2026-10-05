import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/offline/offline_manager.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navia/data/providers/voice_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:navia/data/models/place_node.dart';
import 'package:navia/data/models/campus_node.dart';
import 'package:navia/data/models/campus_edge.dart';
import 'package:navia/data/models/venue.dart';
import 'package:navia/presentation/screens/map/providers/map_providers.dart';
import 'package:navia/core/constants/campus_locations.dart';
import 'package:navia/core/constants/venue_registry.dart';
import 'package:navia/core/constants/app_routes.dart';
import 'package:navia/data/providers/auth_provider.dart';
import 'package:navia/data/providers/navigation_provider.dart';
import 'package:navia/data/providers/settings_provider.dart';
import 'package:navia/presentation/widgets/bottom_nav.dart';
import 'package:navia/core/theme/app_theme.dart';
import 'package:navia/presentation/screens/map/place_visuals.dart';

class MapScreen extends ConsumerStatefulWidget {
  /// Modo "mapa abierto": la pantalla deja de estar anclada a una sede.
  ///
  /// El mapa normal se abre sobre UNA sede y encierra la cámara en su caja
  /// (`cameraTargetBounds`) para que nadie se pierda navegando a ciegas por
  /// la ciudad; además, si detecta que estás lejos, te regresa el encuadre a
  /// la sede. Eso es lo correcto cuando vas a una competencia concreta, pero
  /// vuelve imposible simplemente explorar. En modo abierto la cámara es
  /// libre, se ven los puntos de las 9 sedes a la vez, y nada reencuadra por
  /// su cuenta.
  final bool openMap;

  const MapScreen({super.key, this.openMap = false});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

/// Estados del cuadro de estado de ruta (la barra superior del mapa).
///
/// Antes estos avisos ("calculando ruta", "ya estás ahí", "ya tienes una
/// ruta activa") salían como SnackBar. El problema: en Flutter, con un solo
/// `MaterialApp`/Navigator, el `ScaffoldMessenger` vive ARRIBA de las
/// pantallas — un SnackBar no se cierra ni se mueve solo al cambiar de
/// pantalla, se queda flotando encima de lo que sea que esté visible varios
/// segundos después. Si alguien toca "Trazar Ruta" y se regresa rápido a
/// Inicio (antes de que el aviso alcance a aparecer), el aviso igual sale,
/// pero ya sobre Inicio, no sobre el mapa. Por eso ahora estos avisos viven
/// DENTRO de este mismo cuadro, como parte del árbol de widgets del mapa:
/// si te vas de esta pantalla, el aviso se va con ella, en vez de perseguirte.
enum _RouteBannerKind { calculating, active, alreadyThere, blocked, arrived, error }

/// Cuadro de estado de ruta — un solo widget para todos los avisos de
/// ruteo (ver [_RouteBannerKind]), con el botón de cancelar SOLO visible
/// cuando de verdad hay una ruta que cancelar (estado `active`).
class _RouteStatusBanner extends StatelessWidget {
  final _RouteBannerKind kind;
  final String? label;
  final VoidCallback onCancel;

  const _RouteStatusBanner({
    required this.kind,
    required this.label,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    late final IconData icon;
    late final String text;
    Color accent = cs.primary;
    bool showCancel = false;

    switch (kind) {
      case _RouteBannerKind.calculating:
        icon = Icons.hourglass_top_rounded;
        text = 'Calculando ruta...';
        accent = cs.primary;
      case _RouteBannerKind.active:
        icon = Icons.navigation_rounded;
        text = 'Ruta activa';
        accent = cs.primary;
        showCancel = true;
      case _RouteBannerKind.alreadyThere:
        icon = Icons.check_circle_rounded;
        text = 'Ya estás en ${label ?? "tu destino"}';
        accent = cs.tertiary;
      case _RouteBannerKind.blocked:
        icon = Icons.info_rounded;
        text = 'Ya tienes una ruta activa. Cancélala antes de trazar otra.';
        accent = isDark ? AppWarning.dark : AppWarning.light;
      case _RouteBannerKind.arrived:
        icon = Icons.check_circle_rounded;
        text = 'Has llegado a tu destino';
        accent = cs.tertiary;
      case _RouteBannerKind.error:
        icon = Icons.error_outline_rounded;
        text = 'No se pudo calcular la ruta. Intenta de nuevo.';
        accent = cs.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (kind == _RouteBannerKind.calculating)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(accent)),
            )
          else
            Icon(icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          if (showCancel)
            IconButton(
              onPressed: onCancel,
              tooltip: 'Cancelar ruta',
              icon: Icon(Icons.close_rounded,
                  color: cs.onSurface.withValues(alpha: 0.6)),
              iconSize: 20,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: EdgeInsets.zero,
              splashRadius: 22,
            ),
        ],
      ),
    );
  }
}

/// Aviso de posición fijada a mano ("Estoy Aquí" en un lugar, o QR
/// escaneado): mientras está activa, el GPS en tiempo real se ignora por
/// completo (ver `NavigationService._isManualPosition`). Antes no había
/// ninguna señal de esto en pantalla ni una forma obvia de quitarlo — solo
/// funcionaba si sabías que el botón de centrar ubicación también lo hacía
/// por dentro. Ahora es explícito, con su propio botón "Quitar".
class _ManualPositionBanner extends StatelessWidget {
  final String? label;
  final VoidCallback onClear;

  const _ManualPositionBanner({required this.label, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppWarning.dark : AppWarning.light;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.push_pin_rounded, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ubicación fijada en ${label ?? "un punto"} — el GPS no se actualiza',
              style: TextStyle(
                  color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: accent,
            ),
            child: const Text('QUITAR',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _googleMapController;
  Set<Marker> _googleMarkers = {};
  Set<Polyline> _googlePolylines = {};

  // google_maps_flutter solo tiene implementación nativa en Android/iOS/Web.
  // En desktop (Windows/Linux/macOS) usamos flutter_map con tiles OSM.
  fm.MapController? _flutterMapController;
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  LatLng? _currentPosition;
  LatLng? _displayPosition;
  LatLng? _previousPosition;

  /// Posición interpolada del usuario, actualizada en cada frame de la
  /// animación de suavizado GPS (~60/s). Se lee con un ValueListenableBuilder
  /// acotado solo al widget del mapa, para que mover el punto azul no
  /// reconstruya toda la pantalla (botones, banners, etc.) 60 veces por
  /// segundo — esa era la causa real de que la navegación se sintiera trabada.
  final ValueNotifier<LatLng?> _userPosNotifier = ValueNotifier<LatLng?>(null);

  /// Ícono del usuario para GoogleMap, generado una sola vez (no en cada
  /// frame): regenerarlo por frame implicaba dibujar en Canvas y codificar
  /// PNG ~60 veces por segundo, carísimo para un simple punto que se mueve.
  BitmapDescriptor? _userIconCache;

  /// Última vez que se persistió la posición a disco. Guardar en cada lectura
  /// de GPS sería escribir a SharedPreferences varias veces por segundo; con
  /// refrescar el respaldo cada 15s basta de sobra para el arranque offline.
  DateTime? _lastPositionSaveAt;
  double _currentZoom = 17.0;

  // Zona visible del mapa, solo para el modo edición: se dibujan únicamente
  // los nodos dentro de ella. Algunas sedes traen 600+ nodos y 900+ aristas,
  // y mandarlos todos a Google Maps agotaba la memoria (OutOfMemoryError al
  // tocar el botón de editar).
  LatLngBounds? _editVisibleRegion;
  static const int _maxEditNodes = 150;
  static const int _maxEditEdges = 300;
  double _currentHeading = 0.0;

  bool _centeredOnUser = false;
  // El seguimiento de cámara empieza ACTIVO por diseño (igual que Google
  // Maps/Waze): apenas se abre el mapa, la cámara debe seguir al usuario
  // en cuanto llegue la primera lectura de GPS, sin que tenga que tocar el
  // botón de ubicación primero. Antes solo se activaba dentro del callback
  // de "ya llegó una posición Y está dentro del radio de la sede" — si esa
  // primera lectura tardaba (GPS frío, señal débil) o no llegaba a tiempo,
  // el seguimiento se quedaba apagado para siempre hasta tocar el botón a
  // mano (que sí lo prendía de inmediato, sin esperar nada). El botón sigue
  // sirviendo para RECUPERAR el seguimiento después de mover el mapa.
  bool _isTrackingActive = true;
  bool _isNavigating = false;

  /// true mientras una animación de cámara disparada por nuestro propio
  /// código (seguir al usuario) está en curso — ver _panCamera/_panCameraNavigating.
  bool _isProgrammaticCameraMove = false;

  // ──────────────────────────────────────────────────────────
  //  Editor de administrador (Fase 2)
  // ──────────────────────────────────────────────────────────

  /// Solo visible/activable si isAdminProvider es true. Al tocar el mapa en
  /// este modo se agregan puntos nuevos en vez de solo consultarlos.
  bool _isEditMode = false;

  /// Id del punto que se está reubicando: el siguiente toque en el mapa lo
  /// mueve ahí y sale de este modo. `null` = no hay una reubicación pendiente.
  String? _editMovingId;

  /// Id del punto de origen elegido para trazar una arista nueva ("Conectar").
  /// `null` = no hay ninguna conexión en curso.
  String? _editConnectFromId;

  /// Posición del punto de origen elegido para "Conectar" — se guarda junto
  /// con el id para no tener que volver a buscarlo al crear la arista.
  LatLng? _editConnectFromPos;

  /// Guard para no disparar dos escrituras a la vez desde el editor.
  bool _isEditSaving = false;

  /// true mientras una hoja del editor (agregar/editar punto) está abierta.
  /// GoogleMap en Flutter Web usa un elemento HTML real por debajo (no un
  /// canvas normal de Flutter), y sus toques a veces se "filtran" a través
  /// del modal — sin este guard, tocar un ChoiceChip dentro de la hoja
  /// también llegaba al mapa de fondo y volvía a abrir "Nuevo punto" desde
  /// cero (por eso siempre "regresaba a Edificio", el tipo por defecto).
  bool _isEditSheetOpen = false;

  static const _uuid = Uuid();

  /// Guard para evitar llamadas concurrentes a _fetchRoute cuando el usuario
  /// toca "Trazar Ruta" varias veces antes de que termine la primera peticion.
  bool _isFetchingRoute = false;

  LatLng? _destinationLatLng;
  Timer? _routeRecalcTimer;

  /// Estado actual del cuadro de estado de ruta (null = oculto). Ver
  /// [_RouteBannerKind] arriba del State para por qué esto vive como parte
  /// del árbol del mapa en vez de como SnackBar.
  _RouteBannerKind? _routeBanner;
  String? _routeBannerLabel;
  Timer? _routeBannerTimer;

  void _showRouteBanner(_RouteBannerKind kind,
      {String? label, Duration? autoHide}) {
    _routeBannerTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _routeBanner = kind;
      _routeBannerLabel = label;
    });
    if (autoHide != null) {
      _routeBannerTimer = Timer(autoHide, () {
        if (!mounted) return;
        // Al ocultarse, NO siempre debe irse a "nada": si el aviso
        // temporal (p. ej. "ya tienes una ruta activa") tapó al cuadro de
        // "Ruta activa" real, hay que regresar A ESE, no perderlo — antes
        // se perdía el botón de cancelar hasta recargar la pantalla.
        final stillNavigating =
            ref.read(navigationProvider).status == NavStatus.navigating;
        setState(() {
          _routeBanner =
              stillNavigating ? _RouteBannerKind.active : null;
          _routeBannerLabel = null;
        });
      });
    }
  }

  void _hideRouteBanner() {
    _routeBannerTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _routeBanner = null;
      _routeBannerLabel = null;
    });
  }

  late final AnimationController _posAnimController;
  final Map<String, BitmapDescriptor> _markerIconCache = {};

  static const LatLng _initialPosition =
      LatLng(CampusLocations.centerLat, CampusLocations.centerLng);

  /// Sede que se está mostrando. Se resuelve en [didChangeDependencies] desde
  /// `arguments['venueId']`; por defecto TecNM Colima si no se especifica.
  Venue _venue = VenueRegistry.tecColima;

  /// Centro de la sede que se está viendo. Toda la lógica de GPS se mide
  /// contra ESTO, no contra el centro del TecNM Colima: 6 de las 9 sedes del
  /// evento quedan a más de 2.5 km del Tec (Coquimatlán a ~9.5 km), así que
  /// medir contra el Tec hacía que la app te considerara "fuera del campus"
  /// estando parado justo en la sede.
  LatLng get _venueCenter => LatLng(_venue.centerLat, _venue.centerLng);

  /// Radio alrededor del centro de la sede dentro del cual se considera que
  /// el usuario está "en la sede" y tiene sentido centrar/seguir su GPS.
  static const double _venueRadiusMeters = 2500;

  /// ¿Tiene sentido seguir el GPS del usuario en vez de reencuadrar en la
  /// sede? En modo mapa abierto siempre: no hay una sede a la cual regresar
  /// la vista, y forzar el encuadre era justo lo que impedía moverse.
  bool _puedeSeguirAlUsuario(LatLng p) =>
      widget.openMap ||
      Geolocator.distanceBetween(p.latitude, p.longitude,
              _venueCenter.latitude, _venueCenter.longitude) <
          _venueRadiusMeters;

  /// Distancia (metros) para considerar que el usuario "ya llegó" a un
  /// destino — usado tanto para detectar la llegada durante una navegación
  /// activa (como respaldo de la señal autoritativa `NavStatus.arrived`,
  /// ver [NavigationState]) como para evitar recalcular una ruta hacia un
  /// lugar donde ya se está parado (ver [_handleTraceRouteTo]). 18m en vez
  /// de un valor más ajustado porque las coordenadas de un lugar (el pin,
  /// puesto a mano) casi nunca coinciden exacto con la puerta real, y la
  /// precisión típica de GPS en exteriores ya anda entre 5 y 15m.
  static const double _arrivalRadiusMeters = 18.0;

  /// Caja de restricción de cámara de la sede actual (antes era un único
  /// valor global fijo a TecNM Colima — Sendera/Zentralia ya caían fuera de
  /// esa caja).
  LatLngBounds get _cameraBounds => LatLngBounds(
        southwest: LatLng(_venue.boundsSouthLat, _venue.boundsWestLng),
        northeast: LatLng(_venue.boundsNorthLat, _venue.boundsEastLng),
      );

  late LatLng _mapInitialCenter;
  late double _mapInitialZoom;
  bool _initializedWithArgs = false;

  // Map style strings (cargados desde assets)
  String? _darkMapStyle;
  String? _lightMapStyle;
  String? _currentMapStyle;
  MapType _mapType = MapType.normal;

  @override
  void initState() {
    super.initState();
    _mapInitialCenter = _initialPosition;
    _mapInitialZoom = 17.0;

    _posAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(_onPositionAnimTick);

    if (_isDesktop) {
      _flutterMapController = fm.MapController();
    }

    _loadMapStyles();
  }

  Future<void> _loadMapStyles() async {
    try {
      _darkMapStyle =
          await rootBundle.loadString('assets/map_styles/dark_style.json');
      _lightMapStyle =
          await rootBundle.loadString('assets/map_styles/light_style.json');
      final isDark = ref.read(mapThemeProvider) == 'dark';
      if (mounted) {
        setState(() => _currentMapStyle = isDark ? _darkMapStyle : _lightMapStyle);
      }
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = ref.read(settingsProvider);
    ref.read(mapThemeProvider.notifier).state =
        settings.highContrast ? 'dark' : 'light';

    if (!_initializedWithArgs) {
      if (widget.openMap) {
        // Arranca encuadrando todas las sedes del evento: es un mapa para
        // explorar, así que lo primero que debe verse es dónde está cada una.
        final centro = VenueRegistry.centroDeTodasLasSedes();
        _mapInitialCenter = LatLng(centro.$1, centro.$2);
        _mapInitialZoom = 11.5;
        _centeredOnUser = true; // no reencuadrar por su cuenta al llegar GPS
      }
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        final venueId = args['venueId'] as String?;
        if (venueId != null) {
          _venue = VenueRegistry.byId(venueId);
        }

        final lat = args['lat'] as double?;
        final lng = args['lng'] as double?;
        final zoom = args['zoom'] as double? ?? 17.0;
        if (lat != null && lng != null) {
          _mapInitialCenter = LatLng(lat, lng);
          _mapInitialZoom = zoom;
          _centeredOnUser = true;
        }
      }
      // Sincroniza el provider de sede actual para que filteredPlacesProvider
      // (y con él, todo el pipeline de marcadores) escuche la sede correcta.
      // Se difiere: este mismo widget hace `ref.watch(filteredPlacesProvider)`
      // en su build(), y escribir el provider que depende de él mientras el
      // árbol todavía se está montando dispara "Tried to modify a provider
      // while the widget tree was building" en Riverpod.
      final resolvedVenueId = _venue.id;
      final abierto = widget.openMap;
      Future(() {
        if (mounted) {
          ref.read(currentVenueIdProvider.notifier).state = resolvedVenueId;
          ref.read(openMapModeProvider.notifier).state = abierto;
        }
      });
      _initializedWithArgs = true;

      final navState = ref.read(navigationProvider);
      // Una ruta activa calculada para OTRA sede es una ruta fantasma: no
      // tiene sentido mostrarla aquí (venía de una navegación anterior que
      // el usuario canceló, o de la que simplemente salió sin cancelar).
      // Se descarta y se limpia el estado global para que tampoco reaparezca
      // la próxima vez.
      final routeBelongsHere = navState.routeVenueId == null ||
          navState.routeVenueId == resolvedVenueId;
      if (navState.activeRoute != null && !routeBelongsHere) {
        Future(() {
          if (mounted) {
            ref.read(navigationProvider.notifier).cancelNavigation();
          }
        });
      } else if (navState.activeRoute != null) {
        final points = navState.activeRoute!.steps
            .map((s) => LatLng(s.node.lat, s.node.lng))
            .toList();
        Future.microtask(() {
          _setRoutePolyline(points);
          setState(() {
            _isNavigating = true;
            _destinationLatLng = points.last;
          });
          _showRouteBanner(_RouteBannerKind.active);
        });
        if (_mapInitialCenter == _initialPosition) {
          _mapInitialCenter = points.first;
          _mapInitialZoom = 17.5;
          _centeredOnUser = true;
        }
      } else if (navState.currentNode != null) {
        if (_mapInitialCenter == _initialPosition) {
          _mapInitialCenter =
              LatLng(navState.currentNode!.lat, navState.currentNode!.lng);
          _mapInitialZoom = 18.0;
          _centeredOnUser = true;
        }
      }
    }
  }

  void _speak(String text) {
    ref.read(voiceProvider.notifier).speakAnnouncement(text);
  }

  @override
  void dispose() {
    _posAnimController.removeListener(_onPositionAnimTick);
    _posAnimController.dispose();
    _routeRecalcTimer?.cancel();
    _routeBannerTimer?.cancel();
    _userPosNotifier.dispose();
    _googleMapController?.dispose();
    _flutterMapController?.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────
  //  Marcadores POI — BitmapDescriptor desde Canvas
  // ──────────────────────────────────────────────────────────

  Future<BitmapDescriptor> _buildPoiIcon(
      PlaceCategory category, double devicePixelRatio) async {
    final cacheKey = '${category.name}_$devicePixelRatio';
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }

    // Pin de gota, como los de Google Maps: cabeza redonda con la punta
    // abajo señalando el punto exacto. Relleno plano en azul TecNM, contorno
    // blanco para que se lea sobre cualquier tesela, y sombra suave. Sin
    // resplandores ni degradados.
    const w = 88.0;
    const h = 112.0;
    const cx = w / 2;
    const cy = 40.0; // centro de la cabeza
    const r = 32.0; // radio de la cabeza
    const tipY = h - 6; // punta

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final fill = PlaceVisuals.colorFor(category);

    final pin = Path()
      ..moveTo(cx - r, cy)
      ..arcTo(
          Rect.fromCircle(center: const Offset(cx, cy), radius: r), math.pi,
          math.pi, false)
      ..quadraticBezierTo(cx + r * 0.72, cy + r * 1.05, cx, tipY)
      ..quadraticBezierTo(cx - r * 0.72, cy + r * 1.05, cx - r, cy)
      ..close();

    // Sombra proyectada, discreta.
    canvas.drawPath(
      pin.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(pin, Paint()..color = fill);
    canvas.drawPath(
      pin,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    // El glifo que va dentro del pin es el ícono de la categoría (alberca,
    // básquetbol, béisbol…), como en Google Maps, en vez de la letra del
    // edificio o un pin genérico para todo.
    final icon = PlaceVisuals.iconFor(category);
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 34,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
        canvas, Offset(cx - iconPainter.width / 2, cy - iconPainter.height / 2));

    final img =
        await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      width: 36,
      height: 46,
    );

    _markerIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> _buildUserIcon(double devicePixelRatio) async {
    const cacheKey = 'user_marker';
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }

    // Punto de ubicación al estilo Google Maps: halo de precisión muy tenue,
    // anillo blanco y punto sólido encima. Colores planos, sin pulso ni
    // resplandor (eso es lo que lo hacía ver "de neón").
    const size = 80.0;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Halo de precisión.
    canvas.drawCircle(
      center,
      34,
      Paint()..color = AppMapColors.userLocationHalo.withValues(alpha: 0.14),
    );

    // Sombra sutil bajo el punto, para despegarlo del mapa.
    canvas.drawCircle(
      const Offset(size / 2, size / 2 + 1.5),
      17,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Anillo blanco + punto sólido.
    canvas.drawCircle(center, 17, Paint()..color = Colors.white);
    canvas.drawCircle(center, 12, Paint()..color = AppMapColors.userLocation);

    final img = await recorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      width: 36,
      height: 36,
    );

    _markerIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<void> _rebuildMarkers(List<PlaceNode> places) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final Set<Marker> newMarkers = {};

    for (final place in places) {
      final icon = await _buildPoiIcon(PlaceVisuals.categoryOf(place), dpr);
      newMarkers.add(
        Marker(
          markerId: MarkerId(place.id),
          position: LatLng(place.latitude, place.longitude),
          icon: icon,
          infoWindow: InfoWindow(title: place.name, snippet: place.type),
          onTap: () {
            if (_isEditMode || _editConnectFromId != null) {
              _handleEditTapOnPoint(
                id: place.id,
                name: place.name,
                lat: place.latitude,
                lng: place.longitude,
                hasPlace: true,
              );
            } else {
              ref.read(selectedPlaceProvider.notifier).state = place;
            }
          },
        ),
      );
    }

    if (mounted) setState(() => _googleMarkers = newMarkers);
  }

  // ──────────────────────────────────────────────────────────
  //  Cámara multiplataforma (GoogleMap / flutter_map)
  // ──────────────────────────────────────────────────────────

  ll.LatLng _toLL(LatLng p) => ll.LatLng(p.latitude, p.longitude);

  void _panCamera(LatLng target, {double? zoom}) {
    if (_isDesktop) {
      final controller = _flutterMapController;
      if (controller == null) return;
      controller.move(_toLL(target), zoom ?? controller.camera.zoom);
      return;
    }
    // GoogleMap dispara onCameraMove también para movimientos programáticos
    // (no solo gestos del usuario) — sin esta bandera, seguir al usuario
    // apagaba _isTrackingActive a sí mismo en el primer auto-pan. flutter_map
    // no tiene este problema porque su onPositionChanged sí distingue
    // hasGesture.
    _isProgrammaticCameraMove = true;
    _googleMapController?.animateCamera(
      zoom != null
          ? CameraUpdate.newLatLngZoom(target, zoom)
          : CameraUpdate.newLatLng(target),
    );
  }

  void _panCameraNavigating(LatLng target, double zoom, double bearing) {
    if (_isDesktop) {
      _flutterMapController?.moveAndRotate(_toLL(target), zoom, bearing);
      return;
    }
    _isProgrammaticCameraMove = true;
    _googleMapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
            target: target, zoom: zoom, tilt: 50.0, bearing: bearing),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  GPS y permisos
  // ──────────────────────────────────────────────────────────

  Future<bool> _requestLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) await _showGpsDisabledDialog();
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          final warningColor = Theme.of(context).brightness == Brightness.dark
              ? AppWarning.dark
              : AppWarning.light;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.location_off_rounded, color: warningColor, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Permiso de ubicación denegado. Algunas funciones estarán limitadas.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        final cs = Theme.of(context).colorScheme;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg)),
            icon: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.location_disabled_rounded,
                  color: cs.error, size: 40),
            ),
            title: const Text(
              'Permiso de Ubicación Requerido',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            content: Text(
              'Los permisos de ubicación han sido denegados permanentemente. '
              'Para usar la navegación en el campus, abre los ajustes de la aplicación y habilítalos manualmente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.5),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Abrir Ajustes'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Geolocator.openAppSettings();
                },
              ),
            ],
          ),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> _showGpsDisabledDialog() async {
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.gps_off_rounded, color: cs.onPrimary, size: 36),
        ),
        title: const Text(
          'GPS Desactivado',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Para brindarte la mejor experiencia de navegación en las sedes, TecNM Mapas necesita acceder a tu ubicación en tiempo real.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: cs.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'También puedes navegar escaneando los códigos QR de los pasillos.',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.7),
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continuar sin GPS'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.gps_fixed_rounded, size: 18),
            label: const Text('Activar GPS'),
            onPressed: () {
              Navigator.of(ctx).pop();
              Geolocator.openLocationSettings();
            },
          ),
        ],
      ),
    );
  }

  void _showOutsideVenueSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Estás lejos de ${_venue.label}. Centrando la vista en la sede.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _initializeGpsAndCenter({bool force = false}) async {
    if (_centeredOnUser && !force) return;
    final permissionGranted = await _requestLocationPermission();
    if (!permissionGranted || !mounted) return;

    ref.invalidate(currentLocationStreamProvider);

    // Mostrar algo DE INMEDIATO con la última posición conocida (instantánea,
    // no espera nada) mientras se pide un fix fresco abajo — un GPS "frío"
    // (recién se abrió el mapa, o mala señal en interiores) puede tardar
    // varios segundos en resolver, y no hay razón para que el punto azul
    // tarde en aparecer si el teléfono ya sabe más o menos dónde estás.
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted && _currentPosition == null) {
        final quickLatLng = LatLng(lastKnown.latitude, lastKnown.longitude);
        // Publicar por la misma vía que el stream: setear solo
        // _currentPosition no dibuja nada, porque el punto azul se pinta
        // desde _userPosNotifier + _userIconCache, y ambos se llenan dentro
        // de _onNewGpsPosition. Sin internet el primer fix satelital tarda
        // decenas de segundos, así que este era justo el caso en el que el
        // punto no aparecía nunca.
        _onNewGpsPosition(quickLatLng, heading: lastKnown.heading);
        if (_puedeSeguirAlUsuario(quickLatLng)) {
          _panCamera(quickLatLng, zoom: 17.5);
        }
      }
    } catch (_) {
      // Sin última posición conocida (primer uso del dispositivo) — no pasa
      // nada, se intenta el respaldo propio abajo y se sigue esperando el fix
      // fresco.
    }

    // Último recurso: la posición que guardamos nosotros en SharedPreferences.
    // Android puede devolver null en getLastKnownPosition (tras reiniciar, o
    // si otra app no ha pedido ubicación en un rato), y offline no hay
    // ubicación por red que rellene el hueco.
    if (mounted && _currentPosition == null) {
      final saved = await OfflineManager.loadLastPosition();
      if (saved != null && mounted && _currentPosition == null) {
        final savedLatLng = LatLng(saved.lat, saved.lng);
        _onNewGpsPosition(savedLatLng);
        if (_puedeSeguirAlUsuario(savedLatLng)) {
          _panCamera(savedLatLng, zoom: saved.zoom);
        }
      }
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (!mounted) return;
      final latLng = LatLng(position.latitude, position.longitude);
      _onNewGpsPosition(latLng, heading: position.heading);

      _centeredOnUser = true;
      if (_puedeSeguirAlUsuario(latLng)) {
        _panCamera(latLng, zoom: 17.5);
      } else {
        _panCamera(_venueCenter, zoom: 17.0);
        _showOutsideVenueSnackBar();
      }
    } on TimeoutException {
      debugPrint('GPS: timeout — se usará el stream.');
    } catch (e) {
      debugPrint('GPS: error al obtener posición inicial: $e');
    }
  }

  void _centerOnUser() {
    // Restaurar a GPS real al centrar
    ref.read(navigationProvider.notifier).clearManualPosition();
    setState(() => _isTrackingActive = true);

    LatLng? targetPos = _displayPosition ?? _currentPosition;

    if (targetPos != null) {
      if (_puedeSeguirAlUsuario(targetPos)) {
        // No heredar el zoom tal cual: si lo último que pasó fue un
        // _fitBounds de una ruta (zoom muy abierto para mostrarla completa),
        // "centrar ubicación" se veía casi vacío porque el punto quedaba
        // chiquito en una vista muy alejada. Si ya se estaba viendo de
        // cerca, se respeta ese zoom; si no, se usa uno cercano razonable.
        final zoom = _currentZoom < 16.5 ? 17.5 : _currentZoom;
        _panCamera(targetPos, zoom: zoom);
      } else {
        _panCamera(_venueCenter, zoom: 17.0);
        _showOutsideVenueSnackBar();
      }
    } else {
      _initializeGpsAndCenter(force: true);
    }
  }

  // ──────────────────────────────────────────────────────────
  //  Interpolación GPS suave
  // ──────────────────────────────────────────────────────────

  void _onNewGpsPosition(LatLng newPos, {double heading = 0.0}) {
    _previousPosition = _displayPosition ?? _currentPosition ?? newPos;
    setState(() {
      _currentPosition = newPos;
      if (heading >= 0) _currentHeading = heading;
    });
    if (!_isDesktop) _ensureUserIcon();
    _posAnimController.forward(from: 0.0);
    _persistPositionThrottled(newPos);
    if (_isNavigating) _scheduleRouteRecalc(newPos);
  }

  /// Persiste la posición para que el mapa tenga algo que mostrar en el
  /// próximo arranque sin conexión, cuando el sistema tarda en dar un fix.
  void _persistPositionThrottled(LatLng pos) {
    final now = DateTime.now();
    if (_lastPositionSaveAt != null &&
        now.difference(_lastPositionSaveAt!) < const Duration(seconds: 15)) {
      return;
    }
    _lastPositionSaveAt = now;
    OfflineManager.saveLastPosition(
      latitude: pos.latitude,
      longitude: pos.longitude,
      zoom: _currentZoom,
    );
  }

  /// Genera el ícono del usuario una sola vez y lo cachea (ver comentario en
  /// el campo _userIconCache). Solo hace falta llamarla, es idempotente.
  Future<void> _ensureUserIcon() async {
    if (_userIconCache != null || !mounted) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final icon = await _buildUserIcon(dpr);
    if (mounted) setState(() => _userIconCache = icon);
  }

  void _onPositionAnimTick() {
    if (_previousPosition == null || _currentPosition == null) return;

    final t = Curves.easeOutCubic.transform(_posAnimController.value);
    final lat = _previousPosition!.latitude +
        (_currentPosition!.latitude - _previousPosition!.latitude) * t;
    final lng = _previousPosition!.longitude +
        (_currentPosition!.longitude - _previousPosition!.longitude) * t;

    final interpolated = LatLng(lat, lng);
    // Sin setState: solo el mapa (envuelto en un ValueListenableBuilder) debe
    // reaccionar a esto, no toda la pantalla.
    _displayPosition = interpolated;
    _userPosNotifier.value = interpolated;

    if (_isTrackingActive) {
      if (_puedeSeguirAlUsuario(interpolated)) {
        if (_isNavigating) {
          _panCameraNavigating(interpolated, 19.5, _currentHeading);
        } else {
          _panCamera(interpolated);
        }
      }
    }
  }

  void _scheduleRouteRecalc(LatLng rawPos) {
    _routeRecalcTimer?.cancel();
    _routeRecalcTimer =
        Timer(const Duration(milliseconds: 1200), () async {
      if (!mounted || !_isNavigating || _destinationLatLng == null) return;

      final snapPos = _displayPosition ?? rawPos;
      final navService = ref.read(navigationServiceProvider);
      final graph = navService.graph;
      if (graph == null) return;

      final corridors = graph.nodes.values
          .where((n) =>
              n.type == NodeType.corridor || n.type == NodeType.entrance)
          .toList();
      final nearest =
          _closestNodeTo(corridors, snapPos, maxDistanceM: 100);
      if (nearest == null) return;
      if (nearest.id == navService.currentNodeId) return;

      await calculateAccessibleRoute(_destinationLatLng!);
    });
  }

  /// Punto de entrada único para "Trazar Ruta" hacia un lugar concreto
  /// (llamado desde la hoja de un POI). Antes de calcular nada, revisa si
  /// el usuario ya está parado en/junto al destino — sin esto, tocar
  /// "Trazar Ruta" estando ya ahí disparaba una llamada a Google Routes
  /// (o Dijkstra) para una ruta de un par de metros sin sentido, y encima
  /// dejaba `_isNavigating = true` con una "ruta" fantasma en el mapa.
  void _handleTraceRouteTo(LatLng destination, String? destinationName) {
    // No se permite empalmar una ruta nueva sobre una que sigue en curso —
    // cambiar de destino a medias es justo lo que dejaba estados raros
    // (una ruta calculándose mientras otra seguía "activa" a medias). Hay
    // que cancelar la actual primero (botón "×" de la barra o "FINALIZAR"
    // una vez que se llega) antes de trazar una nueva.
    final navState = ref.read(navigationProvider);
    if (navState.status == NavStatus.navigating) {
      _showRouteBanner(_RouteBannerKind.blocked,
          autoHide: const Duration(seconds: 3));
      return;
    }

    // "Ya estás ahí" se compara contra dos posibles "dónde estoy": la
    // posición cruda de GPS, o — si está activa — la posición fijada a
    // mano con "Estoy Aquí", que tiene prioridad: si alguien fijó su
    // posición en Edificio R y luego toca "Trazar Ruta" ahí mismo, debe
    // contar como "ya estás ahí" sin importar lo que diga el GPS crudo en
    // ese momento (que puede estar impreciso, o simplemente distinto de
    // lo que la persona declaró a mano).
    LatLng? origin = _displayPosition ?? _currentPosition;
    if (navState.isManualPosition && navState.currentNode != null) {
      origin = LatLng(navState.currentNode!.lat, navState.currentNode!.lng);
    }
    if (origin != null) {
      final distance = Geolocator.distanceBetween(
        origin.latitude, origin.longitude,
        destination.latitude, destination.longitude,
      );
      if (distance <= _arrivalRadiusMeters) {
        _announceAlreadyThere(destinationName);
        return;
      }
    }

    // Se guarda SIEMPRE, antes de calcular nada: tanto la llegada por
    // distancia cruda de GPS como el recálculo automático de ruta
    // (_scheduleRouteRecalc) dependen de esto.
    _destinationLatLng = destination;

    // Aviso inmediato: pedir la ruta a Google (o el respaldo por Dijkstra)
    // toma un instante (viaje de red de ida y vuelta). Este cuadro se queda
    // en "calculando" hasta que el listener de más abajo lo cambie a
    // "activa" (o a "error" si no se pudo).
    _showRouteBanner(_RouteBannerKind.calculating);

    // Google Routes API primero (sigue calles/andadores reales); el grafo
    // interno por Dijkstra es el ÚLTIMO recurso — `calculateAccessibleRoute`
    // ya cae a Dijkstra automáticamente por dentro (`_fallbackToDijkstra`)
    // si Google falla: sin internet, sin API key, o sin resultados.
    if (_currentPosition != null) {
      ref.read(navigationProvider.notifier).setPositionByCoordinates(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
    }
    calculateAccessibleRoute(destination, destinationName);
  }

  /// Feedback de "ya estás en tu destino" cuando se pide una ruta estando ya
  /// ahí — mismo tono que [_handleArrival] pero sin tocar el estado de
  /// navegación (no había ruta activa que cancelar).
  void _announceAlreadyThere(String? destinationName) {
    final label = (destinationName == null || destinationName.isEmpty)
        ? 'tu destino'
        : destinationName;
    _speak('Ya estás en $label.');
    _showRouteBanner(_RouteBannerKind.alreadyThere,
        label: label, autoHide: const Duration(seconds: 4));
  }

  // ──────────────────────────────────────────────────────────
  //  Rutas via Google Routes API (backend proxy)
  // ──────────────────────────────────────────────────────────

  Future<void> calculateAccessibleRoute(LatLng destination,
      [String? destinationName]) async {
    if (_isFetchingRoute) return;
    _isFetchingRoute = true;
    _destinationLatLng = destination;

    try {
      // La posición fijada a mano ("Estoy Aquí") tiene prioridad sobre el
      // GPS crudo — para eso existe ese botón: declarar "estoy aquí,
      // ignora el GPS". Sin este chequeo, la ruta calculada CON señal de
      // GPS disponible (el caso normal, "con internet") siempre partía de
      // la posición real, ignorando por completo la posición manual; solo
      // se respetaba la manual cuando el GPS estaba totalmente ausente (el
      // camino de abajo, vía `navService.currentNodeId`) — de ahí que
      // "sin internet" (donde el GPS es más probable que falle) sí se
      // comportara como se esperaba y "con internet" no.
      final navState = ref.read(navigationProvider);
      LatLng? origin;
      if (navState.isManualPosition && navState.currentNode != null) {
        origin =
            LatLng(navState.currentNode!.lat, navState.currentNode!.lng);
      } else {
        origin = _displayPosition ?? _currentPosition;
      }
      if (origin == null) {
        final navService = ref.read(navigationServiceProvider);
        final graph = navService.graph;
        final fromId = navService.currentNodeId;

        if (fromId == null || graph == null) {
          if (mounted) {
            final cs = Theme.of(context).colorScheme;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.gps_off_rounded,
                        color: cs.onPrimary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Activa el GPS para trazar tu ruta.',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onPrimary),
                      ),
                    ),
                  ],
                ),
                backgroundColor: cs.primary,
                behavior: SnackBarBehavior.fixed,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          _hideRouteBanner();
          return;
        }
        // Si hay nodo QR fijado, usar sus coordenadas como origen
        final fromNode = graph.nodes[fromId];
        if (fromNode == null) return;
        final local = ref.read(navigationProvider.notifier).calcularRutaLocal(
              originLat: fromNode.lat,
              originLng: fromNode.lng,
              destLat: destination.latitude,
              destLng: destination.longitude,
              destinationName: destinationName,
            );
        if (!local) {
          _showFarAwayDialog(destination);
        }
        return;
      }

      final local = ref.read(navigationProvider.notifier).calcularRutaLocal(
            originLat: origin.latitude,
            originLng: origin.longitude,
            destLat: destination.latitude,
            destLng: destination.longitude,
            destinationName: destinationName,
          );
      if (!local) {
        debugPrint('Ruta: el grafo local no cubre el trayecto; se muestra el diálogo.');
        _showFarAwayDialog(destination);
      }
    } finally {
      _isFetchingRoute = false;
    }
  }

  void _showFarAwayDialog(LatLng destination) {
    // Cancelar el estado "Calculando..." para que no se quede bloqueado
    ref.read(navigationProvider.notifier).cancelNavigation();
    _hideRouteBanner();

    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.map_rounded, color: cs.primary, size: 40),
        ),
        title: const Text(
          'Estás lejos de la sede',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(
          'El mapa interno de navegación es exclusivo para moverse dentro de las instalaciones.\n\n¿Quieres usar Google Maps para llegar hasta aquí primero?',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.7),
              fontSize: 14,
              height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton.icon(
            icon: Icon(Icons.directions_rounded, size: 18, color: cs.onPrimary),
            label: Text('Usar Google Maps', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _launchExternalGoogleMaps(destination);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _launchExternalGoogleMaps(LatLng dest) async {
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}&travelmode=walking');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      // Cancel internal route calculation
      ref.read(navigationProvider.notifier).cancelNavigation();
    } catch (e) {
      debugPrint('Error launching Google Maps: $e');
      ref.read(navigationProvider.notifier).setRouteError(
          'Estás demasiado lejos de la sede para trazar una ruta a pie y no se pudo abrir Google Maps.');
    }
  }

  void _setRoutePolyline(List<LatLng> points) {
    setState(() {
      _googlePolylines = {
        Polyline(
          polylineId: const PolylineId('campus_route_border'),
          points: points,
          color: Colors.white,
          width: 10,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 1,
        ),
        Polyline(
          polylineId: const PolylineId('campus_route'),
          points: points,
          color: Colors.blueAccent.shade700,
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 2,
        ),
      };
    });
  }

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    if (_isDesktop) {
      _flutterMapController?.fitCamera(
        fm.CameraFit.bounds(
          bounds: fm.LatLngBounds.fromPoints(points.map(_toLL).toList()),
          padding: const EdgeInsets.all(60),
        ),
      );
      return;
    }
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    // Sin esto, onCameraMove interpreta este zoom-out programático como si
    // el usuario hubiera arrastrado el mapa a mano, y apaga
    // _isTrackingActive — la cámara dejaba de seguir al usuario justo al
    // trazar (o recalcular) cada ruta. _panCamera/_panCameraNavigating ya
    // ponen esta bandera; a esta función se le había quedado fuera.
    _isProgrammaticCameraMove = true;
    _googleMapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  CampusNode? _closestNodeTo(List<CampusNode> nodes, LatLng target,
      {double maxDistanceM = double.infinity}) {
    CampusNode? best;
    double bestDist = double.infinity;
    for (final node in nodes) {
      final d = Geolocator.distanceBetween(
          target.latitude, target.longitude, node.lat, node.lng);
      if (d < bestDist) {
        bestDist = d;
        best = node;
      }
    }
    return bestDist <= maxDistanceM ? best : null;
  }

  // ──────────────────────────────────────────────────────────
  //  Bottom Sheet y helpers UI
  // ──────────────────────────────────────────────────────────

  // El aviso de llegada por VOZ (y el SnackBar de respaldo si esta pantalla
  // no está abierta) vive en `main.dart`, a nivel raíz de la app — para que
  // suene sin importar en qué pantalla esté la persona en el momento exacto
  // en que el GPS confirma la llegada. Pero si el mapa SÍ está abierto (que
  // es el caso normal), además se muestra aquí mismo, dentro del cuadro de
  // estado de ruta, para que quien está viendo el mapa lo vea justo ahí.
  void _handleArrival() {
    ref.read(navigationProvider.notifier).cancelNavigation();
    setState(() {
      _isNavigating = false;
      _googlePolylines = {};
      _destinationLatLng = null;
      _isTrackingActive = false;
    });
    _showRouteBanner(_RouteBannerKind.arrived,
        autoHide: const Duration(seconds: 5));
  }

  void _showAccessibleBottomSheet(PlaceNode place) {
    final cs = Theme.of(context).colorScheme;
    final placeAccent = PlaceVisuals.colorOf(place);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          border: Border(top: BorderSide(color: cs.outline)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50, height: 5,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Foto real del lugar (Street View o satelital de Google), igual
            // que el encabezado de una ficha de Google Maps.
            PlacePhotoBanner(place: place),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: placeAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: placeAccent.withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    PlaceVisuals.iconOf(place),
                    color: placeAccent,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.name,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                            letterSpacing: -0.5,
                          )),
                      const SizedBox(height: 4),
                      Text(PlaceVisuals.labelOf(place).toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: placeAccent.withValues(alpha: 0.9),
                            letterSpacing: 1.2,
                          )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _buildInfoBadge(Icons.accessible_rounded,
                    'Nivel: ${place.accessibilityLevel.toUpperCase()}',
                    place.accessibilityLevel.toLowerCase() == 'alto'
                        ? cs.tertiary
                        : (Theme.of(context).brightness == Brightness.dark
                            ? AppWarning.dark
                            : AppWarning.light)),
                const SizedBox(width: 12),
                _buildInfoBadge(Icons.map_rounded, 'Piso: Planta Baja', cs.primary),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.directions_walk_rounded, size: 22, color: cs.onPrimary),
                      label: Text('Trazar Ruta',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cs.onPrimary)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleTraceRouteTo(
                          LatLng(place.latitude, place.longitude),
                          place.name,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.location_on_rounded, size: 22, color: cs.primary),
                      label: Text('Estoy Aquí',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cs.primary)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary.withValues(alpha: 0.05),
                          side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
                      onPressed: () {
                        Navigator.pop(ctx);
                        ref.read(navigationProvider.notifier)
                            .setPosition(place.id, label: place.name);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildThemeToggle(bool isDark) {
    return _buildRoundIconButton(
      icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      tooltip: 'Cambiar tema',
      onPressed: () {
        final newTheme = isDark ? 'light' : 'dark';
        ref.read(mapThemeProvider.notifier).state = newTheme;
        setState(() => _currentMapStyle = newTheme == 'dark' ? _darkMapStyle : _lightMapStyle);
      },
    );
  }

  Widget _buildMapTypeToggle() {
    final isSatellite = _mapType == MapType.hybrid;
    return _buildRoundIconButton(
      icon: isSatellite ? Icons.map_outlined : Icons.layers_outlined,
      tooltip: isSatellite ? 'Ver mapa estándar' : 'Ver vista satélite',
      onPressed: () {
        setState(() {
          _mapType = isSatellite ? MapType.normal : MapType.hybrid;
        });
      },
    );
  }

  /// Botón circular flotante genérico (mismo estilo para volver a Inicio y
  /// para cambiar de tema — antes vivían como parte del AppBar).
  Widget _buildRoundIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        shape: BoxShape.circle,
        border: Border.all(color: cs.outline),
      ),
      child: IconButton(
        icon: Icon(icon, color: cs.primary),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildFABs() {
    final cs = Theme.of(context).colorScheme;
    // El editor se apaga en el mapa abierto: ahí no hay una sede activa, así
    // que un punto nuevo se guardaría en TecNM Colima (la sede por defecto)
    // sin importar en qué parte de Colima se haya tocado.
    final isAdmin =
        !widget.openMap && (ref.watch(isAdminProvider).value ?? false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdmin) ...[
            FloatingActionButton(
              heroTag: 'edit_btn',
              tooltip: _isEditMode ? 'Salir del modo edición' : 'Editar sede (admin)',
              backgroundColor: _isEditMode ? cs.primary : cs.surface,
              onPressed: () async {
                // Al entrar, primero se lee la zona visible: sin ella se
                // dibujarían nodos de toda la sede hasta mover la cámara.
                final region = _isEditMode
                    ? null
                    : await _googleMapController?.getVisibleRegion();
                if (!mounted) return;
                setState(() {
                  _isEditMode = !_isEditMode;
                  _editVisibleRegion = region;
                  _editMovingId = null;
                  _editConnectFromId = null;
                  _editConnectFromPos = null;
                });
              },
              child: Icon(
                _isEditMode ? Icons.close_rounded : Icons.edit_location_alt_rounded,
                color: _isEditMode ? cs.onPrimary : cs.primary,
              ),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            heroTag: 'center_btn',
            onPressed: _centerOnUser,
            backgroundColor: _isTrackingActive ? cs.primary : cs.surface,
            elevation: _isTrackingActive ? 8 : 4,
            child: Icon(
              _isTrackingActive ? Icons.gps_fixed_rounded : Icons.my_location_rounded,
              color: _isTrackingActive ? cs.onPrimary : cs.primary,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Editor de administrador (Fase 2) — agregar/mover/conectar/borrar
  //  puntos del grafo caminable y sus pines de POI.
  // ──────────────────────────────────────────────────────────

  /// Toque sobre el mapa (fuera de cualquier marcador) mientras se está en
  /// modo edición: agrega un punto nuevo, completa una reubicación pendiente,
  /// o cancela una conexión en curso si se tocó vacío.
  void _handleMapBackgroundTap(LatLng point) {
    if (_isEditSheetOpen) return;
    if (_editMovingId != null) {
      final id = _editMovingId!;
      setState(() => _editMovingId = null);
      _moveUnifiedPoint(id, point);
      return;
    }
    if (_editConnectFromId != null) {
      setState(() {
        _editConnectFromId = null;
        _editConnectFromPos = null;
      });
      return;
    }
    if (_isEditMode) {
      _showAddPointSheet(point);
    }
  }

  /// Toque sobre un punto EXISTENTE (POI o nodo de corredor) mientras se está
  /// en modo edición o completando una conexión.
  void _handleEditTapOnPoint({
    required String id,
    required String name,
    required double lat,
    required double lng,
    required bool hasPlace,
  }) {
    if (_isEditSheetOpen) return;
    if (_editConnectFromId != null) {
      final fromId = _editConnectFromId!;
      final fromPos = _editConnectFromPos!;
      setState(() {
        _editConnectFromId = null;
        _editConnectFromPos = null;
      });
      if (fromId == id) return; // tocó el mismo punto de nuevo → cancelar
      _connectNodes(
        fromId: fromId,
        fromPos: fromPos,
        toId: id,
        toPos: LatLng(lat, lng),
      );
      return;
    }
    _showEditPointSheet(id: id, name: name, lat: lat, lng: lng, hasPlace: hasPlace);
  }

  void _showAddPointSheet(LatLng at) {
    final cs = Theme.of(context).colorScheme;
    final nameController = TextEditingController();
    var selectedType = _editPointTypes.first;
    setState(() => _isEditSheetOpen = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          // Con tantos tipos, la lista de chips ya no cabe siempre en
          // pantallas chicas (o con el teclado abierto) — scroll en vez de
          // desbordar.
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nuevo punto',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface)),
              const SizedBox(height: 4),
              Text('Sede: ${_venue.label}',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej. Cancha 3, Entrada Norte...',
                ),
              ),
              const SizedBox(height: 20),
              Text('TIPO',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: cs.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _editPointTypes.map((t) {
                  final selected = identical(t, selectedType);
                  return ChoiceChip(
                    label: Text(t.label, style: const TextStyle(fontSize: 12)),
                    avatar: Icon(t.icon,
                        size: 16, color: selected ? cs.onPrimary : cs.primary),
                    selected: selected,
                    selectedColor: cs.primary,
                    onSelected: (_) => setSheetState(() => selectedType = t),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(ctx);
                    await _createUnifiedPoint(
                        name: name, position: at, typeInfo: selectedType);
                  },
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Guardar',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isEditSheetOpen = false);
    });
  }

  void _showEditPointSheet({
    required String id,
    required String name,
    required double lat,
    required double lng,
    required bool hasPlace,
  }) {
    final cs = Theme.of(context).colorScheme;
    setState(() => _isEditSheetOpen = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_rounded, color: cs.primary),
                title: const Text('Cambiar nombre'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final newName = await _promptRename(name);
                  if (newName != null && newName.isNotEmpty) {
                    _renameUnifiedPoint(id: id, name: newName, hasPlace: hasPlace);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.open_with_rounded, color: cs.primary),
                title: const Text('Mover'),
                subtitle: const Text('Toca el mapa donde quieres reubicarlo'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _editMovingId = id);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.timeline_rounded, color: cs.primary),
                title: const Text('Conectar a otro punto'),
                subtitle: const Text('Traza un camino caminable hasta otro punto'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _editConnectFromId = id;
                    _editConnectFromPos = LatLng(lat, lng);
                  });
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.error),
                title: Text('Eliminar',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await _confirmDelete(name);
                  if (confirmed) _deleteUnifiedPoint(id: id, hasPlace: hasPlace);
                },
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isEditSheetOpen = false);
    });
  }

  Future<String?> _promptRename(String currentName) async {
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: currentName);
    setState(() => _isEditSheetOpen = true);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: const Text('Cambiar nombre'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isEditSheetOpen = false);
    }
  }

  Future<void> _renameUnifiedPoint({
    required String id,
    required String name,
    required bool hasPlace,
  }) async {
    final zoneId = _venue.id;
    try {
      await ref.read(venueGraphRepositoryProvider).renameNode(zoneId, id, name);
    } catch (_) {}
    if (hasPlace) {
      try {
        await ref.read(placeRepositoryProvider).renamePlace(zoneId, id, name);
      } catch (_) {}
    }
  }

  Future<bool> _confirmDelete(String name) async {
    final cs = Theme.of(context).colorScheme;
    setState(() => _isEditSheetOpen = true);
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: const Text('¿Eliminar punto?'),
          content: Text('Se eliminará "$name" permanentemente, junto con sus conexiones.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Eliminar',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        ),
      );
      return result ?? false;
    } finally {
      if (mounted) setState(() => _isEditSheetOpen = false);
    }
  }

  Future<void> _createUnifiedPoint({
    required String name,
    required LatLng position,
    required _EditPointTypeInfo typeInfo,
  }) async {
    if (_isEditSaving) return;
    setState(() => _isEditSaving = true);
    final zoneId = _venue.id;
    final id = _uuid.v4();
    try {
      final node = CampusNode(
        id: id,
        zoneId: zoneId,
        name: name,
        aliases: const [],
        type: typeInfo.nodeType,
        lat: position.latitude,
        lng: position.longitude,
        floor: 0,
        accessible: true,
        description: '',
      );
      await ref.read(venueGraphRepositoryProvider).createNode(node);

      if (typeInfo.placeType != null) {
        final place = PlaceNode(
          id: id,
          zoneId: zoneId,
          name: name,
          latitude: position.latitude,
          longitude: position.longitude,
          type: typeInfo.placeType!,
          accessibilityLevel: 'alto',
        );
        await ref.read(placeRepositoryProvider).createPlace(place);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('"$name" agregado.'),
              backgroundColor: Theme.of(context).colorScheme.tertiary),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al guardar: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isEditSaving = false);
    }
  }

  /// Reubica un punto. Intenta mover tanto el nodo del grafo como el pin de
  /// POI (si existe) — no todos los puntos existentes tienen ambos, así que
  /// los fallos de "documento no existe" en cualquiera de los dos se ignoran
  /// a propósito.
  Future<void> _moveUnifiedPoint(String id, LatLng newPos) async {
    final zoneId = _venue.id;
    try {
      await ref.read(venueGraphRepositoryProvider).moveNode(
            zoneId,
            id,
            lat: newPos.latitude,
            lng: newPos.longitude,
          );
    } catch (_) {}
    try {
      await ref.read(placeRepositoryProvider).movePlace(
            zoneId,
            id,
            lat: newPos.latitude,
            lng: newPos.longitude,
          );
    } catch (_) {}
  }

  Future<void> _deleteUnifiedPoint({
    required String id,
    required bool hasPlace,
  }) async {
    final zoneId = _venue.id;
    try {
      await ref.read(venueGraphRepositoryProvider).deleteNode(zoneId, id);
    } catch (_) {}
    if (hasPlace) {
      try {
        await ref.read(placeRepositoryProvider).deletePlace(zoneId, id);
      } catch (_) {}
    }
  }

  Future<void> _connectNodes({
    required String fromId,
    required LatLng fromPos,
    required String toId,
    required LatLng toPos,
  }) async {
    final distance = Geolocator.distanceBetween(
      fromPos.latitude,
      fromPos.longitude,
      toPos.latitude,
      toPos.longitude,
    );
    final edge = CampusEdge(
      zoneId: _venue.id,
      from: fromId,
      to: toId,
      distance: distance,
      accessible: true,
      direction: 'Continúa por el camino.',
    );
    try {
      await ref.read(venueGraphRepositoryProvider).createEdge(edge);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('Conexión creada.'),
              backgroundColor: Theme.of(context).colorScheme.tertiary),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al conectar: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Escuchar cambios de tema global para regenerar marcadores con nuevos colores
    // (solo aplica a los iconos BitmapDescriptor de GoogleMap; en desktop los
    // marcadores de flutter_map se reconstruyen solos en cada build)
    ref.listen(themeProvider, (_, __) {
      if (_isDesktop) return;
      _markerIconCache.clear();
      _rebuildMarkers(ref.read(filteredPlacesProvider));
    });

    // Lugar seleccionado → bottom sheet
    ref.listen<PlaceNode?>(selectedPlaceProvider, (_, next) {
      if (next != null) {
        _showAccessibleBottomSheet(next);
        Future.delayed(const Duration(milliseconds: 100),
            () => ref.read(selectedPlaceProvider.notifier).state = null);
      }
    });

    // Stream GPS
    ref.listen<AsyncValue<Position>>(currentLocationStreamProvider, (_, next) {
      next.whenData((position) {
        final latLng = LatLng(position.latitude, position.longitude);
        _onNewGpsPosition(latLng, heading: position.heading);

        // Sincronizar posición actual en el provider de navegación local
        ref.read(navigationProvider.notifier).setPositionByCoordinates(
              position.latitude,
              position.longitude,
            );

        if (!_centeredOnUser) {
          _centeredOnUser = true;
          if (_puedeSeguirAlUsuario(latLng)) {
            _isTrackingActive = true;
            _panCamera(latLng, zoom: 17.5);
          } else {
            _panCamera(_venueCenter, zoom: 17.0);
            _showOutsideVenueSnackBar();
          }
        }

        if (_isNavigating && _destinationLatLng != null) {
          final dist = Geolocator.distanceBetween(
            latLng.latitude, latLng.longitude,
            _destinationLatLng!.latitude, _destinationLatLng!.longitude,
          );
          if (dist <= _arrivalRadiusMeters) _handleArrival();
        }
      });
    });

    // Navegación activa → actualizar polilínea
    ref.listen<NavigationState>(navigationProvider, (previous, next) {
      // Señal autoritativa de llegada: `setPositionByCoordinates` (llamado
      // en cada lectura de GPS, arriba) ya calcula esto correctamente tanto
      // para rutas de Google como para rutas por Dijkstra — pero nadie en
      // esta pantalla la escuchaba, así que la ruta terminaba "atorada" en
      // rutas por Dijkstra: el estado interno decía `arrived` pero la UI
      // nunca se enteraba ni mostraba el aviso de llegada.
      if (next.status == NavStatus.arrived &&
          previous?.status != NavStatus.arrived) {
        _handleArrival();
        return;
      }

      // Si se estaba esperando una ruta ("calculando...") y la petición
      // terminó en error (sin internet, sin resultados, etc.), avisar en
      // el mismo cuadro en vez de dejarlo pegado en "calculando" para
      // siempre.
      if (next.status == NavStatus.error &&
          previous?.status != NavStatus.error &&
          _routeBanner == _RouteBannerKind.calculating) {
        _showRouteBanner(_RouteBannerKind.error,
            autoHide: const Duration(seconds: 4));
      }

      if (next.status == NavStatus.ready &&
          previous?.status != NavStatus.ready) {
        _hideRouteBanner();
      }

      if (next.currentNode != previous?.currentNode && next.currentNode != null) {
        _panCamera(LatLng(next.currentNode!.lat, next.currentNode!.lng));
      }

      if (next.activeRoute != previous?.activeRoute ||
          next.routePolylinePoints != previous?.routePolylinePoints) {
        if (next.routePolylinePoints != null) {
          final points = next.routePolylinePoints!
              .map((p) => LatLng(p[0], p[1]))
              .toList();
          _setRoutePolyline(points);
          setState(() => _isNavigating = true);
          _showRouteBanner(_RouteBannerKind.active);
          _fitBounds(points);
        } else if (next.activeRoute != null) {
          final points = next.activeRoute!.getPolylinePoints()
              .map((p) => LatLng(p[0], p[1]))
              .toList();
          _setRoutePolyline(points);
          setState(() => _isNavigating = true);
          _showRouteBanner(_RouteBannerKind.active);
          _fitBounds(points);
        } else {
          setState(() { _googlePolylines = {}; _isNavigating = false; });
        }
      }
    });

    // Lugares filtrados → reconstruir marcadores (solo GoogleMap; en desktop
    // los marcadores de flutter_map se derivan directo del provider en build)
    ref.listen<List<PlaceNode>>(filteredPlacesProvider, (_, next) {
      if (!_isDesktop) _rebuildMarkers(next);
    });

    final isDark = ref.watch(mapThemeProvider) == 'dark';

    // Posición fijada a mano ("Estoy Aquí" en un lugar, o QR escaneado):
    // antes esto vivía escondido dentro de NavigationService, sin ninguna
    // señal en la UI de que el GPS se había "congelado" ahí a propósito ni
    // una forma obvia de quitarlo. Ahora se ve como un aviso persistente
    // con botón para soltarlo (ver [_ManualPositionBanner] más abajo).
    final isManualPosition = ref.watch(
        navigationProvider.select((s) => s.isManualPosition));
    final manualPositionLabel = ref.watch(
        navigationProvider.select((s) => s.manualPositionLabel));

    // Grafo en línea (Firestore) de la sede actual — solo se suscribe
    // mientras el admin está en modo edición, para no gastar lecturas/
    // listeners de Firestore en usuarios normales que solo navegan.
    // Grafo en línea (Firestore) de la sede actual combinado con el grafo offline
    // para que el admin pueda ver y editar los puntos que vienen del JSON.
    final firestoreNodes = _isEditMode
        ? (ref.watch(nodesStreamProvider(_venue.id)).value ?? const <CampusNode>[])
        : const <CampusNode>[];
    final firestoreEdges = _isEditMode
        ? (ref.watch(edgesStreamProvider(_venue.id)).value ?? const <CampusEdge>[])
        : const <CampusEdge>[];

    final editNodesMap = <String, CampusNode>{};
    final editEdgesMap = <String, CampusEdge>{};

    if (_isEditMode) {
      final navService = ref.read(navigationServiceProvider);
      if (navService.graph != null) {
        for (final n in navService.graph!.nodes.values) {
          editNodesMap[n.id] = n;
        }
        for (final e in navService.graph!.edges) {
          editEdgesMap[e.docId] = e;
        }
      }
      for (final n in firestoreNodes) {
        editNodesMap[n.id] = n;
      }
      for (final e in firestoreEdges) {
        editEdgesMap[e.docId] = e;
      }
    }

    // Solo nodos de esta sede y dentro de la zona visible, con tope: ver
    // `_editVisibleRegion`.
    final region = _editVisibleRegion;
    final editNodes = editNodesMap.values
        .where((n) => n.zoneId.isEmpty || n.zoneId == _venue.id)
        .where((n) => region == null || region.contains(LatLng(n.lat, n.lng)))
        .take(_maxEditNodes)
        .toList();
    final editNodesById = {for (final n in editNodes) n.id: n};
    final editEdges = editEdgesMap.values
        .where((e) =>
            editNodesById.containsKey(e.from) &&
            editNodesById.containsKey(e.to))
        .take(_maxEditEdges)
        .toList();

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _buildFABs(),
      bottomNavigationBar: BottomNav(currentIndex: widget.openMap ? 3 : -1),
      body: Stack(
        children: [
          // ── Mapa (Google Maps en Android/iOS/Web, flutter_map en desktop) ──
          // El punto azul del usuario se mueve vía _userPosNotifier dentro de
          // este ValueListenableBuilder para que solo el mapa se redibuje en
          // cada frame de GPS — el resto de la pantalla (botones, banners)
          // vive fuera y no se ve afectado.
          RepaintBoundary(
            child: _isDesktop
                ? _buildDesktopMap(isDark, editNodes, editEdges, editNodesById)
                : ValueListenableBuilder<LatLng?>(
                    valueListenable: _userPosNotifier,
                    builder: (context, userPos, _) {
                      final markers = {
                        // En modo edición solo se muestran los puntos
                        // importantes (_googleMarkers): los puntos de ruta
                        // morados y sus líneas hacían que el mapa se trabara.
                        ..._googleMarkers,
                        if (userPos != null && _userIconCache != null)
                          Marker(
                            markerId: const MarkerId('user_location'),
                            position: userPos,
                            icon: _userIconCache!,
                            zIndexInt: 10,
                            anchor: const Offset(0.5, 0.5),
                          ),
                      };
                      final polylines = {
                        ..._googlePolylines,
                      };
                      return GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _mapInitialCenter,
                          zoom: _mapInitialZoom,
                        ),
                        onMapCreated: (controller) {
                          _googleMapController = controller;
                          _initializeGpsAndCenter();
                          _rebuildMarkers(ref.read(filteredPlacesProvider));
                        },
                        onTap: _handleMapBackgroundTap,
                        onCameraMove: (pos) {
                          _currentZoom = pos.zoom;
                          if (_isTrackingActive && !_isProgrammaticCameraMove) {
                            setState(() => _isTrackingActive = false);
                          }
                        },
                        onCameraIdle: () async {
                          _isProgrammaticCameraMove = false;
                          if (!_isEditMode) return;
                          final region =
                              await _googleMapController?.getVisibleRegion();
                          if (region != null && mounted) {
                            setState(() => _editVisibleRegion = region);
                          }
                        },
                        markers: markers,
                        polylines: polylines,
                        style: _mapType == MapType.normal
                            ? _currentMapStyle
                            : null,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: false,
                        rotateGesturesEnabled: false,
                        // En modo abierto la cámara no se encierra en la caja
                        // de ninguna sede, y se permite alejar más para poder
                        // ver las 9 sedes de Colima de un vistazo.
                        cameraTargetBounds: widget.openMap
                            ? CameraTargetBounds.unbounded
                            : CameraTargetBounds(_cameraBounds),
                        minMaxZoomPreference: widget.openMap
                            ? const MinMaxZoomPreference(9, 20)
                            : const MinMaxZoomPreference(13, 20),
                        mapType: _mapType,
                      );
                    },
                  ),
          ),
          // ── Botón para volver a Inicio ─────────────────────────
          Positioned(
            top: 0, left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildRoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Volver a Inicio',
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, AppRoutes.home),
                ),
              ),
            ),
          ),
          // ── Botones superiores derechos: Satélite + Tema ───────
          Positioned(
            top: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMapTypeToggle(),
                    const SizedBox(width: 8),
                    _buildThemeToggle(isDark),
                  ],
                ),
              ),
            ),
          ),
          // ── Banner de modo edición (admin, Fase 2) ─────────────
          if (_isEditMode)
            Positioned(
              top: 0, left: 16, right: 16,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 76),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_location_alt_rounded,
                            color: cs.onPrimary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _editConnectFromId != null
                                ? 'Toca el segundo punto para conectar'
                                : _editMovingId != null
                                    ? 'Toca el mapa donde quieres mover el punto'
                                    : 'MODO EDICIÓN — toca el mapa para agregar un punto',
                            style: TextStyle(
                                color: cs.onPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5),
                          ),
                        ),
                        if (_editConnectFromId != null || _editMovingId != null)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() {
                              _editConnectFromId = null;
                              _editConnectFromPos = null;
                              _editMovingId = null;
                            }),
                            child: Icon(Icons.close_rounded,
                                color: cs.onPrimary, size: 20),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // ── Avisos superiores: posición manual + estado de ruta ────
          // Van en una sola columna (no dos Positioned independientes) para
          // que si algún día coinciden los dos a la vez, se acomoden uno
          // debajo del otro en vez de encimarse.
          if (isManualPosition || _routeBanner != null)
            Positioned(
              top: 0, left: 16, right: 16,
              child: SafeArea(
                child: Padding(
                  // El botón de volver y el de tema (arriba, top:0 + padding
                  // 16 + ~48 de alto) terminan alrededor de los 64px — este
                  // cuadro debe empezar claramente después de eso, no a los
                  // 60px de antes (prácticamente encimados).
                  padding: const EdgeInsets.only(top: 84),
                  child: Column(
                    children: [
                      if (isManualPosition) ...[
                        _ManualPositionBanner(
                          label: manualPositionLabel,
                          onClear: () {
                            final notifier =
                                ref.read(navigationProvider.notifier);
                            notifier.clearManualPosition();
                            // Sin esto, la posición real no se actualizaba
                            // hasta la SIGUIENTE lectura de GPS — y si la
                            // persona está parada quieta (`distanceFilter:
                            // 2` no dispara nada hasta moverse 2m), eso
                            // podía tardar o no llegar nunca, dejando la
                            // sensación de que "Quitar" no hizo nada. Se
                            // fuerza el resync YA con la última posición de
                            // GPS que ya se tenía, en vez de esperar.
                            final lastKnown =
                                _displayPosition ?? _currentPosition;
                            if (lastKnown != null) {
                              notifier.setPositionByCoordinates(
                                lastKnown.latitude,
                                lastKnown.longitude,
                              );
                            }
                            // Igual que el botón de centrar ubicación:
                            // volver a seguir el GPS de inmediato en vez de
                            // esperar a que alguien toque algo más.
                            setState(() => _isTrackingActive = true);
                          },
                        ),
                        if (_routeBanner != null)
                          const SizedBox(height: 8),
                      ],
                      if (_routeBanner != null)
                        _RouteStatusBanner(
                          kind: _routeBanner!,
                          label: _routeBannerLabel,
                          onCancel: () {
                            ref
                                .read(navigationProvider.notifier)
                                .cancelNavigation();
                            setState(() {
                              _isNavigating = false;
                              _googlePolylines = {};
                              _destinationLatLng = null;
                              _isTrackingActive = false;
                              _routeBanner = null;
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  Mapa alterno para desktop (flutter_map + tiles OSM cacheados)
  // ──────────────────────────────────────────────────────────

  Widget _buildDesktopMap(
    bool isDark,
    List<CampusNode> editNodes,
    List<CampusEdge> editEdges,
    Map<String, CampusNode> editNodesById,
  ) {
    final places = ref.watch(filteredPlacesProvider);
    final cs = Theme.of(context).colorScheme;

    final tileLayer = fm.TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'mx.edu.tecnm.colima.navia',
      maxZoom: 19,
      errorTileCallback: (tile, error, stack) {
        debugPrint('MapScreen (desktop): error de tile → $error');
      },
    );

    return fm.FlutterMap(
      mapController: _flutterMapController,
      options: fm.MapOptions(
        initialCenter: _toLL(_mapInitialCenter),
        initialZoom: _mapInitialZoom,
        minZoom: 13,
        maxZoom: 20,
        cameraConstraint: fm.CameraConstraint.contain(
          bounds: fm.LatLngBounds(
            _toLL(LatLng(_cameraBounds.southwest.latitude,
                _cameraBounds.southwest.longitude)),
            _toLL(LatLng(_cameraBounds.northeast.latitude,
                _cameraBounds.northeast.longitude)),
          ),
        ),
        onMapReady: () => _initializeGpsAndCenter(),
        onTap: (tapPosition, point) => _handleMapBackgroundTap(
            LatLng(point.latitude, point.longitude)),
        onPositionChanged: (position, hasGesture) {
          if (position.zoom != null) _currentZoom = position.zoom!;
          if (hasGesture) {
            if (_isTrackingActive) {
              setState(() => _isTrackingActive = false);
            }
          }
        },
      ),
      children: [
        isDark
            ? ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  -1, 0, 0, 0, 255, //
                  0, -1, 0, 0, 255, //
                  0, 0, -1, 0, 255, //
                  0, 0, 0, 1, 0, //
                ]),
                child: tileLayer,
              )
            : tileLayer,
        fm.PolylineLayer(
          polylines: [
            ..._googlePolylines.map((p) => fm.Polyline(
                  points: p.points.map(_toLL).toList(),
                  color: p.color,
                  strokeWidth: p.width.toDouble(),
                )),
            if (_isEditMode)
              for (final edge in editEdges)
                if (editNodesById[edge.from] != null &&
                    editNodesById[edge.to] != null)
                  fm.Polyline(
                    points: [
                      _toLL(LatLng(editNodesById[edge.from]!.lat,
                          editNodesById[edge.from]!.lng)),
                      _toLL(LatLng(editNodesById[edge.to]!.lat,
                          editNodesById[edge.to]!.lng)),
                    ],
                    color: cs.primary,
                    strokeWidth: 3,
                  ),
          ],
        ),
        fm.MarkerLayer(
          markers: [
            for (final place in places)
              fm.Marker(
                point: ll.LatLng(place.latitude, place.longitude),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () {
                    if (_isEditMode || _editConnectFromId != null) {
                      _handleEditTapOnPoint(
                        id: place.id,
                        name: place.name,
                        lat: place.latitude,
                        lng: place.longitude,
                        hasPlace: true,
                      );
                    } else {
                      ref.read(selectedPlaceProvider.notifier).state = place;
                    }
                  },
                  child: _DesktopPoiIcon(place: place),
                ),
              ),
            if (_isEditMode)
              for (final node in editNodes)
                if (node.type == NodeType.corridor)
                  fm.Marker(
                    point: ll.LatLng(node.lat, node.lng),
                    width: 22,
                    height: 22,
                    child: GestureDetector(
                      onTap: () => _handleEditTapOnPoint(
                        id: node.id,
                        name: node.name,
                        lat: node.lat,
                        lng: node.lng,
                        hasPlace: false,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
          ],
        ),
        // Capa aparte y reactiva solo para el punto del usuario: así el
        // marcador se puede mover en cada frame de GPS sin reconstruir el
        // tile layer ni los marcadores de POIs (que no cambian con el GPS).
        ValueListenableBuilder<LatLng?>(
          valueListenable: _userPosNotifier,
          builder: (context, userPos, _) {
            if (userPos == null) return const SizedBox.shrink();
            return fm.MarkerLayer(
              markers: [
                fm.Marker(
                  point: _toLL(userPos),
                  width: 30,
                  height: 30,
                  child: const _DesktopUserIcon(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Icono de POI para el mapa alterno de escritorio (flutter_map). Replica el
/// estilo de los marcadores de GoogleMap sin depender de BitmapDescriptor/
/// Canvas, que solo tiene sentido junto al plugin nativo de Android/iOS/Web.
class _DesktopPoiIcon extends StatelessWidget {
  final PlaceNode place;
  const _DesktopPoiIcon({required this.place});

  @override
  Widget build(BuildContext context) {
    final category = PlaceVisuals.categoryOf(place);
    return Container(
      decoration: BoxDecoration(
        color: PlaceVisuals.colorFor(category),
        shape: BoxShape.circle,
        border: const Border.fromBorderSide(
            BorderSide(color: Colors.white, width: 2)),
      ),
      alignment: Alignment.center,
      child: Icon(
        PlaceVisuals.iconFor(category),
        color: Colors.white,
        size: 18,
      ),
    );
  }
}

/// Punto de ubicación del usuario en el mapa alterno de escritorio.
class _DesktopUserIcon extends StatelessWidget {
  const _DesktopUserIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppMapColors.userLocation,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 3)),
      ),
    );
  }
}

/// Tipos de punto que el editor de administrador puede crear. Cada uno se
/// traduce en un [CampusNode] (para que el punto sea parte del grafo
/// caminable y las rutas puedan pasar por/hacia él) y, salvo "Corredor", en
/// un [PlaceNode] con el mismo id (para que además aparezca como pin
/// tocable en el mapa) — ver [_MapScreenState._createUnifiedPoint].
class _EditPointTypeInfo {
  final String label;
  final IconData icon;

  /// `null` = punto de solo-ruta (corredor/intersección), sin pin visible.
  final String? placeType;
  final NodeType nodeType;

  const _EditPointTypeInfo(this.label, this.icon, this.placeType, this.nodeType);
}

const List<_EditPointTypeInfo> _editPointTypes = [
  _EditPointTypeInfo('Edificio', Icons.apartment_rounded, 'Edificio', NodeType.building),
  _EditPointTypeInfo('Cancha / Área deportiva', Icons.sports_soccer_rounded, 'Cancha', NodeType.area),
  // Salud y logística — lo más consultado en un evento masivo, van primero.
  _EditPointTypeInfo('Primeros auxilios', Icons.medical_services_rounded, 'Primeros Auxilios', NodeType.service),
  _EditPointTypeInfo('Hidratación', Icons.water_drop_rounded, 'Hidratación', NodeType.service),
  _EditPointTypeInfo('Baños', Icons.wc_rounded, 'Baños', NodeType.service),
  _EditPointTypeInfo('Vestidores', Icons.checkroom_rounded, 'Vestidores', NodeType.service),
  _EditPointTypeInfo('Cafetería / Comida', Icons.restaurant_rounded, 'Cafetería', NodeType.service),
  _EditPointTypeInfo('Podio / Premiación', Icons.emoji_events_rounded, 'Podio', NodeType.area),
  _EditPointTypeInfo('Estacionamiento', Icons.local_parking_rounded, 'Estacionamiento', NodeType.service),
  _EditPointTypeInfo('Transporte / Punto de abordaje', Icons.directions_bus_rounded, 'Transporte', NodeType.service),
  _EditPointTypeInfo('Entrada / Acceso', Icons.meeting_room_rounded, 'Entrada', NodeType.entrance),
  _EditPointTypeInfo('Registro / Acreditación', Icons.how_to_reg_rounded, 'Registro', NodeType.service),
  _EditPointTypeInfo('Seguridad', Icons.security_rounded, 'Seguridad', NodeType.service),
  _EditPointTypeInfo('Información', Icons.info_rounded, 'Información', NodeType.service),
  _EditPointTypeInfo('Corredor / Intersección (solo ruta, sin pin visible)',
      Icons.timeline_rounded, null, NodeType.corridor),
];
