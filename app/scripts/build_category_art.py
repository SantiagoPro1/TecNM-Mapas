# Genera una ilustración por categoría de punto, para encabezar la ficha de
# cada lugar del mapa.
#
# POR QUÉ EXISTEN
#
# La ficha de un punto se veía vacía: solo un ícono chico. Las fotos reales de
# estas canchas no existen con licencia libre (se revisó Wikimedia Commons por
# coordenadas y por nombre, y Openverse: cero resultados útiles), y las de
# Google no se pueden guardar ni redistribuir.
#
# La salida es dibujarlas: cada categoría lleva el trazado real de su cancha
# —el diamante del béisbol, los carriles de la alberca, el óvalo de la pista—
# sobre el color plano que ya usa esa categoría en el mapa. Se reconoce de un
# vistazo, pesa unos pocos KB, funciona sin señal y es material propio.
#
# Las fotos reales, cuando lleguen, ganan sobre estas ilustraciones: ver
# `PlacePhoto.assetParaPunto` en lib/presentation/screens/map/place_visuals.dart.
import math
import os

from PIL import Image, ImageDraw

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA = os.path.join(RAIZ, 'assets', 'categories')

W, H = 1200, 600

# Mismos colores que AppMapColors, para que la ficha combine con su pin.
DEPORTE = (47, 107, 68)
COMIDA = (178, 107, 0)
SERVICIO = (0, 46, 109)
MEDICO = (163, 39, 31)
TRANSPORTE = (74, 88, 102)

LINEA = (255, 255, 255, 70)   # trazado de cancha
FUERTE = (255, 255, 255, 115)  # elemento principal


def lienzo(color):
    im = Image.new('RGB', (W, H), color)
    capa = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    return im, capa, ImageDraw.Draw(capa)


def guardar(nombre, im, capa):
    im = Image.alpha_composite(im.convert('RGBA'), capa).convert('RGB')
    im.save(os.path.join(SALIDA, nombre + '.png'), optimize=True)
    return nombre


def marco(d, m=70, gr=5, color=LINEA):
    d.rectangle([m, m, W - m, H - m], outline=color, width=gr)


# ─────────────────────── una función por categoría ───────────────────────

def swimming():
    im, capa, d = lienzo(DEPORTE)
    marco(d)
    # Carriles de alberca.
    for i in range(1, 6):
        y = 70 + i * (H - 140) / 6
        d.line([90, y, W - 90, y], fill=LINEA, width=4)
    # Flotadores del carril central.
    y = H / 2
    for x in range(120, W - 100, 46):
        d.ellipse([x, y - 13, x + 26, y + 13], fill=FUERTE)
    return guardar('swimming', im, capa)


def basketball():
    im, capa, d = lienzo(DEPORTE)
    marco(d)
    d.line([W / 2, 70, W / 2, H - 70], fill=LINEA, width=5)
    d.ellipse([W / 2 - 85, H / 2 - 85, W / 2 + 85, H / 2 + 85],
              outline=FUERTE, width=6)
    for lado in (0, 1):
        # Arco de tres puntos: es lo que distingue una cancha de básquetbol
        # de una de fútbol de un vistazo (sin él, las dos ilustraciones se
        # veían casi iguales).
        cx = 70 if lado == 0 else W - 70
        r = 250
        d.arc([cx - r, H / 2 - r, cx + r, H / 2 + r],
              -72 if lado == 0 else 108, 72 if lado == 0 else 252,
              fill=FUERTE, width=6)
        # Zona de tiro libre y su círculo.
        x0 = 70 if lado == 0 else W - 70 - 150
        d.rectangle([x0, H / 2 - 105, x0 + 150, H / 2 + 105],
                    outline=LINEA, width=5)
        fx = x0 + 150 if lado == 0 else x0
        d.ellipse([fx - 55, H / 2 - 55, fx + 55, H / 2 + 55],
                  outline=LINEA, width=5)
        # Aro.
        ax = 88 if lado == 0 else W - 88
        d.ellipse([ax - 16, H / 2 - 16, ax + 16, H / 2 + 16], fill=FUERTE)
    return guardar('basketball', im, capa)


