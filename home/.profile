# Read by greetd, and by nothing else on this machine.
#
# greetd starts the session with `/bin/sh -c` and sources /etc/profile and
# this file first (general.source_profile, which defaults to true). It does
# not read ~/.zprofile or ~/.zshrc, so what the graphical session inherits is
# whatever is here -- which is the point of moving the boot off a login shell,
# but it also means the two PATH entries ~/.zshrc adds had to land somewhere.
#
# zsh ignores this file (it reads ~/.zshenv, ~/.zprofile, ~/.zshrc), and bash
# skips it whenever ~/.bash_profile exists, which it does. So there is no
# double-sourcing to worry about: ~/.zshrc still sets PATH for interactive
# shells, and this sets it for everything the session launches.

# Nothing in ~/.local/share/applications relies on this -- every Exec there
# spells the path out in full -- but anything launched by name from a script
# or a keybind would not find osu-wine, ff or taller without it.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac

case ":$PATH:" in
    *":$HOME/.spicetify:"*) ;;
    *) PATH="$PATH:$HOME/.spicetify" ;;
esac

export PATH
