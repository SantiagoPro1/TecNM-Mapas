# Construye y optimiza el grafo caminable de las 9 sedes de NAVIA.
#
# Elimina atajos entre puntos de interés (POIs) que obligaban a "ir a un punto
# para ir a otro punto" y mapea andadores peatonales directos dentro de cada
# sede ("ir al punto al punto").
#
# Genera assets/maps/venues_bundle.json listo para Dijkstra offline.
import json
import math
import os
import heapq

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLE = os.path.join(RAIZ, 'assets', 'maps', 'venues_bundle.json')

def metros(lat1, lon1, lat2, lon2):
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))

def optimize_venue(vid, vdata):
    places = {p['id']: p for p in vdata.get('places', [])}
    nodes = {n['id']: dict(n) for n in vdata.get('nodes', [])}
    edges = [dict(e) for e in vdata.get('edges', [])]
    pids = list(places.keys())

    if not pids:
        return list(nodes.values()), edges, 'sin POIs'

    # Nodos de andador existentes (de OSM)
    corridor_nodes = [nid for nid, n in nodes.items() if n.get('type') == 'corridor']

    # 1. Conectar instalaciones al andador peatonal interno directo.
    # En vez de saltar a través de otras canchas (POI-to-POI), se crean andadores
    # peatonales intermedios entre instalaciones próximas (<= 220 m).
    andador_nodes = {}
    andador_idx = 0
    new_edges = []

    for i in range(len(pids)):
        for j in range(i + 1, len(pids)):
            id1, id2 = pids[i], pids[j]
            p1, p2 = places[id1], places[id2]
            d = metros(p1['latitude'], p1['longitude'], p2['latitude'], p2['longitude'])
            
            # Conexión directa por andador peatonal si caen en la misma zona útil
            if d <= 220.0:
                and_id = f"{vid}_and_{andador_idx}"
                andador_idx += 1
                mid_lat = round((p1['latitude'] + p2['latitude']) / 2.0, 7)
                mid_lng = round((p1['longitude'] + p2['longitude']) / 2.0, 7)
                half_d = round(d / 2.0, 2)
                
                and_node = {
                    'id': and_id,
                    'name': '',
                    'aliases': [],
                    'type': 'corridor',
                    'lat': mid_lat,
                    'lng': mid_lng,
                    'floor': 0,
                    'accessible': True,
                    'description': '',
                    'zoneId': vid
                }
                nodes[and_id] = and_node
                andador_nodes[and_id] = and_node
                
                new_edges.append({'from': id1, 'to': and_id, 'distance': half_d, 'accessible': True, 'direction': '', 'zoneId': vid})
                new_edges.append({'from': id2, 'to': and_id, 'distance': half_d, 'accessible': True, 'direction': '', 'zoneId': vid})

    # 2. Conectar andadores cercanos de forma dispersa (k-nearest vecinos <= 75 m, máx 4)
    # Crea una malla peatonal navegable sin explosión de aristas cuadrática
    and_list = list(andador_nodes.keys())
    for i, aid1 in enumerate(and_list):
        n1 = andador_nodes[aid1]
        vecinos = []
        for j, aid2 in enumerate(and_list):
            if i >= j: continue
            n2 = andador_nodes[aid2]
            d = metros(n1['lat'], n1['lng'], n2['lat'], n2['lng'])
            if d <= 75.0:
                vecinos.append((d, aid2))
        vecinos.sort(key=lambda x: x[0])
        for d, aid2 in vecinos[:4]:
            new_edges.append({'from': aid1, 'to': aid2, 'distance': round(d, 2), 'accessible': True, 'direction': '', 'zoneId': vid})

    # 3. Conectar andadores a los accesos y corredores existentes (de OSM)
    for aid, an in andador_nodes.items():
        c_dists = []
        for cid in corridor_nodes:
            cn = nodes[cid]
            d = metros(an['lat'], an['lng'], cn['lat'], cn['lng'])
            if d <= 50.0:
                c_dists.append((d, cid))
        c_dists.sort(key=lambda x: x[0])
        for d, cid in c_dists[:2]:
            new_edges.append({'from': aid, 'to': cid, 'distance': round(d, 2), 'accessible': True, 'direction': '', 'zoneId': vid})

    # 4. Eliminar estrictamente toda arista directa POI <-> POI
    # Ninguna ruta puede cruzar por en medio de otra cancha/edificio
    all_edges = edges + new_edges
    filtered_edges = []
    seen = set()
    for e in all_edges:
        u, v = e['from'], e['to']
        if u in places and v in places:
            continue  # Cero enlaces POI-POI
        p = (min(u, v), max(u, v))
        if p not in seen:
            seen.add(p)
            filtered_edges.append(e)

    # 5. Validación completa con Dijkstra
    adj = {n: [] for n in nodes}
    for e in filtered_edges:
        if e['from'] in adj and e['to'] in adj:
            adj[e['from']].append((e['to'], e['distance']))
            adj[e['to']].append((e['from'], e['distance']))

    total = len(pids) * (len(pids) - 1) // 2
    hops = 0
    disconnected = 0
    worst_ratio = 1.0

    for i in range(len(pids)):
        for j in range(i + 1, len(pids)):
            id1, id2 = pids[i], pids[j]
            straight = metros(places[id1]['latitude'], places[id1]['longitude'], places[id2]['latitude'], places[id2]['longitude'])
            
            q = [(0.0, id1, [id1], 0.0)]
            visited = {}
            found = False
            while q:
                prio, curr, path, true_d = heapq.heappop(q)
                if curr in visited and visited[curr] <= prio: continue
                visited[curr] = prio
                if curr == id2:
                    found = True
                    inter_places = [nid for nid in path[1:-1] if nid in places]
                    if inter_places: hops += 1
                    ratio = true_d / max(straight, 1.0)
                    if ratio > worst_ratio:
                        worst_ratio = ratio
                    break
                for nxt, weight in adj[curr]:
                    penalty = 1000.0 if (nxt in places and nxt != id2) else 0.0
                    new_prio = prio + weight + penalty
                    if nxt not in visited or visited[nxt] > new_prio:
                        heapq.heappush(q, (new_prio, nxt, path + [nxt], true_d + weight))
            if not found:
                disconnected += 1

    nota = f"pares={total} hops={hops} disc={disconnected} peor_ratio={worst_ratio:.2f}"
    return list(nodes.values()), filtered_edges, nota


def main():
    bundle = json.load(open(BUNDLE, encoding='utf-8'))
    total_n = total_e = 0
    print("=== OPTIMIZANDO RUTAS Y ANDADORES DE LAS 9 SEDES ===")
    for vid, cols in bundle['venues'].items():
        vnodes, vedges, nota = optimize_venue(vid, cols)
        cols['nodes'] = vnodes
        cols['edges'] = vedges
        total_n += len(vnodes)
        total_e += len(vedges)
        print(f"%-18s nodos=%4d aristas=%5d  %s" % (vid, len(vnodes), len(vedges), nota))

    bundle['dataVersion'] = 1000014
    with open(BUNDLE, 'w', encoding='utf-8') as f:
        json.dump(bundle, f, ensure_ascii=False, separators=(',', ':'))
    print(f"\nTOTAL nodos={total_n} aristas={total_e} dataVersion={bundle['dataVersion']} {os.path.getsize(BUNDLE)/1024:.0f} KB")


if __name__ == '__main__':
    main()