def _cancha_futbol(nombre, penal=170):
    im, capa, d = lienzo(DEPORTE)
    marco(d)
    d.line([W / 2, 70, W / 2, H - 70], fill=LINEA, width=5)
    d.ellipse([W / 2 - 78, H / 2 - 78, W / 2 + 78, H / 2 + 78],
              outline=FUERTE, width=6)
    for lado in (0, 1):
        x0 = 70 if lado == 0 else W - 70 - penal
        d.rectangle([x0, H / 2 - 140, x0 + penal, H / 2 + 140],
                    outline=LINEA, width=5)
        x1 = 70 if lado == 0 else W - 70 - penal * 0.45
        d.rectangle([x1, H / 2 - 70, x1 + penal * 0.45, H / 2 + 70],
                    outline=LINEA, width=4)
    return guardar(nombre, im, capa)


def football():
    return _cancha_futbol('football')


def soccerSmall():
    return _cancha_futbol('soccerSmall', penal=110)


def baseball():
    im, capa, d = lienzo(DEPORTE)
    hx, hy = W / 2, H - 110          # home
    lado = 300
    # Diamante.
    pts = [(hx, hy), (hx + lado * 0.7, hy - lado * 0.55),
           (hx, hy - lado * 1.1), (hx - lado * 0.7, hy - lado * 0.55)]
    d.line(pts + [pts[0]], fill=FUERTE, width=6)
    # Líneas de foul.
    d.line([hx, hy, hx + 560, hy - 440], fill=LINEA, width=5)
    d.line([hx, hy, hx - 560, hy - 440], fill=LINEA, width=5)
    # Montículo y bases.
    d.ellipse([hx - 26, hy - lado * 0.62, hx + 26, hy - lado * 0.52],
              fill=FUERTE)
    for x, y in pts:
        d.rectangle([x - 13, y - 13, x + 13, y + 13], fill=FUERTE)
    return guardar('baseball', im, capa)


def volleyball():
    im, capa, d = lienzo(DEPORTE)
    marco(d, m=110)
    # Red.
    d.line([W / 2, 80, W / 2, H - 80], fill=FUERTE, width=7)
    for y in range(95, H - 80, 26):
        d.line([W / 2 - 30, y, W / 2 + 30, y], fill=LINEA, width=3)
    # Líneas de ataque.
    for x in (W / 2 - 150, W / 2 + 150):
        d.line([x, 110, x, H - 110], fill=LINEA, width=4)
    return guardar('volleyball', im, capa)


def tennis():
    im, capa, d = lienzo(DEPORTE)
    marco(d, m=90)
    d.line([W / 2, 70, W / 2, H - 70], fill=FUERTE, width=7)
    # Cuadros de servicio.
    d.line([W / 2 - 200, 90, W / 2 - 200, H - 90], fill=LINEA, width=4)
    d.line([W / 2 + 200, 90, W / 2 + 200, H - 90], fill=LINEA, width=4)
    d.line([W / 2 - 200, H / 2, W / 2 + 200, H / 2], fill=LINEA, width=4)
    # Pasillos de dobles.
    d.line([90, 150, W - 90, 150], fill=LINEA, width=4)
    d.line([90, H - 150, W - 90, H - 150], fill=LINEA, width=4)
    return guardar('tennis', im, capa)


def athletics():
    im, capa, d = lienzo(DEPORTE)
    # Óvalos concéntricos: la pista.
    for i in range(4):
        m = 60 + i * 34
        d.rounded_rectangle([m, m, W - m, H - m], radius=(H - 2 * m) / 2,
                            outline=FUERTE if i == 0 else LINEA, width=5)
    # Línea de meta.
    d.line([W / 2, 60, W / 2, 60 + 34 * 3 + 30], fill=FUERTE, width=6)
    return guardar('athletics', im, capa)


def cycling():
    im, capa, d = lienzo(DEPORTE)
    for i in range(3):
        m = 70 + i * 40
        d.rounded_rectangle([m, m, W - m, H - m], radius=(H - 2 * m) / 2,
                            outline=FUERTE if i == 0 else LINEA, width=5)
    # Dos ruedas.
    for cx in (W / 2 - 110, W / 2 + 110):
        d.ellipse([cx - 58, H / 2 - 58, cx + 58, H / 2 + 58],
                  outline=FUERTE, width=6)
        for a in range(0, 360, 45):
            r = math.radians(a)
            d.line([cx, H / 2, cx + 58 * math.cos(r), H / 2 + 58 * math.sin(r)],
                   fill=LINEA, width=3)
    return guardar('cycling', im, capa)


