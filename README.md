<p align="center">
  <img src="https://banly.pl/banly-18.png" alt="Banly" width="148">
</p>

<h1 align="center">Banly dla AMX Mod X</h1>

<p align="center">
  Automatyczna weryfikacja graczy w Banly.pl.<br>
  Administratorzy od razu wiedzą, czy wchodzący gracz ma aktywne bany na innych sieciach CS,<br>
  i mogą otworzyć jego pełny raport bez wychodzenia z gry.
</p>

## Co widzą admini

Każdy gracz ze Steam jest sprawdzany po wejściu na serwer. Admini z flagą `d` (`ADMIN_BAN`) dostają komunikat na czacie:

```
[BANLY.PL] Gracz Nick ma 3 bany na sieciach cs!
[BANLY.PL] Gracz Nick nie posiada banow na zadnej sieci!
```

Komunikat o graczach bez banów można wyłączyć cvarem `banly_notify_clean` w `addons/amxmodx/configs/plugins/banly.cfg`.

## Raport gracza

Raport z Banly.pl dostępny dla adminów z flagą `d`:

| Sposób | Jak użyć | Uwagi |
|---|---|---|
| Menu | `/banly` na czacie | Lista graczy ze Steam z liczbą aktywnych banów. |
| Komenda | `amx_banly <nick \| #userid \| STEAM_ID>` w konsoli | Działa też dla SteamID gracza, którego nie ma na serwerze. |

## Instalacja

1. Pobierz `banly-vX.Y.zip` z [Releases](https://github.com/Banlypl/BanlyAPI-AMXX/releases/latest).
2. Skompiluj `addons/amxmodx/scripting/banly.sma` i wrzuć `banly.amxx` do `addons/amxmodx/plugins/`.
3. Dopisz `banly.amxx` do `addons/amxmodx/configs/plugins.ini`.
4. Uruchom serwer, żeby wygenerował się plik `addons/amxmodx/configs/plugins/banly.cfg`.
5. Wklej w nim klucz API i zrestartuj serwer lub zmień mapę:

```
banly_api_key "TWOJ_KLUCZ"
```

## Konfiguracja

Plik `addons/amxmodx/configs/plugins/banly.cfg`:

| Cvar | Domyślnie | Opis |
|---|---|---|
| `banly_api_key` | `""` | Klucz API Banly.pl. Bez niego plugin się nie uruchomi |
| `banly_notify_clean` | `1` | Informuj adminów o graczach bez banów (`0` - nie, `1` - tak) |

> **Aktualizujesz plugin?** AMX Mod X nie dodaje nowych cvarów do istniejącego pliku `banly.cfg `. Aby uzupełnić brakujące linie, dodaj je ręcznie lub zapisz swój klucz API przed usunięciem pliku. Po zmianie mapy plugin wygeneruje nowy plik zawierający wszystkie cvary.

## Aktualizacje

Plugin automatycznie sprawdza, czy jest nowsza wersja. Informacja o aktualizacji pojawi się w konsoli, logach serwera oraz na czacie dla adminów z flagą `a`.

```
[BANLY.PL] Dostepna jest nowsza wersja pluginu!
```

## Klucz API

Po klucz zgłoś się do [mT](https://discord.com/users/411086675998015488).

Nigdy nie udostępniaj swojego klucza.

## Wymagania

- AMX Mod X 1.9+
- [ReAPI](https://github.com/rehlds/ReAPI)
- [CromChat](https://github.com/OciXCrom/CromChat)
- [EasyHTTP](https://github.com/Next21Team/AmxxEasyHttp)
- nvault
