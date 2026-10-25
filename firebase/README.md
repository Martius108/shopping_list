# ShoppingList: Firebase und Android-Übergabe

Stand: 23. Oktober 2026. Android Studio ist laut Martin auf diesem Mac einsatzbereit. Die Android-App wird erst beim nächsten Termin umgesetzt.

## Bestehende Einrichtung

- Firebase-Projekt: `shoppinglist-6c6f4`, Spark-Tarif.
- Firestore: Standard, `(default)`, `europe-west3` (Frankfurt).
- Authentication: E-Mail/Passwort. Anmeldung über Google ist nicht erforderlich und nicht aktiviert.
- Zugriff erst nach Bestätigung der E-Mail-Adresse und Aktualisierung des ID-Tokens.
- iOS-App: `com.martinlanius.Shopping-List`; Konfiguration unter `Shopping List/GoogleService-Info.plist`.
- iOS verwendet FirebaseCore, FirebaseAuth und FirebaseFirestore aus Firebase Apple SDK 13.1.1. Firebase Analytics wird nicht eingebunden.
- Die Regeln aus `firestore.rules` wurden am 23.10.2026 nach den lokalen Emulatorprüfungen und Martins Bestätigung veröffentlicht; am 24.10.2026 wurde nach sieben bestandenen Regeltestgruppen das eigentümergeführte Statusfeld `sharingReady` ergänzt.
- Die frühere minimale Homebrew-Installation `android-commandlinetools` samt SDK-Verzeichnis und deren beiden Profilzeilen wurde entfernt. Vorhandene Java-Installationen und Projekte bleiben erhalten.

## Verhalten in iOS

Im Tab „Listen“ bietet die Freigabe einer privaten/iCloud-Liste „Apple / iCloud“ und „Android“. Die Anmeldung ist unter „Einstellungen → ShoppingList-Konto“ sowie beim Freigeben einer Liste erreichbar; Teilnehmer werden im Freigabedialog verwaltet. Eine Freigabe für die bestätigte E-Mail-Adresse erscheint automatisch, ohne zusätzliche Annahme. „Geteilte Listen“ erscheint bei aktiven Freigaben und öffnet eine Auswahl der verfügbaren Listen.

Eine private Liste erhält beim ersten Firebase-Teilen eine Firebase-ID. Für eine Liste mit bestehender CloudKit-Zone entsteht eine separate Firebase-Kopie; die bestehende iCloud-Freigabe bleibt bestehen. Ab diesem Zeitpunkt sind diese beiden Listen unabhängig. Fotos und Einstellungen werden nicht zu Firebase hochgeladen.

Firebase-Listen und Artikel werden mit SwiftData zwischengespeichert. Der Cache ist an die Firebase-UID gebunden und bei Abmeldung oder Anmeldung eines anderen Kontos ausgeblendet. Nach einer vollständigen Serverantwort werden auch Freigaben ausgeblendet, die während einer App-Pause entzogen wurden. Offline kann eine zuletzt zugängliche Kopie noch sichtbar sein, bis der Server wieder erreichbar ist. Firestore selbst verwendet nur einen Speicher-Cache.

Artikeländerungen werden anhand von `updatedAt` zusammengeführt. Neuere Zeitstempel gewinnen pro Artikel; dies ist keine Zusammenführung einzelner Felder. Löschungen einzelner Artikel sind Tombstones. Lokale Änderungen bleiben offline in SwiftData erhalten; erneute Synchronisierung erfolgt beim Öffnen/Aktivieren, Aktualisieren und bei Serverereignissen. Transaktionen benötigen eine Verbindung.

Der Eigentümer kann Teilnehmer hinzufügen/entfernen, die Freigabe beenden oder nach Bestätigung die Liste samt Artikeln löschen. Teilnehmer können Artikel bearbeiten und selbst austreten. Beim Löschen eines ShoppingList-Kontos wird nach erneuter Passworteingabe zuerst dessen eigene Firebase-Listen gelöscht und seine übrige Mitgliedschaft entfernt, dann das Auth-Konto und der zugehörige lokale Firebase-Cache. Bei einem Netzfehler wird die Aktion abgebrochen und ein Fehler angezeigt; bereits ausgeführte Serverlöschungen bleiben wirksam.

## Gemeinsames Datenformat für Android

`shoppingLists/{listID}`:

| Feld | Typ / Bedeutung |
| --- | --- |
| `name` | String, 1–1000 Zeichen |
| `ownerID` | Firebase Auth UID, unveränderlich |
| `ownerEmail` | bestätigte E-Mail in Kleinbuchstaben, unveränderlich |
| `memberEmails` | Array mit höchstens 100 E-Mail-Adressen in Kleinbuchstaben, einschließlich Eigentümer |
| `deleted` | Bool; während der endgültigen Löschung `true` |
| `sharingReady` | Bool; zunächst `false`, erst nach Artikelupload zusammen mit der Teilnehmerfreigabe auf `true` setzen |

