# Construye el grafo caminable de las 9 sedes a partir de las trazas reales
# de OpenStreetMap, y lo inyecta en assets/maps/venues_bundle.json.
#
# POR QUÉ
#
# Sin grafo, cada "Trazar Ruta" tiene que preguntarle a la API de Google
# (de pago). Con grafo, la app usa su propio Dijkstra: gratis, instantáneo y
# sin señal. Las sedes del evento tenían 0 aristas, así que este script las
# construye de una vez.
#
# QUÉ HACE
#
#  1. Recorta las vías de OSM a la zona útil de cada sede (las canchas + un
#     margen), porque Overpass devuelve la vía completa aunque solo un tramo
#     toque la caja — sin recortar, el grafo del Tec incluiría media ciudad.
#  2. Simplifica cada vía (Douglas-Peucker, 3 m) para no arrastrar miles de
#     puntos que no cambian la ruta pero sí el tamaño del APK.
#  3. Une los puntos que coinciden (~2 m) para que las vías que se cruzan
#     compartan nodo: sin esto el grafo queda en pedazos inconexos y Dijkstra
#     no encuentra camino.
#  4. Se queda con el componente conectado más grande y descarta los islotes.
#  5. Engancha cada punto de interés (cancha, alberca...) al nodo de camino
#     más cercano, usando el MISMO id que el POI para que la app pueda pedir
#     una ruta hacia él directamente.
#
# Los escalones (`highway=steps`) quedan marcados accessible=false, para que
# la ruta accesible pueda evitarlos.
import json
import math
import os
import re
from collections import defaultdict

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLE = os.path.join(RAIZ, 'assets', 'maps', 'venues_bundle.json')
REGISTRO = os.path.join(RAIZ, 'lib', 'core', 'constants', 'venue_registry.dart')

MARGEN_M = 250.0      # cuánto se extiende la zona útil más allá de las canchas
TOLERANCIA_M = 3.0    # simplificación de geometría
FUSION_M = 2.0        # dos puntos a menos de esto son el mismo nodo
MAX_CONECTOR_M = 250.0  # si el POI queda más lejos que esto, algo anda mal


def metros(lat1, lon1, lat2, lon2):
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def dist_punto_segmento(p, a, b):
    """Distancia perpendicular en metros, en un plano local (basta a esta escala)."""
    esc = math.cos(math.radians(p[0]))
    px, py = p[1] * esc, p[0]
    ax, ay = a[1] * esc, a[0]
    bx, by = b[1] * esc, b[0]
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return metros(p[0], p[1], a[0], a[1])
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    cx, cy = ax + t * dx, ay + t * dy
    return metros(p[0], p[1], cy, cx / esc)


def simplificar(pts, tol):
    """Douglas-Peucker sobre una polilínea de (lat, lon)."""
    if len(pts) < 3:
        return pts
    dmax, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        d = dist_punto_segmento(pts[i], pts[0], pts[-1])
        if d > dmax:
            dmax, idx = d, i
    if dmax > tol:
        izq = simplificar(pts[:idx + 1], tol)
        der = simplificar(pts[idx:], tol)
        return izq[:-1] + der
    return [pts[0], pts[-1]]


def cargar_registro():
    txt = open(REGISTRO, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r"id: '(\w+)',(.*?)\);", txt, re.S):
        cuerpo = m.group(2)
        d = {}
        for k in ('centerLat', 'centerLng'):
            mm = re.search(k + r':\s*(-?[\d.]+)', cuerpo)
            if mm:
                d[k] = float(mm.group(1))
        if d:
            out[m.group(1)] = d
    return out


