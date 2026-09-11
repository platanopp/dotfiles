#!/usr/bin/env python3
"""Publica la cancion actual de osu!lazer como un reproductor MPRIS.

Por que un puente y no un caso especial en el widget: shell.qml ya tiene
seleccion de reproductor -- activePlayer, playerRank, pinnedPlayer y ciclado --
construida para varios MPRIS a la vez. Apareciendo como uno mas, osu hereda todo
eso gratis y MediaWidget.qml no se toca.

De donde sale el dato: lazer no registra MPRIS ni pone la cancion en el titulo de
la ventana; se comprobo. Lo unico que la publica es su propio log, que en cada
cambio de mapa escribe

    Invalidating working beatmap cache for <artista> - <titulo> (<mapper>) [<dif>]

Eso es fragil por naturaleza -- es un log, no una API, y su formato puede cambiar
en cualquier version. Si un dia osu deja de aparecer en la barra, esa linea es lo
primero a mirar.

Usa Gio en vez de dbus-next o pydbus porque PyGObject ya esta instalado y esas no.
"""

import glob
import os
import re
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "org.mpris.MediaPlayer2.osu"
OBJECT_PATH = "/org/mpris/MediaPlayer2"
MARKER = "working beatmap cache for"

# Lo minimo que quickshell necesita para tratarlo como reproductor. Todo lo que
# se puede controlar va en false: esto es una ventana a lo que osu esta haciendo,
# no un mando a distancia -- no hay forma de pedirle que cambie de cancion.
INTROSPECTION = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <method name="Raise"/>
    <method name="Quit"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""


def strip_trailing(text, opening, closing):
    """Quita un grupo (...) o [...] final contando profundidad.

    Una expresion regular no sirve aca: los nombres de dificultad de osu anidan
    corchetes -- "[Maddy's Boss Stage [Adjusted Offset]]" es real, y habia 140
    lineas asi en el historial. Contar desde la derecha las parsea todas.
    """
    text = text.rstrip()
    if not text.endswith(closing):
        return text
    depth = 0
    for i in range(len(text) - 1, -1, -1):
        if text[i] == closing:
            depth += 1
        elif text[i] == opening:
            depth -= 1
            if depth == 0:
                return text[:i].rstrip()
    return text


def parse_beatmap(payload):
    """'<artista> - <titulo> (<mapper>) [<dif>]' -> (artista, titulo)."""
    rest = strip_trailing(payload, "[", "]")
    rest = strip_trailing(rest, "(", ")")
    if " - " not in rest:
        return None
    artist, title = rest.split(" - ", 1)
    artist, title = artist.strip(), title.strip()
    return (artist, title) if title else None


def log_directory():
    """La carpeta de logs, siguiendo el storage.ini si redirige los datos."""
    local = os.path.expanduser("~/.local/share/osu")
    ini = os.path.join(local, "storage.ini")
    try:
        with open(ini, encoding="utf-8") as handle:
            for line in handle:
                # IniConfigManager de osu-framework: 'Clave = Valor', sin
                # secciones, y descarta cualquier linea sin '='.
                if line.lstrip().startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                if key.strip() == "FullPath" and value.strip():
                    return os.path.join(value.strip(), "logs")
    except OSError:
        pass
    return os.path.join(local, "logs")