Neue Listen zunächst mit `memberEmails: [ownerEmail]`, `deleted: false` und `sharingReady: false` erstellen, dann Artikel hochladen und danach Teilnehmer und `sharingReady: true` gemeinsam aktualisieren. Die Artikelsynchronisierung darf erst nach der Bestätigung des Listendokuments durch den Server starten; lokale ausstehende Snapshots sind keine Zugriffsbestätigung. Auch die Freigabe an die eigene E-Mail auf beiden Plattformen wird erst durch den abschließenden Schreibvorgang als geteilt angezeigt. Abgebrochene Uploads behalten ihre Identität und können fortgesetzt werden. Mitglieder entdecken ihre Listen ausschließlich mit `whereArrayContains("memberEmails", email.lowercase(...))`; eine unbeschränkte Collection-Abfrage ist nicht erlaubt. Die E-Mail-Adressen der Mitglieder sind für alle Teilnehmer der jeweiligen Liste sichtbar.

`shoppingLists/{listID}/items/{itemID}`:

| Feld | Typ |
| --- | --- |
| `name` | String, 1–1000 Zeichen |
| `amount` | positive Ganzzahl |
| `isBought` | Bool |
| `createdAt` | Firestore Timestamp |
| `updatedAt` | Firestore Timestamp |
| `deletedAt` | Firestore Timestamp oder explizit `null` |

Alle sechs Felder müssen vorhanden sein. `itemID` ist eine UUID mit 36 Zeichen. Android muss die UUID wie iOS **in Großbuchstaben** als Dokument-ID schreiben (`uppercase(Locale.ROOT)`), damit derselbe Artikel nicht unter zwei Schreibweisen gespeichert wird. Neue Artikel erzeugen eine UUID; bestehende Artikel behalten ihre ID. Beim Wiederherstellen eines Tombstones `deletedAt` auf `null` setzen und `updatedAt` erhöhen. Schreibvorgänge müssen vorhandene neuere Artikel in einer Transaktion erhalten.

Bei einer endgültigen Listenlöschung zuerst `deleted: true` setzen, dann ausschließlich als Eigentümer die Artikel in begrenzten Batches und zuletzt das Listendokument löschen. Teilnehmer können keine anderen Teilnehmer einladen oder die Eigentümerschaft verändern. Nicht deklarierte Datenpfade sind gesperrt.

## Ausgeführte Prüfungen

- Sieben Gruppen von Firestore-Regeltests erfolgreich im lokalen Emulator: Zugriffsschutz, Einladung und Eigentümerrechte, Feldvalidierung/Tombstones, Entzug/Austritt, endgültiges Löschen, erstmaliges Teilen mit demselben Konto und eigentümergeführter Abschluss mit mehreren Teilnehmern.
- Am 24.10.2026 vier aktuelle Swift-Testfunktionen mit den echten SwiftData-Modellen auf dem Mac ausgeführt: bestätigter Status, Fortsetzen, Wiederverwendung einer eindeutig identifizierten Upload-Kopie und entzogener Zugriff. iPhone-Build erfolgreich; Android-Build, Lint und sieben JVM-Tests ebenfalls bestanden. Android noch nicht mit diesen letzten Änderungen auf dem moto g13 installiert.
- Bestehenden SwiftData-Speicher mit den vorherigen Modellen angelegt und mit den erweiterten Modellen geöffnet: Liste und Artikel erhalten; Kontotrennung und ausgeblendeter entzogener Zugriff geprüft. Diese Prüfung lief als Swift-Programm auf dem Mac.
- Die geänderten Zusammenführungsmethoden separat mit echten SwiftData-Modellen auf dem Mac ausgeführt: iCloud-Quelle blieb erhalten, unterschiedliche Firebase-Konten blieben getrennt, neuere Artikeldaten einer doppelten Firebase-Liste blieben erhalten.
- iOS-App und XCTest-Quellen mit `xcodebuild build-for-testing` für den iOS-Simulator kompiliert. Der vollständige XCTest-Lauf und die neue Oberfläche wurden noch nicht im Simulator oder auf einem iPhone ausgeführt.
- Noch kein Test der tatsächlichen Firebase-Synchronisierung zwischen zwei Geräten. Für den Abschluss Anmeldung, E-Mail-Bestätigung, Teilen, beidseitige Änderungen, Offline/Wiederverbindung, Entzug, Abmeldung/Kontowechsel sowie Löschen mit zwei Testkonten prüfen.
- Lokale Datenschutzdateien in `docs/` wurden ergänzt; eine Veröffentlichung der Webseiten und die Anpassung der Store-Datenschutzangaben stehen vor einem Release noch aus.