def construir(vid, places):
    ruta_osm = os.path.join(RAIZ, 'scripts', 'osm_%s.json' % vid)
    if not os.path.exists(ruta_osm):
        return [], [], 'sin datos de OSM'
    ways = json.load(open(ruta_osm, encoding='utf-8'))

    # Zona útil: caja que cubre las canchas + margen.
    lats = [p['latitude'] for p in places]
    lons = [p['longitude'] for p in places]
    clat = (min(lats) + max(lats)) / 2
    dlat = MARGEN_M / 111320.0
    dlon = MARGEN_M / (111320.0 * math.cos(math.radians(clat)))
    smin, smax = min(lats) - dlat, max(lats) + dlat
    wmin, wmax = min(lons) - dlon, max(lons) + dlon

    def dentro(pt):
        return smin <= pt[0] <= smax and wmin <= pt[1] <= wmax

    # ── nodos por fusión espacial ──
    celda = FUSION_M / 111320.0
    indice = {}
    nodos = []  # (lat, lon)

    def id_nodo(pt):
        cx, cy = int(pt[0] / celda), int(pt[1] / celda)
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                k = indice.get((cx + ox, cy + oy))
                if k is not None:
                    n = nodos[k]
                    if metros(pt[0], pt[1], n[0], n[1]) <= FUSION_M:
                        return k
        nodos.append(pt)
        indice[(cx, cy)] = len(nodos) - 1
        return len(nodos) - 1

    # Los cruces son los puntos que aparecen en más de una vía. Hay que
    # partir ahí antes de simplificar: Douglas-Peucker borra los puntos
    # intermedios de un tramo recto, y si el cruce es uno de ellos, la calle
    # lateral queda desconectada. Ese era el motivo de que el grafo saliera
    # hecho pedazos (52 nodos de 9,021 puntos en TecNM Colima).
    apariciones = defaultdict(int)
    for w in ways:
        vistos = set()
        for g in w.get('geometry', []):
            k = (round(g['lat'], 7), round(g['lon'], 7))
            if k not in vistos:
                vistos.add(k)
                apariciones[k] += 1
    cruces = {k for k, n in apariciones.items() if n > 1}

    aristas = {}
    for w in ways:
        geo = [(g['lat'], g['lon']) for g in w.get('geometry', [])]
        if len(geo) < 2:
            continue
        escalones = w.get('tags', {}).get('highway') == 'steps'
        # Corta la vía en los tramos que caen dentro de la zona útil.
        tramo = []
        for pt in geo:
            if dentro(pt):
                tramo.append(pt)
                # Al llegar a un cruce se cierra el tramo y se abre otro que
                # empieza en ese mismo punto, para que el cruce sobreviva a la
                # simplificación y las dos vías compartan nodo.
                if (round(pt[0], 7), round(pt[1], 7)) in cruces and len(tramo) >= 2:
                    agregar_tramo(tramo, escalones, id_nodo, nodos, aristas)
                    tramo = [pt]
            else:
                if len(tramo) >= 2:
                    agregar_tramo(tramo, escalones, id_nodo, nodos, aristas)
                tramo = []
        if len(tramo) >= 2:
            agregar_tramo(tramo, escalones, id_nodo, nodos, aristas)

    if not aristas:
        return [], [], 'sin caminos dentro de la zona'

    # ── componente conectado más grande ──
    ady = defaultdict(set)
    for a, b in aristas:
        ady[a].add(b)
        ady[b].add(a)
    visto, mejor = set(), []
    for inicio in ady:
        if inicio in visto:
            continue
        pila, comp = [inicio], []
        visto.add(inicio)
        while pila:
            n = pila.pop()
            comp.append(n)
            for v in ady[n]:
                if v not in visto:
                    visto.add(v)
                    pila.append(v)
        if len(comp) > len(mejor):
            mejor = comp
    principal = set(mejor)

    # ── salida: nodos de camino ──
    fuera = {}
    out_nodes, out_edges = [], []
    for k in principal:
        nid = '%s_w%d' % (vid, k)
        fuera[k] = nid
        lat, lon = nodos[k]
        out_nodes.append({
            'id': nid, 'name': '', 'aliases': [], 'type': 'corridor',
            'lat': round(lat, 7), 'lng': round(lon, 7),
            'floor': 0, 'accessible': True, 'description': '',
        })
    for (a, b), acc in aristas.items():
        if a in principal and b in principal:
            d = metros(*nodos[a], *nodos[b])
            out_edges.append({
                'from': fuera[a], 'to': fuera[b],
                'distance': round(d, 2), 'accessible': acc, 'direction': '',
            })

    # ── engancha cada POI a la red ──
    #
    # A los TRES nodos de camino más cercanos, no solo al primero. Con un solo
    # enganche, si ese nodo cae en un andador que va en dirección contraria, la
    # ruta se obliga a rodear: se midieron desvíos de hasta 17 veces la
    # distancia en línea recta entre dos canchas vecinas.
    CONEXIONES_POR_POI = 3

    huerfanos = []
    lejanos = []
    pos_poi = {}
    for p in places:
        cercanos = sorted(
            ((metros(p['latitude'], p['longitude'], *nodos[k]), k) for k in principal),
            key=lambda x: x[0],
        )[:CONEXIONES_POR_POI]
        if not cercanos:
            huerfanos.append((p['id'], -1))
            continue
        if cercanos[0][0] > MAX_CONECTOR_M:
            lejanos.append((p['id'], round(cercanos[0][0])))
        out_nodes.append({
            'id': p['id'], 'name': p.get('name', ''), 'aliases': [],
            'type': 'building', 'lat': p['latitude'], 'lng': p['longitude'],
            'floor': 0, 'accessible': True, 'description': '',
        })
        pos_poi[p['id']] = (p['latitude'], p['longitude'])
        for d, k in cercanos:
            out_edges.append({
                'from': p['id'], 'to': fuera[k],
                'distance': round(d, 2), 'accessible': True, 'direction': '',
            })

    # Canchas contiguas: dos puntos a menos de 80 m dentro de una unidad
    # deportiva están separados por pasto o pavimento abierto, no por un muro.
    # Sin esta arista, ir de una cancha a la de al lado obligaba a salir al
    # andador y volver.
    VECINDAD_M = 80.0
    ids = list(pos_poi)
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            d = metros(*pos_poi[ids[i]], *pos_poi[ids[j]])
            if d <= VECINDAD_M:
                out_edges.append({
                    'from': ids[i], 'to': ids[j],
                    'distance': round(d, 2), 'accessible': True, 'direction': '',
                })

    nota = 'ok'
    if lejanos:
        nota = 'conector largo (recto): %s' % lejanos
    if huerfanos:
        nota += ' | SIN ENGANCHAR: %s' % huerfanos
    return out_nodes, out_edges, nota


