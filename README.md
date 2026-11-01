# XEOKA Pack

Набор инструментов и настроек для оптимизации Windows 10/11 (задержки, драйверы, службы, сеть, питание, BIOS).
Telegram: https://t.me/CMEPT0HOCHbIU

> Все изменения вносятся на ваш риск. Перед применением создайте точку восстановления и сохраните данные.
> Некоторые настройки снижают защиту системы (отключение Defender, обновлений, VBS/HVCI, TPM/Secure Boot в BIOS).

## Быстрый старт
Запустите `RUN-XEOKA-PACK.bat` (распакуйте архив целиком, не запускайте из архива). Откроется меню: отметьте нужные твики и нажмите «ОПТИМИЗИРОВАТЬ».
Перед применением создаётся точка восстановления, изменения реестра запоминаются, кнопка «Откатить последнее» возвращает прежние значения.
Опасные вещи (Defender, обновления, службы, BIOS) на кнопку не вынесены: они запускаются отдельно на вкладке «Инструменты».

## Состав

| Папка | Что внутри |
|---|---|
| 1. База | Активация, UAC, уведомления, удаление ненужных программ |
| 2. Драйверы | Сеть (Realtek), видеокарта (DDU, NVCleanstall, Nvidia Profile Inspector + XEOKA-OPTIMIZED-V2.nip) |
| 3. CRU | Custom Resolution Utility |
| 4. План-питания | Электропитание xeoka.pow |
| 5. Геймбар-И-Игровой-Режим | Ярлыки для отключения |
| 6. Защитник-Виндовс | Переключатель Windows Defender |
| 7. Обновления-Windows | Блокировщик обновлений |
| 8. Авторанс | Autoruns |
| 9. Настройки-Сетевого-Адаптера | Твики сетевой карты |
| 10. Службы-И-Драйверы | Отключение служб |
| 11. Диспетчер-Устройств | Отключение энергосбережения устройств |
| 12. BIOS | SCEWIN и конфиги BIOS (читайте инструкцию в папке) |
| 13. Аффинити | DEVICE-TWEAKER (прерывания, аффинити, USB IMOD) |
| 14-17 | Системный таймер, MMCSS, FSE/FSO, Win32PrioritySeparation |

## Что нужно скачать отдельно
- **RW-Everything** (Rw.exe, RwDrv.sys): нужен для DEVICE-TWEAKER, положите папку `RW-Everything` в `13. Аффинити`. Скачать: http://rweverything.com/download

## Использованные сторонние разработки
У каждой программы своя лицензия, они не входят в лицензию этого репозитория.
- Display Driver Uninstaller (DDU)
- Custom Resolution Utility (CRU), monitortests.com
- Autoruns (Sysinternals, Microsoft)
- NVCleanstall (TechPowerUp)
- NVIDIA Profile Inspector
- PowerRun
- SCEWIN / AMISCE (AMI)
- RW-Everything
- Realtek NetAdapterCx драйвер
- pci.ids (pci-ids.ucw.cz)
- **DEVICE-TWEAKER** - автор BYND_PERF (LLG), https://x.com/BEYONDPERF_LLG . Скрипт включён без изменений в содержимом, в нём сохранены ссылки автора.
- Часть скриптов и твиков (Windows Defender Switcher, Windows Update Blocker, MMCSS, сеть и др.) основана на публичных материалах сообщества Low Latency Corp (LLC). 