## Regeltests erneut ausführen

Voraussetzungen: Node.js passend zur Firebase CLI und Java 21 oder neuer im `PATH`.

```sh
cd firebase
npm install
npm test
```

Auf diesem Mac liegt ein geeignetes Java unter `/opt/homebrew/opt/openjdk/bin`. Falls ein älteres Java zuerst gefunden wird:

```sh
PATH="/opt/homebrew/opt/openjdk/bin:$PATH" npm test
```

Die Konfiguration verwendet ausschließlich das Emulatorprojekt `demo-shopping-list` und lokale Ports 8087/4407/4507. Die Tests schreiben keine Daten in das echte Firebase-Projekt. Eine Regelveröffentlichung ist ein separater Schritt.

## Nächster Termin

1. Installierte Android-Studio-/SDK-Pakete prüfen und die Android-App mit passendem Paketnamen im selben Firebase-Projekt registrieren; `google-services.json` einbinden.
2. Eine native Android-Oberfläche auf Basis des bestehenden Einkaufsablaufs erstellen, ohne die iOS-Oberfläche nachzubauen.
3. Firebase-Anmeldung, bestätigte E-Mail, Listenauswahl, Artikelsynchronisierung und Teilnehmerrechte nach obigem Format umsetzen.
4. Die tatsächliche gemeinsame Nutzung zwischen iPhone und Android mit zwei Testkonten prüfen; danach einen privaten Test-Build vorbereiten.