def archery():
    im, capa, d = lienzo(DEPORTE)
    cx, cy = W / 2, H / 2
    for i, r in enumerate((210, 165, 120, 75, 32)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r],
                  outline=FUERTE if i % 2 == 0 else LINEA, width=6)
    d.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], fill=FUERTE)
    return guardar('archery', im, capa)


def gym():
    im, capa, d = lienzo(DEPORTE)
    cy = H / 2
    d.rectangle([W / 2 - 250, cy - 12, W / 2 + 250, cy + 12], fill=FUERTE)
    for dx in (-250, 250):
        for i, (w, h) in enumerate(((34, 130), (34, 90))):
            x = W / 2 + dx + (1 if dx > 0 else -1) * (i * 52)
            d.rectangle([x - w / 2, cy - h / 2, x + w / 2, cy + h / 2],
                        fill=FUERTE if i == 0 else LINEA)
    return guardar('gym', im, capa)


def martialArts():
    im, capa, d = lienzo(DEPORTE)
    marco(d, m=80)
    d.rectangle([190, 160, W - 190, H - 160], outline=FUERTE, width=7)
    d.ellipse([W / 2 - 90, H / 2 - 90, W / 2 + 90, H / 2 + 90],
              outline=LINEA, width=6)
    return guardar('martialArts', im, capa)


def generalSport():
    im, capa, d = lienzo(DEPORTE)
    marco(d)
    d.line([W / 2, 70, W / 2, H - 70], fill=LINEA, width=5)
    d.ellipse([W / 2 - 95, H / 2 - 95, W / 2 + 95, H / 2 + 95],
              outline=FUERTE, width=6)
    return guardar('generalSport', im, capa)


def park():
    im, capa, d = lienzo(DEPORTE)
    # Senderos cruzados y arbolado.
    d.line([0, H * 0.72, W, H * 0.58], fill=LINEA, width=26)
    d.line([W * 0.32, H, W * 0.46, 0], fill=LINEA, width=18)
    for cx, cy, r in ((230, 230, 86), (860, 180, 64), (1020, 400, 74)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=FUERTE)
        d.rectangle([cx - 9, cy, cx + 9, cy + r + 40], fill=LINEA)
    return guardar('park', im, capa)


def auditorium():
    im, capa, d = lienzo(SERVICIO)
    # Escenario y filas de butacas en abanico.
    d.rectangle([W / 2 - 260, 110, W / 2 + 260, 190], fill=FUERTE)
    for fila in range(5):
        y = 260 + fila * 62
        ancho = 300 + fila * 78
        for i in range(7 + fila * 2):
            x = W / 2 - ancho + i * (2 * ancho / (6 + fila * 2))
            d.rounded_rectangle([x - 20, y - 18, x + 20, y + 18], radius=7,
                                fill=LINEA)
    return guardar('auditorium', im, capa)


def building():
    im, capa, d = lienzo(SERVICIO)
    d.rectangle([W / 2 - 300, 150, W / 2 + 300, H - 90], outline=FUERTE, width=7)
    for f in range(4):
        for c in range(6):
            x = W / 2 - 260 + c * 92
            y = 200 + f * 82
            d.rectangle([x, y, x + 58, y + 52], fill=LINEA)
    d.rectangle([W / 2 - 52, H - 200, W / 2 + 52, H - 90], fill=FUERTE)
    return guardar('building', im, capa)


