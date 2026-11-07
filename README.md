# Agytorna – telepítés GitHub Pages-re

## 1. Feltöltés (kb. 5 perc, kódolás nélkül)
1. Készíts egy ingyenes fiókot a github.com-on, majd **New repository** → név pl. `agytorna` (egy már meglévő repó neve maradhat) → **Public** → Create.
2. Az új repóban: **Add file → Upload files**, húzd be a csomag **összes fájlját** (index.html, manifest.webmanifest, sw.js, icon-192.png, icon-512.png), majd **Commit changes**.
3. **Settings → Pages** → Source: *Deploy from a branch* → Branch: `main`, mappa: `/ (root)` → Save.
4. 1-2 perc múlva megjelenik a cím: `https://FELHASZNÁLÓNÉV.github.io/REPÓNÉV/`

A repó nyilvános, de nincs benne semmilyen személyes adat: a PIN-kódok és a haladás csak a telefon böngészőjében tárolódnak.

## 2. Első indulás
1. Nyisd meg a címet a gyerek telefonján.
2. Egyszeri beállítás: gyerek neve, szülői PIN (4 jegy), gyerek PIN (elhagyható).
3. Utána a belépő képernyőn válaszd a gyereket. Az app megjegyzi, hogy ki lépett be, és legközelebb nem kérdez.

## 3. Főképernyőre tétel
- **iPhone (Safari):** Megosztás → Főképernyőhöz adás.
- **Android (Chrome):** menü (⋮) → Alkalmazás telepítése / Hozzáadás a kezdőképernyőhöz.

iPhone-on a Safarival és a főképernyőről indítva külön tárolót kap az app. Válasszatok egy módot (ajánlott: főképernyőről), és mindig azt használjátok.

## 4. Használat
- **Gyerek:** belép, gyakorol. A „Szülői nézet" gomb szülői PIN-t kér, a gyerek bejelentkezése nem változik.
- **Szülő:** a „Kilépés" után a Szülő gombbal is be lehet lépni. Ez megjegyződik, és a szülői nézetre visz.
- 5 hibás PIN után 30 másodpercet kell várni.

## 5. Haladás mentése / költözés
Szülői nézet → **Haladás mentése fájlba**. Másik telefonon vagy új címen a **Haladás betöltése fájlból** gombbal visszatölthető. Érdemes néha menteni, mert a böngésző adatainak törlésekor a haladás elvész.

## 6. Frissítés
Cseréld ki az `index.html`-t a repóban (Upload files, felülírja). A következő megnyitáskor az új verzió töltődik be; ha mégsem, zárd be és nyisd újra az appot.

## Fontos a biztonságról
A belépés egy **helyi zár**, nem valódi fiókrendszer. A PIN-ek a telefonon, kódolt formában tárolódnak, és a szülői zár megakadályozza, hogy a gyerek véletlenül belépjen a szülői nézetbe. Ügyes, szándékos kísérlet ellen (pl. böngészőadatok törlése, fejlesztői eszközök) nem véd. Valódi, eszközök közötti fiókokhoz később szerveroldali adatbázis kell (pl. Supabase vagy Firebase). Az app adatkezelése egy helyen van (`DB`), így ez később cserélhető.

---

# Felhő (Supabase) beállítása

## Egyszeri előkészítés
1. Supabase-projekt létrehozása (EU régió), majd a `supabase-schema.sql` teljes tartalmának lefuttatása az SQL Editorban.
2. Az Authentication beállításaiban a **névtelen belépés** (anonymous sign-ins) bekapcsolása.
3. A Project URL és a **nyilvános** kulcs (`sb_publishable_…`) bemásolása a `config.js` fájlba (url és key), majd a fájl feltöltése a GitHub-repóba az index.html mellé. A nyilvános kulcs arra való, hogy az appban látszódjon, a védelmet a jogosultsági szabályok adják. A titkos kulcsot SOHA ne tedd ide.
   Alternatíva: ha nem akarod a repóba tenni, minden eszközön egyszer beillesztheted az app saját beállító képernyőjén.

## Szülői telefon
1. Nyisd meg az appot, válaszd: **Szülő vagyok (felhős fiók)**.
2. Hozz létre fiókot (e-mail + jelszó), erősítsd meg az e-mailt, majd lépj be.
3. Add meg a gyerek nevét és osztályát (a család létrehozása).
4. Az Áttekintés oldalon: **Gyerek eszköz párosítása** → 8 jegyű kód (15 percig érvényes).

## Gyerek telefon
- Új eszköz: **Ez a gyerek eszköze** → kód + új szülői PIN.
- Már beállított eszköz: Szülői nézet (PIN) → **☁️ Felhő** → kód.
- Innentől minden kör végén automatikusan szinkronizál. Offline is működik, a következő kapcsolatnál feltölt.

## Amit érdemes tudni
- Az ingyenes Supabase-projekt 7 nap inaktivitás után szünetelhet. Ilyenkor a Supabase felületén kell újraindítani. A gyerek telefonján az adatok megmaradnak.
- Az ingyenes csomagon nincs automatikus mentés, ezért a szülői nézetben érdemes néha fájlba menteni a haladást.
- Az egyszer sikeresen párosított gyerek eszköz a böngésző adatainak törlése után újra párosítást igényel.
