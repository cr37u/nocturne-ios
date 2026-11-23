"""Generates Shared/Resources/Localizable.xcstrings from the Android strings (values/, values-en/,
values-ru/) plus the iOS-only keys below. Android string names are used as keys.
Run from the repo root: python -I tools/make_strings.py <android res dir>"""
import json, re, sys, pathlib
import xml.etree.ElementTree as ET

RES = pathlib.Path(sys.argv[1])
LANGS = {"ro": "values", "en": "values-en", "ru": "values-ru"}
SKIP = re.compile(r"^(battery_|xiaomi_|keep_playing_|channel_|notifications_|notif_pause|notif_cancel|app_name|widget_name|extractor_version|cd_drag)")

def android_to_ios(s: str) -> str:
    s = s.replace("\'", "'").replace('\\"', '"').replace("\n", "\n")
    s = re.sub(r"%(\d+\$)?s", lambda m: f"%{m.group(1) or ''}@", s)
    s = re.sub(r"%(\d+\$)?d", lambda m: f"%{m.group(1) or ''}lld", s)
    return s

def text(el):  # inner text incl. nested markup
    return "".join(el.itertext()).strip()

strings, plurals = {}, {}
for lang, folder in LANGS.items():
    root = ET.parse(RES / folder / "strings.xml").getroot()
    for el in root:
        name = el.get("name")
        if not name or SKIP.match(name) or el.get("translatable") == "false":
            continue
        if el.tag == "string":
            strings.setdefault(name, {})[lang] = android_to_ios(text(el))
        elif el.tag == "plurals":
            plurals.setdefault(name, {})[lang] = {i.get("quantity"): android_to_ios(text(i)) for i in el}

# iOS-only keys: ro, en, ru
EXTRA = {
    "language_ro": ("Română", "Română", "Română"),
    "language_en": ("English", "English", "English"),
    "language_ru": ("Русский", "Русский", "Русский"),
    "language_ios_settings": ("Limba în Setări iOS", "Language in iOS Settings", "Язык в настройках iOS"),
    "language_ios_settings_body": ("Deschide Setări → Nocturne → Limbă", "Opens Settings → Nocturne → Language", "Откроет Настройки → Nocturne → Язык"),
    "cd_airplay": ("AirPlay", "AirPlay", "AirPlay"),
    "cd_track_options": ("Opțiuni melodie", "Song options", "Действия с песней"),
    "cd_lyrics": ("Versuri", "Lyrics", "Текст песни"),
    "sort": ("Sortează", "Sort", "Сортировка"),
    "repeat_cd": ("Repetare", "Repeat", "Повтор"),
    "app_group_title": ("Grup de aplicații", "App Group", "Группа приложений"),
    "app_group_on": ("Activ – widgeturile, Live Activity și Share primesc datele", "Active – widgets, Live Activity and Share get the data", "Активна – виджеты, Live Activity и «Поделиться» получают данные"),
    "app_group_off": ("Indisponibil – widgeturile arată „Deschide Nocturne”; aplicația funcționează normal", "Unavailable – widgets show “Open Nocturne”; the app works normally", "Недоступна – виджеты показывают «Открыть Nocturne»; приложение работает как обычно"),
    "live_activities_title": ("Live Activities", "Live Activities", "Live Activities"),
    "live_activities_on": ("Activate – ecran blocat și Dynamic Island", "On – Lock Screen and Dynamic Island", "Включены – экран блокировки и Dynamic Island"),
    "live_activities_off": ("Dezactivate în Setări iOS → Nocturne", "Turned off in iOS Settings → Nocturne", "Отключены в Настройках iOS → Nocturne"),
    "files_title": ("Fișiere", "Files", "Файлы"),
    "files_body": ("Melodiile sunt în aplicația Fișiere → Pe iPhone → Nocturne → Music", "Songs are in the Files app → On My iPhone → Nocturne → Music", "Песни в приложении «Файлы» → На iPhone → Nocturne → Music"),
    "settings_system_section": ("Sistem", "System", "Система"),
    "widget_open_app": ("Deschide Nocturne", "Open Nocturne", "Открыть Nocturne"),
    "widget_small_name": ("Nocturne", "Nocturne", "Nocturne"),
    "widget_lock_description": ("Melodia curentă pe ecranul blocat", "Current song on the Lock Screen", "Текущая песня на экране блокировки"),
    "share_title": ("Trimis la Nocturne", "Sent to Nocturne", "Отправлено в Nocturne"),
    "share_body": ("Linkul apare în Nocturne → Adaugă muzică.", "The link appears in Nocturne → Add music.", "Ссылка появится в Nocturne → Добавить музыку."),
    "share_open": ("Deschide Nocturne", "Open Nocturne", "Открыть Nocturne"),
    "share_no_link": ("Nu am găsit un link YouTube aici.", "No YouTube link found here.", "Здесь нет ссылки YouTube."),
    "share_done": ("Gata", "Done", "Готово"),
    "pending_link_found": ("Link primit din Share", "Link received from Share", "Ссылка из «Поделиться»"),
    "edit": ("Editează", "Edit", "Изменить"),
    "done": ("Gata", "Done", "Готово"),
    "ok": ("OK", "OK", "OK"),
    "lyrics_retry_hint": ("Reîncearcă", "Retry", "Повторить"),
    "downloads_finished_title": ("Descărcări finalizate", "Downloads finished", "Загрузки завершены"),
    "background_downloads_note": ("Descărcările continuă în fundal.", "Downloads continue in the background.", "Загрузки продолжаются в фоне."),
}
EXTRA_PLURALS = {
    "downloaded_count": {
        "ro": {"one": "%lld melodie descărcată", "few": "%lld melodii descărcate", "other": "%lld de melodii descărcate"},
        "en": {"one": "%lld song downloaded", "other": "%lld songs downloaded"},
        "ru": {"one": "%lld песня загружена", "few": "%lld песни загружены", "many": "%lld песен загружено", "other": "%lld песни загружено"},
    },
}
for k, (ro, en, ru) in EXTRA.items():
    strings[k] = {"ro": ro, "en": en, "ru": ru}
plurals.update(EXTRA_PLURALS)

def unit(v): return {"stringUnit": {"state": "translated", "value": v}}
out = {"sourceLanguage": "ro", "version": "1.0", "strings": {}}
for k in sorted(strings):
    loc = {l: unit(v) for l, v in strings[k].items()}
    for l in LANGS:
        if l not in loc: loc[l] = unit(strings[k].get("ro") or next(iter(strings[k].values())))
    out["strings"][k] = {"extractionState": "manual", "localizations": loc}
for k in sorted(plurals):
    loc = {}
    for l in LANGS:
        forms = plurals[k].get(l) or plurals[k]["ro"]
        loc[l] = {"variations": {"plural": {q: unit(v) for q, v in forms.items()}}}
    out["strings"][k] = {"extractionState": "manual", "localizations": loc}
dst = pathlib.Path("Shared/Resources/Localizable.xcstrings")
dst.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(len(strings), "strings,", len(plurals), "plurals")