def food():
    im, capa, d = lienzo(COMIDA)
    cy = H / 2
    # Plato.
    d.ellipse([W / 2 - 150, cy - 150, W / 2 + 150, cy + 150],
              outline=FUERTE, width=8)
    d.ellipse([W / 2 - 96, cy - 96, W / 2 + 96, cy + 96], outline=LINEA, width=5)
    # Tenedor y cuchillo.
    d.rounded_rectangle([300, cy - 150, 322, cy + 150], radius=11, fill=FUERTE)
    for i in range(3):
        d.rounded_rectangle([282 + i * 20, cy - 150, 294 + i * 20, cy - 60],
                            radius=6, fill=FUERTE)
    d.rounded_rectangle([W - 322, cy - 150, W - 300, cy + 150], radius=11,
                        fill=FUERTE)
    return guardar('food', im, capa)


def water():
    im, capa, d = lienzo(COMIDA)
    cx, cy = W / 2, H / 2 - 20
    # Gota.
    d.pieslice([cx - 120, cy - 60, cx + 120, cy + 180], 0, 180, fill=FUERTE)
    d.polygon([(cx - 120, cy + 60), (cx, cy - 190), (cx + 120, cy + 60)],
              fill=FUERTE)
    for i, r in enumerate((210, 270, 330)):
        d.arc([cx - r, cy + 120 - r / 3, cx + r, cy + 120 + r / 3],
              200, 340, fill=LINEA, width=6)
    return guardar('water', im, capa)


def medical():
    im, capa, d = lienzo(MEDICO)
    cx, cy, b, g = W / 2, H / 2, 190, 66
    d.rectangle([cx - b, cy - g, cx + b, cy + g], fill=FUERTE)
    d.rectangle([cx - g, cy - b, cx + g, cy + b], fill=FUERTE)
    d.ellipse([cx - 250, cy - 250, cx + 250, cy + 250], outline=LINEA, width=7)
    return guardar('medical', im, capa)


def restroom():
    im, capa, d = lienzo(SERVICIO)
    for dx, falda in ((-160, False), (160, True)):
        cx = W / 2 + dx
        d.ellipse([cx - 42, 150, cx + 42, 234], fill=FUERTE)
        if falda:
            d.polygon([(cx - 90, H - 190), (cx, 260), (cx + 90, H - 190)],
                      fill=FUERTE)
        else:
            d.rectangle([cx - 58, 260, cx + 58, H - 240], fill=FUERTE)
            d.rectangle([cx - 52, H - 240, cx - 12, H - 150], fill=FUERTE)
            d.rectangle([cx + 12, H - 240, cx + 52, H - 150], fill=FUERTE)
    d.line([W / 2, 120, W / 2, H - 120], fill=LINEA, width=5)
    return guardar('restroom', im, capa)


def lockerRoom():
    im, capa, d = lienzo(SERVICIO)
    for i in range(5):
        x = 140 + i * 190
        d.rectangle([x, 120, x + 150, H - 120], outline=FUERTE, width=6)
        d.line([x + 20, 300, x + 130, 300], fill=LINEA, width=5)
        d.ellipse([x + 110, 350, x + 130, 370], fill=LINEA)
    return guardar('lockerRoom', im, capa)


def registration():
    im, capa, d = lienzo(SERVICIO)
    d.rounded_rectangle([W / 2 - 280, 140, W / 2 + 280, H - 140], radius=26,
                        outline=FUERTE, width=7)
    d.ellipse([W / 2 - 210, 230, W / 2 - 90, 350], fill=FUERTE)
    d.pieslice([W / 2 - 240, 330, W / 2 - 60, 500], 180, 360, fill=FUERTE)
    for i in range(3):
        d.rounded_rectangle([W / 2 - 20, 250 + i * 62, W / 2 + 220,
                             280 + i * 62], radius=14, fill=LINEA)
    return guardar('registration', im, capa)


def info():
    im, capa, d = lienzo(SERVICIO)
    cx, cy = W / 2, H / 2
    d.ellipse([cx - 190, cy - 190, cx + 190, cy + 190], outline=FUERTE, width=9)
    d.ellipse([cx - 26, cy - 120, cx + 26, cy - 68], fill=FUERTE)
    d.rounded_rectangle([cx - 26, cy - 30, cx + 26, cy + 140], radius=13,
                        fill=FUERTE)
    return guardar('info', im, capa)