def agregar_tramo(tramo, escalones, id_nodo, nodos, aristas):
    simple = simplificar(tramo, TOLERANCIA_M)
    ids = [id_nodo(pt) for pt in simple]
    for a, b in zip(ids, ids[1:]):
        if a == b:
            continue
        clave = (min(a, b), max(a, b))
        # Si un mismo tramo aparece como escalera y como andador, gana el
        # accesible: es el mismo recorrido documentado dos veces.
        aristas[clave] = aristas.get(clave, not escalones) or (not escalones)


def main():
    bundle = json.load(open(BUNDLE, encoding='utf-8'))
    total_n = total_e = 0
    for vid, cols in bundle['venues'].items():
        places = cols.get('places', [])
        if not places:
            print('%-18s sin POIs, se omite' % vid)
            continue
        nodos, aristas, nota = construir(vid, places)
        cols['nodes'] = nodos
        cols['edges'] = aristas
        total_n += len(nodos)
        total_e += len(aristas)
        print('%-18s nodos=%4d aristas=%4d  %s' % (vid, len(nodos), len(aristas), nota))

    # Versión fija y explícita: si se recalcula el grafo, se sube a mano aquí
    # y en el documento `app_meta/venue_data` de Firestore. Autoincrementarla
    # haría que cada corrida del script invalidara el paquete sin motivo.
    bundle['dataVersion'] = 2
    with open(BUNDLE, 'w', encoding='utf-8') as f:
        json.dump(bundle, f, ensure_ascii=False, separators=(',', ':'))
    print('\nTOTAL nodos=%d aristas=%d  dataVersion=%d  %.0f KB'
          % (total_n, total_e, bundle['dataVersion'],
             os.path.getsize(BUNDLE) / 1024))


if __name__ == '__main__':
    main()
