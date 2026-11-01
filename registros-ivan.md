# Registros de Ivan

Cambios que hice en mi copia del rice, traídos a este repo para que elijas cuáles quieres.
Este archivo está escrito para que lo lea tu asistente de IA antes de aplicar nada, y para que tú
veas de un vistazo qué hace cada cosa.

**Cómo llegan:** cuatro PR a `dev`, uno por tema (`ivan/barra`, `ivan/fast-notes`,
`ivan/widgets-overview`, `ivan/acento-terminal`). Son independientes: puedes aceptar los que
quieras y en cualquier orden. Este archivo va igual en los cuatro, así que no choca al mergear.
`mejoras-ivan` junta todo, por si prefieres verlo de una vez.

**Para tu asistente:** todo lo de `home/.config/quickshell` parte de tu `0924de1`, y los
conflictos los resolví a favor de tu código y tus comentarios. Solo `ivan/barra` toca
`hyprland.lua`, y son dos líneas. No tocan `shell-settings.json`, `desktop-widgets.json`,
monitores ni tu `kb_layout`. Antes de aplicar, revisa la columna **Ojo** de cada tabla.

---

## Resumen

| PR (rama `ivan/…`) | Qué cambia | Archivos | Ojo |
|---|---|---|---|
| `barra` | Layout del teclado en la pill de estado + aviso sutil al cambiar + botón de grabar en la pill de notificaciones | `bar/ControlPanel.qml`, `bar/StatusWidget.qml`, `overlays/LayoutToast.qml`, `services/KeyLayout.qml`, `shell.qml` | Botón de grabar nuevo junto a la campana |
| `barra` | El layout se ve como una tecla (keycap); orden de iconos nuevo | `bar/StatusWidget.qml`, `overlays/LayoutToast.qml`, `services/KeyLayout.qml` | Cambia el orden de la pill de estado (ver tabla abajo) |
| `barra` | Punto en el logo de CachyOS cuando hay una versión nueva publicada de la shell | `bar/ControlPanel.qml`, `services/System.qml`, `settings/pages/AboutPage.qml` | Quien publica la shell (tú) no lo verá: tu estado es "ahead". La primera revisión en una máquina cuenta como vista |
| `barra` | La tecla de layout solo aparece si hay más de un layout | `bar/StatusWidget.qml`, `services/KeyLayout.qml` | Con tu `kb_layout = "latam"` no verás nada nuevo en la pill |
| `barra` | `Super+Ctrl+Space`: siguiente layout de teclado | `hypr/hyprland.lua` | Con un solo layout no hace nada |
| `fast-notes` | Widget **Fast Notes**: notas con checkbox guardadas en el vault de Obsidian, con recordatorios | `desktop/widgets/FastNotes.qml`, `services/Notes.qml`, `scripts/obsidian_notes.py`, `services/Widgets.qml`, `desktop/DesktopLayer.qml` | La capa de escritorio pasa a `keyboardFocus: OnDemand` para poder escribir |
| `widgets-overview` | Overview: la tarjeta "nuevo" y las teclas respetan workspaces numerados entre monitores | `overlays/WorkspaceOverview.qml` | Con un monitor o con workspaces 1-10 por monitor se comporta igual que antes |
| `widgets-overview` | Widgets de escritorio: opacidad del vidrio por widget, con un slider en el picker | `desktop/*`, `overlays/WidgetPicker.qml`, `services/Widgets.qml` | Sin valor propio quedan en 0.9, igual que ahora |
| `acento-terminal` | El acento se escribe en `~/.cache/quickshell/accent` (lo usa el prompt de zsh) | `services/Accent.qml` | Sin el hook de zsh no tiene efecto visible |
| `acento-terminal` | Kitty toma la paleta del acento vía matugen | `services/Accent.qml` | **Necesita matugen y plantillas**, ver [Extras](#extras-fuera-del-repo). Sin ellas falla en silencio |

---

## Pill de estado

Orden de los iconos, de izquierda a derecha:

| Antes | Ahora |
|---|---|
| DND · red · bluetooth · volumen · mic | DND · **layout** · bluetooth · red · volumen · mic |

| Elemento | Qué hace |
|---|---|
| Tecla `US` / `LA` | Muestra el layout del teclado principal (el último que se usó). Al hacer clic cambia al siguiente |
| Aviso al cambiar | Una pill de vidrio abajo en el monitor enfocado, con "English (US)" o "Spanish (Latin America)". Dura unos 2 s y no captura clics |

Para usar dos layouts, en `hyprland.lua`:

```lua
kb_layout  = "latam,us",
kb_variant = ",altgr-intl",   -- us con AltGr+n = ñ, AltGr+? = ¿
```

Si quieres otro orden en un teclado concreto (yo lo uso para un Akko sin ñ):

```lua
hl.device({ name = "ducky-akko-3087", kb_layout = "us,latam", kb_variant = "altgr-intl," })
```

`KeyLayout` lee `hyprctl devices -j` (teclado `main`) y se actualiza con el evento `activelayout`.

## Pill de notificaciones

| Botón | Qué hace |
|---|---|
| ⏺ Grabar (nuevo) | `Recorder.toggleRecording(<pantalla de la pill>)`. Mientras graba se oculta y queda el indicador rojo que ya tenías |
| 🔔 Campana | Sin cambios |
| Logo CachyOS | Sin cambios, salvo un punto cuando `System.updateNew` |

**El punto de actualización:** si hay commits omitidos a propósito, el estado de
`shell_update.py` queda en `behind` para siempre. Por eso el punto sale solo cuando el
`head` publicado es distinto del último visto en Ajustes → Acerca de, que se guarda en
`~/.cache/quickshell/update-seen`. Lo revisa un minuto después de iniciar sesión y luego cada 6 h.

## Fast Notes

El widget aparece en el picker, en la categoría **Notes**. Lee y escribe `- [ ] HH:MM texto`
en una nota del vault de Obsidian, así que la misma lista se puede marcar desde Obsidian.

| Acción | Cómo |
|---|---|
| Añadir | Escribir abajo y Enter |
| Marcar hecha | Clic en la nota o en su casilla |
| Editar | Lápiz al pasar el ratón |
| Limpiar hechas | Escoba en la cabecera |
| Abrir en Obsidian | Botón de la cabecera |

**Recordatorios** (`notify-send`):

| En la nota | Avisos |
|---|---|
| `@6/11 10:00` | 4 nov 10:00 "En 2 días", 5 nov "Mañana", 6 nov "Hoy" (todos a las 10:00) |
| `@6/11` | Igual, pero a las 09:00 |
| `@6/11/2027 8:00` | Con año explícito |
| `@18:30` | Todos los días a esa hora hasta marcarla |

- Sin año, toma la fecha más cercana: en diciembre, `@5/1` es enero del año siguiente.
- El aviso del mismo día es `critical` y se queda en pantalla. Los otros son normales.
- En el widget la fecha sale como un chip ("6 nov · 10:00") del color del acento, y en rojo si ya pasó.

**Dependencias:**

| Necesita | Si falta |
|---|---|
| Un vault en `~/.config/obsidian/obsidian.json`, o la variable `QS_OBSIDIAN_VAULT` | El widget muestra "No se encontró ningún vault de Obsidian" |
| `/usr/share/icons/hicolor/512x512/apps/obsidian.png` | La cabecera queda sin icono |
| `notify-send` (libnotify) | No hay recordatorios |

## Overview y widgets

| Cambio | Detalle |
|---|---|
| Overview con workspaces numerados entre monitores | Si un monitor usa 1-5 y otro 6-10, la tarjeta "nuevo" de cada uno no reutiliza un id del otro, y cada monitor tiene sus propias teclas |
| Vidrio por widget | Slider en el picker; se guarda como `glass` en `desktop-widgets.json`. Sin valor propio, `Widgets.glassOf(w)` devuelve `defaultGlass` (0.9, igual que `Theme.glass`), así que nada cambia hasta que muevas el slider |

---

## Extras fuera del repo

No están en commits porque tú no tienes estos archivos en el repo. Son opcionales.

### Kitty con la paleta del acento (`acento-terminal`)

Cuando cambia el acento, `Accent.qml` corre `matugen color hex <acento> -m dark` y le manda
`SIGUSR1` a kitty para que recargue los colores. Necesitas:

1. `matugen` instalado.
2. En `~/.config/matugen/config.toml`:

   ```toml
   [config.custom_colors]
   red     = { color = "#e67e80", blend = true }
   green   = { color = "#a7c080", blend = true }
   yellow  = { color = "#dbbc7f", blend = true }
   blue    = { color = "#7aa2f7", blend = true }
   magenta = { color = "#d699b6", blend = true }
   cyan    = { color = "#83c092", blend = true }

   [templates.kitty]
   input_path = '~/.config/matugen/templates/kitty-colors.conf'
   output_path = '~/.cache/matugen/kitty-colors.conf'
   ```

3. En `kitty.conf`, después de tu tema: `include ~/.cache/matugen/kitty-colors.conf`.

<details>
<summary><code>~/.config/matugen/templates/kitty-colors.conf</code></summary>

```
background {{colors.surface.default.hex}}
foreground {{colors.on_surface.default.hex}}
cursor {{colors.primary.default.hex}}
cursor_text_color {{colors.surface.default.hex}}
selection_background {{colors.surface_variant.default.hex}}
selection_foreground {{colors.on_surface.default.hex}}
url_color {{colors.primary.default.hex}}

active_border_color {{colors.primary.default.hex}}
inactive_border_color {{colors.surface_container_high.default.hex}}
active_tab_background {{colors.surface_container_high.default.hex}}
active_tab_foreground {{colors.primary.default.hex}}
inactive_tab_background {{colors.surface.default.hex}}
inactive_tab_foreground {{colors.outline.default.hex}}
tab_bar_background {{colors.surface.default.hex}}

color0 {{colors.surface_container_high.default.hex}}
color8 {{colors.outline.default.hex}}
color1 {{colors.red.default.hex}}
color9 {{colors.on_red_container.default.hex}}
color2 {{colors.green.default.hex}}
color10 {{colors.on_green_container.default.hex}}
color3 {{colors.yellow.default.hex}}
color11 {{colors.on_yellow_container.default.hex}}
color4 {{colors.blue.default.hex}}
color12 {{colors.on_blue_container.default.hex}}
color5 {{colors.magenta.default.hex}}
color13 {{colors.on_magenta_container.default.hex}}
color6 {{colors.cyan.default.hex}}
color14 {{colors.on_cyan_container.default.hex}}
color7 {{colors.on_surface_variant.default.hex}}
color15 {{colors.on_surface.default.hex}}
```

</details>

Con el mismo método, rofi puede tomar el acento: una plantilla que genera
`accent: {{colors.primary.default.hex}};` y `@import` en `config.rasi`.

### Prompt de zsh con el acento (`acento-terminal`)

En `~/.zshrc`, si usas powerlevel10k:

```zsh
_qs_accent() {
  local f=~/.cache/quickshell/accent c
  [[ -r $f ]] || return
  c=$(<$f)
  [[ $c == $_qs_accent_last || ! $c =~ '^#[0-9a-fA-F]{6}$' ]] && return
  local seen=${+_qs_accent_last}
  typeset -g _qs_accent_last=$c
  typeset -g POWERLEVEL9K_{DIR,DIR_SHORTENED,DIR_ANCHOR}_FOREGROUND=$c
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$c
  (( seen )) && (( $+functions[p10k] )) && p10k reload
}
_qs_accent
precmd_functions=(_qs_accent $precmd_functions)
```

---

## Lo que no traje

| Cambio mío | Por qué no |
|---|---|
| Puntos de workspaces centrados en su pill | Depende de una reescritura de `bar/Workspaces.qml` que tú no tienes |
| Pill de workspaces alineada arriba con las demás (gap < 12) | Tu `1fd6b88` (pills de 36 px) cambió esa zona; no lo pude comprobar sobre tu versión |
| Barra oculta en `HDMI-A-1`, fullscreen en workspaces especiales | Son de mi monitor y mi uso |
| `shell_update.py` en modo git (`qs_pull.sh`) | Es mi forma de traer tus cambios con merge a 3 vías |
| Mi `hypridle` (3600 s) y `kb_layout` | Son mis preferencias |

## Estado de las pruebas

- Todo esto corre a diario en mi PC con la shell completa.
- En este árbol (tu shell + estos commits) **no lo cargué con Quickshell**, porque abriría una segunda barra encima de la mía. Revisé los diffs a mano. Si al recargar sale algún error, `quickshell log` dirá en qué archivo está.