def security():
    im, capa, d = lienzo(SERVICIO)
    cx, cy = W / 2, H / 2
    d.polygon([(cx, cy - 210), (cx + 170, cy - 130), (cx + 170, cy + 40),
               (cx, cy + 210), (cx - 170, cy + 40), (cx - 170, cy - 130)],
              outline=FUERTE, width=8)
    d.line([cx - 70, cy, cx - 20, cy + 60], fill=FUERTE, width=14)
    d.line([cx - 20, cy + 60, cx + 80, cy - 60], fill=FUERTE, width=14)
    return guardar('security', im, capa)


def entrance():
    im, capa, d = lienzo(SERVICIO)
    d.rectangle([W / 2 - 250, 120, W / 2 + 250, H - 100], outline=FUERTE, width=8)
    d.rectangle([W / 2 - 250, 120, W / 2 - 10, H - 100], fill=LINEA)
    d.ellipse([W / 2 - 70, H / 2 - 16, W / 2 - 38, H / 2 + 16], fill=FUERTE)
    for i in range(3):
        d.line([W / 2 + 120 + i * 50, H / 2, W / 2 + 150 + i * 50, H / 2],
               fill=FUERTE, width=10)
    return guardar('entrance', im, capa)


def podium():
    im, capa, d = lienzo(SERVICIO)
    base = H - 130
    for dx, alto in ((-230, 150), (0, 230), (230, 110)):
        d.rectangle([W / 2 + dx - 105, base - alto, W / 2 + dx + 105, base],
                    fill=FUERTE if dx == 0 else LINEA)
    d.ellipse([W / 2 - 62, base - 380, W / 2 + 62, base - 256],
              outline=FUERTE, width=9)
    d.polygon([(W / 2 - 40, base - 270), (W / 2, base - 200),
               (W / 2 + 40, base - 270)], fill=FUERTE)
    return guardar('podium', im, capa)


def parking():
    im, capa, d = lienzo(TRANSPORTE)
    for i in range(5):
        x = 130 + i * 195
        d.line([x, 130, x, H - 130], fill=LINEA, width=6)
    d.line([130, 130, W - 130, 130], fill=LINEA, width=6)
    d.rounded_rectangle([W / 2 - 170, H / 2 - 80, W / 2 + 170, H / 2 + 80],
                        radius=26, fill=FUERTE)
    for cx in (W / 2 - 105, W / 2 + 105):
        d.ellipse([cx - 34, H / 2 + 50, cx + 34, H / 2 + 118], fill=FUERTE)
    return guardar('parking', im, capa)


def transit():
    im, capa, d = lienzo(TRANSPORTE)
    d.rounded_rectangle([200, 130, W - 200, H - 170], radius=32,
                        outline=FUERTE, width=8)
    for i in range(4):
        x = 250 + i * 175
        d.rounded_rectangle([x, 180, x + 130, 300], radius=12, fill=LINEA)
    for cx in (360, W - 360):
        d.ellipse([cx - 52, H - 220, cx + 52, H - 116], fill=FUERTE)
    return guardar('transit', im, capa)


def generic():
    im, capa, d = lienzo(SERVICIO)
    cx, cy = W / 2, H / 2 - 30
    d.ellipse([cx - 130, cy - 130, cx + 130, cy + 130], outline=FUERTE, width=9)
    d.polygon([(cx - 92, cy + 92), (cx, cy + 250), (cx + 92, cy + 92)],
              fill=FUERTE)
    d.ellipse([cx - 46, cy - 46, cx + 46, cy + 46], fill=LINEA)
    return guardar('generic', im, capa)


def main():
    os.makedirs(SALIDA, exist_ok=True)
    funcs = [swimming, basketball, football, soccerSmall, baseball, volleyball,
             tennis, athletics, gym, martialArts, archery, cycling,
             generalSport, auditorium, building, food, medical, restroom,
             lockerRoom, water, registration, info, security, parking,
             transit, entrance, podium, park, generic]
    total = 0
    for f in funcs:
        nombre = f()
        ruta = os.path.join(SALIDA, nombre + '.png')
        total += os.path.getsize(ruta)
        print('  %-16s %5.1f KB' % (nombre, os.path.getsize(ruta) / 1024))
    print('\n%d ilustraciones, %.0f KB en total' % (len(funcs), total / 1024))


if __name__ == '__main__':
    main()