def osu_running():
    return subprocess.run(["pgrep", "-x", "osu!"],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


class OsuPlayer:
    def __init__(self):
        self.artist = ""
        self.title = ""
        self.connection = None
        self.owner_id = None
        self.registrations = []
        self.handle = None
        self.path = None
        self.position = 0

    # ── D-Bus ────────────────────────────────────────────────────────────

    def metadata(self):
        # mpris:trackid es obligatorio; los clientes lo usan como identidad de
        # la pista y algunos descartan la metadata entera sin el.
        items = {
            "mpris:trackid": GLib.Variant("o", "/org/mpris/MediaPlayer2/osu/track"),
            "xesam:title": GLib.Variant("s", self.title),
            "xesam:artist": GLib.Variant("as", [self.artist] if self.artist else []),
        }
        return GLib.Variant("a{sv}", items)

    def get_property(self, _conn, _sender, _path, interface, prop):
        values = {
            "Identity": GLib.Variant("s", "osu!"),
            "DesktopEntry": GLib.Variant("s", "osu"),
            "CanQuit": GLib.Variant("b", False),
            "CanRaise": GLib.Variant("b", False),
            "HasTrackList": GLib.Variant("b", False),
            "PlaybackStatus": GLib.Variant("s", "Playing"),
            "Metadata": self.metadata(),
            "CanPlay": GLib.Variant("b", False),
            "CanPause": GLib.Variant("b", False),
            "CanGoNext": GLib.Variant("b", False),
            "CanGoPrevious": GLib.Variant("b", False),
            "CanSeek": GLib.Variant("b", False),
            "CanControl": GLib.Variant("b", False),
        }
        del interface
        return values.get(prop)

    def on_method(self, _conn, _sender, _path, _iface, _method, _params, invocation):
        invocation.return_value(None)

    def announce(self):
        if self.connection is None:
            return
        # El a{sv} va como dict de Python, no como Variant ya armado: anidar un
        # Variant dentro de otro hace que GLib intente iterarlo como diccionario
        # y reviente con KeyError. Los valores de adentro si son Variant.
        self.connection.emit_signal(
            None, OBJECT_PATH, "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)",
                         ("org.mpris.MediaPlayer2.Player",
                          {"Metadata": self.metadata()}, [])))

    def publish(self):
        if self.owner_id is not None:
            return
        self.connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
        for iface in info.interfaces:
            self.registrations.append(self.connection.register_object(
                OBJECT_PATH, iface, self.on_method, self.get_property, None))
        self.owner_id = Gio.bus_own_name_on_connection(
            self.connection, BUS_NAME, Gio.BusNameOwnerFlags.NONE, None, None)
        print("osu-mpris: publicado", flush=True)

    def unpublish(self):
        if self.owner_id is None:
            return
        Gio.bus_unown_name(self.owner_id)
        for reg in self.registrations:
            self.connection.unregister_object(reg)
        self.registrations = []
        self.owner_id = None
        self.artist = self.title = ""
        print("osu-mpris: retirado", flush=True)

    # ── Lectura del log ──────────────────────────────────────────────────

    def newest_log(self):
        logs = glob.glob(os.path.join(log_directory(), "*.runtime.log"))
        return max(logs, key=os.path.getmtime) if logs else None

    def read_new_lines(self):
        newest = self.newest_log()
        if newest is None:
            return
        # Cada sesion de osu abre un log nuevo. Al cambiar de archivo se empieza
        # desde el principio, para no perderse el mapa que ya estaba puesto.
        if newest != self.path:
            self.path = newest
            self.position = 0
        try:
            size = os.path.getsize(self.path)
            if size < self.position:  # truncado
                self.position = 0
            with open(self.path, encoding="utf-8", errors="replace") as handle:
                handle.seek(self.position)
                chunk = handle.read()
                self.position = handle.tell()
        except OSError:
            return

        # Solo interesa el ultimo mapa del trozo leido, no cada uno por el que
        # paso. Importa sobre todo al arrancar: ahi el trozo es el log entero, y
        # anunciar linea por linea disparaba una rafaga de PropertiesChanged
        # reproduciendo toda la sesion anterior -- setenta y cinco señales para
        # decir una sola cosa.
        latest = None
        for line in chunk.splitlines():
            if MARKER not in line:
                continue
            parsed = parse_beatmap(line.split(MARKER, 1)[1].strip())
            if parsed is not None:
                latest = parsed

        if latest is not None and latest != (self.artist, self.title):
            self.artist, self.title = latest
            self.announce()

    def tick(self):
        if osu_running():
            self.publish()
            self.read_new_lines()
        else:
            self.unpublish()
            self.path = None
        return GLib.SOURCE_CONTINUE


def main():
    player = OsuPlayer()
    # 1s: un cambio de mapa en la seleccion de canciones dura mas que eso, y
    # leer lo nuevo de un archivo abierto no cuesta nada.
    GLib.timeout_add_seconds(1, player.tick)
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    finally:
        player.unpublish()


if __name__ == "__main__":
    sys.exit(main())
