#!/bin/bash
# zusammenfassen.sh — Lokale AI-Summary via Ollama
# Null Abhängigkeiten außer curl + osascript (macOS-nativ)
# Input: Text via stdin | Output: Summary auf stdout

OLLAMA_URL="http://localhost:11434/api/generate"
MODEL="llama3.3:70b"

# Temp-Dateien mit sicherem Cleanup
TEMP_TEXT=$(mktemp /tmp/ollama_text_XXXXXX.txt)
TEMP_JSON=$(mktemp /tmp/ollama_req_XXXXXX.json)
TEMP_RESP=$(mktemp /tmp/ollama_resp_XXXXXX.json)
trap 'rm -f "$TEMP_TEXT" "$TEMP_JSON" "$TEMP_RESP"' EXIT

# Text via stdin
cat > "$TEMP_TEXT"

# Zu kurz? Kein AI nötig
CHARCOUNT=$(wc -c < "$TEMP_TEXT" | tr -d ' ')
if [[ $CHARCOUNT -lt 200 ]]; then
    echo "Audio-Kurznotiz"
    exit 0
fi

# Ollama erreichbar?
if ! curl -s --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "Audio Transkription"
    exit 0
fi

# JSON bauen via osascript
osascript -l JavaScript - "$TEMP_TEXT" "$TEMP_JSON" "$MODEL" > /dev/null << 'JSEOF'
var args = $.NSProcessInfo.processInfo.arguments;
var textPath = ObjC.unwrap(args.objectAtIndex(4));
var jsonPath = ObjC.unwrap(args.objectAtIndex(5));
var model = ObjC.unwrap(args.objectAtIndex(6));

var text = ObjC.unwrap(
    $.NSString.stringWithContentsOfFileEncodingError(
        textPath, $.NSUTF8StringEncoding, null
    )
);

var prompt = "Du extrahierst Goldstuecke aus Transkripten. Jedes Goldstueck ist ein konkreter Gedanke, den man sich an die Wand pinnen koennte.\n\nREGELN:\n- Schreib die Erkenntnis SO WIE SIE GESAGT WURDE, nur ohne Fuellwoerter\n- FALSCH: Es wurde ueber Pornokonsum und Familienkonflikte gesprochen\n- RICHTIG: Pornokonsum ist wie eine Familienaufstellung - du spielst Konflikte nach, die du im echten Leben nicht loesen kannst\n- FALSCH: Der Coach empfahl, Grenzen zu setzen\n- RICHTIG: Coach: Grenzen sind nur Grenzen, wenn die Ueberschreitung Konsequenzen hat\n- FALSCH: Es ist wichtig, Konflikte anzugehen\n- RICHTIG: Konflikte im echten Leben austragen statt in Pornos kompensieren - sonst aendert sich nichts\n- NIEMALS schreiben: es ist wichtig, man sollte, es wurde besprochen, der Fokus lag auf, man\n- NIEMALS man schreiben - immer du oder konkreter Sprecher\n- Die Erkenntnis direkt als Aussage formulieren. Kein Ratgeber-Ton. Rohe Wahrheit.\n- Wenn erkennbar wer spricht: Coach: oder Teilnehmer: voranstellen\n- Skaliere mit der Laenge: kurzes Memo = 2-3 Punkte. Langes Gespraech = so viele wie Gold drin ist, bis 15\n- Metaphern und Bilder WOERTLICH uebernehmen, nicht umformulieren. Beispiel: Pornos sind wie ein Auto das in der Luft haengt - du gibst Vollgas aber die Reifen drehen durch, nichts passiert. NICHT daraus machen: Pornos sind ein luftleerer Raum\n- Buchempfehlungen, Autoren, Frameworks, Modelle, Meditationen, konkrete Uebungen IMMER mit Name aufnehmen\n- Denke wie ein Content-Creator und Coach: Was ist zitierfaehig? Was wuerde jemand screenshotten?\n- Wenn der gleiche Punkt mehrfach formuliert wird, nimm die staerkste Version\n- Ignoriere Smalltalk, Begruessung, Wiederholungen\n- TAGS muessen BEIDES enthalten: spezifische Konzepte/Autoren/Frameworks UND allgemeine Themen\n- Deutsch. Nur Output. Keine Einleitung.\n\nFORMAT (EXAKT so, alles linksbuendig):\nKONTEXT: [Rolle/Name | Thema 3-5 Woerter. KURZ.]\nTAGS: [spezifisch + allgemein kommagetrennt]\n\nGOLDSTUECKE:\n- [Punkt]\n- [Punkt]\n\nTranskript:\n\n" + text;

var req = JSON.stringify({
    model: model,
    prompt: prompt,
    stream: false,
    options: {temperature: 0.05, num_predict: 1800}
});

var nsReq = $.NSString.alloc.initWithUTF8String(req);
nsReq.writeToFileAtomicallyEncodingError(
    jsonPath, true, $.NSUTF8StringEncoding, null
);
JSEOF

# Ollama API — max 5 Min
curl -s --max-time 300 "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d @"$TEMP_JSON" > "$TEMP_RESP" 2>/dev/null

# Antwort extrahieren
RAW=$(osascript -l JavaScript - "$TEMP_RESP" << 'JSEOF2'
var respPath = ObjC.unwrap(
    $.NSProcessInfo.processInfo.arguments.objectAtIndex(4)
);
var raw = ObjC.unwrap(
    $.NSString.stringWithContentsOfFileEncodingError(
        respPath, $.NSUTF8StringEncoding, null
    )
);
try {
    var data = JSON.parse(raw);
    data.response || "Audio Transkription";
} catch(e) {
    "Audio Transkription";
}
JSEOF2
)

# Output formatieren
KONTEXT_LINE=$(echo "$RAW" | grep -m1 "^KONTEXT:" || echo "KONTEXT: Audio Transkription")
TAGS_LINE=$(echo "$RAW" | grep -m1 "^TAGS:" || echo "TAGS: Audio")
REST=$(echo "$RAW" | grep -v "^KONTEXT:" | grep -v "^TAGS:" | sed '/^$/d' | sed '1s/^//')

printf '> %s\n> %s\n\n---\n\ntags-thematisch: #10\ntags-meta: #A/Meta/\nquelle: #A/Kanal/0AppleSprachmemoTranskript\nkanal: #A/Kanal/\nflow: #200_Output/A_Tagebuch\nstatus: #900_Status/1_inbox_zu_taggen\n\n---\n\n%s\n' "$KONTEXT_LINE" "$TAGS_LINE" "$REST"