# Ubuntu Terminal App
 
Eine einfache Linux-Lernumgebung für Hochschulkurse: jede Person bekommt ein eigenes Web-Terminal (Bash im Browser,
Ubuntu 26.04) und ein vorgefertigtes Lernverzeichnis mit Übungsaufgaben und Kurzreferenz zu den wichtigsten
Terminal-Befehlen.
 
## Pod-Version (ab v2.0.0)

Ab `v2.0.0` läuft die App als Pod (`appstore.yaml`, Image unter `image/`), nicht mehr als VM. Die VM-Version (`v1.x`)
bleibt über ihren Git-Tag erreichbar; die Abschnitte weiter unten (ab "Vorinstallierte Software") beschreiben sie.

- **Ein Web-Terminal pro Person** (`scope: user`): eine Bash-Sitzung im Browser (ttyd), kein SSH. Die Adresse und das
  Passwort stehen unter "Meine Zugänge".
- **Die Sitzung überlebt das Schließen des Tabs** (dtach): Seite neu öffnen, und Hintergrundprozesse und
  Arbeitsverzeichnis sind noch da. `https://<adresse>/?arg=2` öffnet ein zweites, unabhängiges Terminal (z. B. für
  Server und Client).
- **Dateien bleiben erhalten** (Volume mit 2 Gi unter `/home/student`), auch bei Pause und Fortsetzen. Beim ersten Start
  wird `~/linux-kurs/` dorthin kopiert.
- **Software:** Python 3 (pip, venv), Node.js (npm), git, curl, wget, tree, htop, nano, vim, openssl, net-tools sowie
  Handbuchseiten (`man`, `info`), `ps`, `top`, `ip`, `ping` und `gawk`.
- **Internetzugang** (`egress: internet`) für `curl`, `ping`, `pip` und `npm`.

Unterschiede zur VM-Version:

| | VM (v1.x) | Pod (v2.x) |
|---|---|---|
| Zugang | SSH, Benutzername aus der E-Mail | Browser, URL und Passwort |
| Maschine | eine VM für alle Teilnehmenden | ein Pod pro Person (keine gemeinsame Umgebung) |
| Rechte | `sudo` für alle | normaler Benutzer ohne `sudo` und ohne root |
| `journalctl`, `ufw`, `chown` auf andere Benutzer | vorhanden | nicht vorhanden; Übung 3 und 5 sind angepasst |
| Bereitstellung | Packer + Terraform, 13-20 min | Image aus der CI, Sekunden |

Grenzen: Das eigene Passwort steht im Terminal in `ps aux` (als Argument von ttyd); das betrifft nur die eigene Umgebung,
andere Personen haben keinen Zugriff auf deinen Pod. SSH, `sudo` und mehrere Benutzer auf einer Maschine kommen erst mit
einer VM-Variante auf KubeVirt wieder.

### Entwicklung

- `image/Dockerfile` baut das Image (Ubuntu 26.04), `image/start.sh` ist der Einstieg (kopiert den Kurs ins Home, startet
  ttyd), `image/shell.sh` startet die Bash-Sitzung, `image/kurs/` enthält die Kursdateien.
- `.github/workflows/ci.yml` baut das Image mit der zentralen Pipeline aus `DHBW-AppStore-T3/app-registry` (Vertrag
  prüfen, hadolint, bauen, Smoke-Test, Trivy, Push nach ghcr.io). Der Smoke-Test (`.github/smoke-test.sh`) startet das Image
  im Sicherheitskontext der Plattform, öffnet echte Terminal-Sitzungen (`.github/test-terminal.py`) und spielt die ersten
  sechs Übungen der Vorlesung (man, cat, echo, wc, sort, uniq, head, Shell-Skripte) durch.
- Nach einem Build auf `main` den Digest aus der Job-Summary in `appstore.yaml` eintragen (`ci.yml` verlangt
  Digests: `strict-image-pin: true`). Das GHCR-Paket muss öffentlich sein, damit der Cluster es ziehen kann.
- Workflow: Feature-Branch -> PR nach `main` -> Tag `v2.x.y` -> Version im AppStore einreichen.

## Vorinstallierte Software (VM-Version v1.x)
 
- Python 3 (inkl. pip, venv)

- Node.js 24 (inkl. npm)

- Git, curl, tree, nano, vim, htop
 
## Lernverzeichnis
 
Jeder Nutzer findet nach dem Login unter `~/linux-kurs/` folgende Struktur vor:
 
    ~/linux-kurs/

    ├── LIES_MICH.txt              ← Kurzreferenz aller wichtigen Befehle

    ├── beispieldaten/

    │   ├── studenten.csv          ← CSV für Übungen mit cut, grep, sort

    │   └── server.log             ← Logdatei für Übungen mit grep, tail, wc

    └── uebungen/

        ├── 01-navigation/

        ├── 02-dateien/

        ├── 03-berechtigungen/

        ├── 04-prozesse/

        └── 05-textverarbeitung/
 
## User-Management
 
- **Ein Account pro Nutzer**, abgeleitet aus der E-Mail-Adresse

  (z.B. `alice.smith@dhbw.de` → Benutzername `alicesmith`)

- Alle Nutzer aller Teams landen auf **einer gemeinsamen VM**

- Jeder Nutzer erhält ein automatisch generiertes, zufälliges Passwort

- SSH-Login mit Passwort-Authentifizierung (kein Key nötig)
 
## VM-Deployment
 
| | |

|---|---|

| VMs gesamt | **1** (geteilt von allen Teams und Nutzern) |

| VMs pro Team | — |

| VMs pro Nutzer | — |

| Flavor | `gp1.small` |

| Floating IP | Ja (öffentlich erreichbar) |
 
## Konfigurierbare Variablen
 
| Variable | Beschreibung | Pflicht |

|---|---|---|

| `network_uuid` | UUID des internen Netzwerks | Ja |

| `floating_ip_pool` | Name des External Networks für Floating IPs | Ja |

| `shared_secgroup_id` | ID der gemeinsamen Security Group | Ja |
 
## Deployment-Dauer
 
| Schritt | Dauer (ca.) |

|---|---|

| Packer Image Build | 10–15 min |

| Terraform apply | 3–5 min |

| **Gesamt (Erstdeployment)** | **13–20 min** |
 
Bei Folge-Deployments (Image bereits gebaut) nur Terraform: **3–5 min**.

 