Offizielle Grundlagen: [Android Studio](https://developer.android.com/studio), [Firebase Apple Setup](https://firebase.google.com/docs/ios/setup), [Firebase Android Setup](https://firebase.google.com/docs/android/setup), [Regeltests mit dem Emulator](https://firebase.google.com/docs/firestore/security/test-rules-emulator).

### iOS-Nachkorrektur am 24.10.2026

Auch die Freigabeschaltflächen richten sich nun nach `firebaseSharingReady`: vor Abschluss Personen-Plus statt Personenpaar und kein Aufheben-Symbol. Unfertige Firebase-Kopien erscheinen nicht unter „Weitere Listen“. Bei älteren eigenen Uploads ohne `sharingReady` und nur einem Mitglied wird der ausstehende Vorgang wieder für „Freigabe fortsetzen“ vorgemerkt. Diese drei UI-/Wiederaufnahme-Anpassungen beim nächsten Android-Update ebenfalls übernehmen; der vorige Android-Build enthält bereits Serverbestätigung und den persistierten Abschlussstatus.

Der iOS-Listendialog verwendet jetzt `.sheet(item: $firebaseList)`, damit der Freigabedialog zuverlässig mit der ausgewählten Liste statt mit `nil` startet. Ist die unfertige Firebase-Kopie bereits die aktuelle Liste, wird ihre anhand identischer Artikel-UUIDs eindeutig zugeordnete CloudKit-Ursprungsliste während des Vorgangs unter „Weitere Listen“ ausgeblendet; beide Datensätze bleiben erhalten.

### Aktueller Geräte- und Einladungsstand, 24.10.2026

Die vorbereiteten Einladungs-Mails enthalten jetzt einen HTTPS-Link ohne Anhang. Die statische Einstiegsseite liegt in `hosting/`, ist auf `shoppinglist-6c6f4.web.app` veröffentlicht und verwendet keine Analyse- oder externen Skriptdienste. Die Einladungsdaten stehen im URL-Fragment; die eigentliche Leseberechtigung kommt weiterhin ausschließlich aus Firestore und der bestätigten Kontoadresse. `.well-known` enthält die Zuordnungen zu den beiden Apps.

Beide Apps unterstützen zusätzlich die Firebase-Anmeldung per E-Mail-Link ohne Abschreiben eines generierten Passworts. Sie verwenden die Standard-Hosting-Domain für Auth-Links ohne expliziten Domain-Override. `signIn.email` ist aktiviert, `passwordRequired` ist false; die API lässt diesen Standardwert in Antworten weg. Das vorhandene Passwort bleibt als weiterer Anmeldeweg nutzbar. Firebase begrenzt diese Auth-Mails im Spark-Projekt auf fünf pro Tag. Die nativen Einladungs-Mails sind davon unabhängig.

Der aktuelle iOS-Build einschließlich Einladungen, vereinfachtem Formular, Fortschrittsanzeige und Anmeldung per E-Mail-Link wurde erfolgreich gebaut und auf ThePhone installiert (`/private/tmp/shopping-list-ios-current-install.json`: success). Es wurden keine bestehenden Konten oder Listen gelöscht und keine echten Einladungs- oder Anmeldemails durch den Agenten ausgelöst.

Wiederholbare Auth-Regression: `tests/email-link-check.py` zusammen mit `tests/auth-emulator.json` im lokalen Projekt `demo-shopping-list` ausführen. Der ausgeführte Test bestätigte dieselbe Konto-ID nach Link-Anmeldung, E-Mail-Bestätigung, Erhalt des vorhandenen Passworts, Einmaligkeit des Links, Ablehnung der falschen Adresse sowie Passwortsetzung für ein per Link angelegtes Testkonto. Mobile Weiterleitung selbst wird vom Auth-Emulator nicht emuliert.

Noch offen: Listenumbenennung und abschließender Abgleich der rechten Aktionsicons auf den jetzt aktualisierten Geräten. Die aktuelle iPhone-Oberfläche wurde nach Installation noch nicht vom Agenten bedient. Android hat eine getestete und installierte Migration für doppelte Cache-Identitäten; deren Anzeige nach erneutem App-Start bleibt zu bestätigen.

### Listenansicht und Mailtext, 24.10.2026

Letzter iOS-Stand erfolgreich auf ThePhone installiert (`shopping-list-ios-actions-final-install.json`). Oben Teilen/Personenpaar plus Löschen für eigene Listen, kein Trennen; „Liste hinzufügen“ direkt darunter. Unter „Weitere Listen“ erscheinen zusätzlich auch die aktuell gewählten geteilten Listen mit Freigabeverwaltung/Trennen/Löschen für Eigentümer, bei Teilnehmern Personenpaar/Verlassen ohne globales Löschen. Der iOS-Freigabemenüpunkt heißt ausdrücklich „Android-Konto“; das Kontomodell bleibt plattformunabhängig.

Neue Firebase-Kopien speichern lokal ihre ursprüngliche Listen-ID. Dadurch bleibt die ungeteilte iCloud-Quelle bei angemeldetem zugehörigem Konto ausgeblendet; erneute Freigabe verwendet dieselbe Kopie. Abmeldung, Kontowechsel und entzogener Zugriff zeigen die ursprüngliche private Liste wieder. Modellmigration und die neue Sichtbarkeits-Testfunktion wurden mit echten SwiftData-Modellen auf dem Mac geprüft.

Der letzte Installationsabsatz der Einladungsmail wurde auf Deutsch und Englisch in beiden Apps entfernt. Android enthält dieselbe neue Anordnung sowie ein sichtbares Trennen-Icon (das vorige VectorDrawable hatte keine Pfade); APK-Build/Prüflauf für den nächsten Gerätewechsel gestartet. Noch nicht mit diesem Stand auf dem moto installiert.

Nur lesende Diagnose ergab vor Änderung drei iPhone-Datensätze mit je 144 Artikeln: iCloud-Original, alte Firebase-Freigabe nur für den Eigentümer sowie neue Firebase-Freigabe mit einem weiteren Teilnehmer. Sicherungen von SwiftData und beiden Firebase-Wurzeln samt Artikeln liegen unter `/private/tmp/shopping-list-approved-cleanup/`. Martin genehmigte erst die Bereinigung, kündigte danach aber an, Freigaben/geteilte Listen selbst zu entfernen und neu zu testen. Deshalb wurden keine realen Listen oder Freigaben gelöscht. Die alte Zeilenanzahl unter „Weitere Listen“ steigt durch die zusätzliche aktuelle geteilte Liste von zwei auf drei, ohne neuen Datensatz. Nicht als neue Duplikaterzeugung auslegen.

Listenumbenennung bleibt offen. Keine Telefonoberfläche automatisiert bedient; Gerätetest der endgültigen Anordnung übernimmt Martin.

### Abschluss der iPhone-Bereinigung und Sprachdateien, 24.10.2026

Die native, ausdrücklich genehmigte Bereinigung lief erfolgreich: alte Firebase-Wurzel `161gTvyB4GCre1LUTQFJ` samt 144 Artikelkopien entfernt, ursprüngliche iCloud-Zone gelöscht, aktuelle Firebase-Liste `0112210C-E3A1-4C3F-A3D3-7531C1C09076` mit 144 Artikeln und denselben zwei Konten unverändert erhalten. Direkt bei Firebase nachgeprüft. Dauerhafte private Sicherungen: `/Users/martin/Library/Application Support/ShoppingList-Backups/2026-10-24-vor-bereinigung`. Temporärer konto-/ID-gebundener Reparaturcode vollständig aus den Quellen entfernt.

Nach der Bereinigung wurde eine leere lokale iCloud-Liste mit neuer UUID, aber derselben alten Zone wiederhergestellt. Eine reine Existenzprüfung reichte nicht. Erfolgreich gelöschte Zonen werden jetzt in `deletedShoppingListCloudZones` gespeichert und nicht passiv wiederimportiert. Der erfolgreiche interne Reparaturbeleg übernimmt die ältere Löschhistorie einmalig. Nur leere eigene private Cacheeinträge werden automatisch entfernt; nicht leere, empfangene oder Firebase-Listen bleiben geschützt. Bewusstes erneutes Annehmen einer CloudKit-Einladung hebt die Markierung für deren Zone wieder auf. Martin hat nach dem letzten Update bestätigt, dass der leere Eintrag verschwunden ist.

Letzte Icon-Vorgabe: aktuelle eigene geteilte Liste oben rechts Personenpaar plus Löschen, kein Trennen; derselbe geteilte Listeneintrag unter „Weitere Listen“ rechts Personen-Plus für weitere Einladungen, Trennen und Löschen. Eingeladene Konten erhalten keine globalen Eigentümerrechte. Diese zwei Zeilen sind eine bewusste Darstellung derselben Liste. Der zusätzliche Link/Dialog „Geteilte Listen“ wurde auf beiden Plattformen entfernt. „Liste hinzufügen“ steht direkt unter der aktuellen Liste. Android-APK mit dieser Anordnung fertig gebaut; Installation beim nun anstehenden Gerätewechsel prüfen.

Localizable.xcstrings auf 118 verwendete, vollständig deutsch/englisch übersetzte Einträge bereinigt. Compilerextraktion nur aus echten Projektquellen auswerten: generierte String-Symbole referenzieren sonst die alten manuellen Schlüssel selbst. `Done`/`OK` explizit übersetzt; leere Navigationstitel verwenden `Text(verbatim: "")`. Beanstandetes `Opacity: %lld%%` durch `Opacity: %@` und native `.percent.precision(.fractionLength(0))` ersetzt. Lokale Prüfung für DE/EN 52 Prozent bestanden. Die existierenden InfoPlist.strings enthalten bereits korrekt Einkaufsliste/Shopping List; Martins Display-Name-Eintrag im Target bleibt erhalten.

Abschlussprüfungen: iOS-Build erfolgreich, vier echte Swift-Regeltestfunktionen auf dem Mac bestanden einschließlich wiederholter Freigabe/älterer fertiger Kopien/Mehrdeutigkeit/Kontotrennung/Löschmarkierungen; acht Firestore-Regeltestgruppen im lokalen Emulator bestanden einschließlich nachlaufender Leseoperation nach Elternlöschung. Artikel-Listener werden vor dem Löschen beendet; iOS stoppt/schützt zusätzlich laufende Synchronisierung für ausdrücklich gelöschte IDs. Android: Assemble, Lint und elf JVM-Tests bestanden. Aktuelle iPhone-Installation: `/private/tmp/shopping-list-ios-retired-zones-install.json` success; Android-Build: `/private/tmp/shopping-list-android-restoration-build.log`. Keine Telefonoberfläche automatisiert bedient. Listenumbenennung aus dem früheren Auftrag bleibt offen.

### Löschsymbol am 24.10.2026 korrigiert

Liste löschen wird ausschließlich in der oberen aktuellen Listenzeile für Eigentümer angeboten. Unter „Weitere Listen“ kein Papierkorb mehr, auch nicht für die zusätzliche Zeile derselben eigenen Freigabe. Untere Freigabeaktionen bleiben Einladen/Zugang verwalten und Freigabe aufheben beziehungsweise Verlassen. iOS-Build und Android Assemble/Lint bestanden. Martin möchte zuerst das Moto aktualisieren und danach das iPhone wieder verbinden; iPhone-Installation dieser letzten Änderung steht deshalb noch aus.

Die Korrektur des Löschsymbols ist jetzt auf beiden Geräten installiert: Moto-Installation Success und iPhone-Receipt `/private/tmp/shopping-list-ios-delete-placement-install.json` success. Keine Einkaufsdaten verändert.

### Morgen fortsetzen: Anmeldung und Listenübersicht

Martin pausiert ausdrücklich für heute. Keine weiteren Codeänderungen oder Tests starten. Beide Geräte haben die letzte Korrektur: Papierkorb nur oben an der aktuellen eigenen Liste, unter „Weitere Listen“ ausschließlich Freigabeaktionen. iPhone-Installation `/private/tmp/shopping-list-ios-delete-placement-install.json` success; Moto-Installation ebenfalls Success.

Für morgen: Einladungsmail und passwortlose Anmeldemail wirken für Martin wie doppelte Verifizierung. Beim aktuellen Test war das Moto-Konto zuvor bereits bestätigt und nur abgemeldet. Unterscheiden: Die einmalige Kontoadress-Bestätigung bleibt nach Abmeldung erhalten; ein neuer Anmeldelink authentifiziert eine neue Sitzung. Aktuelle Einladung enthält ausschließlich Listenzugriff/Empfängeradresse, keinen Auth-Code. Bereits angemeldete passende Empfänger sollen direkt öffnen. Prüfen, wie Einladung und passwortlose Anmeldung mit möglichst einer Mail funktionieren können; gewählte native Absender-Mail und kostenlosen Spark-Tarif/Anmeldelinkkontingent beachten, keine Begrenzung umgehen. Keine automatische erneute Verifikationsmail für bereits bestätigte Konten.

Moto-Anzeige: Bei gewählter privater Liste erscheint nur die geteilte unter „Weitere Listen“. Bei gewählter geteilter Liste erscheinen dort private Liste UND die aktuelle geteilte Liste. Das entspricht dem aktuellen Filter (alle anderen plus aktuelle geteilte) und bedeutet keine neue Datensatzkopie. Die private Moto-Liste mit vier Artikeln ist eine eigenständige Liste und darf nicht bereinigt werden. Für morgen die verwirrende doppelte Darstellung der aktuellen geteilten Liste überarbeiten, gegebenenfalls Freigabeaufhebung im oberen Personen-Dialog zugänglich machen; heute nur Vorschlag, nicht umgesetzt. Frühere offene Listenumbenennung ebenfalls weiterhin ausstehend.

### iPhone-Listenlogik am 25.10.2026

Martins präzisierte Anzeige zuerst ausschließlich in iOS umgesetzt. Eigene Listen haben vorne immer `doc`; empfangene Listen vorne `person.2.fill`. Eigene ungeteilte Listen zeigen Teilen und Löschen auch unter „Weitere Listen“. Eine eigene geteilte aktuelle Liste zeigt Personenpaar und Löschen; ihre zusätzliche Zeile unter „Weitere Listen“ zeigt Einladen und Freigabe aufheben ohne Löschen. Empfangene Listen zeigen rechts ausschließlich Verlassen, auch wenn sie aktuell ausgewählt sind. Einladen/Zugangsverwaltung ist für empfangene Zeilen nicht mehr erreichbar; die vorhandenen Eigentümerprüfungen im Freigabedialog und Backend bleiben bestehen.

Die aktuelle empfangene Liste wird unter „Weitere Listen“ ausgeblendet; eine eigene aktuelle geteilte Liste bleibt dort zusätzlich erhalten. Gemeinsame Regeln `ShoppingListLogic.isReceivedList` und `otherLists` berücksichtigen Firebase-UID und CloudKit-Eigentümer. Drei Regressionstests für den Listenwechsel und beide Freigabesysteme ergänzt. Sieben tatsächliche Swift-Testfunktionskörper mit echten Modellen auf dem Mac erfolgreich ausgeführt; iPhone-Build erfolgreich; DE/EN-Beschriftungen vollständig. Installationsbeleg für den Abschluss: `/private/tmp/shopping-list-ios-owner-ui-install.json`. Geräteansicht prüft Martin manuell.

Android-Code, Authentifizierung, Bestätigungsmails, Backenddaten und vorhandene Listen bei dieser Änderung unverändert. Android-Anpassung erst nach iPhone-Abnahme. Vereinfachter Einladungs-/Anmeldeablauf und Listenumbenennung bleiben spätere offene Punkte.

### Moto-Update am 25.10.2026: Rollen, Wiederaufnahme und Umbenennen

Android-Update erfolgreich auf ZY22GRRS7B installiert. Die zuletzt abgenommenen iPhone-Regeln sind portiert: eigene Listen vorne Blatt, empfangene vorne Personenpaar. Eigene private Zeilen rechts Teilen/Löschen; eigene geteilte aktuelle Zeile Personenpaar/Löschen und zusätzliche Zeile unten Einladen/Trennen. Empfangene Listen haben rechts ausschließlich Verlassen und werden bei aktueller Auswahl unten nicht zusätzlich angezeigt.

Android „Freigabe fortsetzen“ wird nur noch für eine konkret vorgemerkte, eigene und unfertige Freigabe angezeigt. Der frühere Fallback „Konto vorhanden, keine Firebase-Liste sichtbar → aktuelle private Liste anbieten“ wurde entfernt. Erfolgreiches Aufheben/Verlassen löscht die Vormerkung, bevor eine empfangene Liste lokal entfernt wird. Manuelles Teilen über das Symbol bleibt möglich; vor Kontoanmeldung begonnene eigene Freigaben können weiter fortgesetzt werden. Auf dem Moto zeigte die alte Vormerkung noch auf die private Liste BC20A39C-7F6A-45FD-A8A2-B52D5971C4A7 ohne Firebase-ID. Nach Installation bei gestopptem App-Prozess ausschließlich diesen UI-Merker zurückgesetzt; andere Einstellungen überprüft unverändert, private Liste mit allen fünf Artikeln erhalten. Sicherung: `/Users/martin/Library/Application Support/ShoppingList-Backups/2026-10-25-moto-ui/appearance-before-pending-reset.xml`.

Android: langer Druck direkt auf den Namen einer eigenen Liste öffnet den vorhandenen Namensdialog. Privat wird lokal umbenannt; bei eigenen Firebase-Listen wird zuerst die bestätigte Änderung des Serverfelds `name` abgewartet und danach der aktuelle Cacheeintrag aktualisiert. Empfangene Listen sind nicht umbenennbar. Namensnormalisierung/1–1000 Zeichen und Fehlertexte deutsch/englisch; Fortschrittsanzeige bei asynchronen Listenaktionen. Keine echten Namen/Freigaben im Test verändert, keine echten Mails versendet.

Prüfungen: Android Assemble/Lint erfolgreich, vierzehn JVM-Tests erfolgreich; neun lokale Firestore-Testgruppen erfolgreich einschließlich Eigentümer-/Teilnehmerrechten beim Umbenennen und Namensgrenzen. Keine connectedAndroidTest-Ausführung und keine Bedienung der Telefonoberfläche; einmaliger Prozessstopp nur für den sicheren UI-Merker-Reset. Build-/Testprotokolle: `/private/tmp/shopping-list-moto-owner-ui/`. Langer Druck und erneutes Verlassen bleiben von Martin am Gerät zu prüfen.

Wichtig für die nächste iPhone-Änderung: Umbenennen und die nur auf ausdrücklicher Freigabeabsicht beruhende Wiederaufnahme sind bisher nur auf Android implementiert. iOS hat noch seinen früheren Wiederaufnahme-Fallback und keinen Namensdialog. Die vereinfachte Einladung/Anmeldung bleibt weiterhin zurückgestellt. Der gemeinsame Firestore-Test wurde ergänzt; die Produktionsregeln wurden nicht geändert.

### Android „Über diese App“, 25.10.2026

Unten in den Moto-Einstellungen nach dem ShoppingList-Konto den Link „Über diese App“ mit nativem Info-Icon ergänzt. Öffnet eine scrollbare Material3-ModalBottomSheet mit Fertig-Schaltfläche und nativem Zurück/Schließen; Settings bleiben darunter bestehen. Vollständige deutsche/englische Ressourcen (18 neue Einträge je Sprache). Kurze Abschnitte: Umbenennen per langem Druck, Teilen/Einladung und eigene Konten, aktuelle/eigene/empfangene Listen und die bewusste zusätzliche Verwaltungszeile, Aufheben/Verlassen/Löschen/Abmelden, lokal/offline/Deinstallation, Darstellung und Firebase.

Firebase-Abschnitt nennt Google als externen Dienstleister, Authentication samt technischen Verbindungsdaten und Verarbeitung in den USA, Listendatenbank in Frankfurt, übertragene Listen-/Artikel-/Mitgliedsdaten und die innerhalb der Liste sichtbaren Teilnehmeradressen. Fotos und Darstellung werden nicht zu Firebase hochgeladen; Analytics ist nicht eingebunden. Öffnet auf Wunsch https://firebase.google.com/support/privacy im Browser, mit Fehlerbehandlung für fehlenden Browser. Angaben mit aktuellem Code und der offiziellen Firebase-Datenschutzseite abgeglichen. App-Information, keine neue Einwilligungsabfrage und keine Änderung des Auth-Ablaufs.

Android Assemble/Lint erfolgreich; alle 18 neuen Ressourcenschlüssel deutsch/englisch geprüft. Keine neuen Geschäftslogiktests für diese statische UI-Ergänzung; Darstellung und Browseraufruf bleiben manuell zu prüfen. Build: `/private/tmp/shopping-list-about-build.log`. iPhone-Umsetzung von About, Umbenennen und expliziter Wiederaufnahme weiterhin für den anstehenden Plattformwechsel ausstehend.


2026-10-25: Android-Update mit lokalisierten App-/Kontonamen und Einladungsmail auf Moto g13 installiert (adb install -r: Success; assembleDebug und lintDebug bestanden). Auch die Firebase-Hosting-Seiten invite/login verwenden jetzt Einkaufsliste (de) und Shopping List (en); Hosting erfolgreich veröffentlicht. Einladungen fügen Empfänger weiterhin sofort zu memberEmails hinzu, deshalb erscheinen neue Listen vor dem Linkklick. Annahme pro Liste über den Einladungslink vorgeschlagen, aber noch nicht implementiert; Auth, Firestore-Regeln und bestehende Mitgliedschaften bleiben unverändert.


### Abschlussprüfung und Kontomail-Branding, 25.10.2026

Gemeinsamen Funktionsstand von iOS und Android erneut geprüft: Rollen-/Zeilenaktionen, Umbenennen, ausdrückliche Wiederaufnahme, About, Sprachen und Einladungstexte stimmen im geprüften Bereich überein. iOS-Build und 13 gezielte Swift-Prüfungen erfolgreich; Android Assemble/Lint und 14 JVM-Tests erfolgreich. Lokaler Auth-Test erfolgreich; neun lokale Firestore-Testgruppen bestanden, aktive Regeln stimmen exakt mit der getesteten Quelle überein. Keine Produktionslisten oder Mitgliedschaften verändert.

Moto-APK per SHA-256 mit installiertem Paket verglichen: identisch. iPhone-Build nach erneuter USB-Verbindung erfolgreich installiert; Receipt `/private/tmp/shopping-list-ios-final-audit-install.json` success.

Firebase-Absendername in allen vier bestehenden Kontomail-Vorlagen auf Einkaufsliste / Shopping List gesetzt, weitere Vorlagenfelder unverändert geprüft. Martin hat die separate öffentliche Google-App-Konfiguration mit diesem Namen selbst abgeschlossen und Googles Richtlinie selbst bestätigt. Korrigierte interne Entwickler-Kontaktadresse nach seiner ausdrücklichen Auswahl gespeichert. Eine vorhandene OAuth-Markenbezeichnung ersetzt laut Firebase-FAQ den bisherigen Projekt-ID-Fallback für APP_NAME; tatsächlich zugestellte Mail noch manuell prüfen. Die technische Firebase-Absenderdomain bleibt unverändert. Vollständiger Prüfbericht: `/Volumes/Transport/Local Agent/output/shopping-list-review/2026-10-25.md`.

Weiterhin offen: Annahme pro neuer Liste erst durch Einladungslink. Dies wurde noch nicht implementiert; beide Apps gewähren Mitgliedschaft aktuell beim Einladen. Keine vollständige manuelle Telefon-UI-Prüfung und kein echter Test-Mailversand.


### Einladungsmail statt zusätzlicher Annahmelogik, 25.10.2026

Martin hat ausdrücklich die kleinere Lösung gewählt: bestehende sofortige Mitgliedschaft behalten und in der Einladung erklären, dass nichts mehr zu tun ist und die Mail ignoriert werden kann, wenn die Liste bereits in der App erscheint. Zusätzliche Annahme pro Liste ist damit kein offener Umsetzungsauftrag mehr. Deutsch/Englisch in beiden Apps angepasst; Konto-Bestätigung im Text ausdrücklich nur bei einem neuen Konto. Drei Formatargumente und Links unverändert.

iOS-Build und Android Assemble/Lint erfolgreich; tatsächlich kompilierte iOS-DE/EN-Texte mit Android-Ressourcen abgeglichen. Keine neue Auth-, Freigabe- oder Firestore-Logik; keine realen Mails gesendet. Bei Abschluss der Builds war keines der Telefone erreichbar, Installation nach Geräteverbindung noch zu bestätigen.


Nachtrag: Auch der Abschnitt Listen teilen in Über diese App ist jetzt auf beiden Plattformen deutsch/englisch an den vereinfachten Ablauf angepasst: automatische Sichtbarkeit bei passender Anmeldung, Mail bei bereits sichtbarer Liste ignorierbar, einmalige Kontobestätigung bleibt nach Abmeldung erhalten. Hinweis auf eigene Konten/Passwörter beibehalten; Apple/iCloud-Absatz nur auf iOS. Autorenzeile verwendet deutsch Einkaufsliste. Builds erfolgreich; tatsächlich kompilierte iOS-Texte gegen Android abgeglichen. iPhone endgültig erfolgreich installiert: `/private/tmp/shopping-list-ios-about-notice-install.json`. Android-APK fertig gebaut, Installation auf Moto bei nächster Verbindung ausstehend. Keine echten Testmails und keine automatisierte Telefonbedienung.


Moto g13: Update mit angepasster Einladungsmail und Infobereich am 25.10.2026 erfolgreich per adb install -r installiert. SHA-256 der installierten APK stimmt exakt mit dem zuletzt geprüften Build überein. Damit sind diese Änderungen auf iPhone und Moto ausgeliefert. Kein tatsächlicher Mailversand und keine automatisierte Telefonbedienung.
