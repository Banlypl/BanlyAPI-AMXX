<p align="center">
  <img src="https://banly.pl/banly-18.png" alt="Banly" width="148">
</p>

<h1 align="center">Banly dla AMX Mod X</h1>

<p align="center">
  Plugin sprawdzający graczy w Banly.pl. Gdy ktoś wejdzie na serwer,<br>
  admini od razu widzą na czacie liczbę jego aktywnych banów na sieciach CS.
</p>

## Co widzą admini

- komunikat na czacie po wejściu gracza na serwer
- nick gracza i liczbę aktywnych banów na sieciach CS

Komunikaty dostają admini z flagą `d` (`ADMIN_BAN`). Przykład:

```
[BANLY.PL] Gracz Nick ma 3 bany na sieciach cs!
[BANLY.PL] Gracz Nick nie posiada banow na zadnej sieci!
```

## Instalacja

1. Skompiluj `banly.sma` i wrzuć `banly.amxx` do `addons/amxmodx/plugins/`.
2. Dopisz `banly.amxx` do `addons/amxmodx/configs/plugins.ini`.
3. Uruchom serwer, żeby wygenerował się plik `addons/amxmodx/configs/plugins/banly.cfg`.
4. Wklej w nim klucz API i zrestartuj serwer lub zmień mapę:

```
banly_api_key "TWOJ_KLUCZ"
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
