#!/usr/bin/env bash
# Baut Code It! und installiert die App auf einem iPad.
#
#   tools/install.sh                 — bauen und einmal installieren
#   tools/install.sh --warten [min]  — bauen, dann warten bis das Gerät auftaucht
#   tools/install.sh --nurinstall    — nicht neu bauen
#   tools/install.sh --geraete       — erreichbare Geräte auflisten
#   tools/install.sh --demo          — mit Demo-Kurs statt echtem Artemis
#   tools/install.sh --protokoll     — jede Anfrage mit Dauer auf stdout
#   tools/install.sh <UDID|Name>     — auf ein bestimmtes Gerät (sonst $CODEIT_GERAET)
#
# Das iPad meldet sich nur als „available", wenn es entsperrt und im selben
# WLAN ist (oder am Kabel hängt). Im Schlaf ist es „unavailable".
set -euo pipefail

ANZEIGE="Code It!"
STANDARD="${CODEIT_GERAET:-}"   # UDID oder Name des eigenen iPads

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/device/Build/Products/Release-iphoneos/Runner.app"
cd "$ROOT"

NEUBAU=1
WARTEN=0
FRIST_MIN=600
WUNSCH=""
DEFINES=()

while [ $# -gt 0 ]; do
	case "$1" in
		--geraete) xcrun devicectl list devices; exit 0 ;;
		--nurinstall) NEUBAU=0 ;;
		--demo) DEFINES+=(--dart-define=DEMO=true) ;;
		--protokoll) DEFINES+=(--dart-define=PROTOKOLL=true) ;;
		--warten)
			WARTEN=1
			case "${2:-}" in [0-9]*) FRIST_MIN="$2"; shift ;; esac
			;;
		*) WUNSCH="$1" ;;
	esac
	shift
done

bauen() {
	echo "▸ Baue …"
	# Flutter schreibt erst Generated.xcconfig mit den dart-defines, danach
	# signiert xcodebuild über die in Xcode angemeldete Apple-ID. `flutter build
	# ios` allein legt für eine neue Bundle-ID kein Profil an.
	flutter build ios --release --config-only ${DEFINES[@]+"${DEFINES[@]}"}
	xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
		-destination 'generic/platform=iOS' -allowProvisioningUpdates \
		-derivedDataPath build/device build -quiet
}

# Achtung beim Muster: „unavailable" enthält „available". Ohne den
# Whitespace-Anker gilt ein schlafendes Gerät als erreichbar.
#
# `|| true` ist Absicht: ohne das reißt ein leeres grep unter `set -e` das
# ganze Skript ab — kommentarlos, mit Exit 1.
geraet_finden() {
	local liste
	liste=$(xcrun devicectl list devices 2>/dev/null | grep -E "[[:space:]]available" || true)
	if [ -n "$WUNSCH" ]; then
		echo "$liste" | grep -i -- "$WUNSCH" | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27,}' | head -1 || true
	elif [ -n "$STANDARD" ]; then
		echo "$liste" | grep -i -- "$STANDARD" | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27,}' | head -1 || true
	else
		echo "$liste" | grep -i "ipad" | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27,}' | head -1 || true
	fi
}

installieren() {
	xcrun devicectl device install app --device "$1" "$APP"
}

[ "$NEUBAU" = 0 ] || bauen

if [ ! -d "$APP" ]; then
	echo "▸ Kein Build unter $APP" >&2
	exit 1
fi

GEBAUT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$APP/Info.plist" 2>/dev/null || echo "?")

if [ "$WARTEN" = 1 ]; then
	# Nicht auf Verfügbarkeit warten, sondern wiederholt versuchen: ein
	# gesperrtes Gerät steht als „available" da und lehnt trotzdem ab.
	ENDE=$(( $(date +%s) + FRIST_MIN * 60 ))
	echo "▸ Warte aufs Entsperren (bis $(date -r $ENDE '+%H:%M')) …"
	VERSUCH=0
	while [ "$(date +%s)" -lt "$ENDE" ]; do
		VERSUCH=$((VERSUCH + 1))
		UDID=$(geraet_finden)
		if [ -n "$UDID" ] && installieren "$UDID" >/dev/null 2>&1; then
			echo "▸ Installiert um $(date '+%H:%M') nach $VERSUCH Versuchen."
			exit 0
		fi
		sleep 60
	done
	echo "▸ Frist abgelaufen, nicht installiert. Nochmal: tools/install.sh --nurinstall" >&2
	exit 1
fi

# Die CoreDevice-Verbindung bricht gern beim ersten Versuch weg.
for versuch in 1 2 3; do
	UDID=$(geraet_finden)
	if [ -n "$UDID" ] && installieren "$UDID"; then
		echo "▸ Fertig. Die App heißt „$GEBAUT“ auf dem Homescreen."
		[ "$GEBAUT" = "$ANZEIGE" ] || echo "▸ Achtung: erwartet war „$ANZEIGE“ — der Build ist alt." >&2
		exit 0
	fi
	echo "▸ Versuch $versuch fehlgeschlagen, nochmal …" >&2
	sleep 5
done
echo "▸ iPad nicht erreichbar oder Installation abgelehnt. Entsperren und noch einmal," >&2
echo "  oder: tools/install.sh --warten" >&2
exit 1
