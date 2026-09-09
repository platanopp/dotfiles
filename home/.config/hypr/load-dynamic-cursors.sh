#!/usr/bin/env sh
# Carga el plugin de shake-to-find, una vez que Hyprland ya esta arriba.
#
# Por que aca y no en hyprland.lua: estuvo ahi y rompio un inicio de sesion.
# Las claves de config de un plugin no existen hasta que el plugin esta
# cargado, y `hl.plugin.load` durante el parseo no lo cargaba -- ni plugin ni
# linea de log. El hl.config siguiente fallaba con `unknown config key`, y
# Hyprland no arranca con un error de config.
#
# Desde un script eso no puede repetirse: lo peor que pasa es perder el efecto.
#
# OJO con el ABI. No alcanza con que coincida la version de Hyprland: el plugin
# se compila contra aquamarine, hyprutils y companiia, y un bump de cualquiera
# lo invalida. Paso el 2026-09-09 con aquamarine 0.14 -> 0.15, con Hyprland
# quieto en 0.56.2. Para recompilar, ver el .version junto al .so.
set -u

SO="$HOME/.local/share/hyprland/plugins/dynamic-cursors.so"

loaded() {
    hyprctl plugin list 2>/dev/null | grep -q "dynamic-cursors"
}

if [ ! -f "$SO" ]; then
    echo "dynamic-cursors: falta $SO"
    exit 0
fi

if ! loaded; then
    # `hyprctl plugin load` sale con 0 aunque el plugin no cargue -- imprime el
    # motivo y devuelve exito igual. Por eso se comprueba mirando la lista y no
    # el codigo de salida.
    hyprctl plugin load "$SO"
    if ! loaded; then
        echo "dynamic-cursors: no cargo (arriba esta el motivo). Sesion intacta."
        exit 0
    fi
fi

# Lo unico que no viene bien por defecto: 2000ms deja el puntero grande varios
# segundos despues de soltar, y macOS lo achica apenas parás.
hyprctl eval 'hl.config({ plugin = { dynamic_cursors = { shake = { timeout = 0 } } } })' >/dev/null
echo "dynamic-cursors: activo, shake:timeout = $(hyprctl getoption plugin:dynamic-cursors:shake:timeout 2>/dev/null | head -1)"
